import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/transaction_provider.dart';

/// Deletes the transactions with [ids] and shows a snackbar whose UNDO action
/// puts them back, sub-items included. [onUndone] runs after a restore.
Future<void> deleteTransactionsWithUndo(
  BuildContext context,
  List<int> ids, {
  String? message,
  VoidCallback? onUndone,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final transactions = context.read<TransactionProvider>();
  final accounts = context.read<AccountProvider>();

  final removed = await transactions.deleteTransactions(ids);
  await accounts.loadAccounts();

  final count = removed.where((t) => ids.contains(t.id)).length;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message ??
              (count == 1
                  ? 'Transaction deleted'
                  : '$count transactions deleted'),
        ),
        duration: const Duration(seconds: 5),
        action: removed.isEmpty
            ? null
            : SnackBarAction(
                label: 'UNDO',
                onPressed: () async {
                  await transactions.restoreTransactions(removed);
                  await accounts.loadAccounts();
                  onUndone?.call();
                },
              ),
      ),
    );
}
