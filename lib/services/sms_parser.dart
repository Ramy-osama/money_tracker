class SmsParseResult {
  final double? amount;
  final String type; // 'income' or 'expense'
  final String? merchant;
  final String rawBody;
  final bool matched;

  SmsParseResult({
    this.amount,
    this.type = 'expense',
    this.merchant,
    required this.rawBody,
    this.matched = false,
  });
}

class SmsParser {
  static final List<RegExp> _amountPatterns = [
    // "credited by EGP 250" / "charged by EGP 135" (EGBANK format)
    RegExp(r'(?:credited|charged|debited)\s+(?:by\s+)?(?:EGP|E£|LE)\s*([\d,]+\.?\d*)', caseSensitive: false),
    // Standard: "EGP 250" or "EGP250"
    RegExp(r'(?:EGP|E£)\s*([\d,]+\.?\d*)', caseSensitive: false),
    // Reversed: "250 EGP"
    RegExp(r'([\d,]+\.?\d*)\s*(?:EGP|E£)', caseSensitive: false),
    // "LE 250" / "250 LE"
    RegExp(r'LE\s*([\d,]+\.?\d*)', caseSensitive: false),
    RegExp(r'([\d,]+\.?\d*)\s*LE\b', caseSensitive: false),
    // Arabic
    RegExp(r'مبلغ\s*([\d,]+\.?\d*)', caseSensitive: false),
    RegExp(r'([\d,]+\.?\d*)\s*جنيه', caseSensitive: false),
    RegExp(r'بمبلغ\s*([\d,]+\.?\d*)', caseSensitive: false),
    // Generic: "amount: 250"
    RegExp(r'(?:amount|مبلغ|بقيمة)\s*:?\s*([\d,]+\.?\d*)', caseSensitive: false),
  ];

  static const List<String> _expenseKeywords = [
    'purchase', 'debit', 'spent', 'payment', 'withdraw', 'charged',
    'paid', 'debited', 'withdrawn', 'buying', 'transaction',
    'شراء', 'خصم', 'دفع', 'سحب', 'مشتريات',
  ];

  static const List<String> _incomeKeywords = [
    'credit', 'deposit', 'received', 'credited', 'salary', 'refund',
    'transfer', 'incoming',
    'إضافة', 'إيداع', 'تحويل', 'راتب', 'استرداد',
  ];

  /// Built-in keywords that indicate a financial SMS regardless of user config.
  /// These make the parser work out-of-the-box for common bank messages.
  static const List<String> _builtInBankKeywords = [
    // English transaction words
    'credited', 'debited', 'charged', 'withdrawn', 'deposited',
    'purchase', 'payment', 'transfer', 'transaction', 'balance',
    'account', 'spent', 'received',
    // Currency markers
    'egp', 'e£', 'le ',
    // Arabic transaction words
    'حسابك', 'رصيدك', 'تحويل', 'سحب', 'إيداع', 'خصم', 'جنيه',
    // Common bank identifiers
    'bank', 'بنك',
  ];

  /// Default keywords pre-populated for new users
  static const List<String> defaultKeywords = [
    'EGBANK', 'CIB', 'NBE', 'QNB', 'HSBC', 'Banque Misr',
    'credited', 'debited', 'charged', 'withdrawn',
    'purchase', 'payment', 'transaction',
    'حسابك', 'بنك',
  ];

  static bool containsKeyword(String body, List<String> keywords) {
    final lowerBody = body.toLowerCase();
    return keywords.any((kw) => lowerBody.contains(kw.toLowerCase()));
  }

  static SmsParseResult parse(String body, List<String> activeKeywords) {
    // Match against BOTH user keywords AND built-in bank keywords
    final matchesUserKeywords = activeKeywords.isNotEmpty &&
        containsKeyword(body, activeKeywords);
    final matchesBankKeywords = containsKeyword(body, _builtInBankKeywords);

    if (!matchesUserKeywords && !matchesBankKeywords) {
      return SmsParseResult(rawBody: body, matched: false);
    }

    final amount = _extractAmount(body);
    final type = _determineType(body);
    final merchant = _extractMerchant(body);

    return SmsParseResult(
      amount: amount,
      type: type,
      merchant: merchant,
      rawBody: body,
      matched: amount != null,
    );
  }

  static double? _extractAmount(String body) {
    for (final pattern in _amountPatterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final raw = match.group(1);
        if (raw != null) {
          final cleaned = raw.replaceAll(',', '');
          final value = double.tryParse(cleaned);
          if (value != null && value > 0) return value;
        }
      }
    }
    return null;
  }

  static String _determineType(String body) {
    final lower = body.toLowerCase();

    int expenseScore = 0;
    int incomeScore = 0;

    for (final kw in _expenseKeywords) {
      if (lower.contains(kw.toLowerCase())) expenseScore++;
    }
    for (final kw in _incomeKeywords) {
      if (lower.contains(kw.toLowerCase())) incomeScore++;
    }

    return incomeScore > expenseScore ? 'income' : 'expense';
  }

  static String? _extractMerchant(String body) {
    // Try specific patterns for common bank formats
    final patterns = [
      // "from AHMED ADEL NABHAN" (EGBANK sender format)
      RegExp(
        r"from\s+([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s]{2,40?})(?:\*|for\s+details|\s+IPN|\s+REF)",
        caseSensitive: false,
      ),
      // General "at/from/to" pattern
      RegExp(
        r"(?:at|from|to|في|عند|لدى)\s+([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s&\-'\.]{1,40})",
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        var merchant = match.group(1)?.trim();
        if (merchant != null && merchant.isNotEmpty) {
          // Clean up trailing stars/whitespace
          merchant = merchant.replaceAll(RegExp(r'\*+$'), '').trim();
          if (merchant.isNotEmpty) return merchant;
        }
      }
    }
    return null;
  }
}
