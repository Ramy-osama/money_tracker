import 'package:flutter/material.dart';
import '../utils/constants.dart';

class ParticipantChipField extends StatefulWidget {
  final List<String> participants;
  final List<String> suggestions;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final String? selectedParticipant;
  final ValueChanged<String>? onSelect;

  const ParticipantChipField({
    super.key,
    required this.participants,
    this.suggestions = const [],
    required this.onAdd,
    required this.onRemove,
    this.selectedParticipant,
    this.onSelect,
  });

  @override
  State<ParticipantChipField> createState() => _ParticipantChipFieldState();
}

class _ParticipantChipFieldState extends State<ParticipantChipField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _filteredSuggestions = [];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      if (value.isEmpty) {
        _filteredSuggestions = [];
      } else {
        _filteredSuggestions = widget.suggestions
            .where((s) =>
                s.toLowerCase().contains(value.toLowerCase()) &&
                !widget.participants.contains(s))
            .take(5)
            .toList();
      }
    });
  }

  void _addParticipant(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || widget.participants.contains(trimmed)) return;
    widget.onAdd(trimmed);
    _controller.clear();
    setState(() => _filteredSuggestions = []);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...widget.participants.map((name) {
              final isSelected = widget.selectedParticipant == name;
              return GestureDetector(
                onTap: widget.onSelect != null
                    ? () => widget.onSelect!(name)
                    : null,
                child: Chip(
                  label: Text(
                    name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  backgroundColor: isSelected
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.08),
                  deleteIcon: Icon(
                    Icons.close,
                    size: 18,
                    color: isSelected ? Colors.white70 : Colors.grey[600],
                  ),
                  onDeleted: () => widget.onRemove(name),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.grey[300]!,
                    ),
                  ),
                ),
              );
            }),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Add name...',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  border: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                ),
                style: const TextStyle(fontSize: 14),
                onChanged: _onChanged,
                onSubmitted: _addParticipant,
              ),
            ),
          ],
        ),
        if (_filteredSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _filteredSuggestions.map((s) {
                return InkWell(
                  onTap: () => _addParticipant(s),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 18, color: Colors.grey[500]),
                        const SizedBox(width: 8),
                        Text(s),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
