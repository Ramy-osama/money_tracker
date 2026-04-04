import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/transaction_model.dart';
import '../../models/category.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/account_provider.dart';
import '../../services/speech_service.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';

class MultiTransactionDialog extends StatefulWidget {
  final List<VoiceParseResult> parsedResults;

  const MultiTransactionDialog({super.key, required this.parsedResults});

  @override
  State<MultiTransactionDialog> createState() => _MultiTransactionDialogState();
}

class _MultiTransactionDialogState extends State<MultiTransactionDialog> {
  late List<_EditableTransaction> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = widget.parsedResults.map((r) => _EditableTransaction(
      amount: r.amount ?? 0,
      description: r.description ?? r.rawText,
      categoryHint: r.category,
      type: r.type,
      enabled: r.amount != null && r.amount! > 0,
    )).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _matchCategories();
    });
  }

  void _matchCategories() {
    final categories = context.read<TransactionProvider>().categories;
    setState(() {
      for (final item in _items) {
        if (item.categoryHint != null) {
          final match = categories.where((Category c) =>
            c.name.toLowerCase() == item.categoryHint!.toLowerCase() &&
            c.type == item.type
          );
          if (match.isNotEmpty) {
            item.categoryId = match.first.id;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final txnProvider = context.watch<TransactionProvider>();
    final accountProvider = context.watch<AccountProvider>();
    final enabledCount = _items.where((i) => i.enabled).length;
    final totalAmount = _items
        .where((i) => i.enabled)
        .fold<double>(0, (sum, i) => sum + i.amount);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.mic, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$enabledCount Transaction${enabledCount != 1 ? 's' : ''} Detected',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Total: ${CurrencyFormatter.format(totalAmount)}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return _buildTransactionCard(
                    index,
                    _items[index],
                    txnProvider,
                    accountProvider,
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: enabledCount > 0 && !_saving ? _saveAll : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 20),
                      label: Text(
                        _saving ? 'Saving...' : 'Add All ($enabledCount)',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(
    int index,
    _EditableTransaction item,
    TransactionProvider txnProvider,
    AccountProvider accountProvider,
  ) {
    final categories = txnProvider.categories
        .where((Category c) => c.type == item.type)
        .toList();
    final isExpense = item.type == 'expense';

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: item.enabled ? 1.0 : 0.5,
      child: Card(
        elevation: item.enabled ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: item.enabled
                ? (isExpense ? AppColors.expense : AppColors.income).withValues(alpha: 0.3)
                : Colors.grey[300]!,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: isExpense
                          ? AppColors.expense.withValues(alpha: 0.1)
                          : AppColors.income.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isExpense ? AppColors.expense : AppColors.income,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: item.enabled
                        ? TextFormField(
                            initialValue: item.description,
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Transaction name',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8,
                              ),
                            ),
                            onChanged: (v) => item.description = v,
                          )
                        : Text(
                            item.description,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: item.enabled,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => item.enabled = v),
                  ),
                ],
              ),
              if (item.enabled) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: item.amount > 0 ? item.amount.toStringAsFixed(0) : '',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixText: 'EGP ',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10,
                          ),
                        ),
                        onChanged: (v) {
                          final parsed = double.tryParse(v);
                          if (parsed != null) setState(() => item.amount = parsed);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: item.categoryId,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10,
                          ),
                        ),
                        items: categories.map<DropdownMenuItem<int>>((Category c) {
                          return DropdownMenuItem<int>(
                            value: c.id,
                            child: Text(c.name, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => item.categoryId = v),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAll() async {
    final enabled = _items.where((i) => i.enabled && i.amount > 0).toList();
    if (enabled.isEmpty) return;

    final accountProvider = context.read<AccountProvider>();
    final accountId = accountProvider.selectedAccountId ??
        (accountProvider.accounts.isNotEmpty ? accountProvider.accounts.first.id : null);

    if (accountId == null) return;

    final missing = enabled.where((i) => i.categoryId == null).toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category for all transactions')),
      );
      return;
    }

    setState(() => _saving = true);

    final txnProvider = context.read<TransactionProvider>();
    for (final item in enabled) {
      final transaction = MoneyTransaction(
        amount: item.amount,
        type: item.type,
        categoryId: item.categoryId!,
        accountId: accountId,
        description: item.description,
        date: DateTime.now(),
        source: 'voice',
      );
      await txnProvider.addTransaction(transaction);
    }

    await accountProvider.loadAccounts();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${enabled.length} transaction${enabled.length > 1 ? "s" : ""} added'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }
}

class _EditableTransaction {
  double amount;
  String description;
  String? categoryHint;
  int? categoryId;
  String type;
  bool enabled;

  _EditableTransaction({
    required this.amount,
    required this.description,
    this.categoryHint,
    this.categoryId,
    required this.type,
    required this.enabled,
  });
}
