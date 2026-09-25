import 'package:flutter_test/flutter_test.dart';
import 'package:money_tracker/models/transaction_model.dart';
import 'package:money_tracker/services/duplicate_detector.dart';

final _base = DateTime(2026, 9, 20, 13);

MoneyTransaction _txn(
  int id, {
  int seconds = 0,
  double amount = 120,
  String description = 'Carrefour',
  String type = 'expense',
  int categoryId = 1,
  int? parentId,
  bool needsReview = false,
}) {
  return MoneyTransaction(
    id: id,
    amount: amount,
    type: type,
    categoryId: categoryId,
    accountId: 1,
    description: description,
    date: _base.add(Duration(seconds: seconds)),
    parentId: parentId,
    needsReview: needsReview,
  );
}

List<List<int?>> _ids(List<List<MoneyTransaction>> groups) => [
      for (final group in groups) [for (final t in group) t.id],
    ];

List<List<int?>> _find(List<MoneyTransaction> transactions) =>
    _ids(DuplicateDetector.findGroups(transactions));

void main() {
  group('DuplicateDetector.findGroups', () {
    test('flags the same title and amount within a minute', () {
      expect(_find([_txn(1), _txn(2, seconds: 30)]), [
        [1, 2],
      ]);
    });

    test('a gap of exactly one minute counts, a longer one does not', () {
      expect(_find([_txn(1), _txn(2, seconds: 60)]), [
        [1, 2],
      ]);
      expect(_find([_txn(1), _txn(2, seconds: 61)]), isEmpty);
    });

    test('requires the same amount, type and title', () {
      expect(_find([_txn(1), _txn(2, amount: 121)]), isEmpty);
      expect(_find([_txn(1), _txn(2, type: 'income')]), isEmpty);
      expect(_find([_txn(1), _txn(2, description: 'Spinneys')]), isEmpty);
    });

    test('title match ignores case and extra spaces', () {
      expect(
        _find([
          _txn(1, description: 'Uber  Trip'),
          _txn(2, description: ' uber trip '),
        ]),
        [
          [1, 2],
        ],
      );
    });

    test('blank titles fall back to comparing the category', () {
      expect(
        _find([_txn(1, description: ''), _txn(2, description: '')]),
        [
          [1, 2],
        ],
      );
      expect(
        _find([
          _txn(1, description: ''),
          _txn(2, description: '', categoryId: 2),
        ]),
        isEmpty,
      );
    });

    test('amounts equal to the cent match despite floating point noise', () {
      expect(_find([_txn(1, amount: 0.1 + 0.2), _txn(2, amount: 0.3)]), [
        [1, 2],
      ]);
    });

    test('chains copies that are each within a minute of the previous one',
        () {
      expect(
        _find([_txn(3, seconds: 100), _txn(1), _txn(2, seconds: 50)]),
        [
          [1, 2, 3],
        ],
      );
    });

    test('ignores sub-transactions', () {
      expect(_find([_txn(1), _txn(2, seconds: 5, parentId: 1)]), isEmpty);
    });

    test('lists the newest group first', () {
      expect(
        _find([
          _txn(1),
          _txn(2, seconds: 10),
          _txn(3, seconds: 3600, description: 'Uber'),
          _txn(4, seconds: 3610, description: 'Uber'),
        ]),
        [
          [3, 4],
          [1, 2],
        ],
      );
    });
  });

  group('DuplicateDetector.pickKeeper', () {
    test('keeps the copy that has sub-items', () {
      final group = [_txn(1), _txn(2, seconds: 10)];
      expect(DuplicateDetector.pickKeeper(group, {2: 3}).id, 2);
    });

    test('then prefers a copy that was already reviewed', () {
      final group = [_txn(1, needsReview: true), _txn(2, seconds: 10)];
      expect(DuplicateDetector.pickKeeper(group, const {}).id, 2);
    });

    test('otherwise keeps the oldest copy', () {
      final group = [_txn(1), _txn(2, seconds: 10)];
      expect(DuplicateDetector.pickKeeper(group, const {}).id, 1);
    });
  });
}
