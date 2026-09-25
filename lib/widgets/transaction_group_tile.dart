import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../models/category.dart';
import '../providers/transaction_provider.dart';
import '../utils/constants.dart';
import '../utils/currency_formatter.dart';
import 'transaction_tile.dart';

class TransactionGroupTile extends StatefulWidget {
  final MoneyTransaction transaction;
  final Category? category;
  final int childCount;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onMarkReviewed;
  final void Function(MoneyTransaction parent)? onAddSubTransaction;
  final void Function(MoneyTransaction parent)? onBreakDown;
  final void Function(MoneyTransaction child, MoneyTransaction parent)? onEditSubTransaction;

  const TransactionGroupTile({
    super.key,
    required this.transaction,
    this.category,
    this.childCount = 0,
    this.onTap,
    this.onDelete,
    this.onMarkReviewed,
    this.onAddSubTransaction,
    this.onBreakDown,
    this.onEditSubTransaction,
  });

  @override
  State<TransactionGroupTile> createState() => _TransactionGroupTileState();
}

class _TransactionGroupTileState extends State<TransactionGroupTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  List<MoneyTransaction>? _children;
  bool _loadingChildren = false;

  late final AnimationController _animController;
  late final Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TransactionGroupTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new instance means the provider re-read the database, so the cached
    // sub-items may be stale.
    if (identical(oldWidget.transaction, widget.transaction)) return;
    if (!_expanded) {
      _children = null;
    } else if (widget.childCount == 0) {
      _expanded = false;
      _children = null;
      _animController.value = 0;
    } else {
      _reloadChildren();
    }
  }

  Future<void> _reloadChildren() async {
    final children = await context
        .read<TransactionProvider>()
        .getChildTransactions(widget.transaction.id!);
    if (!mounted) return;
    setState(() => _children = children);
  }

  Future<void> _toggleExpand() async {
    if (widget.childCount == 0) return;

    if (_expanded) {
      _animController.reverse();
      setState(() => _expanded = false);
      return;
    }

    if (_children == null) {
      setState(() => _loadingChildren = true);
      final provider = context.read<TransactionProvider>();
      final children =
          await provider.getChildTransactions(widget.transaction.id!);
      if (!mounted) return;
      setState(() {
        _children = children;
        _loadingChildren = false;
        _expanded = true;
      });
    } else {
      setState(() => _expanded = true);
    }
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.childCount > 0;
    final provider = context.watch<TransactionProvider>();
    final id = widget.transaction.id;
    final adj = id != null ? provider.parentAdjustmentFor(id) : 0.0;
    final affectSubCount = id != null ? provider.affectsParentSubItemCountFor(id) : 0;
    final parentIsExpense = widget.transaction.type == 'expense';
    final Color adjLineColor;
    if (parentIsExpense) {
      adjLineColor = adj > 0 ? AppColors.expense : AppColors.income;
    } else {
      adjLineColor = adj > 0 ? AppColors.income : AppColors.expense;
    }

    final hasOppositeChildren = provider.hasOppositeTypeChildren(widget.transaction);
    final remaining = provider.remainingFor(widget.transaction);
    final settled = provider.isSettled(widget.transaction);
    final collected =
        id != null ? provider.oppositeTypeOffsetFor(id) : 0.0;
    final showSameTypeAdjOnly =
        adj != 0 && affectSubCount > 0 && !hasOppositeChildren && id != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            TransactionTile(
              transaction: widget.transaction,
              category: widget.category,
              onTap: widget.transaction.needsReview
                  ? widget.onMarkReviewed
                  : widget.onTap,
              onDelete: widget.onDelete,
              onMarkReviewed: widget.onMarkReviewed,
            ),
            if (hasChildren)
              Positioned(
                left: 8,
                bottom: 4,
                child: GestureDetector(
                  onTap: _toggleExpand,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${widget.childCount} sub',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!hasChildren && !widget.transaction.needsReview)
              Positioned(
                right: 8,
                bottom: 4,
                child: _buildActionChips(),
              ),
          ],
        ),
        if (hasOppositeChildren && id != null)
          _buildSettlementSummary(
            parentIsExpense: parentIsExpense,
            collected: collected,
            remaining: remaining,
            settled: settled,
          ),
        if (showSameTypeAdjOnly)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  adj > 0
                      ? '+${CurrencyFormatter.format(adj)} from $affectSubCount sub-item${affectSubCount == 1 ? '' : 's'}'
                      : '−${CurrencyFormatter.format(adj.abs())} from $affectSubCount sub-item${affectSubCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: adjLineColor,
                  ),
                ),
              ],
            ),
          ),
        if (hasChildren && !widget.transaction.needsReview)
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildSmallAction(
                  Icons.add_circle_outline,
                  'Add Sub',
                  () => widget.onAddSubTransaction?.call(widget.transaction),
                ),
              ],
            ),
          ),
        SizeTransition(
          sizeFactor: _expandAnimation,
          child: _buildChildList(),
        ),
      ],
    );
  }

  /// Compact two-line summary that shows progress toward settling a parent
  /// transaction with opposite-type children. Communicates at a glance:
  ///   - For an expense parent: how much has been paid back, how much owed.
  ///   - For an income parent: how much has been distributed, how much left.
  /// When fully covered, shows a green SETTLED pill instead of the remaining row.
  Widget _buildSettlementSummary({
    required bool parentIsExpense,
    required double collected,
    required double remaining,
    required bool settled,
  }) {
    final parentAmount = widget.transaction.amount;
    // Cap collected at parentAmount for the progress bar (overpayment shown in label).
    final progressValue = parentAmount <= 0
        ? 0.0
        : (collected / parentAmount).clamp(0.0, 1.0).toDouble();

    final remainingLabel = parentIsExpense ? 'Owed to me' : 'To distribute';
    final collectedLabel = parentIsExpense ? 'Paid back' : 'Paid out';
    final settlementColor =
        parentIsExpense ? AppColors.income : AppColors.expense;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: settled
              ? AppColors.income.withValues(alpha: 0.08)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: settled
                ? AppColors.income.withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  settled
                      ? Icons.check_circle
                      : (parentIsExpense
                          ? Icons.savings_outlined
                          : Icons.outbox_outlined),
                  size: 16,
                  color: settled ? AppColors.income : settlementColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    settled
                        ? 'Settled · ${CurrencyFormatter.format(collected)} $collectedLabel'
                        : '$collectedLabel ${CurrencyFormatter.format(collected)} of ${CurrencyFormatter.format(parentAmount)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: settled ? AppColors.income : Colors.grey[800],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!settled)
                  Text(
                    '$remainingLabel · ${CurrencyFormatter.format(remaining)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: settlementColor,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.income,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'SETTLED',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progressValue,
                minHeight: 4,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  settled ? AppColors.income : settlementColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChips() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSmallAction(
          Icons.call_split,
          'Break Down',
          () => widget.onBreakDown?.call(widget.transaction),
        ),
      ],
    );
  }

  Widget _buildSmallAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.grey[600]),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildList() {
    if (_loadingChildren) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_children == null || _children!.isEmpty) {
      return const SizedBox.shrink();
    }

    final provider = context.read<TransactionProvider>();

    return Container(
      margin: const EdgeInsets.only(left: 32, right: 8, bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _children!.map((child) {
          final category = provider.getCategoryById(child.categoryId);
          return _ChildTransactionTile(
            transaction: child,
            category: category,
            onTap: () => widget.onEditSubTransaction?.call(child, widget.transaction),
          );
        }).toList(),
      ),
    );
  }
}

class _ChildTransactionTile extends StatelessWidget {
  final MoneyTransaction transaction;
  final Category? category;
  final VoidCallback? onTap;

  const _ChildTransactionTile({
    required this.transaction,
    this.category,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == 'expense';
    final amountColor = isExpense ? AppColors.expense : AppColors.income;
    final sign = isExpense ? '-' : '+';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: (isExpense ? Colors.red : Colors.green)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  getCategoryIcon(category?.iconName ?? 'more_horiz'),
                  color: isExpense ? Colors.red[300] : Colors.green[400],
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.description.isNotEmpty
                          ? transaction.description
                          : (category?.name ?? 'Sub-item'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      category?.name ?? '',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              if (transaction.affectsParent)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Tooltip(
                    message: 'Affects parent',
                    child: Icon(
                      Icons.swap_vert,
                      size: 15,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              if (transaction.affectsTotal)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'Affects total',
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 15,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              Text(
                '$sign${CurrencyFormatter.format(transaction.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: amountColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
