import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/budget.dart';
import '../models/goal.dart';
import '../utils/constants.dart';

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'money_tracker.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        card_last4 TEXT,
        balance REAL NOT NULL DEFAULT 0,
        type TEXT NOT NULL DEFAULT 'bank',
        color TEXT NOT NULL DEFAULT '#00897B',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon_name TEXT NOT NULL,
        type TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        account_id INTEGER NOT NULL,
        description TEXT,
        date TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        created_at TEXT NOT NULL,
        needs_review INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (account_id) REFERENCES accounts(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        limit_amount REAL NOT NULL,
        period TEXT NOT NULL DEFAULT 'monthly',
        created_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        current_amount REAL NOT NULL DEFAULT 0,
        deadline TEXT,
        icon_name TEXT NOT NULL DEFAULT 'savings',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sms_keywords (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        keyword TEXT NOT NULL UNIQUE,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await _seedData(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0');
    }
  }

  Future<void> _seedData(Database db) async {
    // Seed default account
    await db.insert('accounts', {
      'name': 'Main Account',
      'card_last4': null,
      'balance': 0.0,
      'type': 'bank',
      'color': '#00897B',
      'created_at': DateTime.now().toIso8601String(),
    });

    // Seed expense categories
    for (final cat in DefaultCategories.expense) {
      await db.insert('categories', {
        'name': cat['name'],
        'icon_name': cat['icon'],
        'type': 'expense',
        'is_default': 1,
      });
    }

    // Seed income categories
    for (final cat in DefaultCategories.income) {
      await db.insert('categories', {
        'name': cat['name'],
        'icon_name': cat['icon'],
        'type': 'income',
        'is_default': 1,
      });
    }

    // Seed SMS keywords
    for (final keyword in DefaultSmsKeywords.keywords) {
      await db.insert('sms_keywords', {
        'keyword': keyword,
        'is_active': 1,
      });
    }
  }

  // ─── Account CRUD ───

  Future<int> insertAccount(Account account) async {
    final db = await database;
    return await db.insert('accounts', account.toMap());
  }

  Future<List<Account>> getAccounts() async {
    final db = await database;
    final maps = await db.query('accounts', orderBy: 'created_at ASC');
    final accounts = maps.map((m) => Account.fromMap(m)).toList();

    for (final account in accounts) {
      final computed = await _computeAccountBalance(account.id!);
      if (computed != account.balance) {
        await db.update('accounts', {'balance': computed},
            where: 'id = ?', whereArgs: [account.id]);
      }
    }

    if (accounts.any((a) => a.balance != 0)) {
      final refreshed = await db.query('accounts', orderBy: 'created_at ASC');
      return refreshed.map((m) => Account.fromMap(m)).toList();
    }
    return accounts;
  }

  Future<double> _computeAccountBalance(int accountId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0)
        - COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0)
        AS balance
      FROM transactions
      WHERE account_id = ?
    ''', [accountId]);
    return (result.first['balance'] as num?)?.toDouble() ?? 0.0;
  }

  Future<Account?> getAccount(int id) async {
    final db = await database;
    final maps = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Account.fromMap(maps.first);
  }

  Future<int> updateAccount(Account account) async {
    final db = await database;
    return await db.update(
      'accounts',
      account.toMap(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<int> deleteAccount(int id) async {
    final db = await database;
    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateAccountBalance(int accountId, double delta) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE accounts SET balance = balance + ? WHERE id = ?',
      [delta, accountId],
    );
  }

  // ─── Category CRUD ───

  Future<int> insertCategory(Category category) async {
    final db = await database;
    return await db.insert('categories', category.toMap());
  }

  Future<List<Category>> getCategories({String? type}) async {
    final db = await database;
    if (type != null) {
      final maps = await db.query('categories',
          where: 'type = ?', whereArgs: [type], orderBy: 'name ASC');
      return maps.map((m) => Category.fromMap(m)).toList();
    }
    final maps = await db.query('categories', orderBy: 'type ASC, name ASC');
    return maps.map((m) => Category.fromMap(m)).toList();
  }

  Future<Category?> getCategory(int id) async {
    final db = await database;
    final maps = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Category.fromMap(maps.first);
  }

  Future<int> updateCategory(Category category) async {
    final db = await database;
    return await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Transaction CRUD ───

  Future<int> insertTransaction(MoneyTransaction transaction) async {
    final db = await database;
    final id = await db.insert('transactions', transaction.toMap());

    final delta =
        transaction.type == 'income' ? transaction.amount : -transaction.amount;
    await updateAccountBalance(transaction.accountId, delta);

    return id;
  }

  Future<List<MoneyTransaction>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    String? type,
    int? categoryId,
    int? accountId,
    int? limit,
  }) async {
    final db = await database;
    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (startDate != null) {
      where.add('date >= ?');
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      where.add('date <= ?');
      whereArgs.add(endDate.toIso8601String());
    }
    if (type != null) {
      where.add('type = ?');
      whereArgs.add(type);
    }
    if (categoryId != null) {
      where.add('category_id = ?');
      whereArgs.add(categoryId);
    }
    if (accountId != null) {
      where.add('account_id = ?');
      whereArgs.add(accountId);
    }

    final maps = await db.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
    );
    return maps.map((m) => MoneyTransaction.fromMap(m)).toList();
  }

  Future<int> updateTransaction(MoneyTransaction oldTxn, MoneyTransaction newTxn) async {
    final db = await database;

    // Reverse old transaction's effect on balance
    final oldDelta = oldTxn.type == 'income' ? -oldTxn.amount : oldTxn.amount;
    await updateAccountBalance(oldTxn.accountId, oldDelta);

    final result = await db.update(
      'transactions',
      newTxn.toMap(),
      where: 'id = ?',
      whereArgs: [newTxn.id],
    );

    // Apply new transaction's effect on balance
    final newDelta = newTxn.type == 'income' ? newTxn.amount : -newTxn.amount;
    await updateAccountBalance(newTxn.accountId, newDelta);

    return result;
  }

  Future<int> deleteTransaction(MoneyTransaction transaction) async {
    final db = await database;

    // Reverse the transaction's effect on balance
    final delta =
        transaction.type == 'income' ? -transaction.amount : transaction.amount;
    await updateAccountBalance(transaction.accountId, delta);

    return await db.delete('transactions',
        where: 'id = ?', whereArgs: [transaction.id]);
  }

  Future<int> markTransactionReviewed(int id) async {
    final db = await database;
    return await db.update(
      'transactions',
      {'needs_review': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> markAllReviewed() async {
    final db = await database;
    return await db.update(
      'transactions',
      {'needs_review': 0},
      where: 'needs_review = 1',
    );
  }

  Future<Map<String, double>> getMonthSummary(int year, int month) async {
    final db = await database;
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0, 23, 59, 59);

    final incomeResult = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE type = ? AND date >= ? AND date <= ?',
      ['income', startDate.toIso8601String(), endDate.toIso8601String()],
    );

    final expenseResult = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE type = ? AND date >= ? AND date <= ?',
      ['expense', startDate.toIso8601String(), endDate.toIso8601String()],
    );

    final income = (incomeResult.first['total'] as num).toDouble();
    final expense = (expenseResult.first['total'] as num).toDouble();

    return {'income': income, 'expense': expense, 'net': income - expense};
  }

  Future<Map<String, double>> getPreviousMonthSummary(int year, int month) async {
    final prevMonth = month == 1 ? 12 : month - 1;
    final prevYear = month == 1 ? year - 1 : year;
    return getMonthSummary(prevYear, prevMonth);
  }

  Future<List<Map<String, dynamic>>> getCategoryBreakdown(
      int year, int month, String type) async {
    final db = await database;
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0, 23, 59, 59);

    return await db.rawQuery('''
      SELECT c.id, c.name, c.icon_name, SUM(t.amount) as total
      FROM transactions t
      JOIN categories c ON t.category_id = c.id
      WHERE t.type = ? AND t.date >= ? AND t.date <= ?
      GROUP BY c.id
      ORDER BY total DESC
    ''', [type, startDate.toIso8601String(), endDate.toIso8601String()]);
  }

  // ─── Budget CRUD ───

  Future<int> insertBudget(Budget budget) async {
    final db = await database;
    return await db.insert('budgets', budget.toMap());
  }

  Future<List<Budget>> getBudgets() async {
    final db = await database;
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1);
    final endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final maps = await db.rawQuery('''
      SELECT b.*, c.name as category_name, c.icon_name as category_icon,
        COALESCE((
          SELECT SUM(t.amount) FROM transactions t
          WHERE t.category_id = b.category_id
          AND t.type = 'expense'
          AND t.date >= ? AND t.date <= ?
        ), 0) as spent
      FROM budgets b
      JOIN categories c ON b.category_id = c.id
      ORDER BY b.created_at DESC
    ''', [startDate.toIso8601String(), endDate.toIso8601String()]);

    return maps.map((m) => Budget.fromMap(m)).toList();
  }

  Future<int> updateBudget(Budget budget) async {
    final db = await database;
    return await db.update('budgets', budget.toMap(),
        where: 'id = ?', whereArgs: [budget.id]);
  }

  Future<int> deleteBudget(int id) async {
    final db = await database;
    return await db.delete('budgets', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalBudgetUsed() async {
    final db = await database;
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1);
    final endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(spent_data.spent), 0) as total_spent,
        COALESCE(SUM(b.limit_amount), 0) as total_limit
      FROM budgets b
      LEFT JOIN (
        SELECT category_id, SUM(amount) as spent
        FROM transactions
        WHERE type = 'expense' AND date >= ? AND date <= ?
        GROUP BY category_id
      ) spent_data ON b.category_id = spent_data.category_id
    ''', [startDate.toIso8601String(), endDate.toIso8601String()]);

    final totalSpent = (result.first['total_spent'] as num).toDouble();
    final totalLimit = (result.first['total_limit'] as num).toDouble();
    if (totalLimit <= 0) return 0;
    return (totalSpent / totalLimit * 100).clamp(0, 999);
  }

  // ─── Goal CRUD ───

  Future<int> insertGoal(Goal goal) async {
    final db = await database;
    return await db.insert('goals', goal.toMap());
  }

  Future<List<Goal>> getGoals() async {
    final db = await database;
    final maps = await db.query('goals', orderBy: 'created_at DESC');
    return maps.map((m) => Goal.fromMap(m)).toList();
  }

  Future<int> updateGoal(Goal goal) async {
    final db = await database;
    return await db.update('goals', goal.toMap(),
        where: 'id = ?', whereArgs: [goal.id]);
  }

  Future<int> deleteGoal(int id) async {
    final db = await database;
    return await db.delete('goals', where: 'id = ?', whereArgs: [id]);
  }

  // ─── SMS Keywords ───

  Future<List<String>> getSmsKeywords() async {
    final db = await database;
    final maps = await db.query('sms_keywords',
        where: 'is_active = 1', orderBy: 'keyword ASC');
    return maps.map((m) => m['keyword'] as String).toList();
  }

  Future<int> addSmsKeyword(String keyword) async {
    final db = await database;
    return await db.insert(
      'sms_keywords',
      {'keyword': keyword.trim(), 'is_active': 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> removeSmsKeyword(String keyword) async {
    final db = await database;
    return await db.delete('sms_keywords',
        where: 'keyword = ?', whereArgs: [keyword]);
  }

  // ─── Export ───

  Future<List<Map<String, dynamic>>> getAllTransactionsForExport() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT t.date, t.type, t.amount, t.description, t.source,
             c.name as category, a.name as account
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      LEFT JOIN accounts a ON t.account_id = a.id
      ORDER BY t.date DESC
    ''');
  }
}
