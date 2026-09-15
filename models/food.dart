class Food {
  final String? id;
  final String name;
  final double price;
  final String description;
  final String restaurantId;
  final bool isAvailable;

  Food({
    this.id,
    required this.name,
    required this.price,
    required this.description,
    required this.restaurantId,
    this.isAvailable = true,
  });

  factory Food.fromJson(Map<String, dynamic> json) => Food(
        id: json['id'] as String?,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        description: json['description'] as String,
        restaurantId: json['restaurantId'] as String,
        isAvailable: json['isAvailable'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'description': description,
        'restaurantId': restaurantId,
        'isAvailable': isAvailable,
      };
}