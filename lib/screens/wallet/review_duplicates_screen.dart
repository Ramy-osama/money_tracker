import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/account.dart';
import '../../models/transaction_model.dart';
import '../../providers/account_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/duplicate_detector.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/delete_with_undo.dart';

class ReviewDuplicatesScreen extends StatefulWidget {
  const ReviewDuplicatesScreen({super.key});

  @override
  State<ReviewDuplicatesScreen> createState() => _ReviewDuplicatesScreenState();
}

class _ReviewDuplicatesScreenState extends State<ReviewDuplicatesScreen> {
  final _timeFmt = DateFormat('EEE, MMM d yyyy · HH:mm:ss');
  List<List<MoneyTransaction>>? _groups;
  Map<int, int> _childCounts = const {};
  final Set<int> _selected = {};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    if (!mounted) return;
    final scan =
        await context.read<TransactionProvider>().findSuspectedDuplicates();
    if (!mounted) return;
    setState(() {
      _groups = scan.groups;
      _childCounts = scan.childCounts;
      _selected.clear();
      for (final group in scan.groups) {
        final keeper = DuplicateDetector.pickKeeper(group, scan.childCounts);
        _selected.addAll([
          for (final t in group)
            if (t.id != keeper.id) t.id!,
        ]);
      }
    });
  }

  Future<void> _deleteSelected() async {
    setState(() => _deleting = true);
    try {
      await deleteTransactionsWithUndo(
        context,
        _selected.toList(),
        onUndone: _scan,
      );
      await _scan();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Review Duplicates'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _deleting ? null : _scan,
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan again',
          ),
        ],
      ),
      body: groups == null
          ? const Center(child: CircularProgressIndicator())
          : groups.isEmpty
              ? _buildEmpty()
              : _buildGroups(groups),
      bottomNavigationBar:
          groups == null || groups.isEmpty ? null : _buildDeleteBar(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 64, color: AppColors.income),
            const SizedBox(height: 16),
            const Text(
              'No suspected duplicates',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Transactions with the same title and amount recorded within a '
              'minute of each other show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroups(List<List<MoneyTransaction>> groups) {
    final txnProvider = context.watch<TransactionProvider>();
    final accounts = context.watch<AccountProvider>().accounts;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            'Same title and amount, recorded within a minute of each other. '
            "Checked transactions will be deleted — uncheck any that aren't "
            'duplicates.',
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
        ),
        for (final group in groups) _buildGroupCard(group, txnProvider, accounts),
      ],
    );
  }

  Widget _buildGroupCard(
    List<MoneyTransaction> group,
    TransactionProvider txnProvider,
    List<Account> accounts,
  ) {
    final first = group.first;
    final category = txnProvider.getCategoryById(first.categoryId);
    final isExpense = first.type == 'expense';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    first.description.isNotEmpty
                        ? first.description
                        : (category?.name ?? 'Transaction'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${isExpense ? '-' : '+'}${CurrencyFormatter.format(first.amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isExpense ? AppColors.expense : AppColors.income,
                  ),
                ),
              ],
            ),
          ),
          for (final t in group) _buildRow(t, txnProvider, accounts),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildRow(
    MoneyTransaction t,
    TransactionProvider txnProvider,
    List<Account> accounts,
  ) {
    final selected = _selected.contains(t.id);
    final subItems = _childCounts[t.id] ?? 0;
    final account = accounts.where((a) => a.id == t.accountId).firstOrNull;
    final details = [
      txnProvider.getCategoryById(t.categoryId)?.name ?? 'Uncategorized',
      if (accounts.length > 1 && account != null) account.name,
      t.source.toUpperCase(),
      if (t.needsReview) 'Not reviewed',
      if (subItems > 0)
        '$subItems sub-item${subItems == 1 ? '' : 's'}'
            '${selected ? ' (deleted too)' : ''}',
    ];

    return CheckboxListTile(
      value: selected,
      onChanged: _deleting
          ? null
          : (checked) => setState(() {
                if (checked == true) {
                  _selected.add(t.id!);
                } else {
                  _selected.remove(t.id);
                }
              }),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppColors.expense,
      dense: true,
      title: Text(
        _timeFmt.format(t.date),
        style: TextStyle(
          fontSize: 14,
          decoration: selected ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(details.join(' · ')),
    );
  }

  Widget _buildDeleteBar() {
    final count = _selected.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: count == 0 || _deleting ? null : _deleteSelected,
          icon: const Icon(Icons.delete_outline),
          label: Text('Delete $count selected'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.expense,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}
