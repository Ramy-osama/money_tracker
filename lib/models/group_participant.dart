class GroupParticipant {
  final String id;
  final String groupOrderId;
  final String name;
  final double itemsTotal;
  final double sharedCostShare;
  final double totalAmount;
  final bool isPaid;
  final DateTime? paidDate;

  GroupParticipant({
    required this.id,
    required this.groupOrderId,
    required this.name,
    this.itemsTotal = 0,
    this.sharedCostShare = 0,
    this.totalAmount = 0,
    this.isPaid = false,
    this.paidDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_order_id': groupOrderId,
      'name': name,
      'items_total': itemsTotal,
      'shared_cost_share': sharedCostShare,
      'total_amount': totalAmount,
      'is_paid': isPaid ? 1 : 0,
      'paid_date': paidDate?.toIso8601String(),
    };
  }

  factory GroupParticipant.fromMap(Map<String, dynamic> map) {
    return GroupParticipant(
      id: map['id'] as String,
      groupOrderId: map['group_order_id'] as String,
      name: map['name'] as String,
      itemsTotal: (map['items_total'] as num?)?.toDouble() ?? 0,
      sharedCostShare: (map['shared_cost_share'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      isPaid: (map['is_paid'] as int?) == 1,
      paidDate: map['paid_date'] != null
          ? DateTime.parse(map['paid_date'] as String)
          : null,
    );
  }

  GroupParticipant copyWith({
    String? id,
    String? groupOrderId,
    String? name,
    double? itemsTotal,
    double? sharedCostShare,
    double? totalAmount,
    bool? isPaid,
    DateTime? paidDate,
    bool clearPaidDate = false,
  }) {
    return GroupParticipant(
      id: id ?? this.id,
      groupOrderId: groupOrderId ?? this.groupOrderId,
      name: name ?? this.name,
      itemsTotal: itemsTotal ?? this.itemsTotal,
      sharedCostShare: sharedCostShare ?? this.sharedCostShare,
      totalAmount: totalAmount ?? this.totalAmount,
      isPaid: isPaid ?? this.isPaid,
      paidDate: clearPaidDate ? null : (paidDate ?? this.paidDate),
    );
  }
}
