import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF00897B);
  static const Color primaryDark = Color(0xFF00695C);
  static const Color primaryLight = Color(0xFF4DB6AC);
  static const Color accent = Color(0xFFFF9800);
  static const Color income = Color(0xFF4CAF50);
  static const Color expense = Color(0xFFE53935);
  static const Color background = Color(0xFFF5F7FA);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color divider = Color(0xFFE0E0E0);

  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFF00897B), Color(0xFF4DB6AC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bucketGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFFB388FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class DefaultCategories {
  static const List<Map<String, dynamic>> expense = [
    {'name': 'Food', 'icon': 'restaurant'},
    {'name': 'Transport', 'icon': 'directions_car'},
    {'name': 'Shopping', 'icon': 'shopping_bag'},
    {'name': 'Bills', 'icon': 'receipt_long'},
    {'name': 'Entertainment', 'icon': 'movie'},
    {'name': 'Health', 'icon': 'medical_services'},
    {'name': 'Education', 'icon': 'school'},
    {'name': 'Groceries', 'icon': 'local_grocery_store'},
    {'name': 'Rent', 'icon': 'home'},
    {'name': 'Other', 'icon': 'more_horiz'},
  ];

  static const List<Map<String, dynamic>> income = [
    {'name': 'Salary', 'icon': 'account_balance_wallet'},
    {'name': 'Freelance', 'icon': 'work'},
    {'name': 'Investment', 'icon': 'trending_up'},
    {'name': 'Gift', 'icon': 'card_giftcard'},
    {'name': 'Other Income', 'icon': 'more_horiz'},
  ];
}

class DefaultSmsKeywords {
  static const List<String> keywords = [
    // Bank names (Egypt)
    'EGBANK', 'CIB', 'NBE', 'QNB', 'HSBC', 'Banque Misr',
    'Faisal', 'AAIB', 'Alex Bank', 'BDC',
    // English transaction words
    'transaction', 'purchase', 'payment', 'debit', 'credit',
    'spent', 'balance', 'withdraw', 'deposit', 'transfer',
    'charged', 'credited', 'debited', 'withdrawn', 'received',
    'account', 'EGP',
    // Arabic transaction words
    'عملية', 'شراء', 'دفع', 'خصم', 'إضافة',
    'رصيد', 'سحب', 'إيداع', 'تحويل', 'حسابك', 'بنك', 'جنيه',
  ];
}

const Map<String, IconData> categoryIcons = {
  'restaurant': Icons.restaurant,
  'directions_car': Icons.directions_car,
  'shopping_bag': Icons.shopping_bag,
  'receipt_long': Icons.receipt_long,
  'movie': Icons.movie,
  'medical_services': Icons.medical_services,
  'school': Icons.school,
  'local_grocery_store': Icons.local_grocery_store,
  'home': Icons.home,
  'more_horiz': Icons.more_horiz,
  'account_balance_wallet': Icons.account_balance_wallet,
  'work': Icons.work,
  'trending_up': Icons.trending_up,
  'card_giftcard': Icons.card_giftcard,
  'account_balance': Icons.account_balance,
  'credit_card': Icons.credit_card,
  'money': Icons.money,
  'savings': Icons.savings,
  'payments': Icons.payments,
  'attach_money': Icons.attach_money,
};

IconData getCategoryIcon(String iconName) {
  return categoryIcons[iconName] ?? Icons.category;
}
