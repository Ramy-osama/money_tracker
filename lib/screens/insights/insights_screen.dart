import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/budget_provider.dart';
import '../../widgets/month_selector.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  @override
  Widget build(BuildContext context) {
    final txnProvider = context.watch<TransactionProvider>();
    final budgetProvider = context.watch<BudgetProvider>();

    final income = txnProvider.totalIncome;
    final expense = txnProvider.totalSpent;
    final net = txnProvider.netBalance;
    final prevNet = txnProvider.prevMonthSummary['net'] ?? 0;
    final isOverspending = expense > income && income > 0;
    final isBetter = net > prevNet;
    final total = income + expense;
    final incomePercent = total > 0 ? (income / total * 100).round() : 0;
    final expensePercent = total > 0 ? (expense / total * 100).round() : 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Month selector
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: MonthSelector(
                  selectedMonth: txnProvider.selectedMonth,
                  onPrevious: txnProvider.goToPreviousMonth,
                  onNext: txnProvider.goToNextMonth,
                  showArrows: true,
                ),
              ),
              const SizedBox(height: 16),

              // Net Balance Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (isOverspending)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber, color: Colors.red[600], size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Overspending',
                              style: TextStyle(
                                color: Colors.red[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      'Net Balance',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      CurrencyFormatter.format(net),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: net >= 0 ? AppColors.income : AppColors.expense,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isBetter ? Icons.trending_up : Icons.trending_down,
                          color: isBetter ? AppColors.income : AppColors.expense,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isBetter
                              ? 'Better than last period'
                              : 'Worse than last period',
                          style: TextStyle(
                            color: isBetter ? AppColors.income : AppColors.expense,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Income vs Expense
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _buildDot(AppColors.income),
                              const SizedBox(width: 6),
                              const Text('Income'),
                              const Spacer(),
                              _buildDot(AppColors.expense),
                              const SizedBox(width: 6),
                              const Text('Expenses'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  CurrencyFormatter.format(income),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  CurrencyFormatter.format(expense),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Row(
                              children: [
                                if (incomePercent > 0)
                                  Expanded(
                                    flex: incomePercent,
                                    child: Container(
                                      height: 8,
                                      color: AppColors.income,
                                    ),
                                  ),
                                if (expensePercent > 0)
                                  Expanded(
                                    flex: expensePercent,
                                    child: Container(
                                      height: 8,
                                      color: AppColors.expense.withValues(alpha: 0.3),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$incomePercent% in',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '$expensePercent% out',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Budget donut
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Budget',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: SizedBox(
                        height: 160,
                        width: 160,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
                              PieChartData(
                                sections: [
                                  PieChartSectionData(
                                    value: budgetProvider.totalBudgetUsed.clamp(0, 100),
                                    color: budgetProvider.totalBudgetUsed > 80
                                        ? AppColors.expense
                                        : AppColors.primary,
                                    radius: 14,
                                    showTitle: false,
                                  ),
                                  PieChartSectionData(
                                    value: (100 - budgetProvider.totalBudgetUsed).clamp(0, 100),
                                    color: Colors.grey[200],
                                    radius: 14,
                                    showTitle: false,
                                  ),
                                ],
                                centerSpaceRadius: 55,
                                sectionsSpace: 0,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${budgetProvider.totalBudgetUsed.toInt()}%',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: budgetProvider.totalBudgetUsed > 80
                                        ? AppColors.expense
                                        : AppColors.primary,
                                  ),
                                ),
                                Text(
                                  'used',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
