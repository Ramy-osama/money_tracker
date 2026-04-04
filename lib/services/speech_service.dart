import 'package:flutter/foundation.dart' hide Category;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceParseResult {
  final double? amount;
  final String? category;
  final String? description;
  final String rawText;
  final String type;

  VoiceParseResult({
    this.amount,
    this.category,
    this.description,
    required this.rawText,
    this.type = 'expense',
  });
}

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      debugPrint('Microphone permission granted');
      return true;
    }
    debugPrint('Microphone permission denied: $status');
    if (status.isPermanentlyDenied) {
      debugPrint('Mic permanently denied - user must enable in Settings');
    }
    return false;
  }

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    final micGranted = await requestMicPermission();
    if (!micGranted) {
      debugPrint('Cannot init speech: microphone permission denied');
      return false;
    }

    _isInitialized = await _speech.initialize(
      onError: (error) {
        debugPrint('Speech error: ${error.errorMsg}');
        _isListening = false;
      },
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
        }
      },
    );
    debugPrint('Speech initialized: $_isInitialized');
    return _isInitialized;
  }

  Future<void> startListening({
    required Function(String) onResult,
    String locale = 'en_US',
  }) async {
    if (!_isInitialized) {
      final ready = await initialize();
      if (!ready) return;
    }

    _isListening = true;
    debugPrint('Starting speech recognition with locale: $locale');
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _isListening = false;
          debugPrint('Recognized: ${result.recognizedWords}');
          onResult(result.recognizedWords);
        }
      },
      localeId: locale,
      listenMode: stt.ListenMode.dictation,
    );
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _speech.stop();
    await _speech.cancel();
  }

  static final _categoryMap = {
    'food': ['food', 'eat', 'restaurant', 'lunch', 'dinner', 'breakfast', 'meal', 'اكل', 'طعام'],
    'transport': ['transport', 'uber', 'taxi', 'gas', 'fuel', 'ride', 'مواصلات', 'بنزين'],
    'shopping': ['shopping', 'buy', 'bought', 'purchase', 'store', 'تسوق', 'شراء'],
    'bills': ['bill', 'electricity', 'water', 'internet', 'phone', 'فاتورة', 'كهرباء', 'مياه'],
    'entertainment': ['movie', 'game', 'fun', 'netflix', 'spotify', 'ترفيه', 'فيلم'],
    'health': ['doctor', 'medicine', 'pharmacy', 'hospital', 'health', 'صحة', 'دكتور', 'صيدلية'],
    'groceries': ['grocery', 'groceries', 'supermarket', 'بقالة', 'سوبر ماركت'],
    'education': ['school', 'course', 'book', 'study', 'تعليم', 'كتاب', 'مدرسة'],
    'salary': ['salary', 'income', 'received', 'got paid', 'paycheck', 'راتب', 'مرتب'],
  };

  static final _incomeKeywords = [
    'received', 'earned', 'got', 'salary', 'income', 'paycheck',
    'got paid', 'freelance', 'bonus', 'refund',
    'استلمت', 'راتب', 'مرتب', 'دخل',
  ];

  static final _splitPatterns = [
    RegExp(r'\b(?:and|also|plus|then|another|و|كمان|وكمان)\b', caseSensitive: false),
  ];

  /// Parses voice input and returns a list of detected transactions.
  /// Splits on conjunctions like "and", "also", "plus", "then".
  static List<VoiceParseResult> parseMultiVoiceInput(String text) {
    final segments = _splitIntoSegments(text);

    if (segments.length <= 1) {
      final single = _parseSingleSegment(text, text);
      return single.amount != null ? [single] : [single];
    }

    final results = <VoiceParseResult>[];
    for (final segment in segments) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final parsed = _parseSingleSegment(trimmed, text);
      if (parsed.amount != null) {
        results.add(parsed);
      }
    }

    return results.isNotEmpty
        ? results
        : [_parseSingleSegment(text, text)];
  }

  /// Splits text on conjunctions while preserving context.
  static List<String> _splitIntoSegments(String text) {
    final lower = text.toLowerCase();

    for (final pattern in _splitPatterns) {
      if (pattern.hasMatch(lower)) {
        final parts = text.split(pattern);
        final validParts = parts.where((p) {
          final trimmed = p.trim();
          return trimmed.isNotEmpty && RegExp(r'\d').hasMatch(trimmed);
        }).toList();

        if (validParts.length > 1) return validParts;
      }
    }

    // Try splitting on amount boundaries: "50 on food 30 on transport"
    final amountBoundary = RegExp(
      r'(?<=\s)(?=\d+(?:\.\d+)?\s*(?:pounds?|egp|le|جنيه|on|for|at)\b)',
      caseSensitive: false,
    );
    final boundaryParts = text.split(amountBoundary);
    if (boundaryParts.length > 1) {
      final valid = boundaryParts.where((p) =>
        p.trim().isNotEmpty && RegExp(r'\d').hasMatch(p)
      ).toList();
      if (valid.length > 1) return valid;
    }

    return [text];
  }

  static VoiceParseResult _parseSingleSegment(String segment, String fullText) {
    final lower = segment.toLowerCase();
    double? amount;
    String? category;
    String? description;

    final amountPatterns = [
      RegExp(r'(\d+(?:\.\d+)?)\s*(?:pounds?|egp|le|جنيه)', caseSensitive: false),
      RegExp(r'(?:spent|paid|bought|cost|received|earned|got)\s*(\d+(?:\.\d+)?)', caseSensitive: false),
      RegExp(r'(\d+(?:\.\d+)?)\s*(?:on|for|at)', caseSensitive: false),
    ];

    for (final pattern in amountPatterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        amount = double.tryParse(match.group(1) ?? '');
        if (amount != null) break;
      }
    }

    if (amount == null) {
      final bareNumber = RegExp(r'\b(\d+(?:\.\d+)?)\b').firstMatch(lower);
      if (bareNumber != null) {
        amount = double.tryParse(bareNumber.group(1) ?? '');
      }
    }

    for (final entry in _categoryMap.entries) {
      if (entry.value.any((word) => lower.contains(word))) {
        category = entry.key;
        break;
      }
    }

    final isIncome = _incomeKeywords.any((kw) => lower.contains(kw));

    final descPatterns = [
      RegExp(r'(?:at|from|on|for)\s+(.+?)(?:\s+\d|\s*$)', caseSensitive: false),
    ];
    for (final pattern in descPatterns) {
      final match = pattern.firstMatch(segment);
      if (match != null) {
        description = match.group(1)?.trim();
        break;
      }
    }
    description ??= segment.trim();

    return VoiceParseResult(
      amount: amount,
      category: category,
      description: description,
      rawText: segment.trim(),
      type: isIncome ? 'income' : 'expense',
    );
  }

  /// Legacy single-parse method (kept for backward compat)
  static VoiceParseResult parseVoiceInput(String text) {
    return _parseSingleSegment(text, text);
  }
}
