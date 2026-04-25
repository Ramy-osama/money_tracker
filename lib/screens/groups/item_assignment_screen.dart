import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/group_item.dart';
import '../../models/group_participant.dart';
import '../../providers/group_order_provider.dart';
import '../../services/gemini_service.dart';
import '../../utils/constants.dart';
import '../../widgets/participant_chip_field.dart';

class ItemAssignmentScreen extends StatefulWidget {
  final List<ExtractedItem> extractedItems;
  final bool isGroupOrder;
  final double? deliveryFee;
  final double? tax;

  const ItemAssignmentScreen({
    super.key,
    required this.extractedItems,
    required this.isGroupOrder,
    this.deliveryFee,
    this.tax,
  });

  @override
  State<ItemAssignmentScreen> createState() => _ItemAssignmentScreenState();
}

class _ItemAssignmentScreenState extends State<ItemAssignmentScreen> {
  final _uuid = const Uuid();
  final List<_EditableItem> _items = [];
  final List<String> _participants = [];
  String? _selectedParticipant;
  List<String> _savedContacts = [];

  bool _payerIsMe = true;
  final _payerNameController = TextEditingController();
  final _titleController = TextEditingController(text: 'Group Order');

  final _newItemNameController = TextEditingController();
  final _newItemPriceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final item in widget.extractedItems) {
      _items.add(_EditableItem(
        name: item.item,
        price: item.price,
        assignedTo: item.person,
      ));
    }
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final provider = context.read<GroupOrderProvider>();
    _savedContacts = await provider.getSavedContacts();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _payerNameController.dispose();
    _titleController.dispose();
    _newItemNameController.dispose();
    _newItemPriceController.dispose();
    super.dispose();
  }

  double get _sharedCosts =>
      (widget.deliveryFee ?? 0) + (widget.tax ?? 0);

  double get _subtotal => _items.fold(0.0, (sum, i) => sum + i.price);

  double _unassignedTotal() {
    return _items
        .where((i) => i.assignedTo == null)
        .fold(0.0, (sum, i) => sum + i.price);
  }

  Map<String, double> get _perPersonItemTotals {
    final totals = <String, double>{};
    for (final p in _participants) {
      totals[p] = 0;
    }
    for (final item in _items) {
      if (item.assignedTo != null && totals.containsKey(item.assignedTo)) {
        totals[item.assignedTo!] = totals[item.assignedTo!]! + item.price;
      }
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final itemTotals = _perPersonItemTotals;
    final personCount = _participants.length;
    final sharedPerPerson =
        personCount > 0 ? _sharedCosts / personCount : 0.0;
    final unassigned = _unassignedTotal();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Assign Items'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PEOPLE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap a name to select, then tap items to assign',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 8),
            ParticipantChipField(
              participants: _participants,
              suggestions: _savedContacts,
              selectedParticipant: _selectedParticipant,
              onAdd: (name) {
                setState(() {
                  _participants.add(name);
                  _selectedParticipant ??= name;
                });
              },
              onRemove: (name) {
                setState(() {
                  _participants.remove(name);
                  for (final item in _items) {
                    if (item.assignedTo == name) {
                      item.assignedTo = null;
                    }
                  }
                  if (_selectedParticipant == name) {
                    _selectedParticipant =
                        _participants.isNotEmpty ? _participants.first : null;
                  }
                });
              },
              onSelect: (name) {
                setState(() => _selectedParticipant = name);
              },
            ),

            const SizedBox(height: 20),
            if (_selectedParticipant != null)
              Text(
                'Tap items to assign to $_selectedParticipant:',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            const SizedBox(height: 8),

            ..._items.asMap().entries.map((entry) {
              final item = entry.value;
              final isAssigned = item.assignedTo != null;
              return InkWell(
                onTap: _selectedParticipant == null
                    ? null
                    : () {
                        setState(() {
                          if (item.assignedTo == _selectedParticipant) {
                            item.assignedTo = null;
                          } else {
                            item.assignedTo = _selectedParticipant;
                          }
                        });
                      },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isAssigned
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: item.assignedTo == _selectedParticipant &&
                              isAssigned
                          ? AppColors.primary.withValues(alpha: 0.3)
                          : Colors.grey[200]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          isAssigned ? item.assignedTo! : '',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '\$${item.price.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _addManualItem,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add item'),
            ),

            if (_sharedCosts > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Shared costs: \$${_sharedCosts.toStringAsFixed(2)} / $personCount people = \$${sharedPerPerson.toStringAsFixed(2)} each',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],

            const SizedBox(height: 20),
            const Text(
              'TOTALS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ...itemTotals.entries.map((e) {
              final total = e.value + sharedPerPerson;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.key,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    Text(
                      '\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_sharedCosts > 0)
                      Text(
                        '  (\$${e.value.toStringAsFixed(2)} + \$${sharedPerPerson.toStringAsFixed(2)})',
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                  ],
                ),
              );
            }),

            if (unassigned > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Unassigned: \$${unassigned.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),
            _buildPayerSection(),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _participants.isEmpty ? null : _saveOrder,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Save Order',
                    style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
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

  void _addManualItem() {
    _newItemNameController.clear();
    _newItemPriceController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _newItemNameController,
              decoration: const InputDecoration(
                labelText: 'Item name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newItemPriceController,
              decoration: const InputDecoration(
                labelText: 'Price',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
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
              final name = _newItemNameController.text.trim();
              final price =
                  double.tryParse(_newItemPriceController.text) ?? 0;
              if (name.isNotEmpty && price > 0) {
                setState(() {
                  _items.add(_EditableItem(name: name, price: price));
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveOrder() async {
    final payerName = _payerIsMe ? 'Me' : _payerNameController.text.trim();
    if (!_payerIsMe && payerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the payer name')),
      );
      return;
    }

    final personCount = _participants.length;
    final sharedPerPerson =
        personCount > 0 ? _sharedCosts / personCount : 0.0;
    final itemTotals = _perPersonItemTotals;

    final items = _items.map((i) => GroupItem(
          id: _uuid.v4(),
          groupOrderId: '',
          name: i.name,
          price: i.price,
          assignedTo: i.assignedTo,
        )).toList();

    final participants = _participants.map((name) {
      final itemsTotal = itemTotals[name] ?? 0;
      return GroupParticipant(
        id: _uuid.v4(),
        groupOrderId: '',
        name: name,
        itemsTotal: itemsTotal,
        sharedCostShare: sharedPerPerson,
        totalAmount: itemsTotal + sharedPerPerson,
      );
    }).toList();

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
}

class _EditableItem {
  String name;
  double price;
  String? assignedTo;

  _EditableItem({
    required this.name,
    required this.price,
    this.assignedTo,
  });
}
