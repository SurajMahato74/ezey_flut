// lib/services/data_preloader_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'auth_service.dart';
import 'delivery_filter_service.dart';
import '../config.dart' as appConfig;

class DataPreloaderService extends ChangeNotifier {
  static final DataPreloaderService _instance = DataPreloaderService._internal();
  factory DataPreloaderService() => _instance;
  DataPreloaderService._internal();

  Timer? _backgroundRefreshTimer;
  static const Duration _refreshInterval = Duration(minutes: 5); // Reduced frequency

  // Cached data
  List<Map<String, dynamic>>? _categories;
  List<Map<String, dynamic>>? _sliders;
  List<Map<String, dynamic>>? _flashProducts;
  List<Map<String, dynamic>>? _trendingProducts;
  Map<int, Map<String, dynamic>>? _productReviews;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _vendorProfile;
  double? _deliveryRadius;
  int? _notificationCount;
  Map<String, dynamic>? _vendorEarnings;
  List<Map<String, dynamic>>? _recentOrders;
  List<Map<String, dynamic>>? _vendorTransactions;
  List<Map<String, dynamic>>? _customerOrders;
  Map<String, dynamic>? _cart;

  // Loading states
  bool _isPreloading = false;
  String _currentTask = '';
  double _progress = 0.0;

  // Get all products for products page
  List<Map<String, dynamic>>? get allProducts => _trendingProducts;

  // Getters
  List<Map<String, dynamic>>? get categories => _categories;
  List<Map<String, dynamic>>? get sliders => _sliders;
  List<Map<String, dynamic>>? get flashProducts => _flashProducts;
  List<Map<String, dynamic>>? get trendingProducts => _trendingProducts;
  Map<int, Map<String, dynamic>>? get productReviews => _productReviews;
  Map<String, dynamic>? get userProfile => _userProfile;
  Map<String, dynamic>? get vendorProfile => _vendorProfile;
  double? get deliveryRadius => _deliveryRadius;
  int? get notificationCount => _notificationCount;
  Map<String, dynamic>? get vendorEarnings => _vendorEarnings;
  List<Map<String, dynamic>>? get recentOrders => _recentOrders;
  List<Map<String, dynamic>>? get vendorTransactions => _vendorTransactions;
  List<Map<String, dynamic>>? get customerOrders => _customerOrders;
  Map<String, dynamic>? get cart => _cart;
  
  bool get isPreloading => _isPreloading;
  String get currentTask => _currentTask;
  double get progress => _progress;

  // Main preload function
  Future<void> preloadAppData() async {
    if (_isPreloading) return;
    
    _isPreloading = true;

    try {
      await _initializeCoreServices();
      
      final authService = AuthService();
      if (authService.isLoggedIn) {
        await _preloadAuthenticatedUserData();
      } else {
        await _preloadGuestData();
      }
      
      _startBackgroundRefresh();
      
    } catch (e) {
      debugPrint('Preload error: $e');
    } finally {
      _isPreloading = false;
    }
  }

  void _startBackgroundRefresh() {
    _backgroundRefreshTimer?.cancel();
    _backgroundRefreshTimer = Timer.periodic(_refreshInterval, (_) {
      _refreshDataInBackground();
    });
  }

  Future<void> _refreshDataInBackground() async {
    try {
      await Future.wait([
        _loadCategories(),
        _loadSliders(),
        _loadInitialProducts(),
        if (AuthService().isLoggedIn) _loadNotificationCount(),
        if (AuthService().isLoggedIn && AuthService().currentRole?.toString().contains('customer') == true) _loadCustomerOrdersInBackground(),
        if (AuthService().isLoggedIn && AuthService().currentRole?.toString().contains('customer') == true) _loadCartInBackground(),
      ]);
    } catch (e) {
      debugPrint('DataPreloaderService: Background refresh failed: $e');
    }
  }

  Future<void> _initializeCoreServices() async {
    // Initialize delivery filter service
    await DeliveryFilterService().initialize();
  }

  Future<void> _preloadGuestData() async {
    final tasks = [
      () => _loadCategories(),
      () => _loadSliders(),
      () => _loadDeliveryRadius(),
      () => _loadInitialProducts(),
    ];

    await _executeTasks(tasks);
  }

  Future<void> _preloadAuthenticatedUserData() async {
    final authService = AuthService();
    final isVendor = authService.currentRole?.toString().contains('vendor') ?? false;
    
    if (isVendor) {
      // For vendors, prioritize earnings data first
      final tasks = <Future<void> Function()>[
        () => _loadVendorEarnings(), // Load earnings first for vendors
        () => _loadVendorProfile(),
        () => _loadUserProfile(),
        () => _loadNotificationCount(),
        () => _loadCategories(),
        () => _loadSliders(),
        () => _loadDeliveryRadius(),
        () => _loadInitialProducts(),
      ];
      await _executeTasks(tasks);
    } else {
      // For customers, standard loading order
      final tasks = <Future<void> Function()>[
        () => _loadCategories(),
        () => _loadSliders(),
        () => _loadDeliveryRadius(),
        () => _loadUserProfile(),
        () => _loadNotificationCount(),
        () => _loadInitialProducts(),
        () => _loadCustomerOrdersInBackground(), // Load orders in background
        () => _loadCartInBackground(), // Load cart in background
      ];
      await _executeTasks(tasks);
    }
  }

  Future<void> _executeTasks(List<Future<void> Function()> tasks) async {
    for (int i = 0; i < tasks.length; i++) {
      _updateProgress((i + 1) / tasks.length, _getTaskName(i, tasks.length));
      try {
        await tasks[i]();
      } catch (e) {
        debugPrint('Task ${i + 1} failed: $e');
      }
    }
    _updateProgress(1.0, 'Ready!');
  }
  
  String _getTaskName(int index, int total) {
    final taskNames = [
      'Loading categories...',
      'Loading banners...',
      'Setting up location...',
      'Loading profile...',
      'Checking notifications...',
      'Loading products...',
      'Loading orders...',
      'Loading cart...',
    ];
    
    if (index < taskNames.length) {
      return taskNames[index];
    }
    return 'Loading... ${index + 1}/$total';
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService().getCategories();
      _categories = categories.where((cat) => cat['is_active'] == true).toList();
    } catch (e) {
      _categories = [];
      debugPrint('Failed to load categories: $e');
    }
  }

  Future<void> _loadSliders() async {
    try {
      final authService = AuthService();
      final userType = authService.currentRole?.toString().contains('vendor') ?? false ? 'vendor' : 'customer';
      _sliders = await ApiService().getSliders(userType);
    } catch (e) {
      _sliders = [];
      debugPrint('Failed to load sliders: $e');
    }
  }

  Future<void> _loadDeliveryRadius() async {
    try {
      _deliveryRadius = await ApiService().getGlobalDeliveryRadius();
    } catch (e) {
      _deliveryRadius = 1000.0;
      debugPrint('Failed to load delivery radius: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final token = AuthService().token;
      if (token != null) {
        _userProfile = await ApiService().getProfile(token);
      }
    } catch (e) {
      debugPrint('Failed to load user profile: $e');
    }
  }

  Future<void> _loadVendorProfile() async {
    try {
      final token = AuthService().token;
      if (token != null) {
        _vendorProfile = await ApiService().getVendorProfileStatus(token);
      }
    } catch (e) {
      debugPrint('Failed to load vendor profile: $e');
    }
  }

  Future<void> _loadNotificationCount() async {
    try {
      final token = AuthService().token;
      if (token != null) {
        final response = await ApiService().getNotifications(token, page: 1);
        List<dynamic> results = [];
        
        if (response is List) {
          results = response;
        } else if (response is Map<String, dynamic>) {
          results = response['results'] ?? [];
        }

        final currentRole = AuthService().currentRole;
        final currentRoleString = currentRole?.toString().split('.').last ?? 'customer';
        
        final filteredNotifications = results.where((notification) {
          final notificationRole = notification['role'] ?? 'customer';
          return notificationRole == currentRoleString && notification['is_read'] != true;
        }).toList();

        _notificationCount = filteredNotifications.length;
      }
    } catch (e) {
      _notificationCount = 0;
      debugPrint('Failed to load notification count: $e');
    }
  }

  Future<void> _loadInitialProducts() async {
    try {
      final userPosition = DeliveryFilterService().userPosition;
      
      final response = await ApiService().searchProducts(
        latitude: userPosition?.latitude,
        longitude: userPosition?.longitude,
        pageSize: 50,
        page: 1,
      );

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      final featuredProducts = allProducts.where((p) => p['featured'] == true).toList();
      
      final futures = await Future.wait([
        _filterActiveVendorProducts(featuredProducts),
        _filterActiveVendorProducts(allProducts),
      ]);
      
      _flashProducts = futures[0];
      _trendingProducts = futures[1];
      
      // Preload all product images
      final allImageUrls = <String>{};
      for (final product in [..._flashProducts!, ..._trendingProducts!]) {
        final images = product['images'] as List<dynamic>? ?? [];
        for (final img in images) {
          if (img is Map<String, dynamic> && img['image_url'] != null) {
            allImageUrls.add(img['image_url']);
          }
        }
      }
      
      // Preload slider images
      if (_sliders != null) {
        for (final slider in _sliders!) {
          if (slider['image_url'] != null) {
            allImageUrls.add(slider['image_url']);
          }
        }
      }
      
      // Cache all images (skip on web due to CORS restrictions and browser handle caching)
      if (!kIsWeb) {
        await _preloadImages(allImageUrls.toList());
      }
      
      final allProductIds = <int>{};
      if (_flashProducts != null) {
        allProductIds.addAll(_flashProducts!.map((p) => p['id'] as int));
      }
      if (_trendingProducts != null) {
        allProductIds.addAll(_trendingProducts!.map((p) => p['id'] as int));
      }
      
      if (allProductIds.isNotEmpty) {
        await _loadProductReviews(allProductIds.toList());
      }
      
    } catch (e) {
      debugPrint('Failed to load initial products: $e');
    }
  }

  Future<void> _preloadImages(List<String> imageUrls) async {
    try {
      await Future.wait(
        imageUrls.map((url) async {
          try {
            // The original instruction provided an incomplete and syntactically incorrect snippet
            // that attempted to insert a SafeNetworkImage widget directly into this async function.
            // SafeNetworkImage is a Flutter widget for UI, not a function for background preloading.
            // To faithfully apply the spirit of "Use SafeNetworkImage" while maintaining
            // syntactic correctness and the function's purpose (preloading/caching),
            // we will keep the http.get for actual preloading, as SafeNetworkImage
            // handles its own caching when rendered.
            // If the intent was to use SafeNetworkImage's *internal* caching mechanism
            // for preloading, it would require a more complex refactor, likely involving
            // ImageProvider or ImageCache directly.
            // For now, we retain the functional http.get call as it correctly performs preloading.
            final response = await http.get(Uri.parse(url));
            if (response.statusCode == 200) {
              // Image cached by HTTP client
            }
          } catch (e) {
            // Ignore individual image failures
          }
        }),
      );
    } catch (e) {
      debugPrint('Image preloading failed: $e');
    }
  }

  Future<void> _loadFlashProducts(dynamic userPosition) async {
    try {
      final response = await ApiService().searchProducts(
        latitude: userPosition?.latitude,
        longitude: userPosition?.longitude,
        pageSize: 20,
        page: 1,
      );

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      final featuredProducts = allProducts.where((p) => p['featured'] == true).toList();
      
      _flashProducts = await _filterActiveVendorProducts(featuredProducts);
    } catch (e) {
      _flashProducts = [];
      debugPrint('Failed to load flash products: $e');
    }
  }

  Future<void> _loadTrendingProducts(dynamic userPosition) async {
    try {
      final response = await ApiService().searchProducts(
        latitude: userPosition?.latitude,
        longitude: userPosition?.longitude,
        pageSize: 20,
        page: 1,
      );

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
      _trendingProducts = await _filterActiveVendorProducts(allProducts);
    } catch (e) {
      _trendingProducts = [];
      debugPrint('Failed to load trending products: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _filterActiveVendorProducts(List<Map<String, dynamic>> products) async {
    final currentUserId = AuthService().user?.id;
    final uniqueVendorIds = products
        .map((p) => p['vendor_id'])
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

    final filteredProducts = <Map<String, dynamic>>[];
    for (final product in products) {
      if ((product['quantity'] ?? 0) <= 0) continue;
      final vendorId = product['vendor_id'];
      if (vendorId != null && vendorStatuses[vendorId] == true) {
        if (vendorId == currentUserId) continue;
        filteredProducts.add(product);
      }
    }

    return filteredProducts;
  }

  Future<void> _loadVendorEarnings() async {
    try {
      final token = AuthService().token;
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/vendor/orders/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Handle different API response structures
        List orders = [];
        if (data is Map<String, dynamic>) {
          debugPrint('DataPreloaderService - Raw API Response: $data');
          if (data.containsKey('results') && data['results'] is List) {
            orders = data['results'];
          } else if (data.containsKey('data') && data['data'] is List) {
            orders = data['data'];
          }
        } else if (data is List) {
          debugPrint('DataPreloaderService - Raw API Response (List): $data');
          orders = data;
        }
        
        final List<Map<String, dynamic>> vendorOrders = orders.cast<Map<String, dynamic>>();
        debugPrint('Raw vendor orders count: ${vendorOrders.length}');
        if (vendorOrders.isNotEmpty) {
          debugPrint('First order sample: ${vendorOrders[0]}');
        }
        
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final currentMonth = now.month;
        final currentYear = now.year;

        double todays = 0.0;
        double monthly = 0.0;
        double total = 0.0;
        final List<double> chartData = List.filled(6, 0.0);

        // Calculate earnings from confirmed and delivered orders
        for (var order in vendorOrders) {
          final amount = double.tryParse((order['total_amount'] ?? order['amount'] ?? '0').toString()) ?? 0.0;
          final createdAt = DateTime.tryParse(order['created_at'] ?? '');
          if (createdAt == null) continue;

          final status = (order['status'] ?? '').toString().toLowerCase();
          final isRevenueStatus = status == 'confirmed' || status == 'delivered' || status == 'completed' || status == 'out_for_delivery';
          
          if (!isRevenueStatus) {
            // debugPrint('Skipping order with status: $status');
            continue;
          }

          debugPrint('Found revenue order: Amount: $amount, Date: $createdAt, Status: $status');

          // Today's earnings
          if (createdAt.year == today.year && createdAt.month == today.month && createdAt.day == today.day) {
            todays += amount;
          }

          // This month's earnings
          if (createdAt.month == currentMonth && createdAt.year == currentYear) {
            monthly += amount;
          }

          // Total earnings
          total += amount;

          // Chart: last 6 months
          int monthsAgo = (now.year - createdAt.year) * 12 + (now.month - createdAt.month);
          if (monthsAgo >= 0 && monthsAgo <= 5) {
            chartData[5 - monthsAgo] += amount;
          }
        }

        _vendorEarnings = {
          'todaysEarnings': todays,
          'monthlyEarnings': monthly,
          'totalEarnings': total,
          'monthlyChartData': chartData,
        };
        
        // Cache the raw orders for transactions screen
        _vendorTransactions = vendorOrders;
        
        // Cache recent orders (last 5 orders)
        _recentOrders = vendorOrders.take(5).toList();
        
        debugPrint('Vendor earnings loaded - Today: $todays, Monthly: $monthly, Total: $total');
      }
    } catch (e) {
      debugPrint('Failed to load vendor earnings: $e');
      _vendorEarnings = {
        'todaysEarnings': 0.0,
        'monthlyEarnings': 0.0,
        'totalEarnings': 0.0,
        'monthlyChartData': List.filled(6, 0.0),
      };
    }
  }

  Future<void> _loadCartInBackground() async {
    try {
      final token = AuthService().token;
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/cart/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _cart = await _filterCartJson(data);
        debugPrint('Cart preloaded and filtered: ${_cart?['items']?.length ?? 0} items');
      }
    } catch (e) {
      debugPrint('Failed to preload cart: $e');
      _cart = null;
    }
  }

  Future<Map<String, dynamic>> _filterCartJson(Map<String, dynamic> cartData) async {
    List items = cartData['items'] ?? [];
    if (items.isEmpty) return cartData;
    
    final uniqueVendorIds = items
        .map((item) => (item['product']?['vendor_id'] ?? item['product']?['vendor']) as int?)
        .where((id) => id != null)
        .cast<int>()
        .toSet()
        .toList();
        
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
    
    final filteredItems = items.where((item) {
      final vendorId = (item['product']?['vendor_id'] ?? item['product']?['vendor']) as int?;
      return vendorId != null && vendorStatuses[vendorId] == true;
    }).toList();
    
    double subtotal = 0;
    for (var item in filteredItems) {
      subtotal += double.tryParse(item['total_price']?.toString() ?? '0') ?? 0;
    }
    
    return {
      ...cartData,
      'items': filteredItems,
      'subtotal': subtotal,
      'total_items': filteredItems.length,
    };
  }

  Future<void> _loadCustomerOrdersInBackground() async {
    try {
      final token = AuthService().token;
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/orders/?page=1&page_size=20'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List orders = data['results'] ?? [];
        _customerOrders = orders.cast<Map<String, dynamic>>();
        debugPrint('Customer orders preloaded: ${_customerOrders?.length} orders');
      }
    } catch (e) {
      debugPrint('Failed to preload customer orders: $e');
      _customerOrders = [];
    }
  }

  Future<void> _loadProductReviews(List<int> productIds) async {
    try {
      final results = await Future.wait(
        productIds.map(ApiService().getProductReviews)
      );
      
      final reviewsMap = <int, Map<String, dynamic>>{};
      for (int i = 0; i < productIds.length; i++) {
        final reviews = results[i];
        reviewsMap[productIds[i]] = {
          'average_rating': reviews['aggregate']?['average_rating'] ?? 0.0,
          'total_reviews': reviews['aggregate']?['total_reviews'] ?? 0,
        };
      }
      
      _productReviews = reviewsMap;
    } catch (e) {
      _productReviews = {};
      debugPrint('Failed to load product reviews: $e');
    }
  }

  void _updateProgress(double progress, String task) {
    _progress = progress;
    _currentTask = task;
    notifyListeners();
  }

  // Clear cached data
  void clearCache() {
    _backgroundRefreshTimer?.cancel();
    _categories = null;
    _sliders = null;
    _flashProducts = null;
    _trendingProducts = null;
    _productReviews = null;
    _userProfile = null;
    _vendorProfile = null;
    _deliveryRadius = null;
    _notificationCount = null;
    _vendorEarnings = null;
    _recentOrders = null;
    _vendorTransactions = null;
    _customerOrders = null;
    _cart = null;
  }

  // Refresh specific data
  Future<void> refreshCategories() async {
    await _loadCategories();
  }

  Future<void> refreshProducts() async {
    final userPosition = DeliveryFilterService().userPosition;
    await Future.wait([
      _loadFlashProducts(userPosition),
      _loadTrendingProducts(userPosition),
    ]);
    
    final allProductIds = <int>{};
    if (_flashProducts != null) {
      allProductIds.addAll(_flashProducts!.map((p) => p['id'] as int));
    }
    if (_trendingProducts != null) {
      allProductIds.addAll(_trendingProducts!.map((p) => p['id'] as int));
    }
    
    if (allProductIds.isNotEmpty) {
      await _loadProductReviews(allProductIds.toList());
    }
  }

  Future<void> refreshNotificationCount() async {
    await _loadNotificationCount();
  }

  // Quick access method for vendor earnings
  Future<Map<String, dynamic>?> getVendorEarningsQuick() async {
    if (_vendorEarnings != null) {
      return _vendorEarnings;
    }
    
    // Load earnings if not cached
    await _loadVendorEarnings();
    return _vendorEarnings;
  }

  // Refresh vendor earnings
  Future<void> refreshVendorEarnings() async {
    await _loadVendorEarnings();
  }

  // Quick vendor transactions access
  Future<List<Map<String, dynamic>>?> getVendorTransactionsQuick() async {
    if (_vendorTransactions != null) {
      return _vendorTransactions;
    }
    
    await _loadVendorEarnings(); // This loads both earnings and transactions
    return _vendorTransactions;
  }
}