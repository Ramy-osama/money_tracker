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

  /// Parse a raw SMS body and persist a transaction if it matches.
  /// Returns true if a transaction was saved.
  static Future<bool> handleIncomingSms({
    required String body,
    String? sender,
  }) async {
    if (body.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();

    if (!(prefs.getBool(prefsKeyEnabled) ?? false)) {
      debugPrint('SmsAutoSaver: tracking disabled, skipping');
      return false;
    }

    final keywords = prefs.getStringList(prefsKeyKeywords) ?? const <String>[];

    final result = SmsParser.parse(body, keywords);
    if (!result.matched || result.amount == null || result.amount! <= 0) {
      return false;
    }

    final db = DbHelper();
    final accounts = await db.getAccounts();
    if (accounts.isEmpty) {
      debugPrint('SmsAutoSaver: no accounts configured, skipping');
      return false;
    }

    final categories = await db.getCategories();
    if (categories.isEmpty) {
      debugPrint('SmsAutoSaver: no categories configured, skipping');
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

    final transaction = MoneyTransaction(
      amount: result.amount!,
      type: type,
      categoryId: categoryId,
      accountId: accountId,
      description: description,
      date: DateTime.now(),
      source: 'sms',
      needsReview: true,
    );

    try {
      await db.insertTransaction(transaction);
    } catch (e) {
      debugPrint('SmsAutoSaver: failed to insert transaction: $e');
      return false;
    }

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
