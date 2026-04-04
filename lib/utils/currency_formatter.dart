import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String format(double amount, {String currency = 'EGP'}) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '$currency ${formatter.format(amount)}';
  }

  static String formatCompact(double amount, {String currency = 'EGP'}) {
    final formatter = NumberFormat.compact(locale: 'en_US');
    return '$currency${formatter.format(amount)}';
  }

  static String formatSigned(double amount, {String currency = 'EGP'}) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    final sign = amount >= 0 ? '' : '-';
    return '$currency $sign${formatter.format(amount.abs())}';
  }
}

class DateFormatter {
  static String formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  static String formatDisplay(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  static String formatMonthYear(DateTime date) {
    return DateFormat('MMMM yyyy').format(date);
  }

  static String formatShort(DateTime date) {
    return DateFormat('dd/MM').format(date);
  }
}
