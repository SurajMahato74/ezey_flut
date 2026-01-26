import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/delivery_filter_service.dart';
import '../services/location_service.dart';
import '../services/data_preloader_service.dart';
import '../services/navigation_service.dart';
import '../utils/refresh_helper.dart';
import '../utils/delivery_utils.dart'; // Add this
import '../widgets/unified_bottom_nav.dart';
import 'product_detail_screen.dart';
import 'cart_screen.dart';
import 'checkout_screen.dart';
import '../services/cart_service.dart';
import 'products_page.dart';
import 'order_history_screen.dart';
import 'customer_profile_screen.dart';
import 'message_inbox_screen.dart';
import 'category_detail_screen.dart';
import 'notification_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSwitchToVendor;
  const HomeScreen({super.key, this.onSwitchToVendor});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _sliders = [];
  List<Map<String, dynamic>> _flashProducts = [];
  List<Map<String, dynamic>> _trendingProducts = [];
  Map<int, Map<String, dynamic>> _productReviews = {};

  bool _isLoadingCategories = false;
  bool _isLoadingSliders = false;
  bool _isLoadingFlashProducts = false;
  bool _isLoadingTrendingProducts = false;
  bool _isLoadingMoreFlash = false;
  bool _isLoadingMoreTrending = false;

  bool _hasMoreFlashProducts = true;
  bool _hasMoreTrendingProducts = true;
  int _flashProductsPage = 1;
  int _trendingProductsPage = 1;

  late final PageController _sliderController;
  final ScrollController _flashScrollController = ScrollController();
  final ScrollController _trendingScrollController = ScrollController();
  Timer? _sliderTimer;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  bool _isSearching = false;
  bool _isLoadingSearch = false;
  List<Map<String, dynamic>> _searchResults = [];
  int _unreadNotificationCount = 0;
  String _currentAddress = 'Lazimpat, Kathmandu';
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _sliderController = PageController(
      viewportFraction: 0.8,
      initialPage: 1000,
    );
    _loadDataSynchronously();
    _flashScrollController.addListener(_onFlashScroll);
    _trendingScrollController.addListener(_onTrendingScroll);
    _fetchNotificationCount();
  }

  void _loadDataSynchronously() {
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    
    // Set data immediately without setState to avoid rebuilds
    if (preloader.categories != null) {
      _categories = preloader.categories!;
    }
    
    if (preloader.sliders != null) {
      _sliders = preloader.sliders!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startSliderAutoPlay();
      });
    }
    
    if (preloader.flashProducts != null) {
      _flashProducts = preloader.flashProducts!;
    }
    
    if (preloader.trendingProducts != null) {
      _trendingProducts = preloader.trendingProducts!;
    }
    
    if (preloader.productReviews != null) {
      _productReviews = preloader.productReviews!;
    }
    
    if (preloader.notificationCount != null) {
      _unreadNotificationCount = preloader.notificationCount!;
    }
    
    // Only fetch missing data asynchronously
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (preloader.categories == null) _fetchCategories();
      if (preloader.sliders == null) _fetchSliders();
      if (preloader.flashProducts == null) _fetchFlashProducts();
      if (preloader.trendingProducts == null) _fetchTrendingProducts();
      
      DeliveryFilterService().initialize();
    });
  }





  @override
  void dispose() {
    _sliderTimer?.cancel();
    _sliderController.dispose();
    _flashScrollController.dispose();
    _trendingScrollController.dispose();
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
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
      );

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      final currentUserId = AuthService().user?.id;

      // Filter blocked vendors
      final uniqueVendorIds = allProducts.map((p) => p['vendor_id']).where((id) => id != null).toSet().cast<int>();
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

      final filteredProducts = <Map<String, dynamic>>[];
      for (final product in allProducts) {
        if ((product['quantity'] ?? 0) <= 0) continue;
        final vendorId = product['vendor_id'];
        if (vendorId != null && vendorStatuses[vendorId] == true) {
          if (vendorId == currentUserId) continue;
          filteredProducts.add(product);
        }
      }

      final productIds = filteredProducts
          .map((p) => p['id'] as int)
          .where((id) => !_productReviews.containsKey(id))
          .toList();
      
      if (productIds.isNotEmpty) await _loadReviewsForProducts(productIds);

      if (mounted) {
        setState(() {
          _searchResults = filteredProducts;
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

  void _startSliderAutoPlay() {
    _sliderTimer?.cancel();
    if (_sliders.isEmpty) return;

    _sliderTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_sliderController.hasClients) return;
      final nextPage = (_sliderController.page?.round() ?? 0) + 1;
      _sliderController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  void _onFlashScroll() {
    if (_flashScrollController.position.pixels >=
            _flashScrollController.position.maxScrollExtent - 300 &&
        !_isLoadingFlashProducts &&
        !_isLoadingMoreFlash &&
        _hasMoreFlashProducts) {
      _fetchFlashProducts(loadMore: true);
    }
  }

  void _onTrendingScroll() {
    if (_trendingScrollController.position.pixels >=
            _trendingScrollController.position.maxScrollExtent - 300 &&
        !_isLoadingTrendingProducts &&
        !_isLoadingMoreTrending &&
        _hasMoreTrendingProducts) {
      _fetchTrendingProducts(loadMore: true);
    }
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
      
      final unreadCount = notifications.where((notification) {
        final notificationRole = notification['role'] ?? 'customer';
        return notificationRole == currentRoleString && notification['is_read'] != true;
      }).length;
      
      if (mounted) {
        setState(() {
          _unreadNotificationCount = unreadCount;
        });
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final categories = await ApiService().getCategories();
      if (mounted) {
        setState(() {
        _categories = categories.where((cat) => cat['is_active'] == true).toList();
        _isLoadingCategories = false;
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _categories = [];
        _isLoadingCategories = false;
      });
      }
    }
  }

  Future<void> _fetchSliders() async {
    try {
      final sliders = await ApiService().getSliders('customer');
      if (mounted) {
        setState(() {
        _sliders = sliders;
        _isLoadingSliders = false;
      });
      }
      _startSliderAutoPlay();
    } catch (e) {
      if (mounted) {
        setState(() {
        _sliders = [];
        _isLoadingSliders = false;
      });
      }
    }
  }

  Future<void> _fetchFlashProducts({bool loadMore = false}) async {
    if (loadMore && !_hasMoreFlashProducts) return;
    
    if (!loadMore) {
      setState(() => _isLoadingFlashProducts = true);
      _isLoadingMoreFlash = false;
    } else {
      setState(() => _isLoadingMoreFlash = true);
    }

    try {
      final userPosition = DeliveryFilterService().userPosition;
      final response = await ApiService().searchProducts(
        latitude: userPosition?.latitude,
        longitude: userPosition?.longitude,
        pageSize: 20,
        page: loadMore ? _flashProductsPage : 1,
      );

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      final featuredProducts = allProducts.where((p) => p['featured'] == true).toList();

      final currentUserId = AuthService().user?.id;
      final uniqueVendorIds = featuredProducts.map((p) => p['vendor_id']).where((id) => id != null).toSet().cast<int>();
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
      final filteredProducts = <Map<String, dynamic>>[];
      for (final product in featuredProducts) {
        final vendorId = product['vendor_id'];
        if (vendorId != null && vendorStatuses[vendorId] == true) {
          if (vendorId == currentUserId) continue;
          filteredProducts.add(product);
        }
      }

      final productIds = filteredProducts
          .map((p) => p['id'] as int)
          .where((id) => !_productReviews.containsKey(id))
          .toList();

      if (productIds.isNotEmpty) await _loadReviewsForProducts(productIds);

      if (mounted) {
        setState(() {
        if (loadMore) {
          _flashProducts.addAll(filteredProducts);
          _flashProductsPage++;
        } else {
          _flashProducts = filteredProducts;
          _productReviews.clear();
        }
        
        // Stop pagination if no filtered products returned
        _hasMoreFlashProducts = filteredProducts.isNotEmpty && response['next'] != null;
        
        _isLoadingFlashProducts = false;
        _isLoadingMoreFlash = false;
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _isLoadingFlashProducts = false;
        _isLoadingMoreFlash = false;
        if (!loadMore) _flashProducts = [];
      });
      }
    }
  }

  Future<void> _fetchTrendingProducts({bool loadMore = false}) async {
    if (loadMore && !_hasMoreTrendingProducts) return;
    
    if (!loadMore) {
      setState(() => _isLoadingTrendingProducts = true);
      _isLoadingMoreTrending = false;
    } else {
      setState(() => _isLoadingMoreTrending = true);
    }

    try {
      final userPosition = DeliveryFilterService().userPosition;
      final response = await ApiService().searchProducts(
        latitude: userPosition?.latitude,
        longitude: userPosition?.longitude,
        pageSize: 20,
        page: loadMore ? _trendingProductsPage : 1,
      );

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      final currentUserId = AuthService().user?.id;

      final uniqueVendorIds = allProducts.map((p) => p['vendor_id']).where((id) => id != null).toSet().cast<int>();
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
      final filteredProducts = <Map<String, dynamic>>[];
      for (final product in allProducts) {
        if ((product['quantity'] ?? 0) <= 0) continue;
        final vendorId = product['vendor_id'];
        if (vendorId != null && vendorStatuses[vendorId] == true) {
          if (vendorId == currentUserId) continue;
          filteredProducts.add(product);
        }
      }

      final productIds = filteredProducts
          .map((p) => p['id'] as int)
          .where((id) => !_productReviews.containsKey(id))
          .toList();

      if (productIds.isNotEmpty) await _loadReviewsForProducts(productIds);

      if (mounted) {
        setState(() {
        if (loadMore) {
          _trendingProducts.addAll(filteredProducts);
          _trendingProductsPage++;
        } else {
          _trendingProducts = filteredProducts;
        }
        
        // Stop pagination if no filtered products returned
        _hasMoreTrendingProducts = filteredProducts.isNotEmpty && response['next'] != null;
        
        _isLoadingTrendingProducts = false;
        _isLoadingMoreTrending = false;
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _isLoadingTrendingProducts = false;
        _isLoadingMoreTrending = false;
        if (!loadMore) _trendingProducts = [];
      });
      }
    }
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
      if (mounted) setState(() => _productReviews.addAll(map));
    } catch (_) {}
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
      final response = await ApiService().addToCart(token, productId, 1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Product added to cart successfully'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add to cart'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _buyNow(Map<String, dynamic> productData) {
    if (!AuthService().isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to buy products')),
      );
      return;
    }

    try {
      // Ensure numeric values are parsed correctly
      final modifiedProduct = Map<String, dynamic>.from(productData);
      modifiedProduct['price'] = double.parse(productData['price'].toString());
      if (productData['custom_delivery_fee'] != null) {
        modifiedProduct['custom_delivery_fee'] = double.parse(productData['custom_delivery_fee'].toString());
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/ezeywaylogo.png',
                    width: 50,
                    height: 50,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: _handleLocationTap,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Current Location',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFA1A1AA),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentAddress,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Notification Icon
                    // Notification Icon
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
                          if (_unreadNotificationCount > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                                child: Text(
                                  _unreadNotificationCount > 9 ? '9+' : '$_unreadNotificationCount',
                                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
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
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.message_outlined, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Reference Search Bar (Fixed below Header)
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
                        hintText: 'Search for products or vendors',
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
                      onPressed: () {}, // Image search placeholder
                    ),
                ],
              ),
            ),
          ),

          // Scrollable Content
          Expanded(
            child: _isSearching
                ? _buildSearchResults()
                : RefreshIndicator(
                    color: AppTheme.primaryColor,
                    backgroundColor: const Color(0xFF1E1E1E),
                    strokeWidth: 3,
                    onRefresh: () => RefreshHelper.refreshAppData(context),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        const SizedBox(height: 16),
                        
                        // Sliders
                        SizedBox(
                          height: 150,
                          child: _sliders.isEmpty
                              ? Center(
                                  child: Text(
                                    'No banners available',
                                    style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 14),
                                  ),
                                )
                              : PageView.builder(
                                  controller: _sliderController,
                                  itemBuilder: (context, index) {
                                    final slider = _sliders[index % _sliders.length];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: _buildSliderCard(slider),
                                    );
                                  },
                                ),
                        ),

                  const SizedBox(height: 24),

                  // Categories
                  SizedBox(
                    height: 80,
                    child: _categories.isEmpty
                        ? Center(
                            child: Text(
                              'No categories available',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 14),
                            ),
                          )
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _categories.length,
                            itemBuilder: (_, i) => _buildCategoryCircle(_categories[i]),
                          ),
                  ),

                  const SizedBox(height: 20),

                  // Flash Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Flash',
                      style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: ListView.builder(
                        controller: _flashScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _flashProducts.length + (_isLoadingMoreFlash ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _flashProducts.length) {
                            return const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: SizedBox(
                                width: 160,
                                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _buildFlashProductCard(context, _flashProducts[index]),
                          );
                        },
                      ),
                  ),

                  const SizedBox(height: 20),

                  // Trending Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Trending Near You',
                          style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.filter_list, color: AppTheme.primaryColor),
                              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Filter coming soon!')),
                              ),
                            ),
                            TextButton(
                              onPressed: () {},
                              child: Text(
                                'View All',
                                style: GoogleFonts.plusJakartaSans(color: AppTheme.primaryColor, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Trending Grid with Auto Load More
                  GridView.builder(
                      controller: _trendingScrollController,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.65,
                      ),
                      itemCount: _trendingProducts.length + (_isLoadingMoreTrending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _trendingProducts.length) {
                          return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                        }
                        return _buildFlashProductCard(context, _trendingProducts[index]);
                      },
                    ),

                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildSliderCard(Map<String, dynamic> slider) {
    final imageUrl = slider['image_url'] as String?;
    final title = slider['title'] as String? ?? '';
    final description = slider['description'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        image: imageUrl != null
            ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
            : null,
        color: imageUrl == null ? Colors.grey[800] : null,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (title.isNotEmpty)
              Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(description, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.grey[400])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCircle(Map<String, dynamic> category) {
    final name = category['name'] as String? ?? 'Unknown';
    final iconUrl = category['icon'] as String?;
    final categoryId = category['id'];

    return GestureDetector(
      onTap: () {
        final navigationService = Provider.of<NavigationService>(context, listen: false);
        navigationService.navigateToCategory(categoryId);
      },
      child: Container(
        width: 60,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: Color(0xFF27272A), shape: BoxShape.circle),
              child: ClipOval(
                child: iconUrl != null && iconUrl.isNotEmpty && !iconUrl.toLowerCase().endsWith('.avif')
                    ? Image.network(
                        iconUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) => progress == null ? child : const Icon(Icons.category, color: Colors.grey),
                        errorBuilder: (_, __, ___) => const Icon(Icons.category, color: AppTheme.primaryColor, size: 18),
                      )
                    : const Icon(Icons.category, color: AppTheme.primaryColor, size: 18),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: GoogleFonts.plusJakartaSans(fontSize: 9, color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashProductCard(BuildContext context, Map<String, dynamic> product) {
    final images = product['images'] as List<dynamic>? ?? [];
    final productImages = List<Map<String, dynamic>>.from(images);
    final primaryImage = productImages.firstWhere((img) => img['is_primary'] == true, orElse: () => productImages.isNotEmpty ? productImages.first : {'image_url': ''});
    final imageUrl = primaryImage['image_url'] as String? ?? '';

    final distance = DeliveryFilterService().userPosition != null
        ? '${LocationService().calculateDistance(
            DeliveryFilterService().userPosition!.latitude,
            DeliveryFilterService().userPosition!.longitude,
            product['vendor_latitude'] ?? 0.0,
            product['vendor_longitude'] ?? 0.0,
          ).toStringAsFixed(1)} km'
        : 'Location required';

    final deliveryInfo = getDeliveryInfo(product, null);
    final deliveryText = deliveryInfo['isFreeDelivery'] == true 
        ? 'Free' 
        : 'NPR ${deliveryInfo['deliveryFee']?.toInt() ?? 'TBD'}';

    final productId = product['id'] as int?;
    final rating = productId != null
        ? (_productReviews[productId]?['average_rating'] ?? 0.0).toStringAsFixed(1)
        : '0.0';
    final reviews = productId != null ? (_productReviews[productId]?['total_reviews'] ?? 0) : 0;
    final ratingText = '$rating ($reviews)';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            productId: productId,
            images: productImages,
            restaurant: product['vendor_name'] ?? 'Unknown Vendor',
            itemName: product['name'] ?? 'Unknown Product',
            rating: ratingText,
            distance: distance,
            soldCount: '${product['total_sold'] ?? 0}+ sold',
            price: 'NPR ${(double.tryParse(product['price']?.toString() ?? '0') ?? 0).toInt()}',
            deliveryFee: deliveryText,
            description: product['description'] as String? ?? '',
            stock: product['quantity'] as int? ?? 0,
            category: product['category'] as String? ?? '',
            vendorId: int.tryParse(product['vendor_id'].toString()),
          ),
        ));
      },
      child: Container(
        width: 160,
        decoration: BoxDecoration(color: const Color(0xFF18181B), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Image.network(
                    imageUrl,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? Container(color: Colors.white, child: child)
                        : Container(
                            height: 120,
                            width: double.infinity,
                            color: const Color(0xFF27272A),
                            child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      width: double.infinity,
                      color: const Color(0xFF27272A),
                      padding: const EdgeInsets.all(16.0),
                      child: Image.asset('assets/images/ezeywaylogo.png',
                          fit: BoxFit.contain),
                    ),
                  ),
                ),
                 // Overlay Cart & Buy Buttons
                 Positioned(
                  bottom: 8, 
                  right: 8, 
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       GestureDetector(
                        onTap: () => _addToCart(productId ?? 0),
                        child: Container(
                           width: 28,
                           height: 28,
                           decoration: BoxDecoration(
                             color: Colors.black.withOpacity(0.7),
                             shape: BoxShape.circle,
                           ),
                           child: const Icon(Icons.shopping_cart, color: AppTheme.primaryColor, size: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _buyNow(product),
                        child: Container(
                           width: 28,
                           height: 28,
                           decoration: const BoxDecoration(
                             color: AppTheme.primaryColor,
                             shape: BoxShape.circle, 
                           ),
                           child: const Icon(Icons.shopping_bag, color: Colors.black, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                        Text(
                          product['vendor_name'] ?? 'Unknown Vendor',
                          style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFFA1A1AA)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product['name'] ?? 'Unknown Product',
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
                            Text(rating, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                             const SizedBox(width: 8),
                             const Icon(Icons.local_fire_department, color: Color(0xFFFF5252), size: 12),
                             const SizedBox(width: 2),
                             Expanded(
                               child: Text(
                                '${product['total_sold'] ?? 0} sold',
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
                            Text(deliveryText, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white)),
                            const SizedBox(width: 6),
                            const Text('•', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 10)),
                            const SizedBox(width: 6),
                            const Icon(Icons.location_on, color: Color(0xFFA1A1AA), size: 12),
                            const SizedBox(width: 4),
                            Expanded(child: Text(distance, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFFA1A1AA)), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'NPR ${(double.tryParse(product['price']?.toString() ?? '0') ?? 0).toInt()}',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, Map<String, dynamic> product) {
    final images = product['images'] as List<dynamic>? ?? [];
    final productImages = List<Map<String, dynamic>>.from(images);
    final primaryImage = productImages.firstWhere((img) => img['is_primary'] == true, orElse: () => productImages.isNotEmpty ? productImages.first : {'image_url': ''});
    final imageUrl = primaryImage['image_url'] as String? ?? '';

    final distance = DeliveryFilterService().userPosition != null
        ? '${LocationService().calculateDistance(
            DeliveryFilterService().userPosition!.latitude,
            DeliveryFilterService().userPosition!.longitude,
            product['vendor_latitude'] ?? 0.0,
            product['vendor_longitude'] ?? 0.0,
          ).toStringAsFixed(1)} km'
        : 'Location required';

    final deliveryInfo = getDeliveryInfo(product, null);
    final deliveryText = deliveryInfo['isFreeDelivery'] == true 
        ? 'Free' 
        : 'NPR ${deliveryInfo['deliveryFee']?.toInt() ?? 'TBD'}';

    final productId = product['id'] as int?;
    final rating = productId != null
        ? (_productReviews[productId]?['average_rating'] ?? 0.0).toStringAsFixed(1)
        : '0.0';
    final reviews = productId != null ? (_productReviews[productId]?['total_reviews'] ?? 0) : 0;
    final ratingText = '$rating ($reviews)';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            productId: productId,
            images: productImages,
            restaurant: product['vendor_name'] ?? 'Unknown Vendor',
            itemName: product['name'] ?? 'Unknown Product',
            rating: ratingText,
            distance: distance,
            soldCount: '${product['total_sold'] ?? 0}+ sold',
            price: 'NPR ${(double.tryParse(product['price']?.toString() ?? '0') ?? 0).toInt()}',
            deliveryFee: deliveryText,
            description: product['description'] as String? ?? '',
            stock: product['quantity'] as int? ?? 0,
            category: product['category'] as String? ?? '',
            vendorId: int.tryParse(product['vendor_id'].toString()),
          ),
        ));
      },
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF18181B), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Image.network(
                    imageUrl,
                    height: 110,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? Container(color: Colors.white, child: child)
                        : Container(
                            color: const Color(0xFF27272A),
                            height: 110,
                            child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      height: 110,
                      width: double.infinity,
                      color: const Color(0xFF27272A),
                      padding: const EdgeInsets.all(8.0),
                      child: Image.asset('assets/images/ezeywaylogo.png',
                          fit: BoxFit.contain),
                    ),
                  ),
                ),
                // Overlay Cart & Buy Buttons
                Positioned(
                  bottom: 8, 
                  right: 8, 
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       GestureDetector(
                        onTap: () => _addToCart(productId ?? 0),
                        child: Container(
                           width: 28,
                           height: 28,
                           decoration: BoxDecoration(
                             color: Colors.black.withOpacity(0.7),
                             shape: BoxShape.circle,
                           ),
                           child: const Icon(Icons.shopping_cart, color: AppTheme.primaryColor, size: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _buyNow(product),
                        child: Container(
                           width: 28,
                           height: 28,
                           decoration: const BoxDecoration(
                             color: AppTheme.primaryColor,
                             shape: BoxShape.circle, 
                           ),
                           child: const Icon(Icons.shopping_bag, color: Colors.black, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Text Content Below Image
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                        Text(
                          product['vendor_name'] ?? 'Unknown Vendor',
                          style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFFA1A1AA)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product['name'] ?? 'Unknown Product',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                         // Rating and Sold Count
                        Row(
                          children: [
                            const Icon(Icons.star, color: AppTheme.primaryColor, size: 12),
                            const SizedBox(width: 4),
                            Text(rating, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                             const SizedBox(width: 8),
                             const Icon(Icons.local_fire_department, color: Color(0xFFFF5252), size: 12),
                             const SizedBox(width: 2),
                             Expanded(
                               child: Text(
                                '${product['total_sold'] ?? 0} sold',
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
                            Text(deliveryText, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white)),
                            const SizedBox(width: 6),
                            const Text('•', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 10)),
                            const SizedBox(width: 6),
                            const Icon(Icons.location_on, color: Color(0xFFA1A1AA), size: 12),
                            const SizedBox(width: 4),
                            Expanded(child: Text(distance, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFFA1A1AA)), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'NPR ${(double.tryParse(product['price']?.toString() ?? '0') ?? 0).toInt()}',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color textColor, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppTheme.primaryColor, size: 12),
            const SizedBox(width: 2),
          ],
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(fontSize: 10, color: textColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, {Color? background, Color? iconColor}) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: background ?? const Color(0xFF27272A), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: iconColor ?? AppTheme.primaryColor, size: 14),
    );
  }

  Future<void> _handleLocationTap() async {
    if (_isLocating) return;

    setState(() => _isLocating = true);

    try {
      final position = await LocationService().getCurrentPosition();
      if (position != null) {
        if (mounted) {
          setState(() {
            _currentAddress = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
            _isLocating = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location updated to Kathmandu (${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)})'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _isLocating = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to get location. Please check permissions.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLocating = false);
        debugPrint('Error getting location: $e');
      }
    }
  }

  Widget _buildBottomNavItem(IconData icon, String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isSelected ? AppTheme.primaryColor : const Color(0xFFA1A1AA), fill: isSelected ? 1.0 : 0.0),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? AppTheme.primaryColor : const Color(0xFFA1A1AA),
            ),
          ),
        ],
      ),
    );
  }

  // Placeholders remain the same as in your original code
  Widget _buildSliderPlaceholder() {
    return PageView.builder(
      controller: _sliderController,
      itemCount: 3,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF27272A)),
          child: const Center(child: Icon(Icons.image, color: Color(0xFFA1A1AA), size: 40)),
        ),
      ),
    );
  }

  Widget _buildCategoriesPlaceholder() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        width: 60,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(width: 42, height: 42, decoration: const BoxDecoration(color: Color(0xFF27272A), shape: BoxShape.circle)),
            const SizedBox(height: 4),
            Container(height: 10, width: 50, color: const Color(0xFF27272A)),
          ],
        ),
      ),
    );
  }
  Widget _buildSearchResults() {
    if (_isLoadingSearch) {
      return const Center(child: SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2)));
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.60,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildProductCard(context, _searchResults[index]);
      },
    );
  }

  Widget _buildFlashProductsPlaceholder() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(color: const Color(0xFF18181B), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Container(height: 120, color: const Color(0xFF27272A)),
            const Padding(padding: EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(height: 10, width: 100), SizedBox(height: 8), SizedBox(height: 12, width: 80)])),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingProductsPlaceholder() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.65,
      children: List.generate(6, (_) => Container(decoration: BoxDecoration(color: const Color(0xFF18181B), borderRadius: BorderRadius.circular(12)), child: Column(children: [Container(height: 130, color: const Color(0xFF27272A)), const Padding(padding: EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(height: 10), SizedBox(height: 4), SizedBox(height: 12)]))]))),
    );
  }
}