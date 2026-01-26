// lib/screens/vendor_dashboard_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/data_preloader_service.dart';
import '../config.dart' as appConfig;
import 'vendor_wallet_screen.dart';
import 'vendor_orders_screen.dart';
import 'vendor_notifications_screen.dart';
import 'message_inbox_screen.dart';
import 'vendor_profile_screen.dart';
import 'vendor_earnings_screen.dart';
import 'product_management_screen.dart';
import '../widgets/safe_network_image.dart';

class VendorDashboardScreen extends StatefulWidget {
  final VoidCallback? onSwitchToCustomer;
  const VendorDashboardScreen({super.key, this.onSwitchToCustomer});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen>
    with AutomaticKeepAliveClientMixin {

  bool isOnline = true;
  bool isLoadingStatus = false;
  String earningsPeriod = 'Today'; // Default to Today
  Map<String, dynamic>? _walletData;
  bool _isLoadingWallet = false;

  List<Map<String, dynamic>> _sliders = [];
  bool _isLoadingSliders = true;
  late final PageController _sliderController;
  Timer? _sliderTimer;

  // Products data
  List<Map<String, dynamic>> _products = [];
  bool _isLoadingProducts = true;
  String _selectedProductTab = 'featured';

  // Earnings data
  bool _isLoadingOrders = true;
  double _todaysEarnings = 0.0;
  double _monthlyEarnings = 0.0;
  double _totalEarnings = 0.0;
  List<double> _monthlyChartData = [0, 0, 0, 0, 0, 0]; // Last 6 months

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sliderController = PageController(
      viewportFraction: 0.8,
      initialPage: 1000,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeWithPreloadedData();
    });
  }

  Future<void> _initializeWithPreloadedData() async {
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    
    // Use preloaded data if available
    if (preloader.sliders != null) {
      setState(() {
        _sliders = preloader.sliders!;
        _isLoadingSliders = false;
      });
      _startSliderAutoPlay();
    } else {
      _fetchSliders();
    }
    
    if (preloader.vendorProfile != null) {
      final vendorData = preloader.vendorProfile!;
      setState(() {
        isOnline = vendorData['is_active'] ?? false;
      });
    } else {
      _fetchVendorStatus();
    }
    
    // Use preloaded earnings data if available, otherwise get quick access
    final earningsData = await preloader.getVendorEarningsQuick();
    if (earningsData != null) {
      setState(() {
        _todaysEarnings = earningsData['todaysEarnings'] ?? 0.0;
        _monthlyEarnings = earningsData['monthlyEarnings'] ?? 0.0;
        _totalEarnings = earningsData['totalEarnings'] ?? 0.0;
        _monthlyChartData = List<double>.from(earningsData['monthlyChartData'] ?? [0, 0, 0, 0, 0, 0]);
        _isLoadingOrders = false;
      });
    } else {
      _fetchVendorOrders();
    }
    
    // Always fetch fresh wallet data as it changes frequently
    _fetchVendorWallet();
    
    // Fetch products
    _fetchVendorProducts();
  }

  @override
  void dispose() {
    _sliderTimer?.cancel();
    _sliderController.dispose();
    super.dispose();
  }

  // ==================== FETCH WALLET ====================
  Future<void> _fetchVendorWallet() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    if (mounted) setState(() => _isLoadingWallet = true);

    try {
      final wallet = await ApiService().getVendorWallet(token);
      if (mounted) {
        setState(() {
          _walletData = wallet;
          _isLoadingWallet = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingWallet = false);
    }
  }

  // ==================== FETCH VENDOR STATUS ====================
  Future<void> _fetchVendorStatus() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      final status = await ApiService().getVendorStatus(token);
      if (mounted) {
        setState(() {
          isOnline = status['is_active'] ?? false;
        });
      }
    } catch (e) {
      // Silent
    }
  }

  // ==================== TOGGLE STATUS ====================
  Future<void> _toggleVendorStatus(bool value) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authentication token not found'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Prevent multiple simultaneous requests
    if (isLoadingStatus) return;

    setState(() {
      isLoadingStatus = true;
    });

    try {
      final result = await ApiService().toggleVendorStatus(token, value);
      if (mounted) {
        setState(() {
          isOnline = result['vendor']['is_active'] ?? value;
          isLoadingStatus = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Status updated successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingStatus = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // ==================== FETCH SLIDERS ====================
  Future<void> _fetchSliders() async {
    try {
      final sliders = await ApiService().getSliders('vendor');
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

  // ==================== FETCH PRODUCTS ====================
  Future<void> _fetchVendorProducts() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    if (mounted) setState(() => _isLoadingProducts = true);

    try {
      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/products/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List productsList = [];
        
        if (data is Map<String, dynamic>) {
          productsList = data['results'] ?? data['data'] ?? [];
        } else if (data is List) {
          productsList = data;
        }

        if (mounted) {
          setState(() {
            _products = productsList.cast<Map<String, dynamic>>();
            _isLoadingProducts = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  // ==================== FETCH ORDERS & CALCULATE EARNINGS ====================
  Future<void> _fetchVendorOrders() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    if (mounted) setState(() => _isLoadingOrders = true);

    try {
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
          if (data.containsKey('results') && data['results'] is List) {
            orders = data['results'];
          } else if (data.containsKey('data') && data['data'] is List) {
            orders = data['data'];
          }
        } else if (data is List) {
          orders = data;
        }
        
        final List<Map<String, dynamic>> vendorOrders = orders.cast<Map<String, dynamic>>();

        final completedOrders = vendorOrders.where((o) =>
            o['status'] == 'confirmed' || o['status'] == 'delivered' || o['status'] == 'completed').toList();

        // Debug print to check orders
        print('Total orders: ${vendorOrders.length}');
        print('Completed orders: ${completedOrders.length}');
        print('Order statuses: ${vendorOrders.map((o) => o['status']).toList()}');
        print('Raw API response: $data');

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final currentMonth = now.month;
        final currentYear = now.year;

        double totalRevenueCalculation = 0.0;
        double todays = 0.0;
        double monthly = 0.0;
        final List<double> chartData = List.filled(6, 0.0);

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
          // Today's earnings
          if (createdAt.year == today.year && createdAt.month == today.month && createdAt.day == today.day) {
            todays += amount;
          }

          // This month's earnings
          if (createdAt.month == currentMonth && createdAt.year == currentYear) {
            monthly += amount;
          }

          // Total revenue
          if (isRevenueStatus) {
            totalRevenueCalculation += amount;
          }

          // Chart: last 6 months
          int monthsAgo = (now.year - createdAt.year) * 12 + (now.month - createdAt.month);
          if (monthsAgo >= 0 && monthsAgo <= 5 && isRevenueStatus) {
            chartData[5 - monthsAgo] += amount;
          }
        }

        if (mounted) {
          setState(() {
            _todaysEarnings = todays;
            _monthlyEarnings = monthly;
            _totalEarnings = totalRevenueCalculation; 
            _monthlyChartData = chartData;
            _isLoadingOrders = false;
          });
          
          // Debug print final totals
          print('Final totals - Today: $todays, Monthly: $monthly, Total Revenue: $totalRevenueCalculation');
        }
      }
    } catch (e) {
      print('Error fetching orders: $e');
      if (mounted) setState(() => _isLoadingOrders = false);
    }
  }

  // ==================== NAVIGATION ====================
  void _navigateToWallet() => Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorWalletScreen()));
  
  void _navigateToOrders() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD60A)),
        ),
      );
      
      // Small delay to show loader
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        Navigator.pop(context); // Remove loader
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const VendorOrdersScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Remove loader if still showing
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to open orders page'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  void _navigateToProducts() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD60A)),
        ),
      );
      
      // Small delay to show loader
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        Navigator.pop(context); // Remove loader
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProductManagementScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Remove loader if still showing
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to open products page'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  void _navigateToNotifications() => Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorNotificationsScreen()));
  void _navigateToMessages() => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessageInboxScreen()));
  void _navigateToProfile() => Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorProfileScreen(vendorId: 1)));
  void _navigateToEarnings() => Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorEarningsScreen()));

  // ==================== REFRESH ====================
  Future<void> _onRefresh() async {
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    
    final futures = [
      _fetchVendorStatus(),
      _fetchVendorWallet(),
      _fetchSliders(),
      _fetchVendorProducts(),
      preloader.refreshVendorEarnings(), // Use preloader refresh method
    ];
    await Future.wait(futures);
    
    // Update UI with refreshed earnings data
    final earningsData = preloader.vendorEarnings;
    if (earningsData != null) {
      setState(() {
        _todaysEarnings = earningsData['todaysEarnings'] ?? 0.0;
        _monthlyEarnings = earningsData['monthlyEarnings'] ?? 0.0;
        _totalEarnings = earningsData['totalEarnings'] ?? 0.0;
        _monthlyChartData = List<double>.from(earningsData['monthlyChartData'] ?? [0, 0, 0, 0, 0, 0]);
      });
    }

    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Dashboard refreshed!"), 
          backgroundColor: Color(0xFFFFD60A), 
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      // Widget disposed, ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 80,
        title: Row(
          children: [
            Switch(
              value: isOnline,
              onChanged: isLoadingStatus ? null : _toggleVendorStatus,
              activeThumbColor: const Color(0xFFFFD60A),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFF1E1E1E),
            ),
            const SizedBox(width: 8),
            Text(isOnline ? "ON" : "OFF", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
          ],
        ),
        actions: [
          _iconButton(Icons.notifications_outlined, _navigateToNotifications),
          _iconButton(Icons.chat_bubble_outline, _navigateToMessages),
          _iconButton(Icons.person_outline, _navigateToProfile),
          const SizedBox(width: 16),
        ],
      ),

      body: RefreshIndicator(
        color: const Color(0xFFFFD60A),
        backgroundColor: const Color(0xFF1E1E1E),
        strokeWidth: 3,
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================== WALLET BALANCE ====================
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Wallet Balance", style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                        Text(
                          _isLoadingWallet ? "Loading..." : "NPR ${_formatBalance(_walletData?['balance'])}",
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: _navigateToWallet,
                      icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFFFFD60A)),
                      label: const Text("View Wallet", style: TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ==================== PROMOTIONAL BANNERS ====================
              Text("Promotional Banners", style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                child: _isLoadingSliders
                    ? _buildSliderPlaceholder()
                    : _sliders.isEmpty
                        ? Center(child: Text('No banners available', style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 14)))
                        : PageView.builder(
                            controller: _sliderController,
                            itemBuilder: (context, index) {
                              final slider = _sliders[index % _sliders.length];
                              return Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _buildSliderCard(slider));
                            },
                          ),
              ),
              const SizedBox(height: 24),

              // ==================== EARNINGS ====================
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Earnings", style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        ToggleButtons(
                          borderRadius: BorderRadius.circular(8),
                          selectedColor: Colors.black,
                          fillColor: const Color(0xFFFFD60A),
                          color: Colors.grey,
                          constraints: const BoxConstraints(minHeight: 32, minWidth: 70),
                          isSelected: [earningsPeriod == 'Today', earningsPeriod == 'Month'],
                          onPressed: (i) => setState(() => earningsPeriod = i == 0 ? 'Today' : 'Month'),
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Today")),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Month")),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Today's / Monthly + Total Earnings
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "NPR ${earningsPeriod == 'Today' ? _todaysEarnings.toStringAsFixed(2) : _monthlyEarnings.toStringAsFixed(2)}",
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                earningsPeriod == 'Today' ? "Today's Earnings" : "This Month",
                                style: TextStyle(color: Colors.grey[400], fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "NPR ${_totalEarnings.toStringAsFixed(2)}",
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
                              ),
                              Text("Total Earnings", style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Monthly Bar Chart
                    if (!_isLoadingOrders)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (i) {
                          final value = _monthlyChartData[i];
                          final max = _monthlyChartData.reduce((a, b) => a > b ? a : b) == 0 ? 1 : _monthlyChartData.reduce((a, b) => a > b ? a : b);
                          final height = value == 0 ? 4.0 : (value / max) * 40.0;
                          final isCurrent = i == 5;
                          return Container(
                            width: 12,
                            height: 40,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 10,
                              height: height,
                              decoration: BoxDecoration(
                                color: isCurrent ? const Color(0xFF4CAF50) : value > 0 ? const Color(0xFF2196F3) : Colors.grey[700],
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          );
                        }),
                      ),

                    const SizedBox(height: 16),

                    // View Transactions
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _navigateToEarnings,
                        icon: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFFFD60A)),
                        label: const Text("View Transactions", style: TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ==================== RECENT ORDERS ====================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Recent Orders", style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  GestureDetector(
                    onTap: _navigateToOrders,
                    child: const Text("View All", style: TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Recent Orders List
              Consumer<DataPreloaderService>(
                builder: (context, preloader, child) {
                  final recentOrders = preloader.recentOrders;
                  
                  if (recentOrders == null || recentOrders.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
                      child: Center(
                        child: Text('No recent orders', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                      ),
                    );
                  }
                  
                  return Column(
                    children: recentOrders.take(3).map((order) => _buildOrderItem(order)).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),

              // ==================== YOUR PRODUCTS ====================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Your Products", style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  GestureDetector(onTap: _navigateToProducts, child: const Text("Manage", style: TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.bold))),
                ],
              ),
              const SizedBox(height: 12),
              _buildProductsSection(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsSection() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: const Color(0xFFFFD60A),
            unselectedLabelColor: Colors.grey,
            indicator: const UnderlineTabIndicator(borderSide: BorderSide(color: Color(0xFFFFD60A), width: 3)),
            onTap: (index) {
              setState(() {
                _selectedProductTab = ['featured', 'bestselling'][index];
              });
            },
            tabs: const [
              Tab(text: "Featured"),
              Tab(text: "Best Selling"),
            ],
          ),
          const SizedBox(height: 16),
          _isLoadingProducts
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD60A)))
              : _buildProductGrid(),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    List<Map<String, dynamic>> filteredProducts = [];
    
    switch (_selectedProductTab) {
      case 'featured':
        filteredProducts = _products.where((p) => p['featured'] == true).toList();
        break;
      case 'bestselling':
        filteredProducts = _products.where((p) => (p['total_sold'] ?? 0) > 0).toList();
        filteredProducts.sort((a, b) => (b['total_sold'] ?? 0).compareTo(a['total_sold'] ?? 0));
        break;
    }
    
    if (filteredProducts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No $_selectedProductTab products found',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ),
      );
    }
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: filteredProducts.length > 4 ? 4 : filteredProducts.length,
      itemBuilder: (context, index) {
        final product = filteredProducts[index];
        return _buildProductCard(product);
      },
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final name = product['name'] ?? 'Product';
    final price = product['price'] ?? '0.00';
    final imageUrl = product['images']?.isNotEmpty == true 
        ? product['images'][0]['image_url'] 
        : 'https://via.placeholder.com/150';
    final totalSold = product['total_sold'] ?? 0;
    final isFeatured = product['featured'] == true;
    final freeDelivery = product['free_delivery'] == true;
    final customDeliveryFee = product['custom_delivery_fee'];
    final hasCustomDelivery = product['custom_delivery_fee_enabled'] == true;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SafeNetworkImage(
                  imageUrl: imageUrl,
                  height: 80,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: Container(
                    height: 80,
                    width: double.infinity,
                    color: Colors.white10,
                    child: const Icon(Icons.image, color: Colors.white24, size: 24),
                  ),
                ),
              ),
              if (isFeatured)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD60A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Featured',
                      style: TextStyle(color: Colors.black, fontSize: 7, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              if (totalSold > 0)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$totalSold sold',
                      style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            'NPR $price',
            style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: freeDelivery ? Colors.green.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              freeDelivery 
                  ? 'Free Delivery' 
                  : hasCustomDelivery 
                      ? 'NPR $customDeliveryFee' 
                      : 'Delivery Fee',
              style: TextStyle(
                color: freeDelivery ? Colors.green : Colors.blue,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HELPER METHODS ====================
  String _formatBalance(dynamic balance) {
    if (balance == null) return '0.00';
    if (balance is String) {
      final parsed = double.tryParse(balance);
      return parsed?.toStringAsFixed(2) ?? '0.00';
    }
    if (balance is num) {
      return balance.toStringAsFixed(2);
    }
    return '0.00';
  }

  // ==================== HELPER WIDGETS ====================
  Widget _iconButton(IconData icon, VoidCallback onPressed) => IconButton(onPressed: onPressed, icon: Icon(icon, color: Colors.grey[400], size: 26));

  Widget _buildOrderItem(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    final isCompleted = status == 'delivered' || status == 'completed';
    final itemCount = (order['items'] as List?)?.length ?? 0;
    final amount = double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0.0;
    final customerName = order['customer_details']?['username'] ?? order['delivery_name'] ?? 'Customer';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isCompleted ? Icons.check_circle : Icons.access_time,
              color: isCompleted ? Colors.green : Colors.orange,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order['order_number'] ?? 'Order',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  '$itemCount items • NPR ${amount.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                Text(
                  customerName,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: isCompleted ? Colors.green : Colors.orange,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productCard(String name, String price, String img) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RepaintBoundary(
            child: Container(
              height: 96,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(img), fit: BoxFit.cover)),
            ),
          ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(price, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ]),
      );

  Widget _buildSliderCard(Map<String, dynamic> slider) {
    final imageUrl = slider['image_url'] as String?;
    final title = slider['title'] as String? ?? '';
    final description = slider['description'] as String? ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeNetworkImage(
             imageUrl: imageUrl ?? '',
             fit: BoxFit.cover,
             errorWidget: Container(color: Colors.grey[800]),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.7)]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (title.isNotEmpty) Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                if (description.isNotEmpty) ...[const SizedBox(height: 4), Text(description, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.grey[400]))],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderPlaceholder() => PageView.builder(
        controller: _sliderController,
        itemCount: 3,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF27272A)), child: const Center(child: Icon(Icons.image, color: Color(0xFFA1A1AA), size: 40))),
        ),
      );
}