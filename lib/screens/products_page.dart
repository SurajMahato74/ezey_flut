import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/data_preloader_service.dart';
import '../utils/delivery_utils.dart';
import '../utils/refresh_helper.dart';
import '../widgets/unified_bottom_nav.dart';
import '../services/cart_service.dart';
import 'product_detail_screen.dart';
import 'home_screen.dart';
import 'order_history_screen.dart';
import 'cart_screen.dart';
import 'checkout_screen.dart';
import '../models/order.dart';
import 'customer_profile_screen.dart';
import 'notification_screen.dart';
import 'message_inbox_screen.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final double _minPrice = 0;
  final double _maxPrice = 2000;
  double _currentMinPrice = 0;
  double _currentMaxPrice = 2000;
  String _sortBy = '';
  bool _showFilters = false;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  Map<int, Map<String, dynamic>> _productReviews = {};
  Set<int> _favorites = {};
  Map<String, int> _categoryNameToId = {};

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isLoadingCategories = false;
  bool _hasMoreProducts = true;
  int _productsPage = 1;

  List<String> _availableCategories = ['All'];
  Timer? _debounceTimer;
  final ScrollController _scrollController = ScrollController();
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _currentMinPrice = _minPrice;
    _currentMaxPrice = _maxPrice;
    _scrollController.addListener(_onScroll);
    _loadDataSynchronously();
    _fetchNotificationCount();
  }

  Future<void> _fetchNotificationCount() async {
    final token = AuthService().token;
    if (token == null) return;

    try {
      final response = await ApiService().getNotifications(token, page: 1);
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

  void _loadDataSynchronously() {
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    
    if (preloader.categories != null) {
      _categories = preloader.categories!;
      _categoryNameToId = {
        for (var cat in _categories)
          cat['name'] as String: cat['id'] as int
      };
      _availableCategories = [
        'All',
        ..._categories.map((c) => c['name'] as String)
      ];
    }
    
    if (preloader.allProducts != null && preloader.allProducts!.isNotEmpty) {
      setState(() {
        _products = _processPreloadedProductsSync(preloader.allProducts!);
        _hasMoreProducts = _products.length >= 50;
        _isLoading = false;
      });
      
      if (preloader.productReviews != null) {
        _productReviews = Map.from(preloader.productReviews!);
      }
    }
    
    _fetchFavorites();
    
    if (preloader.categories == null) {
      _fetchCategories();
    }
    if (preloader.allProducts == null || preloader.allProducts!.isEmpty) {
      _fetchData();
    }
  }

  List<Map<String, dynamic>> _processPreloadedProductsSync(List<Map<String, dynamic>> products) {
    final currentUserId = AuthService().user?.id;
    
    return products.where((p) {
      final vendorId = p['vendor_id'];
      if (vendorId == currentUserId) return false;
      if ((p['quantity'] ?? 0) <= 0) return false;
      
      final double priceValue = double.tryParse(p['price'].toString()) ?? 0.0;
      if (priceValue < _currentMinPrice || priceValue > _currentMaxPrice) return false;
      
      return true;
    }).map<Map<String, dynamic>>((p) {
      final List<dynamic>? rawImages = p['images'] as List<dynamic>?;
      final List<Map<String, dynamic>> images = rawImages?.whereType<Map<String, dynamic>>().toList() ?? [];
      Map<String, dynamic>? primaryImg;
      if (images.isNotEmpty) {
        primaryImg = images.firstWhere((img) => img['is_primary'] == true, orElse: () => images.first);
      }

      final double priceValue = double.tryParse(p['price'].toString()) ?? 0.0;
      
      String imageUrl = primaryImg?['image_url'] ?? '/placeholder.svg';
      if (!imageUrl.startsWith('http')) {
        imageUrl = 'https://ezeyway.com$imageUrl';
      }

      return {
        'id': p['id'],
        'name': p['name'] ?? 'Unnamed',
        'vendor': p['vendor_name'] ?? 'Unknown',
        'vendor_id': p['vendor_id'],
        'price': 'Rs ${priceValue.toInt()}',
        'priceValue': priceValue,
        'image': imageUrl,
        'images': images,
        'rating': (p['average_rating'] as num?)?.toDouble() ?? 0.0,
        'distance': 'N/A',
        'distanceValue': double.infinity,
        'inStock': ((p['quantity'] as num?)?.toInt() ?? 0) > 0,
        'totalSold': p['total_sold'] ?? 0,
        'deliveryInfo': {'isFreeDelivery': true, 'deliveryFee': 0},
        'category': p['category']?.toString(), // Ensure string for comparison
        'description': p['description'],
        'quantity': p['quantity'],
      };
    }).toList();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMoreProducts &&
        _products.isNotEmpty) { // Only load more if we have initial products
      _fetchData(loadMore: true);
    }
  }





  Future<void> _fetchCategories() async {
    try {
      final categories = await ApiService().getCategories();
      if (mounted) {
        setState(() {
          _categories = categories
              .where((cat) => cat['is_active'] == true)
              .toList();
          _categoryNameToId = {
            for (var cat in _categories)
              cat['name'] as String: cat['id'] as int
          };
          _availableCategories = [
            'All',
            ..._categories.map((c) => c['name'] as String)
          ];
          _isLoadingCategories = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _categories = [];
          _categoryNameToId = {};
          _availableCategories = ['All'];
          _isLoadingCategories = false;
        });
      }
    }
  }

 Future<void> _fetchData({bool loadMore = false}) async {
  if (_isLoading || _isLoadingMore) return;

  setState(() {
    if (loadMore) {
      _isLoadingMore = true;
    } else {
      _isLoading = true;
      _productsPage = 1;
      _hasMoreProducts = true;
    }
  });

  try {
    final location = await LocationService().getCurrentPosition();
    final latitude = location?.latitude;
    final longitude = location?.longitude;

    final data = await ApiService().searchProducts(
      latitude: latitude,
      longitude: longitude,
      page: loadMore ? _productsPage : 1,
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
      sort: _sortBy.isNotEmpty ? _sortBy : null,
      categories: _selectedCategory != 'All' &&
              _categoryNameToId.containsKey(_selectedCategory)
          ? [_categoryNameToId[_selectedCategory]!.toString()]
          : null,
    );

    final List<dynamic> rawProducts = data['results'] ?? [];

    // Filter by category on client side if needed, being careful with types
    final categoryFiltered = _selectedCategory == 'All'
        ? rawProducts
        : rawProducts.where((p) {
            final pCat = p['category']?.toString();
            return pCat == _selectedCategory || pCat == _categoryNameToId[_selectedCategory]?.toString();
          }).toList();

    final processedProducts = await _processProducts(categoryFiltered, location);

    setState(() {
      if (loadMore) {
        _products.addAll(processedProducts);
        _productsPage++;
      } else {
        _products = processedProducts;
      }
      _hasMoreProducts = data['next'] != null;
    });

    if (!loadMore) {
      final productIds = processedProducts.map((p) => p['id'] as int).toList();
      if (productIds.isNotEmpty) await _loadReviewsForProducts(productIds);
    }
  } catch (e) {
    debugPrint('Error fetching products: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to load products')),
    );
  } finally {
    setState(() {
      _isLoading = false;
      _isLoadingMore = false;
    });
  }
}

Future<List<Map<String, dynamic>>> _processProducts(
    List<dynamic> products, Position? location) async {
  final currentUserId = AuthService().user?.id;
  
  final uniqueVendorIds = products
      .map((p) => (p as Map<String, dynamic>)['vendor_id'])
      .where((id) => id != null)
      .toSet()
      .cast<int>();

  final vendorStatuses = <int, bool>{};
  if (uniqueVendorIds.isNotEmpty) {
    await Future.wait(uniqueVendorIds.map((id) async {
      try {
        final vendor = await ApiService().getVendorDetails(id);
        vendorStatuses[id] = vendor['is_active'] == true;
      } catch (e) {
        vendorStatuses[id] = false;
      }
    }));
  }

  return products.where((dynamic rawProduct) {
    final p = rawProduct as Map<String, dynamic>;

    final vendorId = p['vendor_id'];
    if (vendorId != null && vendorStatuses[vendorId] != true) return false;
    if (vendorId == currentUserId) return false;
    if ((p['quantity'] ?? 0) <= 0) return false;

    final double priceValue = double.tryParse(p['price'].toString()) ?? 0.0;
    final bool inPriceRange = priceValue >= _currentMinPrice && priceValue <= _currentMaxPrice;

    double distance = double.infinity;
    if (location != null &&
        p['vendor_latitude'] != null &&
        p['vendor_longitude'] != null) {
      distance = calculateDistance(
        location.latitude,
        location.longitude,
        p['vendor_latitude'],
        p['vendor_longitude'],
      );
    }
    final double deliveryRadius = getDeliveryRadiusSync(p) ?? double.infinity;
    final bool withinRadius = distance == double.infinity || distance <= deliveryRadius;

    return inPriceRange && withinRadius;
  }).map<Map<String, dynamic>>((dynamic rawProduct) {
    final p = rawProduct as Map<String, dynamic>;

    // Safe image handling
    final List<dynamic>? rawImages = p['images'] as List<dynamic>?;
    final List<Map<String, dynamic>> images = rawImages
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    Map<String, dynamic>? primaryImg;
    if (images.isNotEmpty) {
      primaryImg = images.firstWhere(
        (img) => img['is_primary'] == true,
        orElse: () => images.first,
      );
    }

    // Distance calculation
    final userPosition = location;
    double distance = double.infinity;
    if (userPosition != null &&
        p['vendor_latitude'] != null &&
        p['vendor_longitude'] != null) {
      distance = calculateDistance(
        userPosition.latitude,
        userPosition.longitude,
        p['vendor_latitude'],
        p['vendor_longitude'],
      );
    }

    final deliveryInfo = getDeliveryInfo(p, null);
    final double priceValue = double.tryParse(p['price'].toString()) ?? 0.0;

    String imageUrl = primaryImg?['image_url'] ?? '/placeholder.svg';
    if (!imageUrl.startsWith('http')) {
      imageUrl = 'https://ezeyway.com$imageUrl';
    }

    return {
      'id': p['id'],
      'name': p['name'] ?? 'Unnamed',
      'vendor': p['vendor_name'] ?? 'Unknown',
      'vendor_id': p['vendor_id'],
      'price': 'NPR ${priceValue.toInt()}',
      'priceValue': priceValue,
      'image': imageUrl,
      'images': images,
      'rating': (p['average_rating'] as num?)?.toDouble() ?? 0.0,
      'distance': distance != double.infinity ? '${distance.toStringAsFixed(1)} km' : 'Location required',
      'distanceValue': distance,
      'inStock': ((p['quantity'] as num?)?.toInt() ?? 0) > 0,
      'totalSold': p['total_sold'] ?? 0,
      'deliveryInfo': deliveryInfo,
      'category': p['category']?.toString(), // Ensure string
      'description': p['description'],
      'quantity': p['quantity'],
    };
  }).toList();
}

  Future<void> _loadReviewsForProducts(List<int> productIds) async {
    try {
      final results = await Future.wait(
          productIds.map((id) => ApiService().getProductReviews(id)));
      final map = <int, Map<String, dynamic>>{};
      for (int i = 0; i < productIds.length; i++) {
        final rev = results[i];
        map[productIds[i]] = {
          'average_rating': rev['aggregate']?['average_rating'] ?? 0.0,
          'total_reviews': rev['aggregate']?['total_reviews'] ?? 0,
        };
      }
      setState(() => _productReviews.addAll(map));
    } catch (_) {}
  }

  Future<void> _fetchFavorites() async {
    final token = AuthService().token;
    if (token == null) return;

    try {
      final data = await ApiService().getFavorites(token);
      final favorites = (data['results'] as List<dynamic>?)
              ?.map((f) => f['product']['id'] as int)
              .toSet() ??
          {};
      setState(() => _favorites = favorites);
    } catch (_) {}
  }

  Future<void> _toggleFavorite(int productId) async {
    final token = AuthService().token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to save favorites')),
      );
      return;
    }

    try {
      final result = await ApiService().toggleFavorite(token, productId);
      setState(() {
        if (result['is_favorite']) {
          _favorites.add(productId);
        } else {
          _favorites.remove(productId);
        }
      });
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update favorite')),
      );
    }
  }

  Future<void> _addToCart(int productId) async {
    final token = AuthService().token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to add to cart')),
      );
      return;
    }

    try {
      await ApiService().addToCart(token, productId, 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to cart!')),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add to cart')),
      );
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() => _searchQuery = query.trim());
      _fetchData();
    });
  }

  void _applyFilters() {
    setState(() => _showFilters = false);
    _fetchData();
  }

  void _resetFilters() {
    setState(() {
      _selectedCategory = 'All';
      _currentMinPrice = _minPrice;
      _currentMaxPrice = _maxPrice;
      _sortBy = '';
    });
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppTheme.homeBackgroundDark,
            body: SafeArea(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 48), // Spacer to balance icons
                            Expanded(
                              child: Text(
                                'Products',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            if (AuthService().isLoggedIn)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                        const SizedBox(height: 16),
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF27272A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: _showImageSearchDialog,
                                icon: const Icon(Icons.image_search,
                                    color: Color(0xFFA1A1AA), size: 20),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: _onSearchChanged,
                                  decoration: InputDecoration(
                                    hintText: 'Search products...',
                                    hintStyle: GoogleFonts.plusJakartaSans(
                                        color: const Color(0xFFA1A1AA)),
                                    border: InputBorder.none,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 14),
                                  ),
                                  style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    setState(() => _showFilters = true),
                                icon: const Icon(Icons.tune,
                                    color: Color(0xFFA1A1AA), size: 20),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Active Filters Chips
                  if (_selectedCategory != 'All' ||
                      _currentMinPrice > _minPrice ||
                      _currentMaxPrice < _maxPrice ||
                      _sortBy.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (_selectedCategory != 'All')
                            _buildFilterChip(_selectedCategory, () {
                              setState(() => _selectedCategory = 'All');
                              _fetchData();
                            }),
                          if (_currentMinPrice > _minPrice ||
                              _currentMaxPrice < _maxPrice)
                            _buildFilterChip(
                                'Rs ${_currentMinPrice.toInt()} - ${_currentMaxPrice.toInt()}',
                                () {
                              setState(() {
                                _currentMinPrice = _minPrice;
                                _currentMaxPrice = _maxPrice;
                              });
                              _fetchData();
                            }),
                          if (_sortBy.isNotEmpty)
                            _buildFilterChip(
                                _sortBy == 'price_low'
                                    ? 'Low to High'
                                    : 'High to Low', () {
                              setState(() => _sortBy = '');
                              _fetchData();
                            }),
                        ],
                      ),
                    ),

                  // Products Grid
                  Expanded(
                    child: RefreshIndicator(
                      color: AppTheme.primaryColor,
                      backgroundColor: const Color(0xFF1E1E1E),
                      strokeWidth: 3,
                      onRefresh: _fetchData,
                      child: _products.isEmpty && !_isLoading
                          ? _buildEmptyState()
                          : GridView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              physics: const AlwaysScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.6,
                              ),
                              itemCount: _products.length + (_isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _products.length) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                return _buildProductCard(_products[index]);
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),

          ),
          if (_showFilters) _buildFilterDrawer(),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Chip(
      label: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: AppTheme.homeBackgroundDark)),
      backgroundColor: AppTheme.primaryColor,
      deleteIcon: const Icon(Icons.close,
          size: 16, color: AppTheme.homeBackgroundDark),
      onDeleted: onRemove,
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final bool inStock = product['inStock'] as bool;
    final int productId = product['id'];

    return Material(
      color: const Color(0xFF18181B),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(
                productId: productId,
                images: product['images'],
                restaurant: product['vendor'],
                itemName: product['name'],
                rating:
                    '${product['rating'].toStringAsFixed(1)} (${_productReviews[productId]?['total_reviews'] ?? 0})',
                distance: product['distance'],
                soldCount: '${product['totalSold']}+ sold',
                price: product['price'],
                deliveryFee: product['deliveryInfo']['isFreeDelivery']
                    ? 'Free'
                    : 'NPR ${product['deliveryInfo']['deliveryFee']?.toInt() ?? 'TBD'}',
                description:
                    product['description'] ?? 'No description available.',
                stock: product['quantity'] ?? 0,
                category: product['category'],
                vendorId: product['vendor_id'],
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Section
            Expanded(
              flex: 7,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12)),
                    child: Image.network(
                      product['image'],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain, // Changed to contain
                      loadingBuilder: (_, child, progress) => progress == null
                          ? Container(color: Colors.white, child: child)
                          : Container(
                              color: const Color(0xFF27272A),
                              child: const Center(child: CircularProgressIndicator()),
                            ),
                      errorBuilder: (_, __, ___) => Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: const Color(0xFF27272A),
                        padding: const EdgeInsets.all(8.0),
                        child: Image.asset(
                          'assets/images/ezeywaylogo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      iconSize: 20,
                      onPressed: () => _toggleFavorite(productId),
                      icon: Icon(
                        _favorites.contains(productId)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: _favorites.contains(productId)
                            ? Colors.red
                            : Colors.white,
                      ),
                    ),
                  ),

                ],
              ),
            ),

            // Info Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['vendor'],
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFFA1A1AA)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product['name'],
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Rating and Sold Count
                  Row(
                    children: [
                      const Icon(Icons.star, color: AppTheme.primaryColor, size: 12),
                      const SizedBox(width: 4),
                      Text(product['rating'].toStringAsFixed(1), style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      const Icon(Icons.local_fire_department, color: Color(0xFFFF5252), size: 12),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          '${product['totalSold']} sold',
                          style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFFA1A1AA)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.directions_car, color: AppTheme.primaryColor, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        product['deliveryInfo']['isFreeDelivery'] ? 'Free' : 'NPR ${product['deliveryInfo']['deliveryFee']?.toInt() ?? 'TBD'}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      const Text('•', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 10)),
                      const SizedBox(width: 6),
                      const Icon(Icons.location_on, color: Color(0xFFA1A1AA), size: 12),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          product['distance'],
                          style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFFA1A1AA)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product['price'],
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: inStock ? () => _addToCart(productId) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF27272A),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Cart', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: inStock ? () => _handleBuyNow(product) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Buy Now', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.black, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off,
              size: 64, color: Color(0xFFA1A1AA)),
          const SizedBox(height: 16),
          Text('No products found',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text('Try different keywords or filters',
              style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFA1A1AA))),
        ],
      ),
    );
  }

  Widget _buildFilterDrawer() {
    return GestureDetector(
      onTap: () => setState(() => _showFilters = false),
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            color: const Color(0xFF1C1C1C),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFF27272A)))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Filters',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      IconButton(
                          onPressed: () => setState(() => _showFilters = false),
                          icon: const Icon(Icons.close, color: Colors.white)),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sort By',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        const SizedBox(height: 8),
                        RadioListTile<String>(
                            value: '',
                            groupValue: _sortBy,
                            onChanged: (v) => setState(() => _sortBy = v!),
                            title: const Text('Default')),
                        RadioListTile<String>(
                            value: 'price_low',
                            groupValue: _sortBy,
                            onChanged: (v) => setState(() => _sortBy = v!),
                            title: const Text('Price: Low to High')),
                        RadioListTile<String>(
                            value: 'price_high',
                            groupValue: _sortBy,
                            onChanged: (v) => setState(() => _sortBy = v!),
                            title: const Text('Price: High to Low')),

                        const SizedBox(height: 24),

                        Text('Categories',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _availableCategories.map((cat) => FilterChip(
                                label: Text(cat),
                                selected: _selectedCategory == cat,
                                onSelected: (_) =>
                                    setState(() => _selectedCategory = cat),
                                backgroundColor: Colors.transparent,
                                selectedColor: AppTheme.primaryColor,
                                labelStyle: GoogleFonts.plusJakartaSans(
                                    color: _selectedCategory == cat
                                        ? Colors.black
                                        : Colors.white),
                                side: const BorderSide(color: AppTheme.primaryColor),
                              )).toList(),
                        ),

                        const SizedBox(height: 24),

                        Text('Price Range',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Rs ${_currentMinPrice.toInt()}',
                                style: const TextStyle(
                                    color: Color(0xFFA1A1AA))),
                            Text('Rs ${_currentMaxPrice.toInt()}',
                                style: const TextStyle(
                                    color: Color(0xFFA1A1AA))),
                          ],
                        ),
                        RangeSlider(
                          values:
                              RangeValues(_currentMinPrice, _currentMaxPrice),
                          min: _minPrice,
                          max: _maxPrice,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (v) => setState(() {
                            _currentMinPrice = v.start;
                            _currentMaxPrice = v.end;
                          }),
                        ),

                        const SizedBox(height: 40),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _resetFilters,
                                child: const Text('Reset'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _applyFilters,
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: Colors.black),
                                child: const Text('Apply'),
                              ),
                            ),
                          ],
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
    );
  }

  void _showImageSearchDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: Text('Image Search',
            style: GoogleFonts.plusJakartaSans(color: Colors.white)),
        content: Text('Coming soon!',
            style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFA1A1AA))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'))
        ],
      ),
    );
  }

  void _handleBuyNow(Map<String, dynamic> productData) {
     if (!AuthService().isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to buy products')),
      );
      return;
    }

    try {
      // Ensure numeric values are parsed correctly
      final modifiedProduct = Map<String, dynamic>.from(productData);
      
      // Map 'vendor' (string) to 'vendor_name' if needed by Product.fromJson or just ensure it's handled
      if (modifiedProduct['vendor'] is String) {
        modifiedProduct['vendor_name'] = modifiedProduct['vendor'];
      }

      // Handle price which is stored as 'Rs 123.45' in string in the UI map
      // but we also have priceValue (double) stored
      if (modifiedProduct['priceValue'] != null) {
        modifiedProduct['price'] = modifiedProduct['priceValue'];
      }
      
      if (modifiedProduct['deliveryInfo'] is Map) {
         final dInfo = modifiedProduct['deliveryInfo'];
         modifiedProduct['free_delivery'] = dInfo['isFreeDelivery'];
         modifiedProduct['custom_delivery_fee'] = dInfo['deliveryFee'];
      }

      final product = Product.fromJson(modifiedProduct);
      final cartItem = CartItem(
        id: 0, // 0 indicates direct buy item (not in cart yet)
        product: product,
        quantity: 1,
        totalPrice: product.price,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutScreen(selectedItems: [cartItem]),
        ),
      );
    } catch (e) {
      debugPrint('Error preparing buy now: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error proceeding to checkout')),
      );
    }
  }


}
