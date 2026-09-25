import '../models/transaction_model.dart';

/// Finds transactions that look like the same payment recorded more than once.
class DuplicateDetector {
  /// Largest gap between two copies of the same payment.
  static const Duration window = Duration(minutes: 1);

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Groups top-level [transactions] that share type, amount (to the cent) and
  /// title, where each copy is within [window] of the previous one. A blank
  /// description is matched by category instead, because that is the title
  /// the transaction list shows for it.
  ///
  /// Groups are returned newest first; each group is ordered oldest first.
  static List<List<MoneyTransaction>> findGroups(
    Iterable<MoneyTransaction> transactions,
  ) {
    final buckets = <(String, int, String, int?), List<MoneyTransaction>>{};
    for (final t in transactions) {
      if (t.id == null || t.parentId != null) continue;
      buckets.putIfAbsent(_matchKey(t), () => []).add(t);
    }

    final groups = <List<MoneyTransaction>>[];
    for (final bucket in buckets.values) {
      if (bucket.length < 2) continue;
      bucket.sort(_oldestFirst);
      var current = [bucket.first];
      for (final t in bucket.skip(1)) {
        if (t.date.difference(current.last.date) <= window) {
          current.add(t);
        } else {
          if (current.length > 1) groups.add(current);
          current = [t];
        }
      }
      if (current.length > 1) groups.add(current);
    }

    groups.sort((a, b) => _oldestFirst(b.last, a.last));
    return groups;
  }

  /// The copy to keep from [group]: the one with the most sub-items, then one
  /// that was already reviewed, then the oldest.
  static MoneyTransaction pickKeeper(
    List<MoneyTransaction> group,
    Map<int, int> childCounts,
  ) {
    final ranked = [...group]
      ..sort((a, b) {
        final bySubItems =
            (childCounts[b.id] ?? 0).compareTo(childCounts[a.id] ?? 0);
        if (bySubItems != 0) return bySubItems;
        if (a.needsReview != b.needsReview) return a.needsReview ? 1 : -1;
        return _oldestFirst(a, b);
      });
    return ranked.first;
  }

  static (String, int, String, int?) _matchKey(MoneyTransaction t) {
    final title =
        t.description.trim().toLowerCase().replaceAll(_whitespace, ' ');
    return (
      t.type,
      (t.amount * 100).round(),
      title,
      title.isEmpty ? t.categoryId : null,
    );
  }

  static int _oldestFirst(MoneyTransaction a, MoneyTransaction b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    final byCreated = a.createdAt.compareTo(b.createdAt);
    if (byCreated != 0) return byCreated;
    return (a.id ?? 0).compareTo(b.id ?? 0);
  }
}
