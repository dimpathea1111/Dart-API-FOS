class Address {
  final String? id;
  final String userId;
  final String? restaurantId;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String state;
  final String zipcode;
  final String country;
  final String? latitude;
  final String? longitude;
  final String addressType;
  final bool isDefault;
  final String createdAt;

  Address({
    this.id,
    required this.userId,
    this.restaurantId,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.state,
    required this.zipcode,
    this.country = 'USA',
    this.latitude,
    this.longitude,
    this.addressType = 'home',
    this.isDefault = false,
    required this.createdAt,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      id: json['_id']?.toString(),
      userId: json['user_id']?.toString() ?? '',
      restaurantId: json['restaurant_id']?.toString(),
      addressLine1: json['address_line1']?.toString() ?? '',
      addressLine2: json['address_line2']?.toString(),
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      zipcode: json['zipcode']?.toString() ?? '',
      country: json['country']?.toString() ?? 'USA',
      latitude: json['latitude']?.toString(),
      longitude: json['longitude']?.toString(),
      addressType: json['address_type']?.toString() ?? 'home',
      isDefault: json['is_default'] == true,
      createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'restaurant_id': restaurantId,
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'city': city,
      'state': state,
      'zipcode': zipcode,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'address_type': addressType,
      'is_default': isDefault,
      'created_at': createdAt,
    };
  }
}