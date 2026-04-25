import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import '../database/db_helper.dart';
import '../models/category.dart';
import '../services/sms_service.dart';
import '../services/sms_auto_saver.dart';

class SettingsProvider with ChangeNotifier {
  final DbHelper _db = DbHelper();
  final SmsService _smsService = SmsService();

  List<String> _smsKeywords = [];
  bool _smsTrackingEnabled = false;
  String _currency = 'EGP';
  List<Category> _categories = [];
  String _geminiApiKey = '';
  int? _smsTargetAccountId;
  int? _smsTargetExpenseCategoryId;
  int? _smsTargetIncomeCategoryId;

  List<String> get smsKeywords => _smsKeywords;
  bool get smsTrackingEnabled => _smsTrackingEnabled;
  String get currency => _currency;
  List<Category> get categories => _categories;
  String get geminiApiKey => _geminiApiKey;
  bool get isGeminiConfigured => _geminiApiKey.isNotEmpty;
  int? get smsTargetAccountId => _smsTargetAccountId;
  int? get smsTargetExpenseCategoryId => _smsTargetExpenseCategoryId;
  int? get smsTargetIncomeCategoryId => _smsTargetIncomeCategoryId;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _smsTrackingEnabled = prefs.getBool(SmsAutoSaver.prefsKeyEnabled) ?? false;
    _currency = prefs.getString('currency') ?? 'EGP';
    _geminiApiKey = prefs.getString('gemini_api_key') ?? '';
    _smsTargetAccountId = prefs.getInt(SmsAutoSaver.prefsKeySmsAccountId);
    _smsTargetExpenseCategoryId =
        prefs.getInt(SmsAutoSaver.prefsKeySmsCategoryExpenseId);
    _smsTargetIncomeCategoryId =
        prefs.getInt(SmsAutoSaver.prefsKeySmsCategoryIncomeId);
    _smsKeywords = await _db.getSmsKeywords();
    _categories = await _db.getCategories();
    // Mirror keywords into SharedPreferences so the background isolate
    // can read them without hitting sqflite during cold start.
    await prefs.setStringList(SmsAutoSaver.prefsKeyKeywords, _smsKeywords);
    notifyListeners();
  }

  Future<void> toggleSmsTracking(bool enabled) async {
    _smsTrackingEnabled = enabled;
    if (enabled) {
      final granted = await _smsService.requestPermissions();
      if (granted) {
        await _smsService.startListening(_smsKeywords);
      } else {
        _smsTrackingEnabled = false;
      }
    } else {
      await _smsService.stopListening();
    }
    notifyListeners();
  }

  Future<void> restoreSmsIfEnabled() async {
    if (_smsTrackingEnabled && _smsKeywords.isNotEmpty) {
      await _smsService.restoreIfEnabled(_smsKeywords);
    }
  }

  Future<void> setSmsTargetAccount(int? accountId) async {
    _smsTargetAccountId = accountId;
    final prefs = await SharedPreferences.getInstance();
    if (accountId == null) {
      await prefs.remove(SmsAutoSaver.prefsKeySmsAccountId);
    } else {
      await prefs.setInt(SmsAutoSaver.prefsKeySmsAccountId, accountId);
    }
    notifyListeners();
  }

  Future<void> setSmsTargetExpenseCategory(int? categoryId) async {
    _smsTargetExpenseCategoryId = categoryId;
    final prefs = await SharedPreferences.getInstance();
    if (categoryId == null) {
      await prefs.remove(SmsAutoSaver.prefsKeySmsCategoryExpenseId);
    } else {
      await prefs.setInt(
          SmsAutoSaver.prefsKeySmsCategoryExpenseId, categoryId);
    }
    notifyListeners();
  }

  Future<void> setSmsTargetIncomeCategory(int? categoryId) async {
    _smsTargetIncomeCategoryId = categoryId;
    final prefs = await SharedPreferences.getInstance();
    if (categoryId == null) {
      await prefs.remove(SmsAutoSaver.prefsKeySmsCategoryIncomeId);
    } else {
      await prefs.setInt(
          SmsAutoSaver.prefsKeySmsCategoryIncomeId, categoryId);
    }
    notifyListeners();
  }

  Future<void> addKeyword(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty || _smsKeywords.contains(trimmed)) return;
    await _db.addSmsKeyword(trimmed);
    _smsKeywords = await _db.getSmsKeywords();
    await _smsService.updateKeywords(_smsKeywords);
    notifyListeners();
  }

  Future<void> removeKeyword(String keyword) async {
    await _db.removeSmsKeyword(keyword);
    _smsKeywords = await _db.getSmsKeywords();
    await _smsService.updateKeywords(_smsKeywords);
    notifyListeners();
  }

  Future<void> setCurrency(String currency) async {
    _currency = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency', currency);
    notifyListeners();
  }

  Future<void> setGeminiApiKey(String key) async {
    _geminiApiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _geminiApiKey);
    notifyListeners();
  }

  Future<void> addCategory(Category category) async {
    await _db.insertCategory(category);
    _categories = await _db.getCategories();
    notifyListeners();
  }

  Future<void> updateCategory(Category category) async {
    await _db.updateCategory(category);
    _categories = await _db.getCategories();
    notifyListeners();
  }

  Future<void> deleteCategory(int id) async {
    await _db.deleteCategory(id);
    _categories = await _db.getCategories();
    notifyListeners();
  }

  Future<String?> exportToCsv() async {
    final data = await _db.getAllTransactionsForExport();
    if (data.isEmpty) return null;

    final headers = ['Date', 'Type', 'Amount', 'Description', 'Category', 'Account', 'Source'];
    final rows = <List<dynamic>>[headers];

    for (final row in data) {
      rows.add([
        row['date'],
        row['type'],
        row['amount'],
        row['description'] ?? '',
        row['category'] ?? '',
        row['account'] ?? '',
        row['source'] ?? 'manual',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getExternalStorageDirectory();
    if (dir == null) return null;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/money_tracker_export_$timestamp.csv');
    await file.writeAsString(csv);
    return file.path;
  }
}
