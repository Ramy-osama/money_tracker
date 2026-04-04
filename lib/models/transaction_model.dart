class MoneyTransaction {
  final int? id;
  final double amount;
  final String type; // 'income' or 'expense'
  final int categoryId;
  final int accountId;
  final String description;
  final DateTime date;
  final String source; // 'manual', 'sms', 'voice'
  final DateTime createdAt;
  final bool needsReview;

  MoneyTransaction({
    this.id,
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.accountId,
    required this.description,
    required this.date,
    this.source = 'manual',
    DateTime? createdAt,
    this.needsReview = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'amount': amount,
      'type': type,
      'category_id': categoryId,
      'account_id': accountId,
      'description': description,
      'date': date.toIso8601String(),
      'source': source,
      'created_at': createdAt.toIso8601String(),
      'needs_review': needsReview ? 1 : 0,
    };
  }

  factory MoneyTransaction.fromMap(Map<String, dynamic> map) {
    return MoneyTransaction(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      categoryId: map['category_id'] as int,
      accountId: map['account_id'] as int,
      description: map['description'] as String? ?? '',
      date: DateTime.parse(map['date'] as String),
      source: map['source'] as String? ?? 'manual',
      createdAt: DateTime.parse(map['created_at'] as String),
      needsReview: (map['needs_review'] as int?) == 1,
    );
  }

  MoneyTransaction copyWith({
    int? id,
    double? amount,
    String? type,
    int? categoryId,
    int? accountId,
    String? description,
    DateTime? date,
    String? source,
    bool? needsReview,
  }) {
    return MoneyTransaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      description: description ?? this.description,
      date: date ?? this.date,
      source: source ?? this.source,
      createdAt: createdAt,
      needsReview: needsReview ?? this.needsReview,
    );
  }
}
