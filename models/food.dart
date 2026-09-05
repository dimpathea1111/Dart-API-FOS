import 'package:json_annotation/json_annotation.dart';

part 'food.g.dart';

@JsonSerializable()
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

  factory Food.fromJson(Map<String, dynamic> json) => _$FoodFromJson(json);
  Map<String, dynamic> toJson() => _$FoodToJson(this);
}