import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/delivery_filter_service.dart';
import '../services/location_service.dart';
import 'package:provider/provider.dart';
import '../services/data_preloader_service.dart';
import '../services/navigation_service.dart';
import 'product_detail_screen.dart';
import 'checkout_screen.dart';
import '../services/cart_service.dart';
import 'notification_screen.dart';
import '../utils/delivery_utils.dart';

class CategoryDetailScreen extends StatefulWidget {
  final dynamic categoryId;

  const CategoryDetailScreen({super.key, required this.categoryId});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _subCategories = [];
  final Map<int, Map<String, dynamic>> _productReviews = {};
  Set<int> _favorites = {};
  Map<String, dynamic>? _selectedCategory;
  String _categoryName = 'Unknown';

  bool _isLoadingProducts = true;
  bool _isLoadingSubCategories = true;
  bool _hasMoreProducts = true;
  bool _showFilters = false;
  int _productsPage = 1;

  String _selectedSubCategory = '';
  String _sortBy = '';

  final ScrollController _productsScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  bool _isSearching = false;
  bool _isLoadingSearch = false;
  List<Map<String, dynamic>> _searchResults = [];
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _productsScrollController.addListener(_onProductsScroll);
    _initializeData();
    _fetchNotificationCount();
  }

  @override
  void dispose() {
    _productsScrollController.dispose();
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
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

  void _onProductsScroll() {
    if (_productsScrollController.position.pixels >=
            _productsScrollController.position.maxScrollExtent - 300 &&
        !_isLoadingProducts &&
        _hasMoreProducts) {
      _fetchProducts(loadMore: true);
    }
  }

  void _onSearchChanged(String query) {
    if (_searchDebounceTimer?.isActive ?? false) _searchDebounceTimer!.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isEmpty) {
        setState(() {
          _isSearching = false;
          _searchResults.clear();
        });
        return;
      }
      setState(() {
        _isSearching = true;
        _isLoadingSearch = true;
      });
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final userPosition = DeliveryFilterService().userPosition;
      final response = await ApiService().searchProducts(
        latitude: userPosition?.latitude,
        longitude: userPosition?.longitude,
        search: query,
        pageSize: 50,
        categories: _selectedCategory != null ? [_selectedCategory!['name']] : null,
      );

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      
      // Filter by category explicitly just in case
      final categoryFilteredProducts = _selectedCategory != null 
          ? allProducts.where((p) => p['category'] == _selectedCategory!['name']).toList()
          : allProducts;

      // Filter by global delivery radius
      final radiusFilteredProducts = await DeliveryFilterService().filterProducts(categoryFilteredProducts);

      // Process products (calculate distance, etc.)
      final processedProducts = await _processProducts(radiusFilteredProducts);

      final productIds = processedProducts
          .map((p) => p['id'] as int)
          .where((id) => !_productReviews.containsKey(id))
          .toList();
      
      if (productIds.isNotEmpty) await _loadReviewsForProducts(productIds);

      if (mounted) {
        setState(() {
          _searchResults = processedProducts;
          _isLoadingSearch = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSearch = false;
          _searchResults = [];
        });
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = false;
      _searchResults.clear();
    });
  }

  Future<void> _initializeData() async {
    await DeliveryFilterService().initialize();
    await _fetchSubCategories();
    await _fetchFavorites();
  }

  void _loadPreloadedProducts() {
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    
    if (preloader.allProducts != null && preloader.allProducts!.isNotEmpty && _categoryName != 'Unknown') {
      final categoryProducts = preloader.allProducts!
          .where((p) => p['category'] == _categoryName)
          .toList();
      
      if (categoryProducts.isNotEmpty) {
        final processedProducts = _processPreloadedProductsSync(categoryProducts);
        if (mounted) {
          setState(() {
            _products = processedProducts;
            _isLoadingProducts = false;
          });
        }
        
        if (preloader.productReviews != null) {
          _productReviews.addAll(preloader.productReviews!);
        }
        
        // Background refresh
        _fetchProductsInBackground();
        return;
      } else {
        // No cached products found, show empty state immediately
        if (mounted) {
          setState(() {
            _products = [];
            _isLoadingProducts = false;
          });
        }
        // Still do background refresh to check for new products
        _fetchProductsInBackground();
        return;
      }
    }
    
    // Fallback to API if no preloaded data or category name not set
    if (_categoryName != 'Unknown') {
      _fetchProducts();
    }
  }

  List<Map<String, dynamic>> _processPreloadedProductsSync(List<Map<String, dynamic>> products) {
    final currentUserId = AuthService().user?.id;
    
    return products.where((p) {
      final vendorId = p['vendor_id'];
      if (vendorId == currentUserId) return false;
      if ((p['quantity'] ?? 0) <= 0) return false;
      return true;
    }).map<Map<String, dynamic>>((p) {
      final List<dynamic>? rawImages = p['images'] as List<dynamic>?;
      final List<Map<String, dynamic>> images = rawImages?.whereType<Map<String, dynamic>>().toList() ?? [];
      Map<String, dynamic>? primaryImg;
      if (images.isNotEmpty) {
        primaryImg = images.firstWhere((img) => img['is_primary'] == true, orElse: () => images.first);
      }

      final userPosition = DeliveryFilterService().userPosition;
      double distance = double.infinity;
      if (userPosition != null && p['vendor_latitude'] != null && p['vendor_longitude'] != null) {
        distance = LocationService().calculateDistance(
          userPosition.latitude,
          userPosition.longitude,
          p['vendor_latitude'],
          p['vendor_longitude'],
        );
      }

      final deliveryInfo = getDeliveryInfo(p, null);
      final double priceValue = double.tryParse(p['price'].toString()) ?? 0.0;

      return {
        'id': p['id'],
        'name': p['name'] ?? 'Unnamed',
        'vendor': p['vendor_name'] ?? 'Unknown',
        'vendor_id': p['vendor_id'],
        'price': 'Rs ${priceValue.toInt()}',
        'priceValue': priceValue,
        'image': primaryImg?['image_url'] ?? '/placeholder.svg',
        'images': images,
        'rating': (p['average_rating'] as num?)?.toDouble() ?? 0.0,
        'distance': distance != double.infinity ? '${distance.toStringAsFixed(1)} km' : 'Location required',
        'distanceValue': distance,
        'inStock': ((p['quantity'] as num?)?.toInt() ?? 0) > 0,
        'totalSold': p['total_sold'] ?? 0,
        'deliveryInfo': deliveryInfo,
        'category': p['category'],
        'description': p['description'],
        'quantity': p['quantity'],
      };
    }).toList();
  }

  Future<void> _fetchSubCategories() async {
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    
    if (preloader.categories != null) {
      final categories = preloader.categories!;
      final matchingCategories = categories.where((cat) => cat['id'] == widget.categoryId);
      final category = matchingCategories.isNotEmpty ? matchingCategories.first : null;

      if (category != null) {
        _selectedCategory = category;
        _categoryName = category['name'] ?? 'Unknown';
        _subCategories = category['subcategories'] != null ? List<Map<String, dynamic>>.from(category['subcategories']) : [];
        _isLoadingSubCategories = false;
        
        // Load products immediately after category name is set
        _loadPreloadedProducts();
        return;
      }
    }
    
    // Fallback to API
    try {
      final response = await ApiService().getCategories();
      final categories = response.where((cat) => cat['is_active'] == true).toList();
      final matchingCategories = categories.where((cat) => cat['id'] == widget.categoryId);
      final category = matchingCategories.isNotEmpty ? matchingCategories.first : null;

      if (category != null) {
        _selectedCategory = category;
        _categoryName = category['name'] ?? 'Unknown';
        _subCategories = category['subcategories'] != null ? List<Map<String, dynamic>>.from(category['subcategories']) : [];
        _isLoadingSubCategories = false;
        _loadPreloadedProducts();
      } else {
        _selectedCategory = null;
        _categoryName = 'Unknown';
        _subCategories = [];
        _isLoadingSubCategories = false;
      }
    } catch (e) {
      _selectedCategory = null;
      _categoryName = 'Unknown';
      _subCategories = [];
      _isLoadingSubCategories = false;
    }
  }

  Future<void> _fetchProductsInBackground() async {
    try {
      final userPosition = DeliveryFilterService().userPosition;
      final response = await ApiService().searchProducts(
        latitude: userPosition?.latitude,
        longitude: userPosition?.longitude,
        pageSize: 100,
        page: 1,
        categories: _selectedCategory != null ? [_selectedCategory!['name']] : null,
      );

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      final categoryFilteredProducts = allProducts.where((p) => p['category'] == _selectedCategory!['name']).toList();
      final radiusFilteredProducts = await DeliveryFilterService().filterProducts(categoryFilteredProducts);
      final filteredProducts = radiusFilteredProducts.where((product) {
        final subCategoryMatch = _selectedSubCategory.isEmpty ||
            (product['subcategory']?.toLowerCase() == _selectedSubCategory.toLowerCase());
        return subCategoryMatch;
      }).toList();

      final processedProducts = await _processProducts(filteredProducts);
      final productIds = processedProducts
          .map((p) => p['id'] as int)
          .where((id) => !_productReviews.containsKey(id))
          .toList();
      if (productIds.isNotEmpty) await _loadReviewsForProducts(productIds);

      if (mounted) {
        setState(() {
          _products = processedProducts;
          _hasMoreProducts = response['next'] != null && filteredProducts.length >= 10;
        });
      }
    } catch (e) {
      // Handle silently for background refresh
    }
  }

  Future<void> _fetchProducts({bool loadMore = false}) async {
    if (_isLoadingProducts && loadMore) return;

    setState(() {
      if (loadMore) {
        _isLoadingProducts = true;
      } else {
        _isLoadingProducts = true;
        _productsPage = 1;
        _hasMoreProducts = true;
      }
    });

    try {
      final userPosition = DeliveryFilterService().userPosition;
      final deliveryRadius = DeliveryFilterService().deliveryRadius;
      print('User position: $userPosition, Delivery radius: $deliveryRadius');
      print('Selected category: $_selectedCategory');
      final response = await ApiService().searchProducts(
        latitude: userPosition?.latitude,
        longitude: userPosition?.longitude,
        pageSize: 100,
        page: loadMore ? _productsPage : 1,
        categories: _selectedCategory != null ? [_selectedCategory!['name']] : null,
      );
      print('API response: $response');

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      print('All products from API: ${allProducts.length}');

      // Filter by category on client side since backend doesn't filter
      final categoryFilteredProducts = allProducts.where((p) => p['category'] == _selectedCategory!['name']).toList();
      print('After category filter: ${categoryFilteredProducts.length}');

      // Filter by global delivery radius
      final radiusFilteredProducts = await DeliveryFilterService().filterProducts(categoryFilteredProducts);
      print('After radius filter: ${radiusFilteredProducts.length}');

      // Filter by subcategory only
      final filteredProducts = radiusFilteredProducts.where((product) {
        final subCategoryMatch = _selectedSubCategory.isEmpty ||
            (product['subcategory']?.toLowerCase() == _selectedSubCategory.toLowerCase());
        return subCategoryMatch;
      }).toList();
      print('After subcategory filter: ${filteredProducts.length}');

      // Process products
      final processedProducts = await _processProducts(filteredProducts);
      print('After process products: ${processedProducts.length}');

      // Load reviews
      final productIds = processedProducts
          .map((p) => p['id'] as int)
          .where((id) => !_productReviews.containsKey(id))
          .toList();
      if (productIds.isNotEmpty) await _loadReviewsForProducts(productIds);

      setState(() {
        if (loadMore) {
          _products.addAll(processedProducts);
          _productsPage++;
        } else {
          _products = processedProducts;
        }
        _hasMoreProducts = response['next'] != null && filteredProducts.length >= 10;
        _isLoadingProducts = false;
      });
      print('Final products count: ${_products.length}');
    } catch (e) {
      print('Error fetching products: $e');
      setState(() {
        _isLoadingProducts = false;
        if (!loadMore) _products = [];
      });
    }
  }

  Future<List<Map<String, dynamic>>> _processProducts(List<Map<String, dynamic>> products) async {
    print('Processing products: ${products.length}');
    final userPosition = DeliveryFilterService().userPosition;

    final filtered = products.where((product) {
      // Stock filter
      if ((product['quantity'] ?? 0) <= 0) {
        print('Product ${product['id']} filtered out by stock');
        return false;
      }

      // Vendor status filter
      // Assuming vendors are active if not specified

      return true;
    }).toList();
    print('After stock filter: ${filtered.length}');

    return filtered.map((product) {
      final images = product['images'] as List<dynamic>? ?? [];
      final productImages = List<Map<String, dynamic>>.from(images);
      final primaryImage = productImages.firstWhere(
        (img) => img['is_primary'] == true,
        orElse: () => productImages.isNotEmpty ? productImages.first : {'image_url': ''},
      );

      double distance = double.infinity;
      if (userPosition != null && product['vendor_latitude'] != null && product['vendor_longitude'] != null) {
        distance = LocationService().calculateDistance(
          userPosition.latitude,
          userPosition.longitude,
          product['vendor_latitude'],
          product['vendor_longitude'],
        );
      }

      final deliveryInfo = getDeliveryInfo(product, null);
      final priceValue = double.tryParse(product['price'].toString()) ?? 0.0;

      return {
        'id': product['id'],
        'name': product['name'] ?? 'Unknown',
        'vendor': product['vendor_name'] ?? 'Unknown',
        'vendor_id': product['vendor_id'],
        'price': 'NPR ${priceValue.toInt()}',
        'priceValue': priceValue,
        'image': primaryImage['image_url'] ?? '/placeholder.svg',
        'images': productImages,
        'rating': (product['average_rating'] as num?)?.toDouble() ?? 0.0,
        'distance': distance != double.infinity ? '${distance.toStringAsFixed(1)} km' : 'Location required',
        'distanceValue': distance,
        'inStock': (product['quantity'] ?? 0) > 0,
        'totalSold': product['total_sold'] ?? 0,
        'deliveryInfo': deliveryInfo,
        'category': product['category'],
        'description': product['description'],
        'quantity': product['quantity'],
      };
    }).toList()
    ..sort((a, b) {
      if (_sortBy == 'price_low') return (a['priceValue'] as double).compareTo(b['priceValue'] as double);
      if (_sortBy == 'price_high') return (b['priceValue'] as double).compareTo(a['priceValue'] as double);
      return (a['distanceValue'] as double).compareTo(b['distanceValue'] as double);
    });
  }

  Future<void> _loadReviewsForProducts(List<int> productIds) async {
    try {
      final results = await Future.wait(productIds.map(ApiService().getProductReviews));
      final map = <int, Map<String, dynamic>>{};
      for (int i = 0; i < productIds.length; i++) {
        final reviews = results[i];
        map[productIds[i]] = {
          'average_rating': reviews['aggregate']?['average_rating'] ?? 0.0,
          'total_reviews': reviews['aggregate']?['total_reviews'] ?? 0,
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
      modifiedProduct['price'] = double.parse(productData['priceValue'].toString()); // Use priceValue stored during processing
      // Check for delivery fee in modifiedProduct or parse from string if needed
      if (productData['custom_delivery_fee'] != null) {
        modifiedProduct['custom_delivery_fee'] = double.parse(productData['custom_delivery_fee'].toString());
      }
      
      final product = Product.fromJson(modifiedProduct);
      final cartItem = CartItem(
        id: 0,
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
      print('Error preparing buy now: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error proceeding to checkout')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Fixed Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            decoration: BoxDecoration(
              color: AppTheme.homeBackgroundDark.withOpacity(0.8),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    final navigationService = Provider.of<NavigationService>(context, listen: false);
                    navigationService.setCurrentPage('home');
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _categoryName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${_products.length} products found',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFFA1A1AA),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.filter_list, color: Colors.white),
                      onPressed: () => setState(() => _showFilters = true),
                    ),
                    if (AuthService().isLoggedIn)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const NotificationScreen()),
                              );
                              _fetchNotificationCount();
                            },
                          ),
                          if (_notificationCount > 0)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                child: Text(
                                  _notificationCount > 99 ? '99+' : _notificationCount.toString(),
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF27272A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(Icons.search, color: Color(0xFFA1A1AA), size: 20),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search in $_categoryName...',
                        hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFA1A1AA), fontSize: 16),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFFA1A1AA), size: 20),
                      onPressed: _clearSearch,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.image_search, color: Color(0xFFA1A1AA), size: 20),
                      onPressed: () {},
                    ),
                ],
              ),
            ),
          ),

          // Subcategories
          if (!_isLoadingSubCategories && _subCategories.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildSubCategoryButton('', 'All'),
                    ..._subCategories.map((subCat) => _buildSubCategoryButton(subCat['name'] ?? subCat.toString(), subCat['name'] ?? subCat.toString())),
                  ],
                ),
              ),
            ),

          // Products
          Expanded(
            child: _isSearching 
              ? _buildSearchResults()
              : _products.isEmpty && _isLoadingProducts
                ? _buildSkeletonGrid()
                : _products.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        color: AppTheme.primaryColor,
                        backgroundColor: const Color(0xFF1E1E1E),
                        strokeWidth: 3,
                        onRefresh: _fetchProducts,
                        child: GridView.builder(
                          controller: _productsScrollController,
                          padding: const EdgeInsets.all(16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.65,
                          ),
                          itemCount: _products.length + (_hasMoreProducts && !_isLoadingProducts ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _products.length) {
                              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                            }
                            return _buildProductCard(_products[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    ),
      bottomNavigationBar: null,
      // Filter Sidebar
      floatingActionButton: _showFilters ? _buildFilterDrawer() : null,
    );
  }

  Widget _buildSubCategoryButton(String value, String label) {
    final isSelected = _selectedSubCategory == value;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _selectedSubCategory = value);
          _fetchProducts();
        },
        backgroundColor: const Color(0xFF27272A),
        selectedColor: AppTheme.primaryColor,
        labelStyle: GoogleFonts.plusJakartaSans(
          color: isSelected ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final productId = product['id'] as int;
    final inStock = product['inStock'] as bool;
    final deliveryInfo = product['deliveryInfo'] as Map<String, dynamic>;

    return Material(
      color: const Color(0xFF18181B),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(
                productId: productId,
                images: product['images'],
                restaurant: product['vendor'],
                itemName: product['name'],
                rating: '${product['rating'].toStringAsFixed(1)} (${_productReviews[productId]?['total_reviews'] ?? 0})',
                distance: product['distance'],
                soldCount: '${product['totalSold']}+ sold',
                price: product['price'],
                deliveryFee: deliveryInfo['isFreeDelivery'] ? 'Free' : 'NPR ${(deliveryInfo['deliveryFee'] as num?)?.toInt() ?? 'TBD'}',
                description: product['description'] ?? '',
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
            // Image
            Expanded(
              flex: 6,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Image.network(
                      product['image'],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain, // Changed to contain to show full image
                      loadingBuilder: (_, child, progress) => progress == null
                          ? Container(color: Colors.white, child: child) // Light background for product images
                          : Container(
                              color: const Color(0xFF27272A),
                              child: const Center(child: CircularProgressIndicator()),
                            ),
                      errorBuilder: (_, __, ___) => Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: const Color(0xFF27272A),
                        padding: const EdgeInsets.all(8.0), // Reduced padding
                        child: Image.asset(
                          'assets/images/ezeywaylogo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 6,
                    left: 6,
                    child: IconButton(
                      iconSize: 20,
                      onPressed: () => _toggleFavorite(productId),
                      icon: Icon(
                        _favorites.contains(productId) ? Icons.favorite : Icons.favorite_border,
                        color: _favorites.contains(productId) ? Colors.red : Colors.white,
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
                    product['vendor'] ?? 'Unknown',
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFFA1A1AA)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product['name'] ?? 'Unnamed',
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

  Widget _buildSearchResults() {
    if (_isLoadingSearch) {
      return _buildSkeletonGrid();
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Color(0xFFA1A1AA)),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different keywords',
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFA1A1AA)),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildProductCard(_searchResults[index]);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 64, color: Color(0xFFA1A1AA)),
          const SizedBox(height: 16),
          Text(
            'No products found',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No products available',
            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFA1A1AA)),
          ),
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
            width: MediaQuery.of(context).size.width * 0.8,
            color: const Color(0xFF1C1C1C),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filters',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _showFilters = false),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sort By',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RadioListTile<String>(
                          value: '',
                          groupValue: _sortBy,
                          onChanged: (v) => setState(() => _sortBy = v!),
                          title: const Text('Default', style: TextStyle(color: Colors.white)),
                        ),
                        RadioListTile<String>(
                          value: 'price_low',
                          groupValue: _sortBy,
                          onChanged: (v) => setState(() => _sortBy = v!),
                          title: const Text('Price: Low to High', style: TextStyle(color: Colors.white)),
                        ),
                        RadioListTile<String>(
                          value: 'price_high',
                          groupValue: _sortBy,
                          onChanged: (v) => setState(() => _sortBy = v!),
                          title: const Text('Price: High to Low', style: TextStyle(color: Colors.white)),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _sortBy = '';
                              _showFilters = false;
                            });
                            _fetchProducts();
                          },
                          child: const Text('Clear All Filters'),
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

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => _buildSkeletonProductCard(),
    );
  }

  Widget _buildSkeletonProductCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image placeholder
          Expanded(
            flex: 6,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
          ),
          // Info placeholder
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 80,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 40,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          // Buttons placeholder
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}