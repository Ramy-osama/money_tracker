import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExtractedItem {
  final String? person;
  final String item;
  final double price;

  ExtractedItem({this.person, required this.item, required this.price});

  factory ExtractedItem.fromJson(Map<String, dynamic> json) {
    return ExtractedItem(
      person: json['person'] as String?,
      item: json['item'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ScanResult {
  final List<ExtractedItem> items;
  final bool isGroupOrder;
  final double? detectedDeliveryFee;
  final double? detectedTax;

  ScanResult({
    required this.items,
    required this.isGroupOrder,
    this.detectedDeliveryFee,
    this.detectedTax,
  });
}

class GeminiServiceException implements Exception {
  final String message;
  final GeminiErrorType type;

  GeminiServiceException(this.message, this.type);

  @override
  String toString() => message;
}

enum GeminiErrorType {
  noApiKey,
  invalidApiKey,
  networkError,
  parseError,
  rateLimited,
  unknown,
}

class GeminiService {
  static const String apiKeyPrefKey = 'gemini_api_key';

  static const String _scanPrompt = '''
Analyze this food/drink order image and extract all items with prices.

IMPORTANT: If this is a GROUP ORDER (like Talabat Group Order) where items are organized under different people's names, also extract WHO ordered each item. Look for patterns like "Ahmed's order:", person name headers, or sections separated by names.

Return ONLY valid JSON, no other text:
{
  "items": [
    {"person": "Ahmed", "item": "Chicken Shawarma", "price": 8.00},
    {"person": null, "item": "Beef Burger", "price": 15.00}
  ],
  "delivery_fee": 3.00,
  "tax": 1.50,
  "is_group_order": true
}

Rules:
- "person": name if identifiable from the image, null otherwise
- "is_group_order": true only if person names were detected
- Include quantity in item name if >1 (e.g. "2x Fresh Juice")
- Extract delivery_fee and tax/VAT if visible (null if not found)
- Do NOT include fees, tax, tips, discounts, or totals in the items array
- Prices should be numbers, not strings
''';

  static const String _textPrompt = '''
Analyze this food/drink order text and extract all items with prices.

IMPORTANT: If this text contains a GROUP ORDER where items are organized under different people's names, also extract WHO ordered each item.

Return ONLY valid JSON, no other text:
{
  "items": [
    {"person": "Ahmed", "item": "Chicken Shawarma", "price": 8.00},
    {"person": null, "item": "Beef Burger", "price": 15.00}
  ],
  "delivery_fee": 3.00,
  "tax": 1.50,
  "is_group_order": true
}

Rules:
- "person": name if identifiable, null otherwise
- "is_group_order": true only if person names were detected
- Include quantity in item name if >1 (e.g. "2x Fresh Juice")
- Extract delivery_fee and tax/VAT if visible (null if not found)
- Do NOT include fees, tax, tips, discounts, or totals in the items array
- Prices should be numbers, not strings

Order text:
''';

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(apiKeyPrefKey);
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(apiKeyPrefKey, key.trim());
  }

  Future<bool> get isConfigured async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  Future<ScanResult> scanScreenshot(File imageFile) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw GeminiServiceException(
        'Set up Gemini API key in Settings to scan screenshots',
        GeminiErrorType.noApiKey,
      );
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
      );

      final imageBytes = await imageFile.readAsBytes();
      final mimeType = _getMimeType(imageFile.path);

      final content = Content.multi([
        TextPart(_scanPrompt),
        DataPart(mimeType, imageBytes),
      ]);

      final response = await model.generateContent([content]);
      return _parseResponse(response.text ?? '');
    } on GenerativeAIException catch (e) {
      throw _mapAiException(e);
    } on SocketException {
      throw GeminiServiceException(
        'Could not reach AI service. Check your internet connection',
        GeminiErrorType.networkError,
      );
    } catch (e) {
      if (e is GeminiServiceException) rethrow;
      throw GeminiServiceException(
        'Could not read this image. Try a clearer screenshot',
        GeminiErrorType.parseError,
      );
    }
  }

  Future<ScanResult> parseOrderText(String orderText) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw GeminiServiceException(
        'Set up Gemini API key in Settings to use AI parsing',
        GeminiErrorType.noApiKey,
      );
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
      );

      final content = Content.text('$_textPrompt\n$orderText');
      final response = await model.generateContent([content]);
      return _parseResponse(response.text ?? '');
    } on GenerativeAIException catch (e) {
      throw _mapAiException(e);
    } on SocketException {
      throw GeminiServiceException(
        'Could not reach AI service. Check your internet connection',
        GeminiErrorType.networkError,
      );
    } catch (e) {
      if (e is GeminiServiceException) rethrow;
      throw GeminiServiceException(
        'Could not parse this text. Try reformatting it',
        GeminiErrorType.parseError,
      );
    }
  }

  ScanResult _parseResponse(String responseText) {
    var jsonStr = responseText.trim();

    // Strip markdown code fences if present
    if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      jsonStr = jsonStr.replaceFirst(RegExp(r'\s*```$'), '');
    }

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final itemsList = json['items'] as List<dynamic>? ?? [];
      final items = itemsList
          .map((e) => ExtractedItem.fromJson(e as Map<String, dynamic>))
          .where((item) => item.item.isNotEmpty && item.price > 0)
          .toList();

      if (items.isEmpty) {
        throw GeminiServiceException(
          'No items found in this image. Try a clearer screenshot',
          GeminiErrorType.parseError,
        );
      }

      return ScanResult(
        items: items,
        isGroupOrder: json['is_group_order'] as bool? ?? false,
        detectedDeliveryFee: (json['delivery_fee'] as num?)?.toDouble(),
        detectedTax: (json['tax'] as num?)?.toDouble(),
      );
    } catch (e) {
      if (e is GeminiServiceException) rethrow;
      throw GeminiServiceException(
        'Could not understand the AI response. Try again',
        GeminiErrorType.parseError,
      );
    }
  }

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  GeminiServiceException _mapAiException(GenerativeAIException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('api key') || msg.contains('api_key_invalid') ||
        msg.contains('unauthorized')) {
      return GeminiServiceException(
        'API key is invalid. Check your key in Settings',
        GeminiErrorType.invalidApiKey,
      );
    }
    if (msg.contains('quota') || msg.contains('rate limit') ||
        msg.contains('rate_limit') || msg.contains('resource exhausted') ||
        msg.contains('too many requests')) {
      return GeminiServiceException(
        'Too many scans. Wait a moment and try again',
        GeminiErrorType.rateLimited,
      );
    }
    if (msg.contains('not found') || msg.contains('deprecated') ||
        msg.contains('does not exist') || msg.contains('not supported')) {
      return GeminiServiceException(
        'AI model unavailable. Please update the app',
        GeminiErrorType.unknown,
      );
    }
    return GeminiServiceException(
      'AI service error: ${e.message}',
      GeminiErrorType.unknown,
    );
  }
}
