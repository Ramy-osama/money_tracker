import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/constants.dart';
import 'sms_tracking_screen.dart';
import 'manage_categories_screen.dart';
import 'manage_accounts_screen.dart';
import '../wallet/review_duplicates_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Account section
              _buildSectionHeader('ACCOUNT'),
              _buildSettingsTile(
                icon: Icons.phone,
                iconColor: Colors.green,
                title: 'Accounts',
                subtitle: 'Manage bank accounts & cards',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ManageAccountsScreen(),
                  ),
                ),
              ),
              _buildSettingsTile(
                icon: Icons.tune,
                iconColor: Colors.orange,
                title: 'Preferences',
                subtitle: 'Currency: ${settings.currency}',
                onTap: () => _showCurrencyPicker(context, settings),
              ),
              _buildSettingsTile(
                icon: Icons.category,
                iconColor: AppColors.primary,
                title: 'Manage Categories',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ManageCategoriesScreen(),
                  ),
                ),
              ),
              _buildSettingsTile(
                icon: Icons.sms,
                iconColor: Colors.purple,
                title: 'SMS Auto-Tracking',
                subtitle: settings.smsTrackingEnabled
                    ? 'Enabled (${settings.smsKeywords.length})'
                    : 'Disabled',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SmsTrackingScreen(),
                  ),
                ),
              ),

              // AI Features section
              _buildSectionHeader('AI FEATURES'),
              _buildSettingsTile(
                icon: Icons.auto_awesome,
                iconColor: Colors.deepPurple,
                title: 'Gemini API Key',
                subtitle: settings.isGeminiConfigured
                    ? 'Configured — AI scanning enabled'
                    : 'Not set — tap to configure',
                onTap: () => _showApiKeyDialog(context, settings),
              ),

              // Data section
              _buildSectionHeader('DATA'),
              _buildSettingsTile(
                icon: Icons.download,
                iconColor: Colors.blue,
                title: 'Export Data',
                subtitle: 'Export transactions as CSV',
                onTap: () => _exportData(context, settings),
              ),
              _buildSettingsTile(
                icon: Icons.copy_all,
                iconColor: Colors.deepOrange,
                title: 'Review Duplicates',
                subtitle: 'Same title & amount within a minute',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReviewDuplicatesScreen(),
                  ),
                ),
              ),

              // About section
              _buildSectionHeader('ABOUT'),
              _buildSettingsTile(
                icon: Icons.info_outline,
                iconColor: Colors.blueGrey,
                title: 'About App',
                subtitle: 'Money Tracker v1.0.0',
                onTap: () => _showAbout(context),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              )
            : null,
        trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showCurrencyPicker(BuildContext context, SettingsProvider settings) {
    const currencies = ['EGP', 'USD', 'EUR', 'GBP', 'SAR', 'AED', 'KWD'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Select Currency',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...currencies.map(
            (c) => ListTile(
              title: Text(c),
              trailing: c == settings.currency
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                settings.setCurrency(c);
                Navigator.pop(ctx);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _exportData(BuildContext context, SettingsProvider settings) async {
    final path = await settings.exportToCsv();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path != null
                ? 'Exported to: $path'
                : 'No transactions to export',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showApiKeyDialog(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController(text: settings.geminiApiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Get a free API key from Google AI Studio to enable AI-powered screenshot scanning for group orders.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Free tier: 15 requests/minute',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'Paste your Gemini API key',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              settings.setGeminiApiKey(controller.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    controller.text.trim().isEmpty
                        ? 'API key cleared'
                        : 'API key saved',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Money Tracker',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.account_balance_wallet,
          color: AppColors.primary,
          size: 32,
        ),
      ),
      children: [
        const Text('A personal money tracker with SMS auto-tracking and voice input.'),
        const SizedBox(height: 8),
        const Text('Built with Flutter. All data stored locally on device.'),
      ],
    );
  }
}
