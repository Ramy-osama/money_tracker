import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../models/category.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';

class TransactionTile extends StatelessWidget {
  final MoneyTransaction transaction;
  final Category? category;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onMarkReviewed;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.category,
    this.onTap,
    this.onDelete,
    this.onMarkReviewed,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == 'expense';
    final amountColor = isExpense ? AppColors.expense : AppColors.income;
    final sign = isExpense ? '-' : '+';
    final needsReview = transaction.needsReview;

    return Dismissible(
      key: Key('txn_${transaction.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red[400],
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete?.call(),
      child: Container(
        decoration: needsReview
            ? BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                border: Border(
                  left: BorderSide(color: Colors.amber[700]!, width: 4),
                ),
              )
            : null,
        child: ListTile(
          onTap: needsReview ? onMarkReviewed : onTap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: needsReview
                  ? Colors.amber.withValues(alpha: 0.15)
                  : (isExpense ? Colors.red : Colors.green)
                      .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              needsReview
                  ? Icons.rate_review_outlined
                  : getCategoryIcon(category?.iconName ?? 'more_horiz'),
              color: needsReview
                  ? Colors.amber[700]
                  : (isExpense ? Colors.red[400] : Colors.green[600]),
              size: 22,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  transaction.description.isNotEmpty
                      ? transaction.description
                      : (category?.name ?? 'Transaction'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (needsReview)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber[700],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'REVIEW',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              Text(
                category?.name ?? '',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              if (transaction.source != 'manual') ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    transaction.source.toUpperCase(),
                    style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  ),
                ),
              ],
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${CurrencyFormatter.format(transaction.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: amountColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormatter.formatDate(transaction.date),
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
