import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/budget.dart';
import '../models/goal.dart';
import '../models/group_order.dart';
import '../models/group_participant.dart';
import '../models/group_item.dart';
import '../utils/constants.dart';
import '../models/inbox_log_entry.dart';

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
      version: 7,
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
        parent_id INTEGER,
        affects_parent INTEGER NOT NULL DEFAULT 0,
        affects_total INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (account_id) REFERENCES accounts(id),
        FOREIGN KEY (parent_id) REFERENCES transactions(id) ON DELETE CASCADE
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

    await _createSmsAuxTables(db);

    await _createGroupTables(db);

    await _seedData(db);
  }

  Future<void> _createGroupTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_orders (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        total_amount REAL NOT NULL,
        payer_name TEXT NOT NULL,
        payer_is_me INTEGER NOT NULL DEFAULT 1,
        date TEXT NOT NULL,
        account_id TEXT,
        transaction_id TEXT,
        shared_costs REAL NOT NULL DEFAULT 0,
        is_settled INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_items (
        id TEXT PRIMARY KEY,
        group_order_id TEXT NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        assigned_to TEXT,
        FOREIGN KEY (group_order_id) REFERENCES group_orders(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_participants (
        id TEXT PRIMARY KEY,
        group_order_id TEXT NOT NULL,
        name TEXT NOT NULL,
        items_total REAL NOT NULL DEFAULT 0,
        shared_cost_share REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        is_paid INTEGER NOT NULL DEFAULT 0,
        paid_date TEXT,
        FOREIGN KEY (group_order_id) REFERENCES group_orders(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_contacts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        usage_count INTEGER NOT NULL DEFAULT 1,
        last_used TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN parent_id INTEGER REFERENCES transactions(id)');
    }
    if (oldVersion < 4) {
      await _createGroupTables(db);
    }
    if (oldVersion < 5) {
      await _createSmsAuxTables(db);
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN affects_parent INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN affects_total INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 6) {
      // Persistent dedup so Truecaller / re-broadcasts can't sneak past the
      // in-memory cache (e.g., after the background isolate cold-starts).
      await _addColumnIfMissing(
        db,
        table: 'sms_inbox_log',
        column: 'body_fingerprint',
        ddl: 'TEXT',
      );
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sms_inbox_log_fp_time ON sms_inbox_log(body_fingerprint, received_at)');
    }
    if (oldVersion < 7) {
      // Store the SMS's own OS timestamp so the SAME physical message can be
      // recognised across processing paths (background isolate vs. inbox poll
      // on app re-open) regardless of how much time elapsed between them.
      await _addColumnIfMissing(
        db,
        table: 'sms_inbox_log',
        column: 'sms_date',
        ddl: 'INTEGER',
      );
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sms_inbox_log_fp_smsdate ON sms_inbox_log(body_fingerprint, sms_date)');
    }
  }

  Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String column,
    required String ddl,
  }) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((c) => (c['name'] as String?) == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $ddl');
    }
  }

  Future<void> _createSmsAuxTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sms_sender_blocklist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sms_inbox_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT,
        body TEXT NOT NULL,
        received_at TEXT NOT NULL,
        was_tracked INTEGER NOT NULL DEFAULT 0,
        transaction_id INTEGER,
        matched INTEGER NOT NULL DEFAULT 0,
        blocked_sender INTEGER NOT NULL DEFAULT 0,
        body_fingerprint TEXT,
        sms_date INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sms_inbox_log_fp_time ON sms_inbox_log(body_fingerprint, received_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sms_inbox_log_fp_smsdate ON sms_inbox_log(body_fingerprint, sms_date)');
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
      WHERE account_id = ? AND (parent_id IS NULL OR affects_total = 1)
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

    if (transaction.parentId == null) {
      final delta =
          transaction.type == 'income' ? transaction.amount : -transaction.amount;
      await updateAccountBalance(transaction.accountId, delta);
    } else if (transaction.affectsTotal) {
      final delta =
          transaction.type == 'income' ? transaction.amount : -transaction.amount;
      await updateAccountBalance(transaction.accountId, delta);
    }

    return id;
  }

  /// Insert a sub-transaction. Balance updates only if [affectsTotal] is true.
  Future<int> insertSubTransaction(MoneyTransaction transaction) async {
    final db = await database;
    final id = await db.insert('transactions', transaction.toMap());
    if (transaction.affectsTotal) {
      final delta =
          transaction.type == 'income' ? transaction.amount : -transaction.amount;
      await updateAccountBalance(transaction.accountId, delta);
    }
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

  Future<MoneyTransaction?> getTransactionById(int id) async {
    final db = await database;
    final maps = await db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return MoneyTransaction.fromMap(maps.first);
  }

  Future<int> updateTransaction(MoneyTransaction oldTxn, MoneyTransaction newTxn) async {
    final db = await database;

    final reverseOld = oldTxn.parentId == null || oldTxn.affectsTotal;
    if (reverseOld) {
      final oldDelta = oldTxn.type == 'income' ? -oldTxn.amount : oldTxn.amount;
      await updateAccountBalance(oldTxn.accountId, oldDelta);
    }

    final result = await db.update(
      'transactions',
      newTxn.toMap(),
      where: 'id = ?',
      whereArgs: [newTxn.id],
    );

    final applyNew = newTxn.parentId == null || newTxn.affectsTotal;
    if (applyNew) {
      final newDelta = newTxn.type == 'income' ? newTxn.amount : -newTxn.amount;
      await updateAccountBalance(newTxn.accountId, newDelta);
    }

    return result;
  }

  Future<int> deleteTransaction(MoneyTransaction transaction) async {
    final db = await database;
    final id = transaction.id;
    if (id != null && transaction.parentId == null) {
      final children = await getChildTransactions(id);
      for (final c in children) {
        if (c.affectsTotal) {
          final delta = c.type == 'income' ? -c.amount : c.amount;
          await updateAccountBalance(c.accountId, delta);
        }
      }
    }

    if (transaction.parentId == null) {
      final delta =
          transaction.type == 'income' ? -transaction.amount : transaction.amount;
      await updateAccountBalance(transaction.accountId, delta);
    } else if (transaction.affectsTotal) {
      final delta =
          transaction.type == 'income' ? -transaction.amount : transaction.amount;
      await updateAccountBalance(transaction.accountId, delta);
    }

    if (id != null) {
      await db.delete('transactions', where: 'parent_id = ?', whereArgs: [id]);
    }
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  /// Re-inserts rows removed by [deleteTransaction] under their original ids,
  /// so SMS-log and group-order links to them stay valid, and re-applies their
  /// effect on account balances.
  Future<void> restoreTransactions(List<MoneyTransaction> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final t in rows) {
        await txn.insert('transactions', t.toMap());
        if (t.parentId == null || t.affectsTotal) {
          final delta = t.type == 'income' ? t.amount : -t.amount;
          await txn.rawUpdate(
            'UPDATE accounts SET balance = balance + ? WHERE id = ?',
            [delta, t.accountId],
          );
        }
      }
    });
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

  Future<List<MoneyTransaction>> getChildTransactions(int parentId) async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'date ASC, created_at ASC',
    );
    return maps.map((m) => MoneyTransaction.fromMap(m)).toList();
  }

  Future<int> getChildCount(int transactionId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM transactions WHERE parent_id = ?',
      [transactionId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<Map<int, int>> getChildCounts(List<int> parentIds) async {
    if (parentIds.isEmpty) return {};
    final db = await database;
    final placeholders = parentIds.map((_) => '?').join(',');
    final result = await db.rawQuery(
      'SELECT parent_id, COUNT(*) as cnt FROM transactions '
      'WHERE parent_id IN ($placeholders) GROUP BY parent_id',
      parentIds,
    );
    final counts = <int, int>{};
    for (final row in result) {
      counts[row['parent_id'] as int] = (row['cnt'] as int?) ?? 0;
    }
    return counts;
  }

  /// Signed adjustment to parent display from children with [affects_parent] set,
  /// relative to the parent's type. Batch metadata: adjustment amount and count of such sub-items.
  Future<Map<int, (double, int)>> getParentAffectData(List<int> parentIds) async {
    if (parentIds.isEmpty) return {};
    final db = await database;
    final placeholders = parentIds.map((_) => '?').join(',');
    final result = await db.rawQuery('''
      SELECT t.parent_id,
        COALESCE(SUM(
          CASE WHEN t.type = p.type THEN t.amount ELSE -t.amount END
        ), 0) AS adj,
        COUNT(*) AS cnt
      FROM transactions t
      INNER JOIN transactions p ON p.id = t.parent_id
      WHERE t.parent_id IN ($placeholders) AND t.affects_parent = 1
      GROUP BY t.parent_id
    ''', parentIds);
    final out = <int, (double, int)>{};
    for (final row in result) {
      final id = row['parent_id'] as int;
      final adj = (row['adj'] as num).toDouble();
      final cnt = (row['cnt'] as int?) ?? 0;
      out[id] = (adj, cnt);
    }
    return out;
  }

  Future<double> getParentAdjustment(int parentId) async {
    final m = await getParentAffectData([parentId]);
    return m[parentId]?.$1 ?? 0.0;
  }

  Future<Map<int, double>> getParentAdjustments(List<int> parentIds) async {
    final m = await getParentAffectData(parentIds);
    return {for (final e in m.entries) e.key: e.value.$1};
  }

  /// Sum of OPPOSITE-type children (with `affects_parent = 1`) per parent id.
  ///
  /// Used to compute the "remaining" amount of a parent transaction that is
  /// being settled by counter-type children. Returns absolute amounts:
  ///
  ///   - Expense parent + Income children → returns the income total (money
  ///     paid back so far). Remaining owed = parent.amount − total.
  ///   - Income parent + Expense children → returns the expense total (money
  ///     paid out so far). Remaining to distribute = parent.amount − total.
  ///
  /// Same-type children are excluded; they do not represent settlements.
  Future<Map<int, double>> getOppositeTypeOffsets(List<int> parentIds) async {
    if (parentIds.isEmpty) return {};
    final db = await database;
    final placeholders = parentIds.map((_) => '?').join(',');
    final result = await db.rawQuery('''
      SELECT t.parent_id,
        COALESCE(SUM(t.amount), 0) AS total
      FROM transactions t
      INNER JOIN transactions p ON p.id = t.parent_id
      WHERE t.parent_id IN ($placeholders)
        AND t.affects_parent = 1
        AND t.type <> p.type
      GROUP BY t.parent_id
    ''', parentIds);
    final out = <int, double>{};
    for (final row in result) {
      out[row['parent_id'] as int] = (row['total'] as num).toDouble();
    }
    return out;
  }

  Future<Map<String, double>> getMonthSummary(int year, int month) async {
    final db = await database;
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0, 23, 59, 59);

    final incomeResult = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE type = ? AND date >= ? AND date <= ? AND (parent_id IS NULL OR affects_total = 1)',
      ['income', startDate.toIso8601String(), endDate.toIso8601String()],
    );

    final expenseResult = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE type = ? AND date >= ? AND date <= ? AND (parent_id IS NULL OR affects_total = 1)',
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
      WHERE t.type = ? AND t.date >= ? AND t.date <= ? AND (t.parent_id IS NULL OR t.affects_total = 1)
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
          AND (t.parent_id IS NULL OR t.affects_total = 1)
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
        WHERE type = 'expense' AND date >= ? AND date <= ? AND (parent_id IS NULL OR affects_total = 1)
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

  String _normalizeSenderKey(String? sender) {
    if (sender == null) return '';
    return sender.trim().toLowerCase();
  }

  Future<bool> isSenderBlocked(String? sender) async {
    final key = _normalizeSenderKey(sender);
    if (key.isEmpty) return false;
    final db = await database;
    final rows = await db.query(
      'sms_sender_blocklist',
      where: 'lower(trim(sender)) = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<String>> getBlockedSenders() async {
    final db = await database;
    final maps = await db.query('sms_sender_blocklist',
        orderBy: 'created_at DESC');
    return maps.map((m) => m['sender'] as String).toList();
  }

  Future<int> addBlockedSender(String sender) async {
    final db = await database;
    final key = _normalizeSenderKey(sender);
    if (key.isEmpty) return 0;
    return await db.insert(
      'sms_sender_blocklist',
      {
        'sender': key,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> removeBlockedSender(String sender) async {
    final db = await database;
    return await db.delete(
      'sms_sender_blocklist',
      where: 'lower(trim(sender)) = ?',
      whereArgs: [_normalizeSenderKey(sender)],
    );
  }

  Future<void> logIncomingSms({
    String? sender,
    required String body,
    required bool wasTracked,
    int? transactionId,
    required bool matched,
    bool blockedSender = false,
    String? receivedAt,
    String? bodyFingerprint,
    int? smsDate,
  }) async {
    final db = await database;
    final at = receivedAt ?? DateTime.now().toIso8601String();
    await db.insert('sms_inbox_log', {
      'sender': sender == null || sender.isEmpty ? '' : sender,
      'body': body,
      'received_at': at,
      'was_tracked': wasTracked ? 1 : 0,
      'transaction_id': transactionId,
      'matched': matched ? 1 : 0,
      'blocked_sender': blockedSender ? 1 : 0,
      'body_fingerprint': bodyFingerprint,
      'sms_date': smsDate,
    });
    final countRow = await db.rawQuery('SELECT COUNT(*) as c FROM sms_inbox_log');
    final c = (countRow.first['c'] as int?) ?? 0;
    if (c > 200) {
      final toDelete = c - 200;
      await db.rawDelete(
        'DELETE FROM sms_inbox_log WHERE id IN (SELECT id FROM sms_inbox_log ORDER BY id ASC LIMIT ?)',
        [toDelete],
      );
    }
  }

  /// Returns the transaction id of the most recent SMS that was successfully
  /// tracked AND has the given fingerprint AND was received within
  /// [withinSeconds] of [now]. Used to detect Truecaller / re-broadcast
  /// duplicates that present the same financial content with a slightly
  /// different SMS body.
  ///
  /// Returns `null` if no such recent duplicate exists.
  Future<int?> findRecentTrackedTransactionByFingerprint({
    required String fingerprint,
    required int withinSeconds,
    DateTime? now,
  }) async {
    if (fingerprint.isEmpty) return null;
    final db = await database;
    final ref = (now ?? DateTime.now()).toUtc();
    final cutoff = ref.subtract(Duration(seconds: withinSeconds));
    // We compare ISO8601 strings lexicographically — only safe when both
    // sides are in UTC (Z suffix) or both in local with the same offset.
    // We persist whatever the caller supplied (typically local time without
    // offset), so use a wider numeric comparison via julianday for safety.
    final rows = await db.rawQuery(
      '''
      SELECT transaction_id
      FROM sms_inbox_log
      WHERE body_fingerprint = ?
        AND was_tracked = 1
        AND transaction_id IS NOT NULL
        AND julianday(received_at) >= julianday(?)
      ORDER BY id DESC
      LIMIT 1
      ''',
      [fingerprint, cutoff.toIso8601String()],
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['transaction_id'];
    if (raw is int) return raw;
    return null;
  }

  /// Returns the transaction id of an already-tracked SMS that is the SAME
  /// physical message as the incoming one, identified by an exact match on
  /// both the content [fingerprint] and the SMS's own OS timestamp [smsDate].
  ///
  /// Unlike [findRecentTrackedTransactionByFingerprint], this is NOT time
  /// windowed: the SMS timestamp is assigned once by the OS and is identical
  /// whether the message is first seen by the background isolate (app killed)
  /// or re-read later by the inbox poll (app re-opened). This is what stops a
  /// message detected in the background from being saved a second time when
  /// the app is opened — even hours later.
  ///
  /// Two genuinely separate purchases produce different SMS timestamps, so
  /// this never collapses real repeat transactions.
  ///
  /// Returns `null` if this exact message was not previously tracked.
  Future<int?> findTrackedTransactionBySmsIdentity({
    required String fingerprint,
    required int smsDate,
  }) async {
    if (fingerprint.isEmpty) return null;
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT transaction_id
      FROM sms_inbox_log
      WHERE body_fingerprint = ?
        AND sms_date = ?
        AND was_tracked = 1
        AND transaction_id IS NOT NULL
      ORDER BY id DESC
      LIMIT 1
      ''',
      [fingerprint, smsDate],
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['transaction_id'];
    if (raw is int) return raw;
    return null;
  }

  Future<List<InboxLogEntry>> getRecentInboxLog({int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'sms_inbox_log',
      orderBy: 'id DESC',
      limit: limit,
    );
    return maps.map((m) => InboxLogEntry.fromMap(m)).toList();
  }

  // ─── Group Order CRUD ───

  Future<void> insertGroupOrder(GroupOrder order) async {
    final db = await database;
    await db.insert('group_orders', order.toMap());
    for (final item in order.items) {
      await db.insert('group_items', item.toMap());
    }
    for (final participant in order.participants) {
      await db.insert('group_participants', participant.toMap());
    }
  }

  Future<List<GroupOrder>> getGroupOrders({bool? settled}) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;
    if (settled != null) {
      where = 'is_settled = ?';
      whereArgs = [settled ? 1 : 0];
    }
    final orderMaps = await db.query(
      'group_orders',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date DESC, created_at DESC',
    );

    final orders = <GroupOrder>[];
    for (final map in orderMaps) {
      final orderId = map['id'] as String;
      final participants = await _getParticipantsForOrder(db, orderId);
      final items = await _getItemsForOrder(db, orderId);
      orders.add(GroupOrder.fromMap(map, participants: participants, items: items));
    }
    return orders;
  }

  Future<List<GroupParticipant>> _getParticipantsForOrder(Database db, String orderId) async {
    final maps = await db.query(
      'group_participants',
      where: 'group_order_id = ?',
      whereArgs: [orderId],
      orderBy: 'name ASC',
    );
    return maps.map((m) => GroupParticipant.fromMap(m)).toList();
  }

  Future<List<GroupItem>> _getItemsForOrder(Database db, String orderId) async {
    final maps = await db.query(
      'group_items',
      where: 'group_order_id = ?',
      whereArgs: [orderId],
      orderBy: 'name ASC',
    );
    return maps.map((m) => GroupItem.fromMap(m)).toList();
  }

  Future<void> updateGroupOrder(GroupOrder order) async {
    final db = await database;
    await db.update('group_orders', order.toMap(),
        where: 'id = ?', whereArgs: [order.id]);
  }

  Future<void> deleteGroupOrder(String orderId) async {
    final db = await database;
    await db.delete('group_items', where: 'group_order_id = ?', whereArgs: [orderId]);
    await db.delete('group_participants', where: 'group_order_id = ?', whereArgs: [orderId]);
    await db.delete('group_orders', where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> updateParticipant(GroupParticipant participant) async {
    final db = await database;
    await db.update('group_participants', participant.toMap(),
        where: 'id = ?', whereArgs: [participant.id]);
  }

  Future<bool> areAllParticipantsPaid(String orderId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM group_participants WHERE group_order_id = ? AND is_paid = 0',
      [orderId],
    );
    return (result.first['cnt'] as int) == 0;
  }

  Future<void> markOrderSettled(String orderId, bool settled) async {
    final db = await database;
    await db.update('group_orders', {'is_settled': settled ? 1 : 0},
        where: 'id = ?', whereArgs: [orderId]);
  }

  // ─── Saved Contacts ───

  Future<List<String>> getSavedContacts() async {
    final db = await database;
    final maps = await db.query('saved_contacts',
        orderBy: 'usage_count DESC, last_used DESC');
    return maps.map((m) => m['name'] as String).toList();
  }

  Future<void> upsertSavedContact(String name, String contactId) async {
    final db = await database;
    final existing = await db.query('saved_contacts',
        where: 'name = ?', whereArgs: [name]);

    if (existing.isEmpty) {
      await db.insert('saved_contacts', {
        'id': contactId,
        'name': name,
        'usage_count': 1,
        'last_used': DateTime.now().toIso8601String(),
      });
    } else {
      await db.rawUpdate(
        'UPDATE saved_contacts SET usage_count = usage_count + 1, last_used = ? WHERE name = ?',
        [DateTime.now().toIso8601String(), name],
      );
    }
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
