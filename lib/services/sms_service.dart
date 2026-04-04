import 'dart:async';
import 'package:flutter/foundation.dart' hide Category;
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sms_parser.dart';

typedef OnTransactionDetected = void Function(SmsParseResult result);

class SmsDebugEntry {
  final DateTime time;
  final String source; // 'broadcast', 'poll', 'test', 'info', 'error'
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

  /// Returns true if this body was already processed recently (dedup)
  bool _isDuplicate(String body) {
    final key = body.hashCode.toString();
    if (_recentlyProcessed.contains(key)) return true;
    _recentlyProcessed.add(key);
    // Keep set bounded
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
    _log('info', 'Requesting SMS + Phone permissions...');
    final statuses = await [
      Permission.sms,
      Permission.phone,
    ].request();

    final smsGranted = statuses[Permission.sms]?.isGranted ?? false;
    final phoneGranted = statuses[Permission.phone]?.isGranted ?? false;

    _log('info', 'SMS permission: ${smsGranted ? "GRANTED" : "DENIED"}');
    _log('info', 'Phone permission: ${phoneGranted ? "GRANTED" : "DENIED"}');

    return smsGranted;
  }

  Future<Map<String, bool>> checkPermissionStatus() async {
    final sms = await Permission.sms.status;
    final phone = await Permission.phone.status;
    return {
      'sms': sms.isGranted,
      'phone': phone.isGranted,
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

    // Primary: real-time broadcast listener
    _telephony.listenIncomingSms(
      onNewMessage: _handleIncomingSms,
      listenInBackground: true,
    );
    _log('info', 'Broadcast listener registered');

    // Fallback: poll inbox every 15s
    await _initLastTimestamp();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pollInbox();
    });
    _log('info', 'Polling started (every 15s)');
    _log('info', 'Listening with ${keywords.length} keywords');
  }

  Future<void> _initLastTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    _lastProcessedTimestamp = prefs.getInt('last_sms_timestamp') ??
        DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('last_sms_timestamp', _lastProcessedTimestamp);
  }

  Future<void> _pollInbox() async {
    if (!_isListening || onTransactionDetected == null) return;

    try {
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.BODY, SmsColumn.DATE, SmsColumn.ADDRESS],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      int newCount = 0;
      for (final msg in messages) {
        final msgDate = msg.date;
        if (msgDate == null || msgDate <= _lastProcessedTimestamp) break;

        final body = msg.body;
        if (body == null || body.isEmpty) continue;

        newCount++;
        final preview = body.substring(0, body.length > 60 ? 60 : body.length);

        if (_isDuplicate(body)) {
          _log('poll', 'Skipped duplicate from ${msg.address ?? "?"}: $preview...');
          continue;
        }

        _log('poll', 'New SMS from ${msg.address ?? "?"}: $preview...');

        final result = SmsParser.parse(body, _activeKeywords);
        if (result.matched && onTransactionDetected != null) {
          _log('poll', 'MATCHED! Amount: ${result.amount}, Type: ${result.type}');
          onTransactionDetected!(result);
        } else if (!result.matched) {
          _log('poll', 'No match (no amount or keyword miss)');
        }
      }

      if (messages.isNotEmpty && messages.first.date != null) {
        _lastProcessedTimestamp = messages.first.date!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_sms_timestamp', _lastProcessedTimestamp);
      }

      if (newCount == 0) {
        // Silent - don't spam log with "no new messages"
      }
    } catch (e) {
      _log('error', 'Poll failed: $e');
    }
  }

  void _handleIncomingSms(SmsMessage message) {
    final body = message.body;
    if (body == null || body.isEmpty) return;

    _isDuplicate(body); // Mark as seen so poll skips it

    final preview = body.substring(0, body.length > 60 ? 60 : body.length);
    _log('broadcast', 'RECEIVED from ${message.address ?? "?"}: $preview...');

    // Update timestamp so polling doesn't re-process
    final msgDate = message.date;
    if (msgDate != null && msgDate > _lastProcessedTimestamp) {
      _lastProcessedTimestamp = msgDate;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('last_sms_timestamp', _lastProcessedTimestamp);
      });
    }

    final result = SmsParser.parse(body, _activeKeywords);
    if (result.matched && onTransactionDetected != null) {
      _log('broadcast', 'MATCHED! Amount: ${result.amount}, Type: ${result.type}');
      onTransactionDetected!(result);
    } else {
      _log('broadcast', 'No match (amount: ${result.amount}, matched: ${result.matched})');
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sms_tracking_enabled', false);
  }

  void updateKeywords(List<String> keywords) {
    _activeKeywords = keywords;
    _log('info', 'Keywords updated: ${keywords.length} active');
  }

  Future<void> restoreIfEnabled(List<String> keywords) async {
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled = prefs.getBool('sms_tracking_enabled') ?? false;
    if (wasEnabled && keywords.isNotEmpty) {
      _log('info', 'Restoring SMS tracking from previous session');
      await startListening(keywords);
    }
  }
}

@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  // Background SMS processing handled by telephony package
}
