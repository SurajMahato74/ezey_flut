// lib/services/data_preloader_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'catalog_location_service.dart';
import '../config.dart' as appConfig;

class DataPreloaderService extends ChangeNotifier {
  static final DataPreloaderService _instance = DataPreloaderService._internal();
  factory DataPreloaderService() => _instance;
  DataPreloaderService._internal() {
    _cacheSessionToken = AuthService().token;
    AuthService().addListener(_onSessionChanged);
  }
  String? _cacheSessionToken;

  void _onSessionChanged() {
    if (_cacheSessionToken == AuthService().token) return;
    _cacheSessionToken = AuthService().token;
    _clearPrivateCache();
    notifyListeners();
  }

  void _clearPrivateCache() {
    _userProfile = _vendorProfile = null;
    _notificationCount = null;
    _vendorEarnings = null;
    _recentOrders = _vendorTransactions = _customerOrders = null;
    _cart = null;
  }

  Timer? _backgroundRefreshTimer;
  static const Duration _refreshInterval = Duration(minutes: 5);
  static const Duration _cacheTTL = Duration(minutes: 30);

  // Cache keys
  static const _kCategories = 'cache_categories';
  static const _kSliders = 'cache_sliders';
  static const _kFlashProducts = 'cache_flash_products_v2';
  static const _kTrendingProducts = 'cache_trending_products_v2';
  static const _kTimestamp = 'cache_timestamp';

  // Cached data
  List<Map<String, dynamic>>? _categories;
  List<Map<String, dynamic>>? _sliders;
  List<Map<String, dynamic>>? _flashProducts;
  List<Map<String, dynamic>>? _trendingProducts;
  Map<int, Map<String, dynamic>>? _productReviews;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _vendorProfile;
  int? _notificationCount;
  Map<String, dynamic>? _vendorEarnings;
  List<Map<String, dynamic>>? _recentOrders;
  List<Map<String, dynamic>>? _vendorTransactions;
  List<Map<String, dynamic>>? _customerOrders;
  Map<String, dynamic>? _cart;

  bool _isPreloading = false;
  String _currentTask = '';
  double _progress = 0.0;

  List<Map<String, dynamic>>? get allProducts => _trendingProducts;
  List<Map<String, dynamic>>? get categories => _categories;
  List<Map<String, dynamic>>? get sliders => _sliders;
  List<Map<String, dynamic>>? get flashProducts => _flashProducts;
  List<Map<String, dynamic>>? get trendingProducts => _trendingProducts;
  Map<int, Map<String, dynamic>>? get productReviews => _productReviews;
  Map<String, dynamic>? get userProfile => _userProfile;
  Map<String, dynamic>? get vendorProfile => _vendorProfile;
  int? get notificationCount => _notificationCount;
  Map<String, dynamic>? get vendorEarnings => _vendorEarnings;
  List<Map<String, dynamic>>? get recentOrders => _recentOrders;
  List<Map<String, dynamic>>? get vendorTransactions => _vendorTransactions;
  List<Map<String, dynamic>>? get customerOrders => _customerOrders;
  Map<String, dynamic>? get cart => _cart;
  bool get isPreloading => _isPreloading;
  String get currentTask => _currentTask;
  double get progress => _progress;

  // ── Cache helpers ──────────────────────────────────────────────

  Future<bool> isCacheFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_kTimestamp);
      if (ts == null) return false;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      return age < _cacheTTL.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final catJson = prefs.getString(_kCategories);
      final slidJson = prefs.getString(_kSliders);
      final flashJson = prefs.getString(_kFlashProducts);
      final trendJson = prefs.getString(_kTrendingProducts);

      if (catJson == null || trendJson == null) return false;

      _categories = List<Map<String, dynamic>>.from(jsonDecode(catJson));
      _sliders = slidJson != null ? List<Map<String, dynamic>>.from(jsonDecode(slidJson)) : [];
      _flashProducts = flashJson != null ? List<Map<String, dynamic>>.from(jsonDecode(flashJson)) : [];
      _trendingProducts = List<Map<String, dynamic>>.from(jsonDecode(trendJson));
      return true;
    } catch (e) {
      debugPrint('Cache load failed: $e');
      return false;
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_categories != null) await prefs.setString(_kCategories, jsonEncode(_categories));
      if (_sliders != null) await prefs.setString(_kSliders, jsonEncode(_sliders));
      if (_flashProducts != null) await prefs.setString(_kFlashProducts, jsonEncode(_flashProducts));
      if (_trendingProducts != null) await prefs.setString(_kTrendingProducts, jsonEncode(_trendingProducts));
      await prefs.setInt(_kTimestamp, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Cache save failed: $e');
    }
  }

  // ── Main preload ───────────────────────────────────────────────

  Future<void> preloadAppData() async {
    await AuthService().initialized;
    if (_isPreloading) return;
    _isPreloading = true;

    try {
      await _initializeCoreServices();

      // Try cache first (web: avoids full reload on refresh)
      final cacheHit = await isCacheFresh() && await _loadFromCache();
      if (cacheHit) {
        _updateProgress(0.6, 'Loaded from cache...');
        debugPrint('DataPreloader: cache hit, skipping public API calls');
      }

      final authService = AuthService();
      if (authService.isLoggedIn) {
        await _preloadAuthenticatedUserData(skipPublic: cacheHit);
      } else if (!cacheHit) {
        await _preloadGuestData();
      }

      if (!cacheHit) await _saveToCache();

      _updateProgress(1.0, 'Ready!');
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
        if (AuthService().isLoggedIn && AuthService().currentRole?.toString().contains('customer') == true)
          _loadCustomerOrdersInBackground(),
        if (AuthService().isLoggedIn && AuthService().currentRole?.toString().contains('customer') == true)
          _loadCartInBackground(),
      ]);
      await _saveToCache();
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    }
  }

  Future<void> _initializeCoreServices() async {
    await CatalogLocationService().initialize();
  }

  Future<void> _preloadGuestData() async {
    final tasks = [
      () => _loadCategories(),
      () => _loadSliders(),
      () => _loadInitialProducts(),
    ];
    await _executeTasks(tasks);
  }

  Future<void> _preloadAuthenticatedUserData({bool skipPublic = false}) async {
    final authService = AuthService();
    final isVendor = authService.currentRole?.toString().contains('vendor') ?? false;

    if (isVendor) {
      final tasks = <Future<void> Function()>[
        () => _loadVendorEarnings(),
        () => _loadVendorProfile(),
        () => _loadUserProfile(),
        () => _loadNotificationCount(),
        if (!skipPublic) () => _loadCategories(),
        if (!skipPublic) () => _loadSliders(),
        if (!skipPublic) () => _loadInitialProducts(),
      ];
      await _executeTasks(tasks);
    } else {
      final tasks = <Future<void> Function()>[
        if (!skipPublic) () => _loadCategories(),
        if (!skipPublic) () => _loadSliders(),
        () => _loadUserProfile(),
        () => _loadNotificationCount(),
        if (!skipPublic) () => _loadInitialProducts(),
        () => _loadCustomerOrdersInBackground(),
        () => _loadCartInBackground(),
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
    const taskNames = [
      'Loading categories...',
      'Loading banners...',
      'Setting up location...',
      'Loading profile...',
      'Checking notifications...',
      'Loading products...',
      'Loading orders...',
      'Loading cart...',
    ];
    return index < taskNames.length ? taskNames[index] : 'Loading... ${index + 1}/$total';
  }

  // ── Individual loaders ─────────────────────────────────────────

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

  Future<void> _loadUserProfile() async {
    try {
      final token = AuthService().token;
      if (token == null) return;
      final profile = await ApiService().getProfile(token);
      if (AuthService().token == token) _userProfile = profile;
    } catch (e) {
      debugPrint('Failed to load user profile: $e');
    }
  }

  Future<void> _loadVendorProfile() async {
    try {
      final token = AuthService().token;
      if (token == null) return;
      final profile = await ApiService().getVendorProfileStatus(token);
      if (AuthService().token == token) _vendorProfile = profile;
    } catch (e) {
      debugPrint('Failed to load vendor profile: $e');
    }
  }

  Future<void> _loadNotificationCount() async {
    try {
      final token = AuthService().token;
      if (token == null) return;
      final response = await ApiService().getNotifications(token, page: 1);
      if (AuthService().token != token) return;
      List<dynamic> results = response is List ? response : (response['results'] ?? []);
      final currentRoleString = AuthService().currentRole?.toString().split('.').last ?? 'customer';
      _notificationCount = results
          .where((n) => n['role'] == currentRoleString && n['is_read'] != true)
          .length;
    } catch (e) {
      _notificationCount = 0;
      debugPrint('Failed to load notification count: $e');
    }
  }

  Future<void> _loadInitialProducts() async {
    try {
      final response = await ApiService().searchProducts(
        pageSize: 50,
        page: 1,
      );

      final allProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);

      final futures = await Future.wait([
        ApiService().getFlashProducts(),
        _filterActiveVendorProducts(allProducts),
      ]);

      _flashProducts = futures[0];
      _trendingProducts = futures[1];

      if (!kIsWeb) {
        final allImageUrls = <String>{};
        for (final product in [..._flashProducts!, ..._trendingProducts!]) {
          for (final img in (product['images'] as List<dynamic>? ?? [])) {
            if (img is Map<String, dynamic> && img['image_url'] != null) {
              allImageUrls.add(img['image_url']);
            }
          }
        }
        if (_sliders != null) {
          for (final slider in _sliders!) {
            if (slider['image_url'] != null) allImageUrls.add(slider['image_url']);
          }
        }
        await _preloadImages(allImageUrls.toList());
      }

      final allProductIds = <int>{
        ...?_flashProducts?.map((p) => p['id'] as int),
        ...?_trendingProducts?.map((p) => p['id'] as int),
      };
      if (allProductIds.isNotEmpty) await _loadProductReviews(allProductIds.toList());
    } catch (e) {
      debugPrint('Failed to load initial products: $e');
    }
  }

  Future<void> _preloadImages(List<String> imageUrls) async {
    try {
      await Future.wait(imageUrls.map((url) async {
        try {
          await http.get(Uri.parse(url));
        } catch (_) {}
      }));
    } catch (e) {
      debugPrint('Image preloading failed: $e');
    }
  }

  Future<void> _loadFlashProducts(dynamic userPosition) async {
    try {
      _flashProducts = await ApiService().getFlashProducts();
    } catch (e) {
      debugPrint('Failed to load flash products: $e');
    }
  }

  Future<void> _loadTrendingProducts(dynamic userPosition) async {
    try {
      final response = await ApiService().searchProducts(
        pageSize: 20,
        page: 1,
      );
      _trendingProducts = await _filterActiveVendorProducts(
          List<Map<String, dynamic>>.from(response['results'] ?? []));
    } catch (e) {
      _trendingProducts = [];
      debugPrint('Failed to load trending products: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _filterActiveVendorProducts(
      List<Map<String, dynamic>> products) async {
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

    return products.where((product) {
      if ((product['quantity'] ?? 0) <= 0) return false;
      final vendorId = product['vendor_id'];
      if (vendorId == null || vendorStatuses[vendorId] != true) return false;
      if (vendorId == currentUserId) return false;
      return true;
    }).toList();
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

      if (AuthService().token != token) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List orders = [];
        if (data is Map<String, dynamic>) {
          orders = data['results'] ?? data['data'] ?? [];
        } else if (data is List) {
          orders = data;
        }

        final List<Map<String, dynamic>> vendorOrders = orders.cast<Map<String, dynamic>>();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        double todays = 0, monthly = 0, total = 0;
        final chartData = List.filled(6, 0.0);

        for (var order in vendorOrders) {
          final amount = double.tryParse((order['total_amount'] ?? order['amount'] ?? '0').toString()) ?? 0.0;
          final createdAt = DateTime.tryParse(order['created_at'] ?? '');
          if (createdAt == null) continue;
          final status = (order['status'] ?? '').toString().toLowerCase();
          if (!['confirmed', 'delivered', 'completed', 'out_for_delivery'].contains(status)) continue;

          if (createdAt.year == today.year && createdAt.month == today.month && createdAt.day == today.day) todays += amount;
          if (createdAt.month == now.month && createdAt.year == now.year) monthly += amount;
          total += amount;
          final monthsAgo = (now.year - createdAt.year) * 12 + (now.month - createdAt.month);
          if (monthsAgo >= 0 && monthsAgo <= 5) chartData[5 - monthsAgo] += amount;
        }

        _vendorEarnings = {
          'todaysEarnings': todays,
          'monthlyEarnings': monthly,
          'totalEarnings': total,
          'monthlyChartData': chartData,
        };
        _vendorTransactions = vendorOrders;
        _recentOrders = vendorOrders.take(5).toList();
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
      if (AuthService().token != token) return;
      if (response.statusCode == 200) {
        final cart = await _filterCartJson(jsonDecode(response.body) as Map<String, dynamic>);
        if (AuthService().token == token) _cart = cart;
      }
    } catch (e) {
      debugPrint('Failed to preload cart: $e');
    }
  }

  Future<Map<String, dynamic>> _filterCartJson(Map<String, dynamic> cartData) async {
    final items = cartData['items'] as List? ?? [];
    if (items.isEmpty) return cartData;

    final uniqueVendorIds = items
        .map((item) => (item['product']?['vendor_id'] ?? item['product']?['vendor']) as int?)
        .where((id) => id != null)
        .cast<int>()
        .toSet()
        .toList();

    final vendorStatuses = <int, bool>{};
    await Future.wait(uniqueVendorIds.map((id) async {
      try {
        final vendor = await ApiService().getVendorDetails(id);
        vendorStatuses[id] = vendor['is_active'] == true;
      } catch (_) {
        vendorStatuses[id] = false;
      }
    }));

    final filteredItems = items.where((item) {
      final vendorId = (item['product']?['vendor_id'] ?? item['product']?['vendor']) as int?;
      return vendorId != null && vendorStatuses[vendorId] == true;
    }).toList();

    double subtotal = filteredItems.fold(0, (sum, item) =>
        sum + (double.tryParse(item['total_price']?.toString() ?? '0') ?? 0));

    return {...cartData, 'items': filteredItems, 'subtotal': subtotal, 'total_items': filteredItems.length};
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
      if (AuthService().token != token) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _customerOrders = List<Map<String, dynamic>>.from(data['results'] ?? []);
      }
    } catch (e) {
      debugPrint('Failed to preload customer orders: $e');
      _customerOrders = [];
    }
  }

  Future<void> _loadProductReviews(List<int> productIds) async {
    try {
      final results = await Future.wait(productIds.map(ApiService().getProductReviews));
      _productReviews = {
        for (int i = 0; i < productIds.length; i++)
          productIds[i]: {
            'average_rating': results[i]['aggregate']?['average_rating'] ?? 0.0,
            'total_reviews': results[i]['aggregate']?['total_reviews'] ?? 0,
          }
      };
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

  // ── Public helpers ─────────────────────────────────────────────

  Future<void> clearCache() async {
    _backgroundRefreshTimer?.cancel();
    _categories = _sliders = _flashProducts = _trendingProducts = null;
    _productReviews = null;
    _userProfile = _vendorProfile = null;
    _notificationCount = null;
    _vendorEarnings = null;
    _recentOrders = _vendorTransactions = _customerOrders = null;
    _cart = null;
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_kCategories, _kSliders, _kFlashProducts, _kTrendingProducts, _kTimestamp]) {
      await prefs.remove(key);
    }
  }

  Future<void> refreshCategories() => _loadCategories();

  Future<void> refreshProducts() async {
    final pos = CatalogLocationService().userPosition;
    await Future.wait([_loadFlashProducts(pos), _loadTrendingProducts(pos)]);
    final ids = <int>{
      ...?_flashProducts?.map((p) => p['id'] as int),
      ...?_trendingProducts?.map((p) => p['id'] as int),
    };
    if (ids.isNotEmpty) await _loadProductReviews(ids.toList());
    await _saveToCache();
  }

  Future<void> refreshNotificationCount() => _loadNotificationCount();

  Future<Map<String, dynamic>?> getVendorEarningsQuick() async {
    if (_vendorEarnings != null) return _vendorEarnings;
    await _loadVendorEarnings();
    return _vendorEarnings;
  }

  Future<void> refreshVendorEarnings() => _loadVendorEarnings();

  Future<List<Map<String, dynamic>>?> getVendorTransactionsQuick() async {
    if (_vendorTransactions != null) return _vendorTransactions;
    await _loadVendorEarnings();
    return _vendorTransactions;
  }
}
