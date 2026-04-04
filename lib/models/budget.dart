class Budget {
  final int? id;
  final int categoryId;
  final double limitAmount;
  final String period; // 'monthly', 'weekly'
  final DateTime createdAt;

  // Joined field (not stored)
  final String? categoryName;
  final String? categoryIcon;
  final double? spent;

  Budget({
    this.id,
    required this.categoryId,
    required this.limitAmount,
    this.period = 'monthly',
    DateTime? createdAt,
    this.categoryName,
    this.categoryIcon,
    this.spent,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'category_id': categoryId,
      'limit_amount': limitAmount,
      'period': period,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'] as int?,
      categoryId: map['category_id'] as int,
      limitAmount: (map['limit_amount'] as num).toDouble(),
      period: map['period'] as String? ?? 'monthly',
      createdAt: DateTime.parse(map['created_at'] as String),
      categoryName: map['category_name'] as String?,
      categoryIcon: map['category_icon'] as String?,
      spent: (map['spent'] as num?)?.toDouble(),
    );
  }

  Budget copyWith({
    int? id,
    int? categoryId,
    double? limitAmount,
    String? period,
  }) {
    return Budget(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      limitAmount: limitAmount ?? this.limitAmount,
      period: period ?? this.period,
      createdAt: createdAt,
    );
  }

  double get usedPercentage {
    if (limitAmount <= 0) return 0;
    return ((spent ?? 0) / limitAmount * 100).clamp(0, 999);
  }
}
