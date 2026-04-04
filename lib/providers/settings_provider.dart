import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import '../database/db_helper.dart';
import '../models/category.dart';
import '../services/sms_service.dart';

class SettingsProvider with ChangeNotifier {
  final DbHelper _db = DbHelper();
  final SmsService _smsService = SmsService();

  List<String> _smsKeywords = [];
  bool _smsTrackingEnabled = false;
  String _currency = 'EGP';
  List<Category> _categories = [];

  List<String> get smsKeywords => _smsKeywords;
  bool get smsTrackingEnabled => _smsTrackingEnabled;
  String get currency => _currency;
  List<Category> get categories => _categories;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _smsTrackingEnabled = prefs.getBool('sms_tracking_enabled') ?? false;
    _currency = prefs.getString('currency') ?? 'EGP';
    _smsKeywords = await _db.getSmsKeywords();
    _categories = await _db.getCategories();
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

  Future<void> addKeyword(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty || _smsKeywords.contains(trimmed)) return;
    await _db.addSmsKeyword(trimmed);
    _smsKeywords = await _db.getSmsKeywords();
    _smsService.updateKeywords(_smsKeywords);
    notifyListeners();
  }

  Future<void> removeKeyword(String keyword) async {
    await _db.removeSmsKeyword(keyword);
    _smsKeywords = await _db.getSmsKeywords();
    _smsService.updateKeywords(_smsKeywords);
    notifyListeners();
  }

  Future<void> setCurrency(String currency) async {
    _currency = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency', currency);
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
