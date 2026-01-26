import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class CartItem {
  final int id;
  final Product product;
  final int quantity;
  final double totalPrice;
  
  // Convenience getters
  int get cartItemId => id;
  int get productId => product.id;
  double get price => product.price;

  CartItem({
    required this.id,
    required this.product,
    required this.quantity,
    required this.totalPrice,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'],
      product: Product.fromJson(json['product']),
      quantity: json['quantity'],
      totalPrice: double.parse(json['total_price'].toString()),
    );
  }
}

class Product {
  final int id;
  final String name;
  final double price;
  final String vendorName;
  final int vendorId;
  final List<ProductImage> images;
  final bool freeDelivery;
  final bool customDeliveryFeeEnabled;
  final double? customDeliveryFee;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.vendorName,
    required this.vendorId,
    required this.images,
    required this.freeDelivery,
    required this.customDeliveryFeeEnabled,
    this.customDeliveryFee,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      price: double.parse(json['price'].toString()),
      vendorName: json['vendor_name'] ?? 'Unknown Vendor',
      vendorId: json['vendor_id'] ?? json['vendor'] ?? 0,
      images: (json['images'] as List?)
          ?.map((img) => ProductImage.fromJson(img))
          .toList() ?? [],
      freeDelivery: (json['free_delivery'] as bool?) ?? false,
      customDeliveryFeeEnabled: (json['custom_delivery_fee_enabled'] as bool?) ?? false,
      customDeliveryFee: json['custom_delivery_fee'] != null 
          ? double.parse(json['custom_delivery_fee'].toString()) 
          : null,
    );
  }
}

class ProductImage {
  final String imageUrl;
  final bool isPrimary;

  ProductImage({
    required this.imageUrl,
    required this.isPrimary,
  });

  factory ProductImage.fromJson(Map<String, dynamic> json) {
    return ProductImage(
      imageUrl: json['image_url'],
      isPrimary: json['is_primary'] ?? false,
    );
  }
}

class Cart {
  final List<CartItem> items;
  final double subtotal;
  final int totalItems;

  Cart({
    required this.items,
    required this.subtotal,
    required this.totalItems,
  });

  factory Cart.fromJson(Map<String, dynamic> json) {
    return Cart(
      items: (json['items'] as List)
          .map((item) => CartItem.fromJson(item))
          .toList(),
      subtotal: double.parse(json['subtotal'].toString()),
      totalItems: json['total_items'] ?? 0,
    );
  }
}

class CartService {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  Future<Cart> getCart(String token) async {
    final response = await http.get(
      Uri.parse('${Config.baseUrl}/cart/'),
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode == 200) {
      return Cart.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load cart');
    }
  }

  Future<Map<String, dynamic>> addToCart(String token, int productId, int quantity) async {
    final response = await http.post(
      Uri.parse('${Config.baseUrl}/cart/add/'),
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({
        'product_id': productId,
        'quantity': quantity,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to add to cart');
    }
  }

  Future<Map<String, dynamic>> updateCartItem(String token, int itemId, int quantity) async {
    final response = await http.patch(
      Uri.parse('${Config.baseUrl}/cart/items/$itemId/'),
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({'quantity': quantity}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update cart item');
    }
  }

  Future<void> removeFromCart(String token, int itemId) async {
    final response = await http.delete(
      Uri.parse('${Config.baseUrl}/cart/items/$itemId/'),
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to remove item from cart');
    }
  }

  Future<void> clearCart(String token) async {
    final response = await http.delete(
      Uri.parse('${Config.baseUrl}/cart/clear/'),
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to clear cart');
    }
  }
}