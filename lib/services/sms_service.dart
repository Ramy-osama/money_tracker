import 'dart:async';
import 'package:flutter/foundation.dart' hide Category;
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sms_parser.dart';
import 'sms_auto_saver.dart';

typedef OnTransactionDetected = void Function(SmsParseResult result);

class SmsDebugEntry {
  final DateTime time;
  final String source; // 'broadcast', 'background', 'poll', 'test', 'info', 'error'
  final String message;

  SmsDebugEntry(this.source, this.message) : time = DateTime.now();

  String get formatted {
    final t = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    return '[$t] [$source] $message';
  }
}

class SmsService {
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  final Telephony _telephony = Telephony.instance;

  /// Optional UI callback for live updates while the app is open.
  /// The actual persistence happens in [SmsAutoSaver] regardless of this
  /// callback, so the feature works even when the app is killed.
  OnTransactionDetected? onTransactionDetected;

  List<String> _activeKeywords = [];
  bool _isListening = false;
  Timer? _pollTimer;
  int _lastProcessedTimestamp = 0;
  final Set<String> _recentlyProcessed = {};

  // Debug log accessible from UI
  final List<SmsDebugEntry> debugLog = [];
  VoidCallback? onDebugLogChanged;

  static const int _maxDebugEntries = 50;

  bool get isListening => _isListening;
  List<String> get activeKeywords => List.unmodifiable(_activeKeywords);

  /// Returns true if this body was already processed recently (dedup).
  ///
  /// We key off [SmsParser.fingerprintForDedup] rather than the raw body so
  /// that Truecaller / re-broadcast wrappers (which add caller-info text
  /// around the original bank message) collapse to the same dedup key as
  /// the original. Falls back to body hash when no fingerprint is available
  /// (very short or non-matching messages).
  bool _isDuplicate(String body, {String? sender}) {
    final fp = SmsParser.fingerprintForDedup(body, sender: sender);
    final key = fp.isNotEmpty ? fp : 'raw:${body.hashCode}';
    if (_recentlyProcessed.contains(key)) return true;
    _recentlyProcessed.add(key);
    if (_recentlyProcessed.length > 30) {
      _recentlyProcessed.remove(_recentlyProcessed.first);
    }
    return false;
  }

  void _log(String source, String message) {
    debugPrint('SMS [$source]: $message');
    debugLog.add(SmsDebugEntry(source, message));
    if (debugLog.length > _maxDebugEntries) {
      debugLog.removeAt(0);
    }
    onDebugLogChanged?.call();
  }

  Future<bool> requestPermissions() async {
    _log('info', 'Requesting SMS + Phone + Notification permissions...');
    final statuses = await [
      Permission.sms,
      Permission.phone,
      Permission.notification,
    ].request();

    final smsGranted = statuses[Permission.sms]?.isGranted ?? false;
    final phoneGranted = statuses[Permission.phone]?.isGranted ?? false;
    final notifGranted = statuses[Permission.notification]?.isGranted ?? false;

    _log('info', 'SMS permission: ${smsGranted ? "GRANTED" : "DENIED"}');
    _log('info', 'Phone permission: ${phoneGranted ? "GRANTED" : "DENIED"}');
    _log('info', 'Notification permission: ${notifGranted ? "GRANTED" : "DENIED"}');

    return smsGranted;
  }

  Future<Map<String, bool>> checkPermissionStatus() async {
    final sms = await Permission.sms.status;
    final phone = await Permission.phone.status;
    final notification = await Permission.notification.status;
    return {
      'sms': sms.isGranted,
      'phone': phone.isGranted,
      'notification': notification.isGranted,
    };
  }

  Future<void> startListening(List<String> keywords) async {
    final granted = await requestPermissions();
    if (!granted) {
      _log('error', 'Cannot start: permissions denied');
      return;
    }

    _activeKeywords = keywords;
    _isListening = true;

    // Persist config so the background isolate can read it.
    await _persistRuntimeConfig(keywords: keywords, enabled: true);

    // Primary: real-time broadcast listener with BOTH foreground and
    // background handlers. The background handler runs in a separate
    // isolate when the app is killed.
    _telephony.listenIncomingSms(
      onNewMessage: _handleIncomingSms,
      onBackgroundMessage: smsBackgroundMessageHandler,
      listenInBackground: true,
    );
    _log('info', 'Broadcast listener registered (foreground + background)');

    // Fallback: poll inbox every 15s while the app is alive.
    await _initLastTimestamp();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pollInbox();
    });
    _log('info', 'Polling started (every 15s)');
    _log('info', 'Listening with ${keywords.length} keywords');
  }

  Future<void> _persistRuntimeConfig({
    required List<String> keywords,
    required bool enabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SmsAutoSaver.prefsKeyEnabled, enabled);
    await prefs.setStringList(SmsAutoSaver.prefsKeyKeywords, keywords);
  }

  Future<void> _initLastTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    _lastProcessedTimestamp = prefs.getInt('last_sms_timestamp') ??
        DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('last_sms_timestamp', _lastProcessedTimestamp);
  }

  Future<void> _pollInbox() async {
    if (!_isListening) return;

    try {
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ADDRESS],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      for (final msg in messages) {
        final msgDate = msg.date;
        if (msgDate == null || msgDate <= _lastProcessedTimestamp) break;

        final body = msg.body;
        if (body == null || body.isEmpty) continue;

        final preview = body.substring(0, body.length > 60 ? 60 : body.length);

        if (_isDuplicate(body, sender: msg.address)) {
          _log('poll', 'Skipped duplicate from ${msg.address ?? "?"}: $preview...');
          continue;
        }

        _log('poll', 'New SMS from ${msg.address ?? "?"}: $preview...');

        // Save through the same isolate-safe path used in background.
        final saved = await SmsAutoSaver.handleIncomingSms(
          body: body,
          sender: msg.address,
          smsDate: msgDate,
        );

        if (saved) {
          _log('poll', 'MATCHED + SAVED');
          // Best-effort UI hint (only meaningful if app is alive).
          final result = SmsParser.parse(body, _activeKeywords);
          if (result.matched && onTransactionDetected != null) {
            onTransactionDetected!(result);
          }
        } else {
          _log('poll', 'No match (no amount or keyword miss)');
        }
      }

      if (messages.isNotEmpty && messages.first.date != null) {
        _lastProcessedTimestamp = messages.first.date!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_sms_timestamp', _lastProcessedTimestamp);
      }
    } catch (e) {
      _log('error', 'Poll failed: $e');
    }
  }

  Future<void> _handleIncomingSms(SmsMessage message) async {
    final body = message.body;
    if (body == null || body.isEmpty) return;

    final preview = body.substring(0, body.length > 60 ? 60 : body.length);

    // First-line in-memory dedup: catches Truecaller's near-instant
    // re-broadcast in the foreground isolate without hitting the DB.
    // SmsAutoSaver does a persistent fingerprint check too, which is the
    // authoritative dedup (works after cold-start and across isolates).
    if (_isDuplicate(body, sender: message.address)) {
      _log('broadcast',
          'Skipped duplicate from ${message.address ?? "?"}: $preview...');
      return;
    }

    _log('broadcast', 'RECEIVED from ${message.address ?? "?"}: $preview...');

    // Update timestamp so polling doesn't re-process
    final msgDate = message.date;
    if (msgDate != null && msgDate > _lastProcessedTimestamp) {
      _lastProcessedTimestamp = msgDate;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sms_timestamp', _lastProcessedTimestamp);
    }

    // Always run the persistence path - works whether or not the UI exists.
    final saved = await SmsAutoSaver.handleIncomingSms(
      body: body,
      sender: message.address,
      smsDate: message.date,
    );

    if (saved) {
      _log('broadcast', 'MATCHED + SAVED');
      // Best-effort UI hint for any listening screens.
      final result = SmsParser.parse(body, _activeKeywords);
      if (result.matched && onTransactionDetected != null) {
        onTransactionDetected!(result);
      }
    } else {
      _log('broadcast', 'No match or save skipped');
    }
  }

  /// Manually scan recent inbox messages for debugging
  Future<List<Map<String, String>>> testScanInbox({int count = 5}) async {
    _log('test', 'Manual scan requested (last $count messages)...');
    final results = <Map<String, String>>[];

    try {
      final perms = await checkPermissionStatus();
      if (!(perms['sms'] ?? false)) {
        _log('error', 'SMS permission not granted - cannot read inbox');
        return results;
      }

      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ADDRESS],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final toScan = messages.take(count);
      for (final msg in toScan) {
        final body = msg.body ?? '';
        final sender = msg.address ?? '?';
        final date = msg.date != null
            ? DateTime.fromMillisecondsSinceEpoch(msg.date!).toString()
            : '?';

        final parsed = SmsParser.parse(body, _activeKeywords);

        final entry = {
          'sender': sender,
          'date': date,
          'body': body.length > 80 ? '${body.substring(0, 80)}...' : body,
          'matched': parsed.matched.toString(),
          'amount': parsed.amount?.toString() ?? 'none',
          'type': parsed.type,
          'merchant': parsed.merchant ?? 'none',
        };
        results.add(entry);

        _log('test', 'From $sender: matched=${parsed.matched}, '
            'amount=${parsed.amount ?? "none"}, type=${parsed.type}');
      }

      _log('test', 'Scan complete: ${results.length} messages checked, '
          '${results.where((r) => r['matched'] == 'true').length} matched');
    } catch (e) {
      _log('error', 'Test scan failed: $e');
    }

    return results;
  }

  Future<void> stopListening() async {
    _isListening = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _log('info', 'Listening stopped');
    await _persistRuntimeConfig(keywords: _activeKeywords, enabled: false);
  }

  Future<void> updateKeywords(List<String> keywords) async {
    _activeKeywords = keywords;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(SmsAutoSaver.prefsKeyKeywords, keywords);
    _log('info', 'Keywords updated: ${keywords.length} active');
  }

  Future<void> restoreIfEnabled(List<String> keywords) async {
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled = prefs.getBool(SmsAutoSaver.prefsKeyEnabled) ?? false;
    if (wasEnabled && keywords.isNotEmpty) {
      _log('info', 'Restoring SMS tracking from previous session');
      await startListening(keywords);
    }
  }
}

/// Top-level background handler invoked by the platform when an SMS arrives
/// and the Flutter engine is NOT running (i.e. the app is killed).
///
/// MUST be a top-level / static function and annotated with
/// `@pragma('vm:entry-point')` so the Dart compiler keeps it in tree-shaken
/// release builds and the platform isolate can spawn it.
@pragma('vm:entry-point')
Future<void> smsBackgroundMessageHandler(SmsMessage message) async {
  // Required: bind the background isolate's BinaryMessenger before touching
  // any plugin (sqflite / shared_preferences / notifications).
  // The telephony plugin already calls ensureInitialized in its background
  // entry-point, but we call it here defensively in case that changes.
  // ignore: avoid_print
  print('SMS background handler invoked: ${message.address}');

  final body = message.body;
  if (body == null || body.isEmpty) return;

  await SmsAutoSaver.handleIncomingSms(
    body: body,
    sender: message.address,
    smsDate: message.date,
  );
}
