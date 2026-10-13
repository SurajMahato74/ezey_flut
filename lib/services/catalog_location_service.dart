import 'package:geolocator/geolocator.dart';

/// Optional location for distance labels only; never controls catalog visibility.
class CatalogLocationService {
  static final CatalogLocationService _instance = CatalogLocationService._internal();
  factory CatalogLocationService() => _instance;
  CatalogLocationService._internal();

  Position? _userPosition;
  Position? get userPosition => _userPosition;

  Future<void> initialize() async {
    try {
      // Browsing does not request location permission or wait for a GPS fix.
      _userPosition = await Geolocator.getLastKnownPosition();
    } catch (_) {
      _userPosition = null;
    }
  }
}
