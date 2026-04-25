import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/group_item.dart';
import '../../models/group_participant.dart';
import '../../providers/group_order_provider.dart';
import '../../services/gemini_service.dart';
import '../../utils/constants.dart';
import 'item_assignment_screen.dart';

class ScanReviewScreen extends StatefulWidget {
  final ScanResult scanResult;

  const ScanReviewScreen({super.key, required this.scanResult});

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late List<ExtractedItem> _items;
  late bool _isGroupOrder;
  final _uuid = const Uuid();

  bool _includeDelivery = false;
  bool _includeTax = false;
  final _deliveryController = TextEditingController();
  final _taxController = TextEditingController();
  final _titleController = TextEditingController();
  bool _payerIsMe = true;
  final _payerNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.scanResult.items);
    _isGroupOrder = widget.scanResult.isGroupOrder;

    if (widget.scanResult.detectedDeliveryFee != null) {
      _includeDelivery = true;
      _deliveryController.text =
          widget.scanResult.detectedDeliveryFee!.toStringAsFixed(2);
    }
    if (widget.scanResult.detectedTax != null) {
      _includeTax = true;
      _taxController.text =
          widget.scanResult.detectedTax!.toStringAsFixed(2);
    }
    _titleController.text = 'Group Order';
  }

  @override
  void dispose() {
    _deliveryController.dispose();
    _taxController.dispose();
    _titleController.dispose();
    _payerNameController.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0.0, (sum, i) => sum + i.price);

  double get _sharedCosts {
    double costs = 0;
    if (_includeDelivery) {
      costs += double.tryParse(_deliveryController.text) ?? 0;
    }
    if (_includeTax) {
      costs += double.tryParse(_taxController.text) ?? 0;
    }
    return costs;
  }

  Map<String, double> get _perPersonTotals {
    final totals = <String, double>{};
    for (final item in _items) {
      if (item.person != null) {
        totals[item.person!] = (totals[item.person!] ?? 0) + item.price;
      }
    }
    final personCount = totals.length;
    if (personCount > 0 && _sharedCosts > 0) {
      final share = _sharedCosts / personCount;
      for (final key in totals.keys.toList()) {
        totals[key] = totals[key]! + share;
      }
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isGroupOrder ? 'Review Order' : 'Review Items'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isGroupOrder) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.income.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        color: AppColors.income, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Group order detected!',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.income,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildGroupedItems(),
            ] else ...[
              Text(
                '${_items.length} items found',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 12),
              _buildFlatItems(),
            ],

            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Subtotal: \$${_subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Text(
              'Shared Costs',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            _buildFeeToggle(
              'Delivery',
              _includeDelivery,
              _deliveryController,
              (v) => setState(() => _includeDelivery = v),
            ),
            const SizedBox(height: 8),
            _buildFeeToggle(
              'Tax',
              _includeTax,
              _taxController,
              (v) => setState(() => _includeTax = v),
            ),

            if (_isGroupOrder) ...[
              const SizedBox(height: 20),
              _buildPerPersonTotals(),
              const SizedBox(height: 20),
              _buildPayerSection(),
              const SizedBox(height: 16),
              _buildTitleDateSection(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveGroupOrder,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Looks good — Save!',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ] else ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _goToAssignment,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Next: Add People & Assign',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedItems() {
    final grouped = <String, List<ExtractedItem>>{};
    for (final item in _items) {
      final key = item.person ?? 'Unassigned';
      grouped.putIfAbsent(key, () => []).add(item);
    }

    return Column(
      children: grouped.entries.map((entry) {
        final personTotal =
            entry.value.fold(0.0, (sum, i) => sum + i.price);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${entry.key} (${entry.value.length} ${entry.value.length == 1 ? "item" : "items"})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '\$${personTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...entry.value.map((item) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.item,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ),
                        Text(
                          '\$${item.price.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFlatItems() {
    return Column(
      children: _items.asMap().entries.map((entry) {
        final item = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(item.item,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              Text(
                '\$${item.price.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFeeToggle(
    String label,
    bool enabled,
    TextEditingController controller,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: enabled,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(label),
        const SizedBox(width: 12),
        if (enabled)
          SizedBox(
            width: 100,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: '\$ ',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
      ],
    );
  }

  Widget _buildPerPersonTotals() {
    final totals = _perPersonTotals;
    if (totals.isEmpty) return const SizedBox.shrink();

    final personCount = totals.length;
    final sharePerPerson =
        personCount > 0 ? _sharedCosts / personCount : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PER-PERSON TOTALS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...totals.entries.map((e) {
          final itemsOnly = e.value - sharePerPerson;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(child: Text(e.key)),
                Text(
                  '\$${e.value.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (_sharedCosts > 0)
                  Text(
                    '  (\$${itemsOnly.toStringAsFixed(2)} + \$${sharePerPerson.toStringAsFixed(2)} fees)',
                    style:
                        TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPayerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Who paid?',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Me'),
              selected: _payerIsMe,
              onSelected: (v) => setState(() => _payerIsMe = true),
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Someone else'),
              selected: !_payerIsMe,
              onSelected: (v) => setState(() => _payerIsMe = false),
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
            ),
          ],
        ),
        if (!_payerIsMe) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _payerNameController,
            decoration: InputDecoration(
              hintText: 'Payer name',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTitleDateSection() {
    return TextField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Title',
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }

  Future<void> _saveGroupOrder() async {
    final totals = _perPersonTotals;
    if (totals.isEmpty) return;

    final payerName = _payerIsMe ? 'Me' : _payerNameController.text.trim();
    if (!_payerIsMe && payerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the payer name')),
      );
      return;
    }

    final personCount = totals.length;
    final sharePerPerson =
        personCount > 0 ? _sharedCosts / personCount : 0.0;

    final items = <GroupItem>[];
    final participants = <GroupParticipant>[];

    for (final extractedItem in _items) {
      items.add(GroupItem(
        id: _uuid.v4(),
        groupOrderId: '',
        name: extractedItem.item,
        price: extractedItem.price,
        assignedTo: extractedItem.person,
      ));
    }

    for (final entry in totals.entries) {
      final itemsTotal = entry.value - sharePerPerson;
      participants.add(GroupParticipant(
        id: _uuid.v4(),
        groupOrderId: '',
        name: entry.key,
        itemsTotal: itemsTotal,
        sharedCostShare: sharePerPerson,
        totalAmount: entry.value,
      ));
    }

    final provider = context.read<GroupOrderProvider>();
    await provider.createGroupOrder(
      title: _titleController.text.trim().isEmpty
          ? 'Group Order'
          : _titleController.text.trim(),
      totalAmount: _subtotal + _sharedCosts,
      payerName: payerName,
      payerIsMe: _payerIsMe,
      date: DateTime.now(),
      items: items,
      participants: participants,
      sharedCosts: _sharedCosts,
    );

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _goToAssignment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemAssignmentScreen(
          extractedItems: _items,
          isGroupOrder: false,
          deliveryFee:
              _includeDelivery ? double.tryParse(_deliveryController.text) : null,
          tax: _includeTax ? double.tryParse(_taxController.text) : null,
        ),
      ),
    );
  }
}
