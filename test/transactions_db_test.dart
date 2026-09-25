// Every test that touches the database belongs in this file: DbHelper is a
// singleton bound to one SQLite file, and test files run in parallel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tracker/database/db_helper.dart';
import 'package:money_tracker/models/transaction_model.dart';
import 'package:money_tracker/providers/account_provider.dart';
import 'package:money_tracker/providers/transaction_provider.dart';
import 'package:money_tracker/screens/wallet/wallet_screen.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final db = DbHelper();

  setUpAll(() async {
    sqfliteFfiInit();
    // No background isolate, so queries also complete under testWidgets'
    // fake async zone.
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.deleteDatabase(
      join(await databaseFactory.getDatabasesPath(), 'money_tracker.db'),
    );
  });

  setUp(() async {
    final database = await db.database;
    await database.delete('transactions');
    await database.update('accounts', {'balance': 0.0});
  });

  Future<int> insert(
    double amount, {
    String type = 'expense',
    DateTime? date,
    int? parentId,
    bool affectsTotal = false,
  }) {
    return db.insertTransaction(MoneyTransaction(
      amount: amount,
      type: type,
      categoryId: 1,
      accountId: 1,
      description: 'Dinner',
      date: date ?? DateTime.now(),
      parentId: parentId,
      affectsTotal: affectsTotal,
    ));
  }

  Future<double> storedBalance() async => (await db.getAccount(1))!.balance;

  test('undo brings back a deleted transaction with its sub-items and balance',
      () async {
    final parentId = await insert(300);
    final paybackId = await insert(
      100,
      type: 'income',
      parentId: parentId,
      affectsTotal: true,
    );
    final noteId = await insert(50, parentId: parentId);
    final balanceBefore = await storedBalance();

    final provider = TransactionProvider();
    await provider.loadData();

    final removed = await provider.deleteTransactions([parentId]);
    expect(await db.getTransactionById(parentId), isNull);
    expect(await db.getChildTransactions(parentId), isEmpty);
    expect(await storedBalance(), 0);

    await provider.restoreTransactions(removed);
    expect(await db.getTransactionById(parentId), isNotNull);
    expect(
      [for (final child in await db.getChildTransactions(parentId)) child.id],
      unorderedEquals([paybackId, noteId]),
    );
    expect(await storedBalance(), balanceBefore);
    expect(provider.transactions.map((t) => t.id), contains(parentId));
  });

  test('deleting drops the row at once and never shows the loading state',
      () async {
    final keptId = await insert(10);
    final deletedId = await insert(20);
    final provider = TransactionProvider();
    await provider.loadData();

    final states = <(bool, bool)>[];
    provider.addListener(() => states.add((
          provider.isLoading,
          provider.transactions.any((t) => t.id == deletedId),
        )));

    await provider.deleteTransactions([deletedId]);

    expect(states, isNotEmpty);
    expect(states.first.$2, isFalse,
        reason: 'the deleted row should be gone on the first rebuild');
    expect(states.map((s) => s.$1), everyElement(isFalse));
    expect(provider.transactions.map((t) => t.id), [keptId]);
  });

  test('duplicate scan covers every month and reports sub-item counts',
      () async {
    final lastYear = DateTime(2025, 1, 15, 9, 30);
    final firstId = await insert(75, date: lastYear);
    final secondId =
        await insert(75, date: lastYear.add(const Duration(seconds: 20)));
    await insert(75, date: lastYear.add(const Duration(minutes: 10)));
    await insert(5, parentId: secondId);

    final scan = await TransactionProvider().findSuspectedDuplicates();

    expect(
      [
        for (final group in scan.groups) [for (final t in group) t.id],
      ],
      [
        [firstId, secondId],
      ],
    );
    expect(scan.childCounts[secondId], 1);
  });

  testWidgets('swipe-delete keeps the scroll position and UNDO restores the row',
      (tester) async {
    final txnProvider = TransactionProvider();
    final accountProvider = AccountProvider();
    late int targetId;
    await tester.runAsync(() async {
      final now = DateTime.now();
      for (var i = 0; i < 30; i++) {
        final id =
            await insert(10.0 + i, date: now.subtract(Duration(minutes: i)));
        if (i == 15) targetId = id;
      }
      await txnProvider.loadData();
      await accountProvider.loadAccounts();
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: txnProvider),
        ChangeNotifierProvider.value(value: accountProvider),
      ],
      child: const MaterialApp(home: WalletScreen()),
    ));
    await tester.pump();

    final list = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    final target = find.byKey(ValueKey<int?>(targetId));
    await tester.scrollUntilVisible(target, 300, scrollable: list.first);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(list.first).position;
    final offsetBefore = position.pixels;
    expect(offsetBefore, greaterThan(0));

    // Queries finish synchronously here, so a loading state never reaches a
    // frame; on a device it swaps the list for a spinner and loses the offset.
    final loadingStates = <bool>[];
    txnProvider.addListener(() => loadingStates.add(txnProvider.isLoading));

    await tester.drag(find.byKey(Key('txn_$targetId')), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(txnProvider.transactions.map((t) => t.id), isNot(contains(targetId)));
    expect(position.pixels, offsetBefore);
    expect(find.text('UNDO'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();

    expect(txnProvider.transactions.map((t) => t.id), contains(targetId));
    expect(position.pixels, offsetBefore);
    expect(target, findsOneWidget);
    expect(loadingStates, isNotEmpty);
    expect(loadingStates, everyElement(isFalse));
  });
}
