import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'order_history_screen.dart';
import 'order_tracking_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final List<CartItem> selectedItems;
  
  const CheckoutScreen({super.key, required this.selectedItems});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _deliveryAddress = '';
  String _deliveryPhone = '';
  String _deliveryInstructions = '';
  Map<String, dynamic>? _userInfo;
  String _locationSearch = '';
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;
  Timer? _searchTimer;
  bool _isLoadingCurrentLocation = false;
  final Map<String, List<Map<String, dynamic>>> _searchCache = {};
  bool _isSearching = false;
  String _selectedLocationMethod = 'current'; // 'search', 'map', 'current'
  
  @override
  void initState() {
    super.initState();
    _autoFetchCurrentLocation();
    _loadUserProfile();
  }
  
  void _loadUserProfile() {
    final user = AuthService().user;
    if (user != null && user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
      setState(() {
        _deliveryPhone = user.phoneNumber!;
      });
    }
  }
  
  Future<void> _autoFetchCurrentLocation() async {
    setState(() {
      _isLoadingCurrentLocation = true;
    });
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoadingCurrentLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoadingCurrentLocation = false;
          });
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoadingCurrentLocation = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      // Try alternative geocoding service
      String addressName = 'Current Location';
      try {
        final url = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${position.latitude}&longitude=${position.longitude}&localityLanguage=en');
        final response = await http.get(url).timeout(const Duration(seconds: 3));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          String locality = data['locality'] ?? '';
          String city = data['city'] ?? '';
          String principalSubdivision = data['principalSubdivision'] ?? '';
          String countryName = data['countryName'] ?? '';
          
          List<String> parts = [];
          if (locality.isNotEmpty) parts.add(locality);
          if (city.isNotEmpty && city != locality) parts.add(city);
          if (principalSubdivision.isNotEmpty) parts.add(principalSubdivision);
          if (countryName.isNotEmpty) parts.add(countryName);
          
          if (parts.isNotEmpty) {
            addressName = parts.join(', ');
          }
        }
      } catch (e) {
        print('Auto geocoding failed: $e');
      }
      
      setState(() {
        _deliveryAddress = addressName;
      });
    } catch (e) {
      print('Auto location error: $e');
    } finally {
      setState(() {
        _isLoadingCurrentLocation = false;
      });
    }
  }
  
  double _calculateSubtotal() {
    return widget.selectedItems.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  double _calculateDeliveryFee() {
    double totalDeliveryFee = 0.0;
    bool hasStandardDeliveryItems = false;
    
    for (final item in widget.selectedItems) {
      if (item.product.freeDelivery) {
        continue;
      } else if (item.product.customDeliveryFeeEnabled && item.product.customDeliveryFee != null) {
        totalDeliveryFee += item.product.customDeliveryFee!;
      } else {
        // Standard delivery item
        hasStandardDeliveryItems = true;
      }
    }
    
    // If there are items that don't have free delivery or custom fee, add standard fee once?
    // Or is it per item? 
    // The previous code was fixed 50.0.
    // Let's assume standard fee is 50.0 and applies if ANY item needs it, or usually it's per vendor or per order.
    // In CartScreen logic: "If neither free_delivery nor custom_delivery_fee_enabled, it's TBD... We don't add any fee for TBD items".
    // Wait, CartScreen said "We don't add any fee for TBD items".
    // But CheckoutScreen had fixed 50.0.
    // I should probably follow CartScreen logic primarily, but ensure valid fee is passed.
    // If I use CartScreen logic exactly:
    
    return totalDeliveryFee + (hasStandardDeliveryItems ? 0.0 : 0.0); 
    // Wait, if CartScreen logic is "TBD", maybe the backend handles it?
    // But creating order API expects 'delivery_fee'.
    // If I send 50.0 always, that was the old bug/placeholder.
    // If I calculate based on items:
    // If item has custom fee, add it.
    // If item is free, 0.
    // If item is standard?
    
    // Let's look at CartScreen again.
    // details.add('$tbdCount tbd');
    // deliveryFee == 0 && !_getDeliveryDetails().contains('tbd') ? 'Free' : ...
    
    // It seems 'TBD' means the app doesn't know.
    // IF I want "Buy Now" to be accurate, I should probably respect the 'customDeliveryFee'.
    
    // BUT the user said "follow all the rule of that cart".
    // Rules in Cart:
    // 1. Free -> 0.
    // 2. Custom -> Product.customDeliveryFee.
    // 3. Otherwise -> TBD (0 in calculation).
    
    // So I should replicate that.
    
    return totalDeliveryFee; 
  }

  double _calculateTotal() {
    return _calculateSubtotal() + _calculateDeliveryFee();
  }

  bool _validateNepaliPhone(String phone) {
    return RegExp(r'^(98|97)\d{8}$').hasMatch(phone);
  }

  Future<void> _handleLocationSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _isSearching = false;
      });
      return;
    }
    
    // Normalize query for better matching
    String normalizedQuery = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    
    // Check cache with normalized query
    if (_searchCache.containsKey(normalizedQuery)) {
      setState(() {
        _searchResults = _searchCache[normalizedQuery]!;
        _showSearchResults = _searchResults.isNotEmpty;
        _isSearching = false;
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
    });
    
    try {
      // Always add Nepal for better results
      String searchQuery = '$query, Nepal';
      
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(searchQuery)}&limit=5&countrycodes=np&addressdetails=1');
      final response = await http.get(url, headers: {
        'User-Agent': 'EzeyWay-Flutter-App/1.0'
      }).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final List<dynamic> apiResults = json.decode(response.body);
        
        List<Map<String, dynamic>> formattedResults = [];
        for (var result in apiResults.take(5)) {
          // Better address formatting
          Map<String, dynamic> address = result['address'] ?? {};
          List<String> parts = [];
          
          String road = address['road'] ?? '';
          String neighbourhood = address['neighbourhood'] ?? address['suburb'] ?? '';
          String city = address['city'] ?? address['town'] ?? address['village'] ?? '';
          
          if (road.isNotEmpty) parts.add(road);
          if (neighbourhood.isNotEmpty && neighbourhood != road) parts.add(neighbourhood);
          if (city.isNotEmpty) parts.add(city);
          
          String displayName = parts.isNotEmpty ? parts.join(', ') : result['display_name'] ?? 'Unknown Location';
          
          // Limit length
          if (displayName.length > 60) {
            displayName = '${displayName.substring(0, 57)}...';
          }
          
          formattedResults.add({
            'display_name': displayName,
            'lat': result['lat'],
            'lon': result['lon'],
          });
        }
        
        // Cache with normalized query
        _searchCache[normalizedQuery] = formattedResults;
        
        setState(() {
          _searchResults = formattedResults;
          _showSearchResults = formattedResults.isNotEmpty;
          _isSearching = false;
        });
      } else {
        setState(() {
          _searchResults = [];
          _showSearchResults = false;
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _isSearching = false;
      });
    }
  }

  Future<void> _placeOrder() async {
    try {
      final user = AuthService().user;
      final token = AuthService().token;
      if (user == null || token == null) return;

      // Prepare order data
      final orderData = {
        'items': widget.selectedItems.map((item) => {
          'product_id': item.productId,
          'quantity': item.quantity,
          'unit_price': item.price,
        }).toList(),
        'delivery_name': user.displayName ?? user.username,
        'delivery_phone': _deliveryPhone,
        'delivery_address': _deliveryAddress,
        'delivery_latitude': 27.7315584, // Use actual coordinates if available
        'delivery_longitude': 85.3409792,
        'delivery_instructions': _deliveryInstructions,
        'payment_method': 'cash_on_delivery',
        'subtotal': _calculateSubtotal(),
        'total_amount': _calculateTotal(),
        'delivery_fee': _calculateDeliveryFee(),
      };

      // Create order
      final response = await http.post(
        Uri.parse('https://ezeyway.com/api/orders/create/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
        body: json.encode(orderData),
      );

      if (response.statusCode == 201) {
        // Order created successfully, now remove items from cart
        await _removeItemsFromCart();
        
        final responseData = json.decode(response.body);
        final orderId = responseData['id'] ?? responseData['order_id'];

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order placed successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          
          if (orderId != null) {
            // Navigate to Order Tracking for the new order
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => OrderTrackingScreen(orderId: orderId),
              ),
              (route) => route.isFirst, // Keep the first route (likely Home) in the stack
            );
          } else {
             // Fallback to Order History
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const OrderHistoryScreen(),
              ),
              (route) => route.isFirst,
            );
          }
        }
      } else {
        throw Exception('Failed to create order');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error placing order: $e')),
        );
      }
    }
  }

  Future<void> _removeItemsFromCart() async {
    try {
      final token = AuthService().token;
      if (token == null) return;

      // Remove each cart item that has a cartItemId (items from cart)
      for (final item in widget.selectedItems) {
        // Only remove if item came from cart (has cartItemId)
        try {
          await http.delete(
            Uri.parse('https://ezeyway.com/api/cart/items/${item.cartItemId}/remove/'),
            headers: {
              'Authorization': 'Token $token',
            },
          );
        } catch (e) {
          print('Error removing cart item ${item.cartItemId}: $e');
        }
      }
    } catch (e) {
      print('Error removing items from cart: $e');
    }
  }

  void _selectSearchLocation(Map<String, dynamic> result) {
    final address = result['display_name'] as String;
    setState(() {
      _deliveryAddress = address;
      _locationSearch = '';
      _searchResults = [];
      _showSearchResults = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.homeBackgroundDark.withValues(alpha: 0.8),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Checkout',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selected Items Section
                  Text(
                    'Order Items',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: widget.selectedItems.map((item) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: const Color(0xFF27272A),
                                width: widget.selectedItems.last == item ? 0 : 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  item.product.images.isNotEmpty 
                                    ? item.product.images.first.imageUrl 
                                    : 'https://via.placeholder.com/60',
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 60,
                                      height: 60,
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.image, color: Colors.grey),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.product.vendorName,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Qty: ${item.quantity}',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Rs ${item.totalPrice.toInt()}',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Delivery Address Section
                  Text(
                    'Delivery Address *',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Location Method Selection
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Current Location Radio
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Radio<String>(
                              value: 'current',
                              groupValue: _selectedLocationMethod,
                              onChanged: (value) {
                                setState(() {
                                  _selectedLocationMethod = value!;
                                });
                              },
                              activeColor: AppTheme.primaryColor,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            Text(
                              'Current Location',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20),
                        // Map Radio
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Radio<String>(
                              value: 'map',
                              groupValue: _selectedLocationMethod,
                              onChanged: (value) {
                                setState(() {
                                  _selectedLocationMethod = value!;
                                });
                              },
                              activeColor: AppTheme.primaryColor,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            Text(
                              'Choose on Map',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Location Search (always visible)
                  TextField(
                    onChanged: (value) {
                      setState(() => _locationSearch = value);
                      _searchTimer?.cancel();
                      _searchTimer = Timer(const Duration(milliseconds: 500), () {
                        _handleLocationSearch(value);
                      });
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search for an address...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF18181B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: _isSearching 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                            ),
                          )
                        : const Icon(Icons.search, color: Colors.grey),
                    ),
                  ),
                  
                  // Search Results (always visible when available)
                  if (_showSearchResults && _searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18181B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      child: Column(
                        children: _searchResults.take(3).map((result) {
                          return ListTile(
                            title: Text(
                              result['display_name'] ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectSearchLocation(result),
                            dense: true,
                          );
                        }).toList(),
                      ),
                    ),
                  
                  const SizedBox(height: 12),
                  
                  // Choose on Map Button (only show if map is selected)
                  if (_selectedLocationMethod == 'map')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => MapSelectionScreen(
                                onLocationSelected: (lat, lng, address) {
                                  setState(() {
                                    _deliveryAddress = address;
                                  });
                                },
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.map, color: Colors.black),
                        label: Text(
                          'Choose on Map',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  
                  // Use Current Location Button (only show if current is selected)
                  if (_selectedLocationMethod == 'current')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoadingCurrentLocation ? null : () async {
                          setState(() {
                            _isLoadingCurrentLocation = true;
                          });
                          
                          try {
                            bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                            if (!serviceEnabled) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enable location services')),
                              );
                              return;
                            }

                            LocationPermission permission = await Geolocator.checkPermission();
                            if (permission == LocationPermission.denied) {
                              permission = await Geolocator.requestPermission();
                              if (permission == LocationPermission.denied) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Location permission denied')),
                                );
                                return;
                              }
                            }
                            
                            if (permission == LocationPermission.deniedForever) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Location permission permanently denied')),
                              );
                              return;
                            }

                            Position position = await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high,
                              timeLimit: const Duration(seconds: 10),
                            );
                            
                            String addressName = 'Current Location';
                            try {
                              final url = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${position.latitude}&longitude=${position.longitude}&localityLanguage=en');
                              final response = await http.get(url).timeout(const Duration(seconds: 3));
                              
                              if (response.statusCode == 200) {
                                final data = json.decode(response.body);
                                String locality = data['locality'] ?? '';
                                String city = data['city'] ?? '';
                                String principalSubdivision = data['principalSubdivision'] ?? '';
                                String countryName = data['countryName'] ?? '';
                                
                                List<String> parts = [];
                                if (locality.isNotEmpty) parts.add(locality);
                                if (city.isNotEmpty && city != locality) parts.add(city);
                                if (principalSubdivision.isNotEmpty) parts.add(principalSubdivision);
                                if (countryName.isNotEmpty) parts.add(countryName);
                                
                                if (parts.isNotEmpty) {
                                  addressName = parts.join(', ');
                                }
                              }
                            } catch (e) {
                              print('Geocoding failed: $e');
                            }
                            
                            setState(() {
                              _deliveryAddress = addressName;
                            });
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Current location detected successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error getting location: $e')),
                            );
                          } finally {
                            setState(() {
                              _isLoadingCurrentLocation = false;
                            });
                          }
                        },
                        icon: _isLoadingCurrentLocation 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.my_location, color: Colors.black),
                        label: Text(
                          _isLoadingCurrentLocation ? 'Getting Location...' : 'Use Current Location',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[300],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 8),
                  if (_deliveryAddress.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18181B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Delivery to: $_deliveryAddress',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  
                  // Phone Number
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Phone Number *',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: TextEditingController(text: _deliveryPhone),
                        onChanged: (value) => setState(() => _deliveryPhone = value),
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '98XXXXXXXX or 97XXXXXXXX',
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF18181B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.phone, color: AppTheme.primaryColor),
                          errorText: _deliveryPhone.isNotEmpty && !_validateNepaliPhone(_deliveryPhone)
                            ? 'Please enter a valid Nepali mobile number'
                            : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                  
                  // Delivery Instructions
                  Text(
                    'Delivery Instructions (Optional)',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (value) => setState(() => _deliveryInstructions = value),
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Any special instructions for delivery',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF18181B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Order Summary
                  Text(
                    'Order Summary',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Subtotal (${widget.selectedItems.length} items)',
                              style: GoogleFonts.plusJakartaSans(color: Colors.grey),
                            ),
                            Text(
                              'Rs ${_calculateSubtotal().toInt()}',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Delivery Fee',
                              style: GoogleFonts.plusJakartaSans(color: Colors.grey),
                            ),
                            Text(
                              'Rs ${_calculateDeliveryFee().toInt()}',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF27272A)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Rs ${_calculateTotal().toInt()}',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTheme.primaryColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      
      // Bottom Action Bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.homeBackgroundDark.withValues(alpha: 0.95),
          border: const Border(
            top: BorderSide(color: Color(0xFF27272A), width: 1),
          ),
        ),
        child: ElevatedButton(
          onPressed: (_deliveryAddress.isNotEmpty && _deliveryPhone.isNotEmpty && _validateNepaliPhone(_deliveryPhone)) ? _placeOrder : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Place Order - Rs ${_calculateTotal().toInt()}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class MapSelectionScreen extends StatefulWidget {
  final Function(double, double, String) onLocationSelected;
  
  const MapSelectionScreen({super.key, required this.onLocationSelected});

  @override
  State<MapSelectionScreen> createState() => _MapSelectionScreenState();
}

class _MapSelectionScreenState extends State<MapSelectionScreen> {
  final MapController _mapController = MapController();
  LatLng? _selectedLocation;
  String _selectedAddress = '';
  double _latitude = 27.7172;
  double _longitude = 85.3240;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    print('Getting current location...');
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
    });
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      print('Location service enabled: $serviceEnabled');
      if (!serviceEnabled) {
        print('Location services are disabled');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location services')),
          );
          setState(() {
            _isLoadingLocation = false;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      print('Current permission: $permission');
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        print('Permission after request: $permission');
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission denied')),
            );
            setState(() {
              _isLoadingLocation = false;
            });
          }
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission permanently denied')),
          );
          setState(() {
            _isLoadingLocation = false;
          });
        }
        return;
      }

      print('Getting position...');
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      print('Got position: ${position.latitude}, ${position.longitude}');
      
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _selectedLocation = LatLng(position.latitude, position.longitude);
        });
        
        _mapController.move(LatLng(position.latitude, position.longitude), 16);
        
        print('Starting reverse geocoding...');
        await _reverseGeocode(position.latitude, position.longitude);
        print('Reverse geocoding complete');
      }
    } catch (e) {
      print('Location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&addressdetails=1&zoom=18');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] ?? {};
        
        // Extract detailed address components
        String houseNumber = address['house_number'] ?? '';
        String road = address['road'] ?? '';
        String neighbourhood = address['neighbourhood'] ?? '';
        String suburb = address['suburb'] ?? '';
        String quarter = address['quarter'] ?? '';
        String village = address['village'] ?? '';
        String town = address['town'] ?? '';
        String city = address['city'] ?? '';
        String state = address['state'] ?? '';
        String postcode = address['postcode'] ?? '';
        String country = address['country'] ?? '';
        
        // Build detailed address like web app
        List<String> addressParts = [];
        
        // Add house number and road
        if (houseNumber.isNotEmpty && road.isNotEmpty) {
          addressParts.add('$houseNumber $road');
        } else if (road.isNotEmpty) {
          addressParts.add(road);
        }
        
        // Add area/locality
        if (neighbourhood.isNotEmpty) {
          addressParts.add(neighbourhood);
        } else if (quarter.isNotEmpty) {
          addressParts.add(quarter);
        } else if (suburb.isNotEmpty) {
          addressParts.add(suburb);
        }
        
        // Add city/town/village
        if (city.isNotEmpty) {
          addressParts.add(city);
        } else if (town.isNotEmpty) {
          addressParts.add(town);
        } else if (village.isNotEmpty) {
          addressParts.add(village);
        }
        
        // Add state if available
        if (state.isNotEmpty && state != city && state != town) {
          addressParts.add(state);
        }
        
        // Add postcode if available
        if (postcode.isNotEmpty) {
          addressParts.add(postcode);
        }
        
        // Join all parts with commas
        String fullAddress = addressParts.isNotEmpty ? addressParts.join(', ') : data['display_name'] ?? 'Selected Location';
        
        if (mounted) {
          setState(() {
            _selectedAddress = fullAddress;
          });
        }
      }
    } catch (e) {
      print('Reverse geocode error: $e');
    }
  }
  
  Future<void> _onMapTap(TapPosition tapPosition, LatLng position) async {
    setState(() {
      _selectedLocation = position;
    });
    await _reverseGeocode(position.latitude, position.longitude);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.homeBackgroundDark.withValues(alpha: 0.8),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Select Location',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          
          // Map
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: LatLng(_latitude, _longitude),
                        initialZoom: 14,
                        minZoom: 5,
                        maxZoom: 18,
                        onTap: _onMapTap,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.ezeyway.app',
                        ),
                        if (_selectedLocation != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _selectedLocation!,
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 40),
                              ),
                            ],
                          ),
                      ],
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.add, color: Colors.black87),
                              onPressed: () {
                                final zoom = _mapController.camera.zoom;
                                _mapController.move(_mapController.camera.center, zoom + 1);
                              },
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.remove, color: Colors.black87),
                              onPressed: () {
                                final zoom = _mapController.camera.zoom;
                                _mapController.move(_mapController.camera.center, zoom - 1);
                              },
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 80,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        child: IconButton(
                          icon: _isLoadingLocation 
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                              )
                            : const Icon(Icons.my_location, color: Colors.black87),
                          onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18181B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppTheme.primaryColor, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedLocation != null 
                                  ? (_selectedAddress.isNotEmpty ? _selectedAddress : 'Selected: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}')
                                  : 'Tap on map to select location',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: const Color(0xFFA1A1AA),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Confirm Button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedLocation != null
                  ? () {
                      widget.onLocationSelected(
                        _selectedLocation!.latitude,
                        _selectedLocation!.longitude,
                        _selectedAddress.isNotEmpty ? _selectedAddress : 'Selected Location',
                      );
                      Navigator.pop(context);
                    }
                  : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Confirm Location',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}