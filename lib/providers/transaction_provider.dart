import 'package:flutter/foundation.dart' hide Category;
import '../database/db_helper.dart';
import '../models/transaction_model.dart';
import '../models/category.dart';
import '../services/duplicate_detector.dart';

class TransactionProvider with ChangeNotifier {
  final DbHelper _db = DbHelper();

  List<MoneyTransaction> _transactions = [];
  Map<String, double> _monthSummary = {'income': 0, 'expense': 0, 'net': 0};
  Map<String, double> _prevMonthSummary = {'income': 0, 'expense': 0, 'net': 0};
  List<Category> _categories = [];
  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = false;
  Map<int, int> _childCounts = {};
  Map<int, double> _parentAdjustments = {};
  Map<int, int> _affectsParentSubItemCounts = {};
  Map<int, double> _oppositeTypeOffsets = {};

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

    await _fetchAll();

    _isLoading = false;
    notifyListeners();
  }

  /// Re-reads the current month without entering the loading state, so the
  /// wallet list stays mounted and keeps its scroll position.
  Future<void> refresh() async {
    await _fetchAll();
    notifyListeners();
  }

  Future<void> _fetchAll() async {
    await Future.wait([
      _loadTransactions(),
      _loadSummary(),
      _loadCategories(),
    ]);
  }

  Future<void> _loadTransactions() async {
    final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endDate = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);

    final all = await _db.getTransactions(
      startDate: startDate,
      endDate: endDate,
    );

    // Show only top-level transactions in the main list
    _transactions = all.where((t) => t.parentId == null).toList();

    // Pre-load child counts for parent transactions
    final parentIds = _transactions
        .where((t) => t.id != null)
        .map((t) => t.id!)
        .toList();
    _childCounts = await _db.getChildCounts(parentIds);
    final affect = await _db.getParentAffectData(parentIds);
    _parentAdjustments = {for (final e in affect.entries) e.key: e.value.$1};
    _affectsParentSubItemCounts = {for (final e in affect.entries) e.key: e.value.$2};
    _oppositeTypeOffsets = await _db.getOppositeTypeOffsets(parentIds);
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

  /// Re-read categories from DB so newly added ones appear immediately.
  Future<void> refreshCategories() async {
    _categories = await _db.getCategories();
    notifyListeners();
  }

  int getChildCount(int transactionId) => _childCounts[transactionId] ?? 0;

  double parentAdjustmentFor(int parentId) =>
      _parentAdjustments[parentId] ?? 0.0;

  int affectsParentSubItemCountFor(int parentId) =>
      _affectsParentSubItemCounts[parentId] ?? 0;

  /// Sum of opposite-type children (with affects_parent=1) collected so far.
  /// 0 if none — meaning this parent has no settlement-style children.
  double oppositeTypeOffsetFor(int parentId) =>
      _oppositeTypeOffsets[parentId] ?? 0.0;

  /// True iff [parent] has at least one opposite-type child marked
  /// `affects_parent`. Used to decide whether to show the "remaining" line.
  bool hasOppositeTypeChildren(MoneyTransaction parent) {
    if (parent.id == null) return false;
    return (_oppositeTypeOffsets[parent.id!] ?? 0.0) > 0;
  }

  /// Money still outstanding on [parent]:
  ///   - Expense parent: amount you laid out minus what people have paid back.
  ///   - Income parent: amount you received minus what you've paid out.
  /// Clamped to 0 (overpayment doesn't make remaining go negative).
  /// Returns 0 if there are no opposite-type children (nothing to settle).
  double remainingFor(MoneyTransaction parent) {
    if (!hasOppositeTypeChildren(parent)) return 0;
    final offset = _oppositeTypeOffsets[parent.id!] ?? 0.0;
    final remaining = parent.amount - offset;
    return remaining < 0 ? 0 : remaining;
  }

  /// True when opposite-type children fully (or more than) cover the parent.
  bool isSettled(MoneyTransaction parent) {
    if (!hasOppositeTypeChildren(parent)) return false;
    final offset = _oppositeTypeOffsets[parent.id!] ?? 0.0;
    return offset >= parent.amount;
  }

  Future<List<MoneyTransaction>> getChildTransactions(int parentId) async {
    return _db.getChildTransactions(parentId);
  }

  Future<void> addSubTransaction(MoneyTransaction child, int parentId) async {
    final subTxn = child.copyWith(parentId: parentId);
    await _db.insertSubTransaction(subTxn);
    await refresh();
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
    await refresh();
  }

  /// Deletes the transactions with [ids] together with their sub-items, and
  /// returns every removed row so [restoreTransactions] can undo it.
  Future<List<MoneyTransaction>> deleteTransactions(Iterable<int> ids) async {
    final idSet = ids.toSet();
    // Must happen before the first await: a swiped Dismissible has to leave
    // the tree on the very next frame.
    _transactions = _transactions.where((t) => !idSet.contains(t.id)).toList();
    notifyListeners();

    final removed = <MoneyTransaction>[];
    for (final id in idSet) {
      final txn = await _db.getTransactionById(id);
      if (txn == null) continue;
      removed.add(txn);
      if (txn.parentId == null) {
        removed.addAll(await _db.getChildTransactions(id));
      }
      await _db.deleteTransaction(txn);
    }
    await refresh();
    return removed;
  }

  Future<void> restoreTransactions(List<MoneyTransaction> rows) async {
    await _db.restoreTransactions(rows);
    await refresh();
  }

  /// Suspected duplicates across all months (see [DuplicateDetector]), plus
  /// the sub-item count of each transaction in them.
  Future<({List<List<MoneyTransaction>> groups, Map<int, int> childCounts})>
      findSuspectedDuplicates() async {
    final groups = DuplicateDetector.findGroups(await _db.getTransactions());
    final ids = [
      for (final group in groups)
        for (final t in group) t.id!,
    ];
    return (groups: groups, childCounts: await _db.getChildCounts(ids));
  }

  Future<void> updateTransaction(
      MoneyTransaction oldTxn, MoneyTransaction newTxn) async {
    await _db.updateTransaction(oldTxn, newTxn);
    await refresh();
  }

  Future<void> markReviewed(MoneyTransaction txn) async {
    if (txn.id == null) return;
    await _db.markTransactionReviewed(txn.id!);
    await refresh();
  }

  Future<void> markAllReviewed() async {
    await _db.markAllReviewed();
    await refresh();
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
