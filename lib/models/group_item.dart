class GroupItem {
  final String id;
  final String groupOrderId;
  final String name;
  final double price;
  final String? assignedTo;

  GroupItem({
    required this.id,
    required this.groupOrderId,
    required this.name,
    required this.price,
    this.assignedTo,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_order_id': groupOrderId,
      'name': name,
      'price': price,
      'assigned_to': assignedTo,
    };
  }

  factory GroupItem.fromMap(Map<String, dynamic> map) {
    return GroupItem(
      id: map['id'] as String,
      groupOrderId: map['group_order_id'] as String,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      assignedTo: map['assigned_to'] as String?,
    );
  }

  GroupItem copyWith({
    String? id,
    String? groupOrderId,
    String? name,
    double? price,
    String? assignedTo,
    bool clearAssignedTo = false,
  }) {
    return GroupItem(
      id: id ?? this.id,
      groupOrderId: groupOrderId ?? this.groupOrderId,
      name: name ?? this.name,
      price: price ?? this.price,
      assignedTo: clearAssignedTo ? null : (assignedTo ?? this.assignedTo),
    );
  }
}
