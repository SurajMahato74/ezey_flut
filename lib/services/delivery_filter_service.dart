import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'location_service.dart';
import 'auth_service.dart';

class DeliveryFilterService {
  static final DeliveryFilterService _instance = DeliveryFilterService._internal();
  factory DeliveryFilterService() => _instance;
  DeliveryFilterService._internal();

  double? _deliveryRadius;
  Position? _userPosition;

  Future<void> initialize() async {
    // Get delivery radius from API
    try {
      _deliveryRadius = await ApiService().getGlobalDeliveryRadius();
    } catch (e) {
      _deliveryRadius = 1000.0; // Default fallback
    }

    // Get user location
    _userPosition = await LocationService().getCurrentPosition();
  }

  Future<bool> isProductVisible(Map<String, dynamic> product) async {
    // Ensure we have the required data
    if (_deliveryRadius == null) {
      await initialize();
    }

    // Check if vendor is within delivery radius
    final vendorLat = product['vendor_latitude'];
    final vendorLon = product['vendor_longitude'];

    if (vendorLat == null || vendorLon == null || _userPosition == null) {
      return false; // Can't determine location
    }

    final distance = LocationService().calculateDistance(
      _userPosition!.latitude,
      _userPosition!.longitude,
      vendorLat,
      vendorLon,
    );

    // Check if within delivery radius
    if (distance > _deliveryRadius!) {
      return false;
    }

    // Check if vendor is online (assuming vendor_online field exists)
    final vendorOnline = product['vendor_online'] ?? true; // Default to true if not specified
    if (!vendorOnline) {
      return false;
    }

    // Check if this is not the user's own product
    final vendorId = product['vendor_id'];
    final currentUserId = AuthService().user?.id;

    if (vendorId != null && currentUserId != null && vendorId == currentUserId) {
      return false; // Don't show own products
    }

    return true;
  }

  Future<List<Map<String, dynamic>>> filterProducts(List<Map<String, dynamic>> products) async {
    if (_deliveryRadius == null) {
      await initialize();
    }

    final filteredProducts = <Map<String, dynamic>>[];

    for (final product in products) {
      if (await isProductVisible(product)) {
        filteredProducts.add(product);
      }
    }

    return filteredProducts;
  }

  double? get deliveryRadius => _deliveryRadius;
  Position? get userPosition => _userPosition;

  // Refresh location and radius data
  Future<void> refresh() async {
    await initialize();
  }
}