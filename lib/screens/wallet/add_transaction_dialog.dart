import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/transaction_model.dart';
import '../../models/category.dart';
import '../../models/account.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/account_provider.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';

class AddTransactionDialog extends StatefulWidget {
  final double? prefillAmount;
  final String? prefillDescription;
  final String? prefillCategory;
  final String source;
  final MoneyTransaction? existingTransaction;
  final MoneyTransaction? parentTransaction;

  const AddTransactionDialog({
    super.key,
    this.prefillAmount,
    this.prefillDescription,
    this.prefillCategory,
    this.source = 'manual',
    this.existingTransaction,
    this.parentTransaction,
  });

  bool get isEditing => existingTransaction != null;
  bool get isSubTransaction => parentTransaction != null;

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _type = 'expense';
  int? _categoryId;
  int? _accountId;
  int? _selectedParentId;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();

    if (widget.isEditing) {
      final txn = widget.existingTransaction!;
      _amountController.text = txn.amount.toStringAsFixed(2);
      _descriptionController.text = txn.description;
      _type = txn.type;
      _categoryId = txn.categoryId;
      _accountId = txn.accountId;
      _selectedParentId = txn.parentId;
      _date = txn.date;
    } else if (widget.isSubTransaction) {
      final parent = widget.parentTransaction!;
      _type = parent.type;
      _accountId = parent.accountId;
      _date = parent.date;
    } else {
      if (widget.prefillAmount != null) {
        _amountController.text = widget.prefillAmount!.toStringAsFixed(2);
      }
      if (widget.prefillDescription != null) {
        _descriptionController.text = widget.prefillDescription!;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final accountProvider = context.read<AccountProvider>();
        setState(() {
          _accountId = accountProvider.selectedAccountId;
        });

        if (widget.prefillCategory != null) {
          final categories = context.read<TransactionProvider>().categories;
          final match = categories.where(
            (Category c) => c.name.toLowerCase() == widget.prefillCategory!.toLowerCase(),
          );
          if (match.isNotEmpty) {
            setState(() => _categoryId = match.first.id);
          }
        }
      });
    }

    // Ensure categories are fresh from DB (picks up any added in Settings)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TransactionProvider>().refreshCategories();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txnProvider = context.watch<TransactionProvider>();
    final accountProvider = context.watch<AccountProvider>();
    final categories = txnProvider.categories
        .where((Category c) => c.type == _type)
        .toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.isEditing
                            ? 'Edit Transaction'
                            : widget.isSubTransaction
                                ? 'Add Sub-Transaction'
                                : 'Add Transaction',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                if (widget.isSubTransaction) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.subdirectory_arrow_right, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Under: ${widget.parentTransaction!.description.isNotEmpty ? widget.parentTransaction!.description : "Parent transaction"}',
                            style: const TextStyle(fontSize: 13, color: AppColors.primary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),

                _buildTypeToggle(),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: 'EGP ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter an amount';
                    if (double.tryParse(v) == null) return 'Invalid number';
                    if (double.parse(v) <= 0) return 'Must be positive';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g. Lunch at KFC',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<int>(
                  value: _categoryId,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  items: categories.map<DropdownMenuItem<int>>((Category c) {
                    return DropdownMenuItem<int>(
                      value: c.id,
                      child: Row(
                        children: [
                          Icon(getCategoryIcon(c.iconName), size: 20),
                          const SizedBox(width: 8),
                          Text(c.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _categoryId = v),
                  validator: (v) => v == null ? 'Select a category' : null,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<int>(
                  value: _accountId,
                  decoration: InputDecoration(
                    labelText: 'Account',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  items: accountProvider.accounts.map((Account a) {
                    return DropdownMenuItem<int>(
                      value: a.id,
                      child: Text(a.name),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _accountId = v),
                ),
                const SizedBox(height: 12),

                if (!widget.isSubTransaction)
                  _buildParentPicker(txnProvider),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(
                    '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                  ),
                  onTap: _pickDate,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    if (widget.isEditing) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _delete,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.expense,
                            side: BorderSide(color: AppColors.expense.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: widget.isEditing ? 2 : 1,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          widget.isEditing
                              ? 'Save Changes'
                              : widget.isSubTransaction
                                  ? 'Add Sub-Item'
                                  : 'Save Transaction',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _type = 'expense';
                _categoryId = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _type == 'expense' ? AppColors.expense : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Expense',
                    style: TextStyle(
                      color: _type == 'expense' ? Colors.white : Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _type = 'income';
                _categoryId = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _type == 'income' ? AppColors.income : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Income',
                    style: TextStyle(
                      color: _type == 'income' ? Colors.white : Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentPicker(TransactionProvider txnProvider) {
    // Show top-level transactions of the same type as possible parents
    // Exclude the current transaction when editing to prevent self-reference
    final possibleParents = txnProvider.transactions.where((t) {
      if (t.parentId != null) return false;
      if (t.type != _type) return false;
      if (widget.isEditing && t.id == widget.existingTransaction!.id) return false;
      return true;
    }).toList();

    return Column(
      children: [
        DropdownButtonFormField<int?>(
          value: _selectedParentId,
          decoration: InputDecoration(
            labelText: 'Parent Transaction (optional)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[50],
            suffixIcon: _selectedParentId != null
                ? IconButton(
                    icon: Icon(Icons.clear, size: 18, color: Colors.grey[500]),
                    onPressed: () => setState(() => _selectedParentId = null),
                  )
                : null,
          ),
          isExpanded: true,
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('None (standalone)', style: TextStyle(color: Colors.grey)),
            ),
            ...possibleParents.map((t) {
              final label = t.description.isNotEmpty
                  ? t.description
                  : 'Transaction #${t.id}';
              final amountStr = CurrencyFormatter.format(t.amount);
              return DropdownMenuItem<int?>(
                value: t.id,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      amountStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: (v) => setState(() => _selectedParentId = v),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null || _accountId == null) return;

    final parentId = widget.isSubTransaction
        ? widget.parentTransaction!.id
        : _selectedParentId;

    final newTxn = MoneyTransaction(
      id: widget.existingTransaction?.id,
      amount: double.parse(_amountController.text),
      type: _type,
      categoryId: _categoryId!,
      accountId: _accountId!,
      description: _descriptionController.text.trim(),
      date: _date,
      source: widget.existingTransaction?.source ?? widget.source,
      createdAt: widget.existingTransaction?.createdAt,
      parentId: parentId,
    );

    final txnProvider = context.read<TransactionProvider>();

    if (widget.isEditing) {
      txnProvider.updateTransaction(widget.existingTransaction!, newTxn);
    } else if (parentId != null) {
      txnProvider.addSubTransaction(newTxn, parentId);
    } else {
      txnProvider.addTransaction(newTxn);
    }

    context.read<AccountProvider>().loadAccounts();
    Navigator.pop(context);
  }

  void _delete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Are you sure you want to delete this transaction?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<TransactionProvider>().deleteTransaction(widget.existingTransaction!);
              context.read<AccountProvider>().loadAccounts();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
