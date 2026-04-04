import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../models/category.dart';
import '../../models/transaction_model.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/account_provider.dart';
import '../../services/notification_service.dart';
import '../../services/speech_service.dart';
import '../../services/sms_service.dart';
import '../../services/sms_parser.dart';
import '../../widgets/month_selector.dart';
import '../../widgets/account_card.dart';
import '../../widgets/transaction_tile.dart';
import '../../utils/constants.dart';
import '../../utils/currency_formatter.dart';
import 'add_transaction_dialog.dart';
import 'multi_transaction_dialog.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final SpeechService _speechService = SpeechService();
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _setupSmsListener();
  }

  void _setupSmsListener() {
    final smsService = SmsService();
    smsService.onTransactionDetected = (SmsParseResult result) {
      if (!mounted) return;
      _autoSaveSmsTransaction(result);
    };
  }

  Future<void> _autoSaveSmsTransaction(SmsParseResult result) async {
    if (result.amount == null || result.amount! <= 0) return;

    final txnProvider = context.read<TransactionProvider>();
    final accountProvider = context.read<AccountProvider>();

    final accounts = accountProvider.accounts;
    if (accounts.isEmpty) return;

    // Find a default category for the transaction type
    final categories = txnProvider.categories;
    final targetType = result.type;
    final matchingCategories =
        categories.where((Category c) => c.type == targetType).toList();
    final categoryId = matchingCategories.isNotEmpty
        ? matchingCategories.first.id!
        : categories.first.id!;

    final description = result.merchant ??
        result.rawBody.substring(
          0,
          result.rawBody.length > 50 ? 50 : result.rawBody.length,
        );

    final transaction = MoneyTransaction(
      amount: result.amount!,
      type: targetType,
      categoryId: categoryId,
      accountId: accounts.first.id!,
      description: description,
      date: DateTime.now(),
      source: 'sms',
      needsReview: true,
    );

    await txnProvider.addTransaction(transaction);
    await accountProvider.loadAccounts();

    NotificationService().showSmsTransactionNotification(
      amount: result.amount!,
      merchant: result.merchant,
      type: targetType,
    );
  }

  Future<void> _startVoiceInput() async {
    final ready = await _speechService.initialize();
    if (!ready) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Microphone permission denied. Please enable it in Settings > Apps > Money Tracker > Permissions.',
          ),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'SETTINGS',
            textColor: Colors.white,
            onPressed: () => openAppSettings(),
          ),
        ),
      );
      return;
    }

    setState(() => _isRecording = true);
    await _speechService.startListening(
      onResult: (text) {
        if (!mounted) return;
        setState(() => _isRecording = false);

        if (text.trim().isEmpty) return;

        final results = SpeechService.parseMultiVoiceInput(text);

        if (results.length > 1) {
          showDialog(
            context: context,
            builder: (_) => MultiTransactionDialog(parsedResults: results),
          );
        } else {
          final parsed = results.first;
          showDialog(
            context: context,
            builder: (_) => AddTransactionDialog(
              prefillAmount: parsed.amount,
              prefillDescription: parsed.description,
              prefillCategory: parsed.category,
              source: 'voice',
            ),
          );
        }
      },
    );
  }

  Future<void> _stopVoiceInput() async {
    await _speechService.stopListening();
    if (mounted) {
      setState(() => _isRecording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txnProvider = context.watch<TransactionProvider>();
    final accountProvider = context.watch<AccountProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () async {
          await txnProvider.loadData();
          await accountProvider.loadAccounts();
        },
        child: CustomScrollView(
          slivers: [
            _buildHeader(txnProvider),
            if (accountProvider.accounts.isNotEmpty)
              SliverToBoxAdapter(
                child: AccountCard(
                  account: accountProvider.selectedAccount ??
                      accountProvider.accounts.first,
                ),
              ),
            _buildTransactionHeader(txnProvider),
            _buildTransactionList(txnProvider),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isRecording ? _stopVoiceInput : _startVoiceInput,
        backgroundColor: _isRecording ? AppColors.expense : Colors.white,
        elevation: 4,
        child: Icon(
          _isRecording ? Icons.stop : Icons.mic,
          color: _isRecording ? Colors.white : AppColors.primary,
          size: 28,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader(TransactionProvider provider) {
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.headerGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              children: [
                MonthSelector(
                  selectedMonth: provider.selectedMonth,
                  onPrevious: provider.goToPreviousMonth,
                  onNext: provider.goToNextMonth,
                  textColor: Colors.white,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSummaryColumn(
                      'SPENT',
                      CurrencyFormatter.format(provider.totalSpent),
                      Colors.white,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    _buildSummaryColumn(
                      'INCOME',
                      CurrencyFormatter.format(provider.totalIncome),
                      Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'THIS MONTH  ${CurrencyFormatter.formatSigned(provider.netBalance)}  ${provider.netBalance >= 0 ? '📈' : '📉'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryColumn(String label, String amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionHeader(TransactionProvider provider) {
    final reviewCount = provider.unreviewedCount;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showAddDialog(),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Add Transaction'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
            if (reviewCount > 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.rate_review, color: Colors.amber[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$reviewCount transaction${reviewCount > 1 ? 's' : ''} to review',
                        style: TextStyle(
                          color: Colors.amber[900],
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => provider.markAllReviewed(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.amber[800],
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Mark All Reviewed',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(TransactionProvider provider) {
    if (provider.isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.transactions.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'No transactions yet',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _showAddDialog,
                child: const Text('Add your first transaction'),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final txn = provider.transactions[index];
          final category = provider.getCategoryById(txn.categoryId);
          return TransactionTile(
            transaction: txn,
            category: category,
            onTap: () => _showEditDialog(txn),
            onDelete: () => provider.deleteTransaction(txn),
            onMarkReviewed: () async {
              await provider.markReviewed(txn);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Reviewed: ${txn.description.isNotEmpty ? txn.description : "Transaction"}',
                    ),
                    duration: const Duration(seconds: 2),
                    action: SnackBarAction(
                      label: 'EDIT',
                      onPressed: () => _showEditDialog(
                        txn.copyWith(needsReview: false),
                      ),
                    ),
                  ),
                );
              }
            },
          );
        },
        childCount: provider.transactions.length,
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (_) => const AddTransactionDialog(),
    );
  }

  void _showEditDialog(MoneyTransaction transaction) {
    showDialog(
      context: context,
      builder: (_) => AddTransactionDialog(existingTransaction: transaction),
    );
  }

}
