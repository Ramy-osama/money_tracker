import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/group_order.dart';
import '../../providers/group_order_provider.dart';
import '../../utils/constants.dart';

class GroupOrderDetailSheet extends StatelessWidget {
  final GroupOrder order;

  const GroupOrderDetailSheet({super.key, required this.order});

  static Future<void> show(BuildContext context, GroupOrder order) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GroupOrderDetailSheet(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupOrderProvider>();
    final current = [...provider.activeOrders, ...provider.settledOrders]
        .where((o) => o.id == order.id)
        .firstOrNull;
    final displayOrder = current ?? order;

    final total = displayOrder.participants.length;
    final paid = displayOrder.paidCount;
    final progress = total > 0 ? paid / total : 0.0;
    final dateStr = DateFormat('MMM d, yyyy').format(displayOrder.date);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayOrder.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '\$${displayOrder.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$dateStr  ·  ${displayOrder.payerIsMe ? "I paid" : "${displayOrder.payerName} paid"}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),

                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      'PARTICIPANTS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'tap to settle',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                ...displayOrder.participants.map((p) {
                  return InkWell(
                    onTap: () {
                      provider.toggleParticipantPaid(p.id, displayOrder.id);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: p.isPaid
                            ? AppColors.income.withValues(alpha: 0.06)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            p.isPaid
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: p.isPaid
                                ? AppColors.income
                                : Colors.grey[400],
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                decoration: p.isPaid
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: p.isPaid
                                    ? Colors.grey[500]
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '\$${p.totalAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: p.isPaid
                                      ? Colors.grey[500]
                                      : AppColors.textPrimary,
                                ),
                              ),
                              if (p.isPaid && p.paidDate != null)
                                Text(
                                  'Paid ${DateFormat('MMM d').format(p.paidDate!)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.income,
                                  ),
                                )
                              else if (!p.isPaid)
                                Text(
                                  'Pending',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange[700],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Collected: \$${displayOrder.collectedAmount.toStringAsFixed(2)} / \$${displayOrder.totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 6,
                  ),
                ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Order'),
                              content: const Text(
                                  'Are you sure you want to delete this group order?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  child: const Text('Delete',
                                      style:
                                          TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && context.mounted) {
                            await provider
                                .deleteGroupOrder(displayOrder.id);
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red, size: 18),
                        label: const Text('Delete',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
