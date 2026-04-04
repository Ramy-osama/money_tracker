import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../models/account.dart';

class AccountProvider with ChangeNotifier {
  final DbHelper _db = DbHelper();

  List<Account> _accounts = [];
  int _selectedAccountId = 1;

  List<Account> get accounts => _accounts;
  int get selectedAccountId => _selectedAccountId;

  Account? get selectedAccount {
    try {
      return _accounts.firstWhere((a) => a.id == _selectedAccountId);
    } catch (_) {
      return _accounts.isNotEmpty ? _accounts.first : null;
    }
  }

  Future<void> loadAccounts() async {
    _accounts = await _db.getAccounts();
    if (_accounts.isNotEmpty && !_accounts.any((a) => a.id == _selectedAccountId)) {
      _selectedAccountId = _accounts.first.id!;
    }
    notifyListeners();
  }

  void selectAccount(int id) {
    _selectedAccountId = id;
    notifyListeners();
  }

  Future<void> addAccount(Account account) async {
    await _db.insertAccount(account);
    await loadAccounts();
  }

  Future<void> updateAccount(Account account) async {
    await _db.updateAccount(account);
    await loadAccounts();
  }

  Future<void> deleteAccount(int id) async {
    if (_accounts.length <= 1) return;
    await _db.deleteAccount(id);
    await loadAccounts();
  }
}
