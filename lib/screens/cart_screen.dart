import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/data_preloader_service.dart';
import 'order_confirmation_screen.dart';
import 'notification_screen.dart';
import 'checkout_screen.dart';
import 'message_inbox_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with WidgetsBindingObserver {
  final CartService _cartService = CartService();
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();
  
  Cart? cart;
  bool loading = false;
  List<int> selectedIds = [];
  List<Map<String, dynamic>> recommendedProducts = [];
  bool loadingRecommended = false;
  bool isLoadingMore = false;
  bool hasMoreProducts = true;
  int currentPage = 1;
  final ScrollController _scrollController = ScrollController();
  Timer? _cartSyncTimer;
  String? _lastCartHash;
  int _notificationCount = 0;
  final Map<int, bool> _vendorStatuses = {};
  final bool _isFiltering = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadCart();
    _loadRecommendedProducts();
    _startCartSync();
    _fetchNotificationCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _cartSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncCartImmediately();
    }
  }

  void _startCartSync() {
    _cartSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _syncCartImmediately();
    });
  }

  String _generateCartHash(Cart? cart) {
    if (cart == null) return '';
    final items = cart.items.map((item) => '${item.id}:${item.quantity}').join(',');
    return '${cart.items.length}:$items';
  }

  Future<void> _syncCartImmediately() async {
    try {
      final token = _authService.token;
      if (token != null) {
        final freshCart = await _cartService.getCart(token);
        final newHash = _generateCartHash(freshCart);
        
        if (_lastCartHash != null && _lastCartHash != newHash && mounted) {
          final filteredItems = await _filterCartItems(freshCart.items ?? []);
          
          if (mounted) {
            setState(() {
              double newSubtotal = 0;
              for (var item in filteredItems) {
                newSubtotal += item.totalPrice;
              }
              
              cart = Cart(
                items: filteredItems,
                subtotal: newSubtotal,
                totalItems: filteredItems.length,
              );
              
              // Preserve selections for existing items
              selectedIds = selectedIds.where((id) => 
                filteredItems.any((item) => item.id == id) ?? false
              ).toList();
            });
          }
        }
        _lastCartHash = newHash;
      }
    } catch (e) {
      // Handle silently
    }
  }

  Future<void> _fetchNotificationCount() async {
    final token = _authService.token;
    if (token == null) return;

    try {
      final response = await _apiService.getNotifications(token, page: 1);
      List<dynamic> notifications = [];
      if (response is List) {
        notifications = response;
      } else if (response is Map && response['results'] != null) {
        notifications = response['results'];
      }
      
      final currentRole = AuthService().currentRole;
      final currentRoleString = currentRole?.toString().split('.').last ?? 'customer';
      
      final filteredNotifications = notifications.where((notification) {
        final notificationRole = notification['role'] ?? 'customer';
        return notificationRole == currentRoleString && notification['is_read'] != true;
      }).toList();
      
      if (mounted) {
        setState(() {
          _notificationCount = filteredNotifications.length;
        });
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _loadCart() async {
    // Load cached cart first for instant display
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    final cachedCartData = preloader.cart;
    
    if (cachedCartData != null) {
      try {
        final cachedCart = Cart.fromJson(cachedCartData);
        final filteredItems = await _filterCartItems(cachedCart.items);
        
        if (mounted) {
          setState(() {
            double newSubtotal = 0;
            for (var item in filteredItems) {
              newSubtotal += item.totalPrice;
            }
            
            cart = Cart(
              items: filteredItems,
              subtotal: newSubtotal,
              totalItems: filteredItems.length,
            );
            selectedIds = [];
          });
        }
        _lastCartHash = _generateCartHash(cart);
      } catch (e) {
        debugPrint('Error parsing cached cart: $e');
      }
    }
    
    // Background refresh
    _refreshCartInBackground();
  }

  Future<void> _refreshCartInBackground() async {
    try {
      final token = _authService.token;
      if (token != null) {
        final loadedCart = await _cartService.getCart(token);
        final filteredItems = await _filterCartItems(loadedCart.items);
        
        if (mounted) {
          setState(() {
            double newSubtotal = 0;
            for (var item in filteredItems) {
              newSubtotal += item.totalPrice;
            }
            
            cart = Cart(
              items: filteredItems,
              subtotal: newSubtotal,
              totalItems: filteredItems.length,
            );
          });
        }
      }
    } catch (e) {
      // Handle error silently for background refresh
    }
  }

  Future<void> _refreshCart() async {
    try {
      final token = _authService.token;
      if (token != null) {
        final loadedCart = await _cartService.getCart(token);
        final filteredItems = await _filterCartItems(loadedCart.items);
        
        if (mounted) {
          setState(() {
            double newSubtotal = 0;
            for (var item in filteredItems) {
              newSubtotal += item.totalPrice;
            }
            
            cart = Cart(
              items: filteredItems,
              subtotal: newSubtotal,
              totalItems: filteredItems.length,
            );
            
            // Preserve selections for existing items
            selectedIds = selectedIds.where((id) => 
              filteredItems.any((item) => item.id == id) ?? false
            ).toList();
          });
        }
      }
    } catch (e) {
      // Handle error silently for refresh
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !isLoadingMore &&
        hasMoreProducts) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadRecommendedProducts() async {
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    final cachedProducts = preloader.trendingProducts;
    
    if (cachedProducts != null && cachedProducts.isNotEmpty) {
      final filteredProducts = await _filterRawProducts(cachedProducts);
      
      final products = filteredProducts.take(6).map((product) {
        final primaryImage = (product['images'] as List?)
            ?.firstWhere((img) => img['is_primary'] == true, orElse: () => (product['images'] as List).isNotEmpty ? (product['images'] as List)[0] : null);
        
        return {
          'id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'image': primaryImage?['image_url'] ?? 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&q=80&w=200&h=200',
          'vendor': product['vendor_name'] ?? 'Unknown Vendor',
          'vendor_id': product['vendor_id'],
          'distance': 'N/A',
        };
      }).toList();
      
      if (mounted) {
        setState(() {
          recommendedProducts = products;
          loadingRecommended = false;
          hasMoreProducts = filteredProducts.length > 6;
        });
      }
      
      // Background refresh
      _refreshProductsInBackground();
      return;
    }
    
    await _fetchFreshProducts();
  }

  Future<void> _refreshProductsInBackground() async {
    try {
      await _fetchFreshProducts(showLoading: false);
    } catch (e) {
      // Handle silently
    }
  }

  Future<void> _fetchFreshProducts({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => loadingRecommended = true);
    
    try {
      final location = await _locationService.getCurrentPosition();
      final response = await _apiService.searchProducts(
        latitude: location?.latitude,
        longitude: location?.longitude,
        pageSize: 6,
        page: 1,
      );
      
      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      final filteredRawProducts = await _filterRawProducts(allProducts);
      
      final products = filteredRawProducts.map((product) {
        final primaryImage = (product['images'] as List?)
            ?.firstWhere((img) => img['is_primary'] == true, orElse: () => (product['images'] as List).isNotEmpty ? (product['images'] as List)[0] : null);
        
        String distance = 'N/A';
        if (location != null && product['vendor_latitude'] != null && product['vendor_longitude'] != null) {
          final distanceKm = _locationService.calculateDistance(
            location.latitude,
            location.longitude,
            product['vendor_latitude'].toDouble(),
            product['vendor_longitude'].toDouble(),
          );
          distance = '${distanceKm.toStringAsFixed(1)} km';
        }
        
        return {
          'id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'image': primaryImage?['image_url'] ?? 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&q=80&w=200&h=200',
          'vendor': product['vendor_name'] ?? 'Unknown Vendor',
          'vendor_id': product['vendor_id'],
          'distance': distance,
        };
      }).toList();
      
      if (mounted) {
        setState(() {
          recommendedProducts = products;
          loadingRecommended = false;
          currentPage = 1;
          hasMoreProducts = response['next'] != null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loadingRecommended = false);
    }
  }

  Future<void> _loadMoreProducts() async {
    if (isLoadingMore || !hasMoreProducts) return;
    
    setState(() => isLoadingMore = true);
    
    try {
      final location = await _locationService.getCurrentPosition();
      final response = await _apiService.searchProducts(
        latitude: location?.latitude,
        longitude: location?.longitude,
        pageSize: 6,
        page: currentPage + 1,
      );
      
      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      final filteredRawProducts = await _filterRawProducts(allProducts);
      
      final products = filteredRawProducts.map((product) {
        final primaryImage = (product['images'] as List?)
            ?.firstWhere((img) => img['is_primary'] == true, orElse: () => (product['images'] as List).isNotEmpty ? (product['images'] as List)[0] : null);
        
        String distance = 'N/A';
        if (location != null && product['vendor_latitude'] != null && product['vendor_longitude'] != null) {
          final distanceKm = _locationService.calculateDistance(
            location.latitude,
            location.longitude,
            product['vendor_latitude'].toDouble(),
            product['vendor_longitude'].toDouble(),
          );
          distance = '${distanceKm.toStringAsFixed(1)} km';
        }
        
        return {
          'id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'image': primaryImage?['image_url'] ?? 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&q=80&w=200&h=200',
          'vendor': product['vendor_name'] ?? 'Unknown Vendor',
          'vendor_id': product['vendor_id'],
          'distance': distance,
        };
      }).toList();
      
      if (mounted) {
        setState(() {
          recommendedProducts.addAll(products);
          currentPage++;
          hasMoreProducts = response['next'] != null;
          isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoadingMore = false);
    }
  }

  Future<void> _updateCartItemQuantity(int itemId, int quantity) async {
    final token = _authService.token;
    if (token == null) return;

    try {
      await _apiService.updateCartItem(token, itemId, quantity);
      _refreshCart();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update cart item'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeCartItem(int itemId) async {
    final token = _authService.token;
    if (token == null) return;

    try {
      await _apiService.removeCartItem(token, itemId);
      _refreshCart();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to remove cart item'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _updateQuantity(int itemId, int delta) async {
    final item = cart?.items.firstWhere((item) => item.id == itemId);
    if (item != null) {
      final newQuantity = item.quantity + delta;
      if (newQuantity > 0) {
        await _updateCartItemQuantity(itemId, newQuantity);
      } else {
        await _removeCartItem(itemId);
      }
    }
  }

  Future<void> _removeItem(int itemId) async {
    await _removeCartItem(itemId);
  }

  Future<List<CartItem>> _filterCartItems(List<CartItem> items) async {
    final uniqueVendorIds = items.map((item) => item.product.vendorId).toSet().toList();
    
    await Future.wait(uniqueVendorIds.map((vendorId) async {
      // Don't refetch if we already checked in this session
      if (!_vendorStatuses.containsKey(vendorId)) {
        try {
          final vendor = await _apiService.getVendorDetails(vendorId);
          _vendorStatuses[vendorId] = vendor['is_active'] == true;
        } catch (e) {
          _vendorStatuses[vendorId] = false;
        }
      }
    }));
    
    return items.where((item) => _vendorStatuses[item.product.vendorId] == true).toList();
  }

  Future<List<Map<String, dynamic>>> _filterRawProducts(List<Map<String, dynamic>> products) async {
    final uniqueVendorIds = products
        .map((p) => p['vendor_id'] ?? p['vendor'] as int?)
        .where((id) => id != null)
        .cast<int>()
        .toSet()
        .toList();
    
    await Future.wait(uniqueVendorIds.map((vendorId) async {
      if (!_vendorStatuses.containsKey(vendorId)) {
        try {
          final vendor = await _apiService.getVendorDetails(vendorId);
          _vendorStatuses[vendorId] = vendor['is_active'] == true;
        } catch (e) {
          _vendorStatuses[vendorId] = false;
        }
      }
    }));
    
    return products.where((p) {
      final vendorId = p['vendor_id'] ?? p['vendor'] as int?;
      return vendorId != null && _vendorStatuses[vendorId] == true;
    }).toList();
  }

  Future<void> _addToCart(int productId) async {
    try {
      final token = _authService.token;
      if (token != null) {
        await _cartService.addToCart(token, productId, 1);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to cart')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add to cart')),
      );
    }
  }

  void _toggleSelect(int id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
  }

  void _selectAll(bool? selected) {
    setState(() {
      if (selected == true) {
        selectedIds = cart?.items.map((item) => item.id).toList() ?? [];
      } else {
        selectedIds.clear();
      }
    });
  }

  double _getSelectedTotal() {
    if (cart == null) return 0.0;
    return cart!.items
        .where((item) => selectedIds.contains(item.id))
        .fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  double _getSelectedDeliveryFee() {
    if (cart == null) return 0.0;
    double totalDeliveryFee = 0.0;
    
    for (final item in cart!.items) {
      if (selectedIds.contains(item.id)) {
        if (item.product.freeDelivery) {
          // Free delivery, no charge
          continue;
        } else if (item.product.customDeliveryFeeEnabled && item.product.customDeliveryFee != null) {
          // Custom delivery fee specified
          totalDeliveryFee += item.product.customDeliveryFee!;
        }
        // If neither free_delivery nor custom_delivery_fee_enabled, it's TBD (To Be Decided)
        // We don't add any fee for TBD items
      }
    }
    
    return totalDeliveryFee;
  }

  String _getDeliveryDetails() {
    if (cart == null) return '';
    
    int freeCount = 0;
    int customCount = 0;
    int tbdCount = 0;
    
    for (final item in cart!.items) {
      if (selectedIds.contains(item.id)) {
        if (item.product.freeDelivery) {
          freeCount++;
        } else if (item.product.customDeliveryFeeEnabled && item.product.customDeliveryFee != null) {
          customCount++;
        } else {
          tbdCount++;
        }
      }
    }
    
    List<String> details = [];
    if (freeCount > 0) details.add('$freeCount free');
    if (customCount > 0) details.add('$customCount charged');
    if (tbdCount > 0) details.add('$tbdCount tbd');
    
    return details.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: AppTheme.homeBackgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    final cartItems = cart?.items ?? [];
    final selectedItems = cartItems.where((item) => selectedIds.contains(item.id)).toList();
    final allSelected = selectedIds.length == cartItems.length && cartItems.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const SizedBox(width: 48), // Spacer to balance icons
                  Expanded(
                    child: Text(
                    'My Cart (${cartItems.length})',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_authService.isLoggedIn)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Notification Icon with Badge
                      GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NotificationScreen()),
                          );
                          _fetchNotificationCount();
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.notifications_outlined, color: Colors.white, size: 20),
                            if (_notificationCount > 0)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 14,
                                    minHeight: 14,
                                  ),
                                  child: Text(
                                    _notificationCount > 9 ? '9+' : _notificationCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Message Icon
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MessageInboxScreen(title: "Messages", isVendor: false),
                          ),
                        ),
                        child: const Icon(Icons.message_outlined, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await Future.wait([_refreshCart(), _fetchFreshProducts()]);
              },
              color: AppTheme.primaryColor,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                child: cartItems.isEmpty ? _buildEmptyCart() : _buildCartContent(cartItems, allSelected),
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: cartItems.isNotEmpty ? _buildCheckoutBar(selectedItems) : null,
    );
  }

  Widget _buildEmptyCart() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Your Cart is Empty',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Discover products near you',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 32),
          _buildRecommendedProducts(),
        ],
      ),
    );
  }

  Widget _buildCartContent(List<CartItem> cartItems, bool allSelected) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Select All Row
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: _selectAll,
                  activeColor: AppTheme.primaryColor,
                  checkColor: Colors.black,
                ),
                Text(
                  'Select all (${cartItems.length})',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (selectedIds.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      for (final id in selectedIds) {
                        await _removeItem(id);
                      }
                    },
                    child: Text(
                      'Delete (${selectedIds.length})',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Cart Items
          ...cartItems.map((item) => _buildCartItem(item)),

          const SizedBox(height: 32),
          _buildRecommendedProducts(),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildCheckoutBar(List<CartItem> selectedItems) {
    final subtotal = _getSelectedTotal();
    final deliveryFee = _getSelectedDeliveryFee();
    final total = subtotal + deliveryFee;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppTheme.homeBackgroundDark,
        border: Border(top: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Subtotal (${selectedItems.length} items):',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Rs ${subtotal.toInt()}',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery:',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _getDeliveryDetails(),
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                deliveryFee == 0 && !_getDeliveryDetails().contains('tbd') ? 'Free' : 
                _getDeliveryDetails().contains('tbd') ? 'Rs ${deliveryFee.toInt()} + TBD' :
                'Rs ${deliveryFee.toInt()}',
                style: GoogleFonts.plusJakartaSans(
                  color: deliveryFee == 0 && !_getDeliveryDetails().contains('tbd') ? AppTheme.primaryColor : 
                         _getDeliveryDetails().contains('tbd') ? Colors.orange :
                         Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF27272A)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Expanded(
                child: Text(
                  _getDeliveryDetails().contains('tbd') ? 'Rs ${subtotal.toInt()} + TBD' : 'Rs ${total.toInt()}',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: selectedItems.isNotEmpty ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CheckoutScreen(selectedItems: selectedItems),
                  ),
                );
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Proceed to Checkout',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    final imageUrl = item.product.images.isNotEmpty 
        ? item.product.images.first.imageUrl 
        : 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&q=80&w=200&h=200';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              onPressed: () => _removeItem(item.id),
              icon: const Icon(Icons.close, color: Colors.red, size: 18),
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ),
          Row(
            children: [
              Checkbox(
                value: selectedIds.contains(item.id),
                onChanged: (value) => _toggleSelect(item.id),
                activeColor: AppTheme.primaryColor,
                checkColor: Colors.black,
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 60,
                    height: 60,
                    color: Colors.grey[800],
                    child: const Icon(Icons.image, color: Colors.grey),
                  ),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Sold by ${item.product.vendorName}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: const Color(0xFFA1A1AA),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text(
                                  'Rs ${item.product.price.toInt()}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                 Text(
                                   item.product.freeDelivery ? 'Free' :
                                   item.product.customDeliveryFeeEnabled && item.product.customDeliveryFee != null ?
                                   'NPR ${item.product.customDeliveryFee!.toInt()}' :
                                   'TBD',
                                   style: GoogleFonts.plusJakartaSans(
                                     fontSize: 11,
                                     color: item.product.freeDelivery ? AppTheme.primaryColor :
                                            Colors.white,
                                   ),
                                   maxLines: 1,
                                   overflow: TextOverflow.ellipsis,
                                 ),
                              ],
                            ),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _updateQuantity(item.id, -1),
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.white, size: 20),
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                            Text(
                              item.quantity.toString(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              onPressed: () => _updateQuantity(item.id, 1),
                              icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor, size: 20),
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedProducts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Products Near You',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (loadingRecommended)
          const SizedBox(height: 100, child: Center(child: Text('Loading products...', style: TextStyle(color: Colors.grey))))
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: recommendedProducts.length,
              itemBuilder: (context, index) {
                final product = recommendedProducts[index];
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              child: Image.network(
                                product['image'],
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: Colors.grey[800],
                                  child: const Icon(Icons.image, color: Colors.grey),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () => _addToCart(product['id']),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.add_shopping_cart,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                  Text(
                                    product['vendor'],
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: const Color(0xFFA1A1AA),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(Icons.directions_car, color: AppTheme.primaryColor, size: 10),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Free',
                                        style: TextStyle(color: AppTheme.primaryColor, fontSize: 9, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text('•', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 9)),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.location_on, color: Color(0xFFA1A1AA), size: 10),
                                      const SizedBox(width: 2),
                                      Expanded(
                                        child: Text(
                                          product['distance'],
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 9,
                                            color: const Color(0xFFA1A1AA),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                Text(
                                  product['name'],
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Rs ${(double.tryParse(product['price'].toString()) ?? 0).toInt()}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
