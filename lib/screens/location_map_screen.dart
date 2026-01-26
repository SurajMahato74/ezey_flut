import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme/app_theme.dart';

class LocationMapScreen extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String address;
  final double? vendorShopLatitude;
  final double? vendorShopLongitude;
  final double? vendorCurrentLatitude;
  final double? vendorCurrentLongitude;

  const LocationMapScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.vendorShopLatitude,
    this.vendorShopLongitude,
    this.vendorCurrentLatitude,
    this.vendorCurrentLongitude,
  });

  @override
  State<LocationMapScreen> createState() => _LocationMapScreenState();
}

class _LocationMapScreenState extends State<LocationMapScreen> {
  String _detailedAddress = '';
  bool _isLoadingAddress = false;

  @override
  void initState() {
    super.initState();
    _getDetailedAddress();
  }

  Future<void> _getDetailedAddress() async {
    setState(() => _isLoadingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(widget.latitude, widget.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final addressParts = [
          place.name,
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.country,
        ].where((part) => part != null && part.isNotEmpty).join(', ');
        setState(() {
          _detailedAddress = addressParts;
        });
      }
    } catch (e) {
      // Use the provided address if reverse geocoding fails
      setState(() {
        _detailedAddress = widget.address;
      });
    } finally {
      setState(() => _isLoadingAddress = false);
    }
  }

  void _openInExternalMaps() {
    final url = 'https://maps.google.com/?q=${widget.latitude},${widget.longitude}';
    // In a real app, you would use a package like url_launcher to open this URL
    // For now, we'll just show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Would open: $url')),
    );
  }

  LatLng _getMapCenter() {
    List<LatLng> points = [LatLng(widget.latitude, widget.longitude)];
    
    if (widget.vendorShopLatitude != null && widget.vendorShopLongitude != null) {
      points.add(LatLng(widget.vendorShopLatitude!, widget.vendorShopLongitude!));
    }
    if (widget.vendorCurrentLatitude != null && widget.vendorCurrentLongitude != null) {
      points.add(LatLng(widget.vendorCurrentLatitude!, widget.vendorCurrentLongitude!));
    }
    
    if (points.length == 1) {
      return points[0];
    }
    
    double centerLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    double centerLng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    return LatLng(centerLat, centerLng);
  }

  double _getMapZoom() {
    int locationCount = 1; // Always have delivery location
    if (widget.vendorShopLatitude != null && widget.vendorShopLongitude != null) locationCount++;
    if (widget.vendorCurrentLatitude != null && widget.vendorCurrentLongitude != null) locationCount++;
    
    return locationCount > 1 ? 12.0 : 15.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.homeBackgroundDark,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text(
          'Shared Location',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _openInExternalMaps,
            icon: const Icon(Icons.open_in_new, color: Colors.white),
            tooltip: 'Open in Maps',
          ),
        ],
      ),
      body: Column(
        children: [
          // Address info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Location Details',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _isLoadingAddress
                  ? const Text(
                      'Loading address...',
                      style: TextStyle(color: Colors.grey),
                    )
                  : Text(
                      _detailedAddress.isNotEmpty ? _detailedAddress : widget.address,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.grey[300],
                      ),
                    ),
                const SizedBox(height: 8),
                Text(
                  'Lat: ${widget.latitude.toStringAsFixed(6)}, Lng: ${widget.longitude.toStringAsFixed(6)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
          
          // Map Legend
          if (widget.vendorShopLatitude != null || widget.vendorCurrentLatitude != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (widget.vendorCurrentLatitude != null && widget.vendorCurrentLongitude != null)
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 8),
                        ),
                        const SizedBox(width: 4),
                        Text('Your Location', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white)),
                      ],
                    ),
                  if (widget.vendorShopLatitude != null && widget.vendorShopLongitude != null)
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.store, color: Colors.white, size: 8),
                        ),
                        const SizedBox(width: 4),
                        Text('Shop Location', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white)),
                      ],
                    ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.red, size: 12),
                      const SizedBox(width: 4),
                      Text('Shared Location', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white)),
                    ],
                  ),
                ],
              ),
            ),
          
          // Map
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: _getMapCenter(),
                    initialZoom: _getMapZoom(),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ezeyway.app',
                    ),
                    if (widget.vendorShopLatitude != null && widget.vendorShopLongitude != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [LatLng(widget.vendorShopLatitude!, widget.vendorShopLongitude!), LatLng(widget.latitude, widget.longitude)],
                            strokeWidth: 3.0,
                            color: AppTheme.primaryColor,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (widget.vendorCurrentLatitude != null && widget.vendorCurrentLongitude != null)
                          Marker(
                            point: LatLng(widget.vendorCurrentLatitude!, widget.vendorCurrentLongitude!),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.person_pin_circle,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        if (widget.vendorShopLatitude != null && widget.vendorShopLongitude != null)
                          Marker(
                            point: LatLng(widget.vendorShopLatitude!, widget.vendorShopLongitude!),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.store,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        Marker(
                          point: LatLng(widget.latitude, widget.longitude),
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
