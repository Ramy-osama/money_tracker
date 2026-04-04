import 'package:flutter/foundation.dart' hide Category;
import '../database/db_helper.dart';
import '../models/transaction_model.dart';
import '../models/category.dart';

class TransactionProvider with ChangeNotifier {
  final DbHelper _db = DbHelper();

  List<MoneyTransaction> _transactions = [];
  Map<String, double> _monthSummary = {'income': 0, 'expense': 0, 'net': 0};
  Map<String, double> _prevMonthSummary = {'income': 0, 'expense': 0, 'net': 0};
  List<Category> _categories = [];
  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = false;

  List<MoneyTransaction> get transactions => _transactions;
  Map<String, double> get monthSummary => _monthSummary;
  Map<String, double> get prevMonthSummary => _prevMonthSummary;
  List<Category> get categories => List<Category>.from(_categories);
  DateTime get selectedMonth => _selectedMonth;
  bool get isLoading => _isLoading;

  double get totalSpent => _monthSummary['expense'] ?? 0;
  double get totalIncome => _monthSummary['income'] ?? 0;
  double get netBalance => _monthSummary['net'] ?? 0;

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    await Future.wait([
      _loadTransactions(),
      _loadSummary(),
      _loadCategories(),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadTransactions() async {
    final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endDate = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);

    _transactions = await _db.getTransactions(
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<void> _loadSummary() async {
    _monthSummary = await _db.getMonthSummary(
      _selectedMonth.year,
      _selectedMonth.month,
    );
    _prevMonthSummary = await _db.getPreviousMonthSummary(
      _selectedMonth.year,
      _selectedMonth.month,
    );
  }

  Future<void> _loadCategories() async {
    _categories = await _db.getCategories();
  }

  void setSelectedMonth(DateTime month) {
    _selectedMonth = month;
    loadData();
  }

  void goToPreviousMonth() {
    _selectedMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month - 1,
    );
    loadData();
  }

  void goToNextMonth() {
    _selectedMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
    );
    loadData();
  }

  Future<void> addTransaction(MoneyTransaction transaction) async {
    await _db.insertTransaction(transaction);
    await loadData();
  }

  Future<void> deleteTransaction(MoneyTransaction transaction) async {
    await _db.deleteTransaction(transaction);
    await loadData();
  }

  Future<void> updateTransaction(
      MoneyTransaction oldTxn, MoneyTransaction newTxn) async {
    await _db.updateTransaction(oldTxn, newTxn);
    await loadData();
  }

  Future<void> markReviewed(MoneyTransaction txn) async {
    if (txn.id == null) return;
    await _db.markTransactionReviewed(txn.id!);
    await loadData();
  }

  Future<void> markAllReviewed() async {
    await _db.markAllReviewed();
    await loadData();
  }

  int get unreviewedCount =>
      _transactions.where((t) => t.needsReview).length;

  Future<List<Map<String, dynamic>>> getCategoryBreakdown(String type) async {
    return _db.getCategoryBreakdown(
      _selectedMonth.year,
      _selectedMonth.month,
      type,
    );
  }

  Category? getCategoryById(int id) {
    try {
      return _categories.firstWhere((Category c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
}
