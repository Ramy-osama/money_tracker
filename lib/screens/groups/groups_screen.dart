import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/group_order_provider.dart';
import '../../services/gemini_service.dart';
import '../../utils/constants.dart';
import '../../widgets/group_order_card.dart';
import 'create_group_order_screen.dart';
import 'group_order_detail_sheet.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  bool _showSettled = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupOrderProvider>();
    final active = provider.activeOrders;
    final settled = provider.settledOrders;
    final owedToMe = provider.totalOwedToMe;
    final iOwe = provider.totalIOwe;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: active.isEmpty && settled.isEmpty
            ? _buildEmptyState(context)
            : _buildContent(
                context, active, settled, owedToMe, iOwe),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createOrder(context),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.group,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Split group orders\nwith coworkers',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a screenshot to auto-detect\nitems and people',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _createOrder(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Group Order'),
            ),
            const SizedBox(height: 16),
            FutureBuilder<bool>(
              future: GeminiService().isConfigured,
              builder: (context, snapshot) {
                if (snapshot.data == true) return const SizedBox.shrink();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.orange[700], size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Set up AI scanning in Settings',
                        style: TextStyle(
                            color: Colors.orange[700], fontSize: 13),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List active,
    List settled,
    double owedToMe,
    double iOwe,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Groups',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),

          if (owedToMe > 0 || iOwe > 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.headerGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  if (owedToMe > 0)
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '\$${owedToMe.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "You're owed",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (owedToMe > 0 && iOwe > 0)
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  if (iOwe > 0)
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '\$${iOwe.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'You owe',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          if (active.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'ACTIVE (${active.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ...active.map((order) => GroupOrderCard(
                  order: order,
                  onTap: () =>
                      GroupOrderDetailSheet.show(context, order),
                )),
          ],

          if (settled.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _showSettled = !_showSettled),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'SETTLED (${settled.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showSettled
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),
            if (_showSettled)
              ...settled.map((order) => GroupOrderCard(
                    order: order,
                    onTap: () =>
                        GroupOrderDetailSheet.show(context, order),
                  )),
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  void _createOrder(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupOrderScreen()),
    );
  }
}
