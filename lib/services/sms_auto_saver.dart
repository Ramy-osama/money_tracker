import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../models/transaction_model.dart';
import 'sms_parser.dart';
import 'notification_service.dart';

/// Isolate-safe auto-saver for SMS-detected transactions.
///
/// This MUST work both in the main isolate (when the app is open) and in the
/// background isolate spawned by `another_telephony` (when the app is killed).
///
/// Constraints:
/// - No access to Provider / BuildContext.
/// - No reliance on the SmsService singleton's in-memory state.
/// - All configuration is read from SharedPreferences each invocation.
/// - DB and notifications are accessed directly (both are isolate-safe in
///   their respective ways: sqflite uses platform channels, and the local
///   notifications plugin re-initializes per isolate).
class SmsAutoSaver {
  static const String prefsKeySmsAccountId = 'sms_target_account_id';
  static const String prefsKeySmsCategoryExpenseId =
      'sms_target_category_expense_id';
  static const String prefsKeySmsCategoryIncomeId =
      'sms_target_category_income_id';
  static const String prefsKeyKeywords = 'sms_active_keywords';
  static const String prefsKeyEnabled = 'sms_tracking_enabled';

  /// How recent a previously-tracked SMS with the same fingerprint must be
  /// to be considered a re-broadcast/Truecaller duplicate.
  ///
  /// 5 minutes is wide enough to cover Truecaller's classification delay
  /// (typically <60s) plus polling fallback (15s cadence) without being so
  /// wide that legitimately repeated bank notifications later in the day
  /// (e.g., two separate purchases of the same amount at the same merchant)
  /// get dropped. A real second purchase will almost always be > 5min apart.
  static const int dedupWindowSeconds = 300;

  /// Parse a raw SMS body and persist a transaction if it matches.
  /// Returns true if a transaction was saved.
  ///
  /// [smsDate] is the message's own OS timestamp (milliseconds since epoch),
  /// taken from the platform SMS record. It is stable across processing paths
  /// (background isolate vs. inbox poll), so it is the key signal used to stop
  /// the same physical message from being saved twice.
  static Future<bool> handleIncomingSms({
    required String body,
    String? sender,
    int? smsDate,
  }) async {
    if (body.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();

    if (!(prefs.getBool(prefsKeyEnabled) ?? false)) {
      debugPrint('SmsAutoSaver: tracking disabled, skipping');
      return false;
    }

    final db = DbHelper();
    final receivedAt = DateTime.now().toIso8601String();

    Future<void> log({
      required bool wasTracked,
      int? transactionId,
      required bool matched,
      bool blockedSender = false,
      String? bodyFingerprint,
    }) async {
      try {
        await db.logIncomingSms(
          sender: sender,
          body: body,
          wasTracked: wasTracked,
          transactionId: transactionId,
          matched: matched,
          blockedSender: blockedSender,
          receivedAt: receivedAt,
          bodyFingerprint: bodyFingerprint,
          smsDate: smsDate,
        );
      } catch (e) {
        debugPrint('SmsAutoSaver: log failed: $e');
      }
    }

    if (await db.isSenderBlocked(sender)) {
      await log(
        wasTracked: false,
        matched: false,
        blockedSender: true,
      );
      debugPrint('SmsAutoSaver: sender blocked, skipping');
      return false;
    }

    final keywords = prefs.getStringList(prefsKeyKeywords) ?? const <String>[];

    final result = SmsParser.parse(body, keywords);
    if (!result.matched || result.amount == null || result.amount! <= 0) {
      await log(
        wasTracked: false,
        matched: result.matched,
        blockedSender: false,
      );
      return false;
    }

    final fingerprint = SmsParser.fingerprintForDedup(body, sender: sender);

    // Identity dedup (the primary defense against the "detected in background,
    // detected again on app open" duplication).
    //
    // The same physical SMS is seen by two independent paths: the background
    // isolate when the app is killed, and the inbox poll when the app is
    // re-opened. Both observe the OS-assigned [smsDate], which never changes.
    // If we've already tracked a transaction for this exact (fingerprint,
    // smsDate) pair, this is a re-read of a message we already saved — skip it
    // no matter how long ago that was. This is what the time-windowed check
    // below cannot do once the app is opened more than [dedupWindowSeconds]
    // after the background save.
    if (smsDate != null && fingerprint.isNotEmpty) {
      try {
        final existingTxnId = await db.findTrackedTransactionBySmsIdentity(
          fingerprint: fingerprint,
          smsDate: smsDate,
        );
        if (existingTxnId != null) {
          debugPrint(
            'SmsAutoSaver: same SMS already tracked (identity match → '
            'tx#$existingTxnId, smsDate=$smsDate), skipping insert',
          );
          await log(
            wasTracked: false,
            matched: true,
            blockedSender: false,
            bodyFingerprint: fingerprint,
          );
          return false;
        }
      } catch (e) {
        debugPrint('SmsAutoSaver: identity dedup lookup failed: $e');
      }
    }

    // Persistent, isolate-safe duplicate check (re-broadcast wrappers).
    //
    // Truecaller (and similar SMS classifier apps) re-broadcasts the
    // original bank SMS wrapped in extra annotation text, arriving as a
    // distinct message with its own (later) timestamp. The body looks
    // different to the OS so the in-memory dedup in SmsService does not
    // catch it, and on cold-start the background isolate has no in-memory
    // history at all. We persist a normalized fingerprint per processed SMS
    // and reject any incoming SMS whose fingerprint matches a recently
    // tracked one.
    if (fingerprint.isNotEmpty) {
      try {
        final existingTxnId = await db.findRecentTrackedTransactionByFingerprint(
          fingerprint: fingerprint,
          withinSeconds: dedupWindowSeconds,
        );
        if (existingTxnId != null) {
          debugPrint(
            'SmsAutoSaver: duplicate SMS detected (fingerprint match → '
            'tx#$existingTxnId, sender=${sender ?? "?"}), skipping insert',
          );
          await log(
            wasTracked: false,
            matched: true,
            blockedSender: false,
            bodyFingerprint: fingerprint,
          );
          return false;
        }
      } catch (e) {
        // Dedup is a best-effort optimisation; on failure, fall through
        // and let the regular insert path run. Worst case we record one
        // duplicate, which is still recoverable from the inbox log.
        debugPrint('SmsAutoSaver: dedup lookup failed: $e');
      }
    }

    final accounts = await db.getAccounts();
    if (accounts.isEmpty) {
      debugPrint('SmsAutoSaver: no accounts configured, skipping');
      await log(
        wasTracked: false,
        matched: true,
        blockedSender: false,
        bodyFingerprint: fingerprint,
      );
      return false;
    }

    final categories = await db.getCategories();
    if (categories.isEmpty) {
      debugPrint('SmsAutoSaver: no categories configured, skipping');
      await log(
        wasTracked: false,
        matched: true,
        blockedSender: false,
        bodyFingerprint: fingerprint,
      );
      return false;
    }

    final preferredAccountId = prefs.getInt(prefsKeySmsAccountId);
    final accountId = accounts
        .firstWhere(
          (a) => a.id == preferredAccountId,
          orElse: () => accounts.first,
        )
        .id!;

    final type = result.type;
    final preferredCategoryKey = type == 'income'
        ? prefsKeySmsCategoryIncomeId
        : prefsKeySmsCategoryExpenseId;
    final preferredCategoryId = prefs.getInt(preferredCategoryKey);

    final matchingCategories =
        categories.where((c) => c.type == type).toList();
    final fallbackCategory = matchingCategories.isNotEmpty
        ? matchingCategories.first
        : categories.first;
    final categoryId = matchingCategories
        .firstWhere(
          (c) => c.id == preferredCategoryId,
          orElse: () => fallbackCategory,
        )
        .id!;

    final description = (result.merchant != null && result.merchant!.isNotEmpty)
        ? result.merchant!
        : body.substring(0, body.length > 50 ? 50 : body.length);

    // Date the transaction by when the SMS actually arrived, not when we got
    // around to processing it. For background detection these are nearly the
    // same, but a message recovered by the poll on app re-open could otherwise
    // be stamped well after the real event (even into the wrong month).
    final transactionDate = smsDate != null
        ? DateTime.fromMillisecondsSinceEpoch(smsDate)
        : DateTime.now();

    final transaction = MoneyTransaction(
      amount: result.amount!,
      type: type,
      categoryId: categoryId,
      accountId: accountId,
      description: description,
      date: transactionDate,
      source: 'sms',
      needsReview: true,
    );

    int? newId;
    try {
      newId = await db.insertTransaction(transaction);
    } catch (e) {
      debugPrint('SmsAutoSaver: failed to insert transaction: $e');
      await log(
        wasTracked: false,
        matched: true,
        blockedSender: false,
        bodyFingerprint: fingerprint,
      );
      return false;
    }

    await log(
      wasTracked: true,
      transactionId: newId,
      matched: true,
      blockedSender: false,
      bodyFingerprint: fingerprint,
    );

    try {
      await NotificationService().showSmsTransactionNotification(
        amount: result.amount!,
        merchant: result.merchant,
        type: type,
      );
    } catch (e) {
      debugPrint('SmsAutoSaver: failed to show notification: $e');
    }

    debugPrint(
      'SmsAutoSaver: saved $type ${result.amount} from ${sender ?? "?"} '
      '(merchant=${result.merchant ?? "n/a"})',
    );
    return true;
  }
}
