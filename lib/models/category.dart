class Category {
  final int? id;
  final String name;
  final String iconName;
  final String type; // 'income' or 'expense'
  final bool isDefault;

  Category({
    this.id,
    required this.name,
    required this.iconName,
    required this.type,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'icon_name': iconName,
      'type': type,
      'is_default': isDefault ? 1 : 0,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      iconName: map['icon_name'] as String,
      type: map['type'] as String,
      isDefault: (map['is_default'] as int?) == 1,
    );
  }

  Category copyWith({
    int? id,
    String? name,
    String? iconName,
    String? type,
    bool? isDefault,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      type: type ?? this.type,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
