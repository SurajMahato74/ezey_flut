// lib/models/order.dart
enum OrderStatus { 
  newOrder, 
  confirmed, 
  shipped, 
  delivered, 
  cancelled, 
  returnRequested,
  refunded 
}

class DeliveryInfo {
  final String deliveryBoyName;
  final String deliveryBoyPhone;
  final String bikeNumber;
  final String bikeColor;
  final DateTime estimatedDelivery;

  DeliveryInfo({
    required this.deliveryBoyName,
    required this.deliveryBoyPhone,
    required this.bikeNumber,
    required this.bikeColor,
    required this.estimatedDelivery,
  });
}

class CustomerReview {
  final int rating;
  final String comment;
  final DateTime reviewDate;

  CustomerReview({
    required this.rating,
    required this.comment,
    required this.reviewDate,
  });
}

class Order {
  final String id;
  final String orderNumber;
  final String customerName;
  final String customerPhone;
  final String location;
  final String deliveryAddress;
  final double amount;
  OrderStatus status;
  final DateTime timestamp;
  final String timeAgo;
  final List<OrderItem> items;
  DeliveryInfo? deliveryInfo;
  CustomerReview? review;
  String? returnReason;
  String? cancellationReason;

  Order({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.customerPhone,
    required this.location,
    required this.deliveryAddress,
    required this.amount,
    required this.status,
    required this.timestamp,
    required this.timeAgo,
    required this.items,
    this.deliveryInfo,
    this.review,
    this.returnReason,
    this.cancellationReason,
  });
}

class OrderItem {
  final String productName;
  final int quantity;
  final double price;
  final String? imageUrl;

  OrderItem({
    required this.productName,
    required this.quantity,
    required this.price,
    this.imageUrl,
  });
}