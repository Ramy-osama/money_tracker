import 'group_participant.dart';
import 'group_item.dart';

class GroupOrder {
  final String id;
  final String title;
  final double totalAmount;
  final String payerName;
  final bool payerIsMe;
  final DateTime date;
  final String? accountId;
  final String? transactionId;
  final double sharedCosts;
  final bool isSettled;
  final DateTime createdAt;
  final List<GroupParticipant> participants;
  final List<GroupItem> items;

  GroupOrder({
    required this.id,
    required this.title,
    required this.totalAmount,
    required this.payerName,
    required this.payerIsMe,
    required this.date,
    this.accountId,
    this.transactionId,
    this.sharedCosts = 0,
    this.isSettled = false,
    DateTime? createdAt,
    this.participants = const [],
    this.items = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  int get paidCount => participants.where((p) => p.isPaid).length;

  double get collectedAmount =>
      participants.where((p) => p.isPaid).fold(0.0, (sum, p) => sum + p.totalAmount);

  double get pendingAmount =>
      participants.where((p) => !p.isPaid).fold(0.0, (sum, p) => sum + p.totalAmount);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'total_amount': totalAmount,
      'payer_name': payerName,
      'payer_is_me': payerIsMe ? 1 : 0,
      'date': date.toIso8601String(),
      'account_id': accountId,
      'transaction_id': transactionId,
      'shared_costs': sharedCosts,
      'is_settled': isSettled ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory GroupOrder.fromMap(
    Map<String, dynamic> map, {
    List<GroupParticipant> participants = const [],
    List<GroupItem> items = const [],
  }) {
    return GroupOrder(
      id: map['id'] as String,
      title: map['title'] as String,
      totalAmount: (map['total_amount'] as num).toDouble(),
      payerName: map['payer_name'] as String,
      payerIsMe: (map['payer_is_me'] as int) == 1,
      date: DateTime.parse(map['date'] as String),
      accountId: map['account_id'] as String?,
      transactionId: map['transaction_id'] as String?,
      sharedCosts: (map['shared_costs'] as num?)?.toDouble() ?? 0,
      isSettled: (map['is_settled'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      participants: participants,
      items: items,
    );
  }

  GroupOrder copyWith({
    String? id,
    String? title,
    double? totalAmount,
    String? payerName,
    bool? payerIsMe,
    DateTime? date,
    String? accountId,
    String? transactionId,
    double? sharedCosts,
    bool? isSettled,
    List<GroupParticipant>? participants,
    List<GroupItem>? items,
  }) {
    return GroupOrder(
      id: id ?? this.id,
      title: title ?? this.title,
      totalAmount: totalAmount ?? this.totalAmount,
      payerName: payerName ?? this.payerName,
      payerIsMe: payerIsMe ?? this.payerIsMe,
      date: date ?? this.date,
      accountId: accountId ?? this.accountId,
      transactionId: transactionId ?? this.transactionId,
      sharedCosts: sharedCosts ?? this.sharedCosts,
      isSettled: isSettled ?? this.isSettled,
      createdAt: createdAt,
      participants: participants ?? this.participants,
      items: items ?? this.items,
    );
  }
}
