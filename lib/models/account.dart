class Account {
  final int? id;
  final String name;
  final String? cardLast4;
  final double balance;
  final String type; // 'bank', 'cash', 'credit'
  final String color;
  final DateTime createdAt;

  Account({
    this.id,
    required this.name,
    this.cardLast4,
    this.balance = 0.0,
    this.type = 'bank',
    this.color = '#00897B',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'card_last4': cardLast4,
      'balance': balance,
      'type': type,
      'color': color,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as int?,
      name: map['name'] as String,
      cardLast4: map['card_last4'] as String?,
      balance: (map['balance'] as num).toDouble(),
      type: map['type'] as String? ?? 'bank',
      color: map['color'] as String? ?? '#00897B',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Account copyWith({
    int? id,
    String? name,
    String? cardLast4,
    double? balance,
    String? type,
    String? color,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      cardLast4: cardLast4 ?? this.cardLast4,
      balance: balance ?? this.balance,
      type: type ?? this.type,
      color: color ?? this.color,
      createdAt: createdAt,
    );
  }
}
