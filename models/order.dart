class Order {
  final String? id;
  final String userId;
  final String restaurantId;
  final String addressId;
  final String orderNumber;
  final String orderType;
  final double subtotal;
  final double tax;
  final double deliveryFee;
  final double serviceCharge;
  final double discount;
  final double totalAmount;
  final String paymentStatus;
  final String orderStatus;
  final String? deliveryInstructions;
  final String? scheduledTime;
  final String? estimatedDeliveryTime;
  final String? actualDeliveryTime;
  final String createdAt;
  final String updatedAt;

  Order({
    this.id,
    required this.userId,
    required this.restaurantId,
    required this.addressId,
    required this.orderNumber,
    required this.orderType,
    required this.subtotal,
    this.tax = 0.0,
    this.deliveryFee = 0.0,
    this.serviceCharge = 0.0,
    this.discount = 0.0,
    required this.totalAmount,
    this.paymentStatus = 'pending',
    this.orderStatus = 'placed',
    this.deliveryInstructions,
    this.scheduledTime,
    this.estimatedDeliveryTime,
    this.actualDeliveryTime,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['_id']?.toString(),
      userId: json['user_id']?.toString() ?? '',
      restaurantId: json['restaurant_id']?.toString() ?? '',
      addressId: json['address_id']?.toString() ?? '',
      orderNumber: json['order_number']?.toString() ?? '',
      orderType: json['order_type']?.toString() ?? 'delivery',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      tax: (json['tax'] as num?)?.toDouble() ?? 0.0,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      serviceCharge: (json['service_charge'] as num?)?.toDouble() ?? 0.0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      paymentStatus: json['payment_status']?.toString() ?? 'pending',
      orderStatus: json['order_status']?.toString() ?? 'placed',
      deliveryInstructions: json['delivery_instructions']?.toString(),
      scheduledTime: json['scheduled_time']?.toString(),
      estimatedDeliveryTime: json['estimated_delivery_time']?.toString(),
      actualDeliveryTime: json['actual_delivery_time']?.toString(),
      createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'restaurant_id': restaurantId,
      'address_id': addressId,
      'order_number': orderNumber,
      'order_type': orderType,
      'subtotal': subtotal,
      'tax': tax,
      'delivery_fee': deliveryFee,
      'service_charge': serviceCharge,
      'discount': discount,
      'total_amount': totalAmount,
      'payment_status': paymentStatus,
      'order_status': orderStatus,
      'delivery_instructions': deliveryInstructions,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
