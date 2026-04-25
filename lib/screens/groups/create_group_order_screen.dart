import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/gemini_service.dart';
import '../../utils/constants.dart';
import 'scan_review_screen.dart';
import 'item_assignment_screen.dart';

class CreateGroupOrderScreen extends StatefulWidget {
  const CreateGroupOrderScreen({super.key});

  @override
  State<CreateGroupOrderScreen> createState() =>
      _CreateGroupOrderScreenState();
}

class _CreateGroupOrderScreenState extends State<CreateGroupOrderScreen> {
  final _geminiService = GeminiService();
  bool _isScanning = false;
  bool _isConfigured = false;

  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  Future<void> _checkConfig() async {
    _isConfigured = await _geminiService.isConfigured;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('New Group Order'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isScanning ? _buildLoadingState() : _buildInputModes(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Scanning order...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'AI is extracting items and people',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildInputModes() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How would you like to add items?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),

          _buildModeCard(
            icon: Icons.document_scanner_outlined,
            iconColor: AppColors.primary,
            title: 'Scan Screenshot',
            subtitle: 'Auto-detect items and people from\nyour Talabat or delivery app',
            enabled: _isConfigured,
            disabledHint: 'Requires API key — set up in Settings',
            onTap: () => _scanScreenshot(ImageSource.gallery),
          ),
          const SizedBox(height: 12),

          _buildModeCard(
            icon: Icons.camera_alt_outlined,
            iconColor: Colors.blue,
            title: 'Take Photo',
            subtitle: 'Photograph a receipt or order screen',
            enabled: _isConfigured,
            disabledHint: 'Requires API key — set up in Settings',
            onTap: () => _scanScreenshot(ImageSource.camera),
          ),
          const SizedBox(height: 12),

          _buildModeCard(
            icon: Icons.content_paste,
            iconColor: Colors.orange,
            title: 'Paste Order Text',
            subtitle: 'Paste the order summary text',
            enabled: _isConfigured,
            disabledHint: 'Requires API key — set up in Settings',
            onTap: _pasteOrderText,
          ),
          const SizedBox(height: 12),

          _buildModeCard(
            icon: Icons.edit_note,
            iconColor: Colors.purple,
            title: 'Enter Manually',
            subtitle: 'Type items and prices yourself',
            enabled: true,
            onTap: _enterManually,
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool enabled,
    String? disabledHint,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                      if (!enabled && disabledHint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            disabledHint,
                            style: TextStyle(
                              color: Colors.orange[700],
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _scanScreenshot(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null) return;

    setState(() => _isScanning = true);

    try {
      final result = await _geminiService.scanScreenshot(File(picked.path));
      if (mounted) {
        setState(() => _isScanning = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScanReviewScreen(scanResult: result),
          ),
        );
      }
    } on GeminiServiceException catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        _showError(e.message);
      }
    }
  }

  Future<void> _pasteOrderText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste Order Text'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Paste your order summary here...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Extract Items'),
          ),
        ],
      ),
    );

    if (text == null || text.trim().isEmpty) return;

    setState(() => _isScanning = true);

    try {
      final result = await _geminiService.parseOrderText(text);
      if (mounted) {
        setState(() => _isScanning = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScanReviewScreen(scanResult: result),
          ),
        );
      }
    } on GeminiServiceException catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        _showError(e.message);
      }
    }
  }

  void _enterManually() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ItemAssignmentScreen(
          extractedItems: [],
          isGroupOrder: false,
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }
}
