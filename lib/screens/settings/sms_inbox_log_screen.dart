import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/inbox_log_entry.dart';
import '../../providers/settings_provider.dart';
import '../../screens/wallet/add_transaction_dialog.dart';
import '../../utils/constants.dart';
import '../../widgets/delete_with_undo.dart';

class SmsInboxLogScreen extends StatefulWidget {
  const SmsInboxLogScreen({super.key});

  @override
  State<SmsInboxLogScreen> createState() => _SmsInboxLogScreenState();
}

class _SmsInboxLogScreenState extends State<SmsInboxLogScreen> {
  List<InboxLogEntry>? _entries;
  String? _error;
  final _dateFmt = DateFormat('MMM d, HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
    });
    try {
      final list =
          await context.read<SettingsProvider>().getRecentInboxLog(limit: 50);
      if (mounted) {
        setState(() {
          _entries = list;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Recent SMS'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries!.isEmpty) {
      return const Center(
        child: Text(
          'No SMS log entries yet. Incoming messages appear here after they are processed.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _entries!.length,
        itemBuilder: (context, i) {
          final e = _entries![i];
          return _InboxLogTile(
            entry: e,
            timeLabel: _dateFmt.format(e.receivedAt.toLocal()),
            onTap: () => _openActions(context, e),
          );
        },
      ),
    );
  }

  Future<void> _openActions(BuildContext context, InboxLogEntry e) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                e.sender.isEmpty ? '(No sender)' : e.sender,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                e.body,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _onBlockSender(e);
                },
                icon: const Icon(Icons.block, size: 20),
                label: const Text('Block this sender'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                ),
              ),
              if (!e.wasTracked) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (dCtx) => AddTransactionDialog(
                        prefillDescription: e.body,
                        source: 'sms_inbox',
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_card, size: 20),
                  label: const Text('Mark as transaction (manual)'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onBlockSender(InboxLogEntry e) async {
    if (e.sender.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No sender to block for this message.'),
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final settings = context.read<SettingsProvider>();
    await settings.addBlockedSender(e.sender);
    if (e.wasTracked && e.transactionId != null) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete saved transaction?'),
          content: const Text(
            'A transaction was already created from this SMS. Delete it as well?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (go == true) {
        await deleteTransactionsWithUndo(
          context,
          [e.transactionId!],
          message: 'Sender blocked. Transaction removed.',
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Sender blocked. Transaction kept.')),
        );
      }
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sender blocked.')),
      );
    }
    if (!mounted) return;
    await _reload();
  }
}

class _InboxLogTile extends StatelessWidget {
  const _InboxLogTile({
    required this.entry,
    required this.timeLabel,
    required this.onTap,
  });

  final InboxLogEntry entry;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, String label) = entry.blockedSender
        ? (Colors.red[50]!, Colors.red[900]!, 'Blocked')
        : entry.wasTracked
            ? (Colors.green[50]!, Colors.green[900]!, 'Tracked')
            : (Colors.grey[200]!, Colors.grey[800]!, 'Not tracked');

    final preview = entry.body.length > 120
        ? '${entry.body.substring(0, 120)}…'
        : entry.body;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.sender.isEmpty ? '(Unknown sender)' : entry.sender,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                timeLabel,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                preview,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
