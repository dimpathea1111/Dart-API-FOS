import 'package:mongo_dart/mongo_dart.dart';

class User {
  final ObjectId? id;
  final String name;
  final String email;
  final String? phone;
  final String passwordHash;
  final String? profilePic;
  final bool isVerified;
  final String? deviceToken;
  final double walletBalance;
  final String preferredLanguage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  static DateTime _dateTimeFromValue(Object? value, {DateTime? fallback}) {
    if (value == null) return fallback ?? DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.now();
  }

  static DateTime? _nullableDateTimeFromValue(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  User({
    this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.passwordHash,
    this.profilePic,
    this.isVerified = false,
    this.deviceToken,
    this.walletBalance = 0.0,
    this.preferredLanguage = 'en',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastLogin,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // ⭐ សម្រាប់ Login
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['_id'] is ObjectId ? map['_id'] as ObjectId : null,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String?,
      passwordHash: map['password_hash'] as String? ?? '',
      profilePic: map['profile_pic'] as String?,
      isVerified: (map['is_verified'] as bool?) ?? false,
      deviceToken: map['device_token'] as String?,
      walletBalance: ((map['wallet_balance'] as num?) ?? 0.0).toDouble(),
      preferredLanguage: map['preferred_language'] as String? ?? 'en',
      createdAt: _dateTimeFromValue(map['created_at']),
      updatedAt: _dateTimeFromValue(map['updated_at'], fallback: DateTime.now()),
      lastLogin: _nullableDateTimeFromValue(map['last_login']),
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] is ObjectId ? json['_id'] as ObjectId : null,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      passwordHash: json['password_hash'] as String? ?? '',
      profilePic: json['profile_pic'] as String?,
      isVerified: (json['is_verified'] as bool?) ?? false,
      deviceToken: json['device_token'] as String?,
      walletBalance: ((json['wallet_balance'] as num?) ?? 0.0).toDouble(),
      preferredLanguage: json['preferred_language'] as String? ?? 'en',
      createdAt: _dateTimeFromValue(json['created_at']),
      updatedAt: _dateTimeFromValue(json['updated_at'], fallback: DateTime.now()),
      lastLogin: _nullableDateTimeFromValue(json['last_login']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id?.toHexString(),
      'name': name,
      'email': email,
      'phone': phone,
      'profile_pic': profilePic,
      'is_verified': isVerified,
      'wallet_balance': walletBalance,
      'preferred_language': preferredLanguage,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) '_id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'password_hash': passwordHash,
      'profile_pic': profilePic,
      'is_verified': isVerified,
      'device_token': deviceToken,
      'wallet_balance': walletBalance,
      'preferred_language': preferredLanguage,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_login': lastLogin,
    };
  }

  Map<String, dynamic> toDb() => toMap();
}