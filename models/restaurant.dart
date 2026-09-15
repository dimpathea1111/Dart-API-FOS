class Restaurant {
  final String? id;
  final String name;
  final String? description;
  final String? cuisineType;
  final double rating;
  final double deliveryFee;
  final double minOrderAmount;
  final String? phone;
  final String? email;
  final String? openingTime;
  final String? closingTime;
  final bool isActive;
  final String? bannerImage;
  final String createdAt;
  final String updatedAt;

  Restaurant({
    this.id,
    required this.name,
    this.description,
    this.cuisineType,
    this.rating = 0.0,
    this.deliveryFee = 0.0,
    this.minOrderAmount = 0.0,
    this.phone,
    this.email,
    this.openingTime,
    this.closingTime,
    this.isActive = true,
    this.bannerImage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['_id']?.toString(),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      cuisineType: json['cuisine_type']?.toString(),
      rating: ((json['rating'] as num?) ?? 0).toDouble(),
      deliveryFee: ((json['delivery_fee'] as num?) ?? 0).toDouble(),
      minOrderAmount: ((json['min_order_amount'] as num?) ?? 0).toDouble(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      openingTime: json['opening_time']?.toString(),
      closingTime: json['closing_time']?.toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      bannerImage: json['banner_image']?.toString(),
      createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'cuisine_type': cuisineType,
      'rating': rating,
      'delivery_fee': deliveryFee,
      'min_order_amount': minOrderAmount,
      'phone': phone,
      'email': email,
      'opening_time': openingTime,
      'closing_time': closingTime,
      'is_active': isActive,
      'banner_image': bannerImage,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}