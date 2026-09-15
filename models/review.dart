class Review {
  final String? id;
  final String userId;
  final String restaurantId;
  final String? orderId;
  final double rating;
  final String? reviewText;
  final List<String>? images;
  final bool isVerifiedPurchase;
  final String status;
  final String createdAt;
  final String updatedAt;

  Review({
    this.id,
    required this.userId,
    required this.restaurantId,
    this.orderId,
    required this.rating,
    this.reviewText,
    this.images,
    this.isVerifiedPurchase = false,
    this.status = 'pending',
    required this.createdAt,
    required this.updatedAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['_id']?.toString(),
      userId: json['user_id']?.toString() ?? '',
      restaurantId: json['restaurant_id']?.toString() ?? '',
      orderId: json['order_id']?.toString(),
      rating: double.tryParse((json['rating'] ?? 0).toString()) ?? 0.0,
      reviewText: json['review_text']?.toString(),
      images: (json['images'] as List?)?.cast<String>(),
      isVerifiedPurchase: (json['is_verified_purchase'] as bool?) ?? false,
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'restaurant_id': restaurantId,
      'order_id': orderId,
      'rating': rating,
      'review_text': reviewText,
      'images': images,
      'is_verified_purchase': isVerifiedPurchase,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}