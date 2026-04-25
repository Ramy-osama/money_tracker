import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/group_order.dart';
import '../models/group_participant.dart';
import '../models/group_item.dart';

class GroupOrderProvider with ChangeNotifier {
  final DbHelper _db = DbHelper();
  final _uuid = const Uuid();

  List<GroupOrder> _activeOrders = [];
  List<GroupOrder> _settledOrders = [];

  List<GroupOrder> get activeOrders => _activeOrders;
  List<GroupOrder> get settledOrders => _settledOrders;

  double get totalOwedToMe {
    return _activeOrders
        .where((o) => o.payerIsMe)
        .fold(0.0, (sum, o) => sum + o.pendingAmount);
  }

  double get totalIOwe {
    double total = 0;
    for (final order in _activeOrders.where((o) => !o.payerIsMe)) {
      for (final p in order.participants.where((p) => !p.isPaid)) {
        total += p.totalAmount;
      }
    }
    return total;
  }

  Future<void> loadData() async {
    _activeOrders = await _db.getGroupOrders(settled: false);
    _settledOrders = await _db.getGroupOrders(settled: true);
    notifyListeners();
  }

  Future<void> createGroupOrder({
    required String title,
    required double totalAmount,
    required String payerName,
    required bool payerIsMe,
    required DateTime date,
    String? accountId,
    required List<GroupItem> items,
    required List<GroupParticipant> participants,
    double sharedCosts = 0,
  }) async {
    final orderId = _uuid.v4();

    final finalItems = items.map((item) => item.copyWith(
      id: item.id.isEmpty ? _uuid.v4() : null,
      groupOrderId: orderId,
    )).toList();

    final finalParticipants = participants.map((p) => p.copyWith(
      id: p.id.isEmpty ? _uuid.v4() : null,
      groupOrderId: orderId,
    )).toList();

    final order = GroupOrder(
      id: orderId,
      title: title,
      totalAmount: totalAmount,
      payerName: payerName,
      payerIsMe: payerIsMe,
      date: date,
      accountId: accountId,
      sharedCosts: sharedCosts,
      participants: finalParticipants,
      items: finalItems,
    );

    await _db.insertGroupOrder(order);

    for (final p in finalParticipants) {
      await _db.upsertSavedContact(p.name, _uuid.v4());
    }

    await loadData();
  }

  Future<void> toggleParticipantPaid(String participantId, String orderId) async {
    final order = [..._activeOrders, ..._settledOrders]
        .where((o) => o.id == orderId)
        .firstOrNull;
    if (order == null) return;

    final participant = order.participants
        .where((p) => p.id == participantId)
        .firstOrNull;
    if (participant == null) return;

    final updated = participant.copyWith(
      isPaid: !participant.isPaid,
      paidDate: !participant.isPaid ? DateTime.now() : null,
      clearPaidDate: participant.isPaid,
    );

    await _db.updateParticipant(updated);

    final allPaid = await _db.areAllParticipantsPaid(orderId);
    await _db.markOrderSettled(orderId, allPaid);

    await loadData();
  }

  Future<void> deleteGroupOrder(String orderId) async {
    await _db.deleteGroupOrder(orderId);
    await loadData();
  }

  Future<List<String>> getSavedContacts() async {
    return await _db.getSavedContacts();
  }
}
