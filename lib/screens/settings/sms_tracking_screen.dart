import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../models/account.dart';
import '../../models/category.dart';
import '../../providers/account_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/sms_service.dart';
import '../../utils/constants.dart';
import 'sms_inbox_log_screen.dart';

class SmsTrackingScreen extends StatefulWidget {
  const SmsTrackingScreen({super.key});

  @override
  State<SmsTrackingScreen> createState() => _SmsTrackingScreenState();
}

class _SmsTrackingScreenState extends State<SmsTrackingScreen> {
  final _keywordController = TextEditingController();
  final _blockedSenderController = TextEditingController();
  final _smsService = SmsService();
  bool _showDebug = false;
  bool _scanning = false;
  List<Map<String, String>> _scanResults = [];

  @override
  void initState() {
    super.initState();
    _smsService.onDebugLogChanged = () {
      if (mounted && _showDebug) setState(() {});
    };
  }

  @override
  void dispose() {
    _smsService.onDebugLogChanged = null;
    _keywordController.dispose();
    _blockedSenderController.dispose();
    super.dispose();
  }

  Future<void> _runTestScan() async {
    setState(() => _scanning = true);
    final results = await _smsService.testScanInbox(count: 10);
    if (mounted) {
      setState(() {
        _scanResults = results;
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('SMS Auto-Tracking'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showDebug ? Icons.bug_report : Icons.bug_report_outlined),
            tooltip: 'Debug Panel',
            onPressed: () => setState(() => _showDebug = !_showDebug),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToggleCard(settings),
            _buildTargetCard(settings),
            _buildKeywordsCard(settings),
            _buildBlockedSendersCard(settings),
            _buildRecentSmsCard(),
            if (_showDebug) ...[
              _buildDebugPanel(),
              _buildScanResultsCard(),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleCard(SettingsProvider settings) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Status',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  Text(
                    settings.smsTrackingEnabled ? 'Enabled' : 'Disabled',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Spacer(),
              Switch(
                value: settings.smsTrackingEnabled,
                onChanged: (enabled) async {
                  await settings.toggleSmsTracking(enabled);
                  if (enabled && !settings.smsTrackingEnabled && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'SMS permission denied. Enable in Settings > Apps > Money Tracker > Permissions.',
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
                  }
                },
                activeColor: AppColors.primary,
              ),
            ],
          ),
          const Divider(height: 24),
          _buildInfoRow(Icons.sms,
              'Automatically detect bank SMS and save transactions.'),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.verified_user,
              'Your SMS messages are processed locally and never uploaded.'),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.battery_charging_full,
              'Samsung: Go to Settings > Apps > Money Tracker > Battery > Unrestricted to prevent background kill.'),
        ],
      ),
    );
  }

  Widget _buildTargetCard(SettingsProvider settings) {
    final accountProvider = context.watch<AccountProvider>();
    final accounts = accountProvider.accounts;
    final expenseCategories =
        settings.categories.where((c) => c.type == 'expense').toList();
    final incomeCategories =
        settings.categories.where((c) => c.type == 'income').toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Auto-Save Target',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Where SMS-detected transactions should be saved (used by the '
            'background handler when the app is closed)',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (accounts.isEmpty)
            const Text(
              'No accounts yet. Add an account first.',
              style: TextStyle(color: Colors.redAccent),
            )
          else
            DropdownButtonFormField<int?>(
              value: settings.smsTargetAccountId != null &&
                      accounts.any((a) => a.id == settings.smsTargetAccountId)
                  ? settings.smsTargetAccountId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Account',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('First account (default)'),
                ),
                ...accounts.map(
                  (Account a) => DropdownMenuItem<int?>(
                    value: a.id,
                    child: Text(a.name),
                  ),
                ),
              ],
              onChanged: (value) => settings.setSmsTargetAccount(value),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: settings.smsTargetExpenseCategoryId != null &&
                    expenseCategories
                        .any((c) => c.id == settings.smsTargetExpenseCategoryId)
                ? settings.smsTargetExpenseCategoryId
                : null,
            decoration: const InputDecoration(
              labelText: 'Expense category',
              prefixIcon: Icon(Icons.shopping_cart_outlined),
            ),
            items: <DropdownMenuItem<int?>>[
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('First expense category (default)'),
              ),
              ...expenseCategories.map(
                (Category c) => DropdownMenuItem<int?>(
                  value: c.id,
                  child: Text(c.name),
                ),
              ),
            ],
            onChanged: (value) =>
                settings.setSmsTargetExpenseCategory(value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: settings.smsTargetIncomeCategoryId != null &&
                    incomeCategories
                        .any((c) => c.id == settings.smsTargetIncomeCategoryId)
                ? settings.smsTargetIncomeCategoryId
                : null,
            decoration: const InputDecoration(
              labelText: 'Income category',
              prefixIcon: Icon(Icons.attach_money),
            ),
            items: <DropdownMenuItem<int?>>[
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('First income category (default)'),
              ),
              ...incomeCategories.map(
                (Category c) => DropdownMenuItem<int?>(
                  value: c.id,
                  child: Text(c.name),
                ),
              ),
            ],
            onChanged: (value) => settings.setSmsTargetIncomeCategory(value),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordsCard(SettingsProvider settings) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Keywords (${settings.smsKeywords.length})',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: settings.loadSettings,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('SMS containing these keywords will be processed',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...settings.smsKeywords.map(
                (kw) => Chip(
                  label: Text(kw),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => settings.removeKeyword(kw),
                  backgroundColor: Colors.grey[100],
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
              ActionChip(
                avatar:
                    const Icon(Icons.add, size: 18, color: AppColors.primary),
                label: const Text('Add Keyword',
                    style: TextStyle(color: AppColors.primary)),
                onPressed: _showAddKeywordDialog,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedSendersCard(SettingsProvider settings) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Blocked senders (${settings.blockedSenders.length})',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Messages from these numbers or names are never auto-tracked',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...settings.blockedSenders.map(
                (s) => Chip(
                  label: Text(s),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => settings.removeBlockedSender(s),
                  backgroundColor: Colors.grey[100],
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18, color: AppColors.primary),
                label: const Text('Add sender',
                    style: TextStyle(color: AppColors.primary)),
                onPressed: _showAddBlockedSenderDialog,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSmsCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Inbox log',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Last processed SMS messages and whether they were saved',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SmsInboxLogScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.sms_outlined),
              label: const Text('View recent SMS'),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddBlockedSenderDialog() {
    _blockedSenderController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block sender'),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: TextField(
          controller: _blockedSenderController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Name or number as shown in SMS...',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_blockedSenderController.text.trim().isNotEmpty) {
                context
                    .read<SettingsProvider>()
                    .addBlockedSender(_blockedSenderController.text);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 8),
              const Text('Diagnostics',
                  style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: _scanning ? null : _runTestScan,
                icon: _scanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.amber))
                    : const Icon(Icons.search, size: 16, color: Colors.amber),
                label: Text(_scanning ? 'Scanning...' : 'Test Scan',
                    style: const TextStyle(color: Colors.amber, fontSize: 13)),
              ),
            ],
          ),
          const Divider(color: Colors.grey, height: 16),

          // Status indicators
          _buildStatusRow(
              'Listener active', _smsService.isListening, Colors.greenAccent),
          _buildStatusRow('Keywords loaded',
              _smsService.activeKeywords.isNotEmpty, Colors.greenAccent),
          _buildStatusRow('Callback set',
              _smsService.onTransactionDetected != null, Colors.greenAccent),

          FutureBuilder<Map<String, bool>>(
            future: _smsService.checkPermissionStatus(),
            builder: (_, snap) {
              if (!snap.hasData) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  _buildStatusRow('SMS permission',
                      snap.data!['sms'] ?? false, Colors.greenAccent),
                  _buildStatusRow('Phone permission',
                      snap.data!['phone'] ?? false, Colors.greenAccent),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          const Text('Event Log',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          Container(
            height: 200,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _smsService.debugLog.isEmpty
                ? const Center(
                    child: Text('No events yet.\nEnable SMS tracking and wait for messages.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                        textAlign: TextAlign.center))
                : ListView.builder(
                    reverse: true,
                    itemCount: _smsService.debugLog.length,
                    itemBuilder: (_, i) {
                      final entry = _smsService
                          .debugLog[_smsService.debugLog.length - 1 - i];
                      Color color;
                      switch (entry.source) {
                        case 'broadcast':
                          color = Colors.cyanAccent;
                        case 'poll':
                          color = Colors.amberAccent;
                        case 'test':
                          color = Colors.lightGreenAccent;
                        case 'error':
                          color = Colors.redAccent;
                        default:
                          color = Colors.white70;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          entry.formatted,
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontFamily: 'monospace'),
                        ),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              _buildLegendDot(Colors.cyanAccent, 'Broadcast'),
              const SizedBox(width: 12),
              _buildLegendDot(Colors.amberAccent, 'Poll'),
              const SizedBox(width: 12),
              _buildLegendDot(Colors.lightGreenAccent, 'Test'),
              const SizedBox(width: 12),
              _buildLegendDot(Colors.redAccent, 'Error'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanResultsCard() {
    if (_scanResults.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Last Scan Results',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._scanResults.map((r) {
            final matched = r['matched'] == 'true';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: matched ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: matched ? Colors.green[200]! : Colors.red[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(matched ? Icons.check_circle : Icons.cancel,
                          color: matched ? Colors.green : Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'From: ${r['sender']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(r['body'] ?? '',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text(
                    matched
                        ? 'Amount: ${r['amount']} | Type: ${r['type']} | Merchant: ${r['merchant']}'
                        : 'Not matched',
                    style: TextStyle(
                        fontSize: 11,
                        color: matched ? Colors.green[800] : Colors.red[800],
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, bool ok, Color activeColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.error,
              color: ok ? activeColor : Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text(ok ? 'OK' : 'FAIL',
              style: TextStyle(
                  color: ok ? activeColor : Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 10)),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: TextStyle(color: Colors.grey[700], fontSize: 14)),
        ),
      ],
    );
  }

  void _showAddKeywordDialog() {
    _keywordController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Keyword'),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: TextField(
          controller: _keywordController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter keyword...',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_keywordController.text.trim().isNotEmpty) {
                context
                    .read<SettingsProvider>()
                    .addKeyword(_keywordController.text);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
