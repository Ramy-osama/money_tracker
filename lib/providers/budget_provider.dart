import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/budget.dart';
import '../models/goal.dart';

class BudgetProvider with ChangeNotifier {
  final DbHelper _db = DbHelper();

  List<Budget> _budgets = [];
  List<Goal> _goals = [];
  double _totalBudgetUsed = 0;
  bool _isLoading = false;

  List<Budget> get budgets => _budgets;
  List<Goal> get goals => _goals;
  double get totalBudgetUsed => _totalBudgetUsed;
  bool get isLoading => _isLoading;

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    await Future.wait([
      _loadBudgets(),
      _loadGoals(),
      _loadTotalBudgetUsed(),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadBudgets() async {
    _budgets = await _db.getBudgets();
  }

  Future<void> _loadGoals() async {
    _goals = await _db.getGoals();
  }

  Future<void> _loadTotalBudgetUsed() async {
    _totalBudgetUsed = await _db.getTotalBudgetUsed();
  }

  Future<void> addBudget(Budget budget) async {
    await _db.insertBudget(budget);
    await loadData();
  }

  Future<void> updateBudget(Budget budget) async {
    await _db.updateBudget(budget);
    await loadData();
  }

  Future<void> deleteBudget(int id) async {
    await _db.deleteBudget(id);
    await loadData();
  }

  Future<void> addGoal(Goal goal) async {
    await _db.insertGoal(goal);
    await loadData();
  }

  Future<void> updateGoal(Goal goal) async {
    await _db.updateGoal(goal);
    await loadData();
  }

  Future<void> deleteGoal(int id) async {
    await _db.deleteGoal(id);
    await loadData();
  }

  Future<void> addToGoal(int goalId, double amount) async {
    final goal = _goals.firstWhere((g) => g.id == goalId);
    final updated = goal.copyWith(currentAmount: goal.currentAmount + amount);
    await _db.updateGoal(updated);
    await loadData();
  }
}
