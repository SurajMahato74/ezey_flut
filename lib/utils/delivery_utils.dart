// lib/utils/delivery_utils.dart
import 'dart:math' as math;

Map<String, dynamic> getDeliveryInfo(Map<String, dynamic> product, double? vendorDeliveryFee) {
  // Helper to check truthy values
  bool isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  final bool freeDelivery = isTruthy(product['free_delivery']);
  
  // Try multiple common keys for custom delivery fee
  final dynamic rawCustomFee = product['custom_delivery_fee'] ?? 
                               product['custom_delivery_price'];
  final double? customFee = double.tryParse(rawCustomFee?.toString() ?? '');
  
  // Check if custom fee is specifically enabled OR if the key exists with a value
  final bool hasCustomFee = isTruthy(product['custom_delivery_fee_enabled']) || 
                           (rawCustomFee != null && customFee != null);
  
  // Try multiple common keys for vendor-level delivery fee
  final double? effectiveVendorFee = vendorDeliveryFee ?? 
                                   double.tryParse(product['vendor_delivery_fee']?.toString() ?? '') ??
                                   double.tryParse(product['vendor_delivery_price']?.toString() ?? '') ??
                                   double.tryParse(product['delivery_fee']?.toString() ?? '') ??
                                   double.tryParse(product['vendor']?['delivery_fee']?.toString() ?? '');

  // 1. Explicit Free Delivery
  if (freeDelivery) {
    return {
      'isFreeDelivery': true,
      'deliveryFee': 0.0,
    };
  }

  // 2. Custom Product Fee (if enabled or clearly provided)
  if (hasCustomFee && customFee != null) {
    if (customFee == 0) {
      return {
        'isFreeDelivery': true,
        'deliveryFee': 0.0,
      };
    }
    return {
      'isFreeDelivery': false,
      'deliveryFee': customFee,
    };
  }

  // 3. Vendor Level Fee
  if (effectiveVendorFee != null) {
    if (effectiveVendorFee == 0) {
      return {
        'isFreeDelivery': true,
        'deliveryFee': 0.0,
      };
    }
    return {
      'isFreeDelivery': false,
      'deliveryFee': effectiveVendorFee,
    };
  }

  // 4. Fallback (TBD)
  return {
    'isFreeDelivery': false,
    'deliveryFee': null,
  };
}

double? getDeliveryRadiusSync(Map<String, dynamic> item) {
  // Assuming the item has delivery_radius field, default to 100 km if not present
  return item['delivery_radius']?.toDouble() ?? 100.0;
}

double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371000; // Earth's radius in meters
  double toRad(double deg) => deg * (math.pi / 180);

  final double dLat = toRad(lat2 - lat1);
  final double dLon = toRad(lon2 - lon1);
  final double lat1Rad = toRad(lat1);
  final double lat2Rad = toRad(lat2);

  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1Rad) * math.cos(lat2Rad) *
      math.sin(dLon / 2) * math.sin(dLon / 2);

  final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return (R * c) / 1000; // Return in kilometers
}