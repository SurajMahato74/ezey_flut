// lib/models/product.dart
class Product {
  final String id;
  String name;
  List<String> imageUrls;
  double price;
  double? costPrice;
  int quantity;
  int soldQuantity;
  List<String> tags;
  bool isOutOfStock;
  String? category;
  String? subcategory;
  String? description;
  bool freeDelivery;
  double? customDeliveryPrice;
  bool isActive;
  List<String> sizes;
  DateTime createdAt;
  DateTime updatedAt;

  Product({
    required this.id,
    required this.name,
    required this.imageUrls,
    required this.price,
    this.costPrice,
    required this.quantity,
    this.soldQuantity = 0,
    required this.tags,
    this.isOutOfStock = false,
    this.category,
    this.subcategory,
    this.description,
    this.freeDelivery = false,
    this.customDeliveryPrice,
    this.isActive = true,
    this.sizes = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Helper getter for main image
  String get imageUrl => imageUrls.isNotEmpty ? imageUrls.first : '';
}