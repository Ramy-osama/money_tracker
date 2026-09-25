class InboxLogEntry {
  final int id;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final bool wasTracked;
  final int? transactionId;
  final bool matched;
  final bool blockedSender;

  InboxLogEntry({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.wasTracked,
    this.transactionId,
    required this.matched,
    required this.blockedSender,
  });

  factory InboxLogEntry.fromMap(Map<String, Object?> m) {
    return InboxLogEntry(
      id: m['id'] as int,
      sender: m['sender'] as String? ?? '',
      body: m['body'] as String,
      receivedAt: DateTime.parse(m['received_at'] as String),
      wasTracked: (m['was_tracked'] as int) == 1,
      transactionId: m['transaction_id'] as int?,
      matched: (m['matched'] as int) == 1,
      blockedSender: (m['blocked_sender'] as int? ?? 0) == 1,
    );
  }
}
