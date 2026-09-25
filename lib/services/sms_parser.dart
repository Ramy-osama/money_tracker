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
  /// Truecaller and similar SMS classifier apps re-broadcast the original
  /// bank message wrapped in extra annotation text (caller info, "Reported
  /// safe by N users", spam/category labels, separator dashes, etc.). The
  /// stripped substrings below are matched case-insensitively and removed
  /// before fingerprinting so the wrapped copy hashes the same as the
  /// original bank SMS.
  static final List<RegExp> _wrapperStripPatterns = [
    // Truecaller line markers
    RegExp(r'truecaller', caseSensitive: false),
    RegExp(r'reported\s+safe(?:\s+by\s+\d+\s+users?)?', caseSensitive: false),
    RegExp(r'reported\s+as\s+spam(?:\s+by\s+\d+\s+users?)?',
        caseSensitive: false),
    RegExp(r'spam\s+score[:\s]+\d+', caseSensitive: false),
    RegExp(r'identified\s+as[:\s].*', caseSensitive: false),
    // SMS app forwarding artefacts
    RegExp(r'^\s*from[:\s].*$', caseSensitive: false, multiLine: true),
    RegExp(r'^\s*sender[:\s].*$', caseSensitive: false, multiLine: true),
    RegExp(r'^\s*forwarded\s+message.*$', caseSensitive: false, multiLine: true),
    // Visual separators that wrappers commonly add
    RegExp(r'[─━═\-]{3,}'),
  ];

  /// Build a stable fingerprint suitable for cross-isolate, time-windowed
  /// duplicate detection.
  ///
  /// Strategy: the fingerprint is built from the **content that is
  /// invariant across re-broadcasts** rather than from the raw body, so
  /// that Truecaller-wrapped copies of the same bank SMS collapse to the
  /// same key. We use:
  ///   - the extracted amount (cents-precision integer)
  ///   - the inferred type (income/expense)
  ///   - a normalized excerpt of the body with wrapper text removed,
  ///     whitespace collapsed, Arabic-Indic digits folded to ASCII,
  ///     and case-folded
  ///
  /// Returns an empty string when no usable signal is present (caller
  /// should treat empty as "no fingerprint, do not dedupe").
  static String fingerprintForDedup(String body, {String? sender}) {
    if (body.isEmpty) return '';
    final normalized = _normalizeForFingerprint(body);
    if (normalized.isEmpty) return '';

    final amount = _extractAmount(body);
    final type = _determineType(body);

    // Cap the normalized excerpt to keep the key bounded but distinctive.
    final excerptLen = normalized.length > 240 ? 240 : normalized.length;
    final excerpt = normalized.substring(0, excerptLen);

    final amountKey = amount == null
        ? 'na'
        : (amount * 100).round().toString(); // cents
    return '$type|$amountKey|$excerpt';
  }

  static String _normalizeForFingerprint(String body) {
    var s = body;
    for (final p in _wrapperStripPatterns) {
      s = s.replaceAll(p, ' ');
    }
    s = _foldArabicIndicDigits(s);
    s = s.toLowerCase();
    // Strip every char that isn't a letter (any script), digit, or '.'
    // Keeping '.' preserves decimal amounts.
    s = s.replaceAll(RegExp(r"[^\p{L}\p{N}.]+", unicode: true), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _foldArabicIndicDigits(String s) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
    final buf = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final ai = arabicIndic.indexOf(ch);
      if (ai >= 0) {
        buf.write(ai.toString());
        continue;
      }
      final ei = easternArabicIndic.indexOf(ch);
      if (ei >= 0) {
        buf.write(ei.toString());
        continue;
      }
      buf.write(ch);
    }
    return buf.toString();
  }

  static final List<RegExp> _amountPatterns = [
    // AlAhly / Arabic bank: "تم خصم 500 جم" or "تم إضافة 500 جم"
    RegExp(r'تم\s+خصم\s*([\d,]+\.?\d*)', caseSensitive: false),
    RegExp(r'تم\s+إضافة\s*([\d,]+\.?\d*)', caseSensitive: false),
    // "credited by EGP 250" / "charged by EGP 135" (EGBANK format)
    RegExp(r'(?:credited|charged|debited)\s+(?:by\s+)?(?:EGP|E£|LE)\s*([\d,]+\.?\d*)', caseSensitive: false),
    // Standard: "EGP 250" or "EGP250"
    RegExp(r'(?:EGP|E£)\s*([\d,]+\.?\d*)', caseSensitive: false),
    // Reversed: "250 EGP"
    RegExp(r'([\d,]+\.?\d*)\s*(?:EGP|E£)', caseSensitive: false),
    // "LE 250" / "250 LE"
    RegExp(r'LE\s*([\d,]+\.?\d*)', caseSensitive: false),
    RegExp(r'([\d,]+\.?\d*)\s*LE\b', caseSensitive: false),
    // Arabic with جم (abbreviation for جنيه مصري, used by AlAhly and others)
    RegExp(r'خصم\s*([\d,]+\.?\d*)\s*جم', caseSensitive: false),
    RegExp(r'إضافة\s*([\d,]+\.?\d*)\s*جم', caseSensitive: false),
    // Arabic with full جنيه
    RegExp(r'مبلغ\s*([\d,]+\.?\d*)', caseSensitive: false),
    RegExp(r'([\d,]+\.?\d*)\s*جنيه', caseSensitive: false),
    RegExp(r'بمبلغ\s*([\d,]+\.?\d*)', caseSensitive: false),
    // Generic جم fallback (matches first occurrence of "number جم")
    RegExp(r'([\d,]+\.?\d*)\s*جم\b', caseSensitive: false),
    // Generic: "amount: 250"
    RegExp(r'(?:amount|مبلغ|بقيمة)\s*:?\s*([\d,]+\.?\d*)', caseSensitive: false),
  ];

  static const List<String> _expenseKeywords = [
    'purchase', 'debit', 'spent', 'payment', 'withdraw', 'charged',
    'paid', 'debited', 'withdrawn', 'buying', 'transaction',
    'شراء', 'خصم', 'دفع', 'سحب', 'مشتريات', 'تم خصم',
  ];

  static const List<String> _incomeKeywords = [
    'credit', 'deposit', 'received', 'credited', 'salary', 'refund',
    'transfer', 'incoming',
    'إضافة', 'إيداع', 'تحويل', 'راتب', 'استرداد', 'تم إضافة',
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
    'تم خصم', 'تم إضافة', 'جم', 'المتاح', 'بطاقة',
    // Common bank identifiers
    'bank', 'بنك',
  ];

  /// Default keywords pre-populated for new users
  static const List<String> defaultKeywords = [
    'EGBANK', 'CIB', 'NBE', 'QNB', 'HSBC', 'Banque Misr', 'AlAhly',
    'credited', 'debited', 'charged', 'withdrawn',
    'purchase', 'payment', 'transaction',
    'حسابك', 'بنك', 'تم خصم', 'تم إضافة',
  ];

  /// Keywords that indicate a non-transactional SMS (promotions, OTPs, etc.)
  static const List<String> _excludeKeywords = [
    // Promotional / marketing
    'عرض', 'عروض', 'اشترك', 'تقسيط', 'قسط',
    'مبروك', 'فوز', 'اربح', 'جائزة', 'مجاني', 'كود التفعيل',
    'offer', 'subscribe', 'win', 'free', 'promo', 'discount',
    'activate your', 'congratulations',
    'big savings', 'limited time', 'use code', '% off', 'save up to',
    'voucher', 'coupon', 'cashback offer',
    'mins!',
    // OTP / verification
    'otp', 'verify', 'verification code', 'one-time', 'one time password',
    'كلمة السر', 'رمز التحقق', 'رمز التأكيد',
    // Informational / non-transaction
    'تفعيل', 'اشتراك', 'كود',
  ];

  /// High-signal retail/marketing fragments (EN + AR). Scored, not all single-shot excludes.
  static const List<String> _promoScoreSubstrings = [
    'big savings',
    'limited time',
    'use code',
    '% off',
    'save up to',
    'voucher',
    'coupon',
    'cashback offer',
    'groceries',
    ' minutes',
    ' mins',
    'mins!',
    'كوبون',
    'وفر',
    'خصم %',
    'استخدم كود',
    'كود الخصم',
    'استخدم الكود',
  ];

  /// If this returns `true`, the message is treated as non-transactional even when
  /// amount and bank-style keywords match (e.g. “EGP 150” in a promo blurb).
  static bool isLikelyPromotional(String body) {
    if (body.isEmpty) return false;
    final lower = body.toLowerCase();
    int score = 0;
    for (final p in _promoScoreSubstrings) {
      if (lower.contains(p)) score++;
    }
    if (_startsWithAllCapsBlurb(body)) score++;
    if (_multipleExclaimNearDiscount(body)) score++;
    return score >= 2;
  }

  static bool _startsWithAllCapsBlurb(String body) {
    final firstLine = body.split(RegExp(r'[\r\n]')).first.trim();
    if (firstLine.length < 8) return false;
    final take = firstLine.length > 48 ? 48 : firstLine.length;
    final head = firstLine.substring(0, take);
    int letters = 0;
    int upperLetters = 0;
    for (final rune in head.runes) {
      final c = String.fromCharCode(rune);
      if (RegExp(r'[A-Z]').hasMatch(c)) {
        upperLetters++;
        letters++;
      } else if (RegExp(r'[a-z]').hasMatch(c)) {
        letters++;
      }
    }
    if (letters < 5) return false;
    return upperLetters >= (letters * 0.75).round();
  }

  static bool _multipleExclaimNearDiscount(String body) {
    final exclaim = '!'.allMatches(body).length;
    if (exclaim <= 1) return false;
    final lower = body.toLowerCase();
    final nearDiscount = lower.contains('%') ||
        lower.contains(' off') ||
        lower.contains('خصم') ||
        RegExp(r'\d+\s*%').hasMatch(body);
    return nearDiscount;
  }

  static bool containsKeyword(String body, List<String> keywords) {
    final lowerBody = body.toLowerCase();
    return keywords.any((kw) => lowerBody.contains(kw.toLowerCase()));
  }

  static SmsParseResult parse(String body, List<String> activeKeywords) {
    // Early exit: skip promotional, OTP, and non-transactional messages
    if (containsKeyword(body, _excludeKeywords)) {
      return SmsParseResult(rawBody: body, matched: false);
    }

    if (isLikelyPromotional(body)) {
      return SmsParseResult(rawBody: body, matched: false);
    }

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
    final patterns = [
      // "from AHMED ADEL NABHAN" (EGBANK sender format)
      RegExp(
        r"from\s+([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s]{2,40?})(?:\*|for\s+details|\s+IPN|\s+REF)",
        caseSensitive: false,
      ),
      // AlAhly format: "عند MERCHANT يوم" — merchant ends at "يوم"
      RegExp(
        r"عند\s+([A-Za-z\u0600-\u06FF][A-Za-z\u0600-\u06FF\s&\-'\.0-9]{1,40?})\s+يوم",
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
