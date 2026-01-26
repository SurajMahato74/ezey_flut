// lib/screens/vendor_orders_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../services/data_preloader_service.dart';
import '../services/auth_service.dart';
import '../config.dart' as appConfig;
import '../widgets/vendor_proof_upload_dialog.dart';
import '../widgets/safe_network_image.dart';
import 'location_map_screen.dart';

class VendorOrdersScreen extends StatefulWidget {
  const VendorOrdersScreen({super.key});

  @override
  State<VendorOrdersScreen> createState() => _VendorOrdersScreenState();
}

class _VendorOrdersScreenState extends State<VendorOrdersScreen> with TickerProviderStateMixin {
  String activeTab = 'all';
  List<Map<String, dynamic>> orders = [];
  bool isLoading = true;
  late TabController _tabController;
  
  // Pagination variables
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  int _currentPage = 1;
  final int _pageSize = 10;
  
  // Debounce timer for button clicks
  Timer? _debounceTimer;
  
  // Auto refresh timer
  Timer? _autoRefreshTimer;
  String? _lastOrderHash;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _scrollController.addListener(_onScroll);
    _startAutoRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrdersData();
    });
  }
  
  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _syncOrdersImmediately();
      }
    });
  }
  
  String _generateOrderHash(List<Map<String, dynamic>> orders) {
    final orderData = orders.map((order) {
      final id = order['id'];
      final status = order['status'];
      final reviewData = order['review'];
      final reviewHash = reviewData != null ? 
        '${reviewData['overall_rating']}_${reviewData['review_text']}_${reviewData['created_at']}' : 'no_review';
      final refundData = order['refunds'] as List?;
      final refundHash = refundData?.isNotEmpty == true ? 
        refundData!.map((r) => '${r['id']}_${r['status']}_${r['requested_at']}_${r['approved_at']}_${r['processed_at']}_${r['evidence_photos']?.length ?? 0}_${r['vendor_supporting_docs']?.length ?? 0}').join('|') : 'no_refund';
      final returnData = order['returns'] as List?;
      final returnHash = returnData?.isNotEmpty == true ? 
        returnData!.map((r) => '${r['id']}_${r['status']}_${r['requested_at']}_${r['approved_at']}_${r['processed_at']}').join('|') : 'no_return';
      return '$id:$status:$reviewHash:$refundHash:$returnHash';
    }).join(',');
    return '${orders.length}:$orderData';
  }
  
  Future<void> _syncOrdersImmediately() async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token != null) {
        print('SYNC: Checking for updates...');
        final response = await http.get(
          Uri.parse('${appConfig.Config.baseUrl}/vendor/orders/?page=1&page_size=20&_t=${DateTime.now().millisecondsSinceEpoch}'),
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
            'Cache-Control': 'no-cache',
          },
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List freshOrders = [];
          
          if (data is Map<String, dynamic>) {
            freshOrders = data['results'] ?? data['data'] ?? [];
          } else if (data is List) {
            freshOrders = data;
          }
          
          final freshOrdersList = freshOrders.cast<Map<String, dynamic>>();
          
          // Log first order details for debugging
          if (freshOrdersList.isNotEmpty) {
            final firstOrder = freshOrdersList[0];
            print('SYNC: First order - ID: ${firstOrder['id']}, Status: ${firstOrder['status']}, Review: ${firstOrder['review'] != null}');
          }
          
          final newHash = _generateOrderHash(freshOrdersList);
          
          print('SYNC: Orders count: ${freshOrdersList.length}');
          print('SYNC: Old hash length: ${_lastOrderHash?.length ?? 0}');
          print('SYNC: New hash length: ${newHash.length}');
          
          // Force update every 5th sync to ensure freshness
          bool forceUpdate = DateTime.now().second % 50 == 0;
          
          if (_lastOrderHash == null || _lastOrderHash != newHash || forceUpdate) {
            print('SYNC: ${forceUpdate ? 'Force updating' : 'Changes detected'}, updating UI');
            if (mounted) {
              setState(() {
                orders = freshOrdersList;
                _currentPage = 1;
                _hasMoreData = freshOrdersList.length == 20;
              });
            }
          } else {
            print('SYNC: No changes detected');
          }
          _lastOrderHash = newHash;
        } else {
          print('SYNC: API error ${response.statusCode}');
        }
      }
    } catch (e) {
      print('SYNC: Error - $e');
    }
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMoreOrders();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadOrdersData() async {
    if (mounted) {
      setState(() {
        _currentPage = 1;
        _hasMoreData = true;
        orders.clear();
      });
    }
    
    // Skip cache and fetch fresh data directly
    await _fetchFreshData();
  }
  
  Future<void> _refreshDataInBackground() async {
    try {
      await _fetchFreshData(showLoading: false);
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    }
  }

  Future<void> _fetchFreshData({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => isLoading = true);
    
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/vendor/orders/?page=$_currentPage&page_size=$_pageSize'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List ordersList = [];
        
        if (data is Map<String, dynamic>) {
          ordersList = data['results'] ?? data['data'] ?? [];
        } else if (data is List) {
          ordersList = data;
        }

        if (mounted) {
          setState(() {
            if (_currentPage == 1) {
              orders = ordersList.cast<Map<String, dynamic>>();
              _lastOrderHash = _generateOrderHash(orders);
            } else {
              orders.addAll(ordersList.cast<Map<String, dynamic>>());
            }
            _hasMoreData = ordersList.length == _pageSize;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading orders: $e');
    } finally {
      if (showLoading && mounted) setState(() => isLoading = false);
    }
  }
  
  Future<void> _loadMoreOrders() async {
    if (_isLoadingMore || !_hasMoreData) return;
    
    if (mounted) setState(() => _isLoadingMore = true);
    
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token == null) return;
      
      _currentPage++;
      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/vendor/orders/?page=$_currentPage&page_size=$_pageSize'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List ordersList = [];
        
        if (data is Map<String, dynamic>) {
          ordersList = data['results'] ?? data['data'] ?? [];
        } else if (data is List) {
          ordersList = data;
        }

        if (mounted) {
          setState(() {
            orders.addAll(ordersList.cast<Map<String, dynamic>>());
            _hasMoreData = ordersList.length == _pageSize;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading more orders: $e');
      _currentPage--;
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.blue;
      case 'confirmed':
        return Colors.orange;
      case 'out_for_delivery':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.access_time;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'out_for_delivery':
        return Icons.local_shipping;
      case 'delivered':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.receipt;
    }
  }

  void _showCallOptions(BuildContext context, String phoneNumber) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Call Customer',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.phone, color: Colors.green),
              title: const Text('Device Call', style: TextStyle(color: Colors.white)),
              subtitle: Text(phoneNumber, style: TextStyle(color: Colors.grey[400])),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Calling $phoneNumber...')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_call, color: Colors.blue),
              title: const Text('Online Call', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Coming Soon', style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Online call feature coming soon')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  void _showMessageDialog(BuildContext context, String phoneNumber, String orderNumber) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Send Message', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Send message to customer about order $orderNumber', 
                 style: TextStyle(color: Colors.grey[300])),
            const SizedBox(height: 16),
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type your message...',
                hintStyle: TextStyle(color: Colors.grey[500]),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFFD60A)),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Message sent successfully')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD60A)),
            child: const Text('Send', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
  
  void _showLocationOnMap(BuildContext context, Map<String, dynamic> order) {
    final lat = order['delivery_latitude'];
    final lng = order['delivery_longitude'];
    
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location coordinates not available')),
      );
      return;
    }
    
    // Store navigator and context before any async operations
    final navigator = Navigator.of(context);
    
    // Get vendor shop location from order data
    double? vendorShopLat = order['vendor_details']?['latitude']?.toDouble();
    double? vendorShopLng = order['vendor_details']?['longitude']?.toDouble();
    
    // Navigate immediately using stored navigator
    navigator.push(
      MaterialPageRoute(
        builder: (context) => LocationMapScreen(
          latitude: double.tryParse(lat.toString()) ?? 0.0,
          longitude: double.tryParse(lng.toString()) ?? 0.0,
          address: order['delivery_address'] ?? 'Delivery Location',
          vendorShopLatitude: vendorShopLat,
          vendorShopLongitude: vendorShopLng,
          vendorCurrentLatitude: null,
          vendorCurrentLongitude: null,
        ),
      ),
    );
  }

  void _showLocationDistance(BuildContext context, Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delivery Distance', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.store, color: Color(0xFFFFD60A)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'From: ${order['vendor_details']?['location_address'] ?? 'Vendor Location'}',
                    style: TextStyle(color: Colors.grey[300], fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'To: ${order['delivery_address']}',
                    style: TextStyle(color: Colors.grey[300], fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD60A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Estimated Distance: ${(order['delivery_distance'] ?? 0.0).toStringAsFixed(1)} km',
                style: const TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFFFFD60A))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showLocationOnMap(context, order);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD60A),
              foregroundColor: Colors.black,
            ),
            child: const Text('View on Map'),
          ),
        ],
      ),
    );
  }
  
  void _showShippingDialog(BuildContext context, Map<String, dynamic> order) {
    final TextEditingController deliveryBoyController = TextEditingController();
    final TextEditingController vehicleNumberController = TextEditingController();
    final TextEditingController vehicleColorController = TextEditingController();
    final TextEditingController deliveryTimeController = TextEditingController();
    final TextEditingController deliveryFeeController = TextEditingController();
    
    // Determine delivery fee logic from order items
    bool isDeliveryFeeReadonly = false;
    String deliveryFeeSource = '';
    
    final items = order['items'] as List? ?? [];
    
    // Check for free delivery
    final hasFreeDelivery = items.any((item) => 
        item['product_details']?['free_delivery'] == true);
    
    // Check for custom delivery fee
    final hasCustomFee = items.any((item) =>
        item['product_details']?['custom_delivery_fee_enabled'] == true &&
        item['product_details']?['custom_delivery_fee'] != null);
    
    if (hasFreeDelivery) {
      // Free delivery - readonly, set to 0
      isDeliveryFeeReadonly = true;
      deliveryFeeController.text = '0';
      deliveryFeeSource = 'Free delivery';
    } else if (hasCustomFee) {
      // Custom delivery fee - editable, pre-filled with custom fee
      final customFeeItem = items.firstWhere((item) =>
          item['product_details']?['custom_delivery_fee_enabled'] == true &&
          item['product_details']?['custom_delivery_fee'] != null);
      final customFee = customFeeItem['product_details']['custom_delivery_fee'] ?? 0;
      isDeliveryFeeReadonly = false;
      deliveryFeeController.text = customFee.toString();
      deliveryFeeSource = 'Custom fee: NPR $customFee';
    } else {
      // To be determined - user input required
      isDeliveryFeeReadonly = false;
      deliveryFeeController.text = '';
      deliveryFeeSource = 'Enter delivery fee';
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, color: Color(0xFFFFD60A)),
                const SizedBox(width: 8),
                Text(
                  'Ship Order - ${order['order_number']}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            _buildTextField('Delivery Boy Phone', deliveryBoyController, 'Enter delivery boy phone number'),
            const SizedBox(height: 12),
            _buildTextField('Vehicle Number', vehicleNumberController, 'Enter vehicle number'),
            const SizedBox(height: 12),
            _buildTextField('Vehicle Color', vehicleColorController, 'Enter vehicle color'),
            const SizedBox(height: 12),
            _buildTextField('Estimated Delivery Time (hours)', deliveryTimeController, 'Enter hours (e.g., 2)', isNumber: true),
            const SizedBox(height: 12),
            _buildDeliveryFeeField(deliveryFeeController, deliveryFeeSource, isDeliveryFeeReadonly),
            
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.grey),
                      foregroundColor: Colors.grey,
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _shipOrder(context, order, {
                      'delivery_boy_phone': deliveryBoyController.text,
                      'vehicle_number': vehicleNumberController.text,
                      'vehicle_color': vehicleColorController.text,
                      'estimated_delivery_time': deliveryTimeController.text,
                      'delivery_fee': deliveryFeeController.text,
                    }),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD60A)),
                    child: const Text('Confirm & Ship', style: TextStyle(color: Colors.black)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      ),
    );
  }
  
  Widget _buildDeliveryFeeField(TextEditingController controller, String source, bool isReadonly) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Delivery Fee', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          enabled: !isReadonly,
          style: TextStyle(
            color: isReadonly ? Colors.grey[400] : Colors.white,
          ),
          decoration: InputDecoration(
            hintText: isReadonly ? source : 'Enter delivery fee',
            hintStyle: TextStyle(color: Colors.grey[500]),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[600]!),
              borderRadius: BorderRadius.circular(8),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[600]!),
              borderRadius: BorderRadius.circular(8),
            ),
            disabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[700]!),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFFFFD60A)),
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: isReadonly ? Colors.grey[800] : const Color(0xFF1E1E1E),
          ),
        ),
        if (source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              source,
              style: TextStyle(
                color: isReadonly ? Colors.green[400] : Colors.grey[400],
                fontSize: 12,
                fontWeight: isReadonly ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildTextField(String label, TextEditingController controller, String hint, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[500]),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[600]!),
              borderRadius: BorderRadius.circular(8),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[600]!),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFFFFD60A)),
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
          ),
        ),
      ],
    );
  }
  
  Color _getRefundStatusColor(String status) {
    switch (status) {
      case 'requested':
        return Colors.orange;
      case 'approved':
        return Colors.blue;
      case 'processed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusMessage(String status, Map<String, dynamic> refund) {
    switch (status) {
      case 'approved':
        return 'Approved: Return approved. Now process the refund payment.';
      case 'processed':
        return 'Processed: Refund payment has been transferred to customer.';
      case 'rejected':
        return 'Rejected: ${refund['admin_notes'] ?? 'Return request rejected'}';
      case 'requested':
        return 'Note: Customer has provided payment details. Approve to process the refund or reject the return request.';
      default:
        return refund['admin_notes'] ?? '';
    }
  }

  Future<void> _approveRefund(int refundId) async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token == null) return;
      
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/vendor/refunds/$refundId/approve/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'status': 'approved',
          'admin_notes': 'Return request approved by vendor'
        }),
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund approved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchFreshData();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectRefund(int refundId) async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token == null) return;
      
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/vendor/refunds/$refundId/reject/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'status': 'rejected',
          'admin_notes': 'Return request rejected by vendor'
        }),
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund rejected'),
            backgroundColor: Colors.orange,
          ),
        );
        _fetchFreshData();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markRefundAsProcessed(int refundId) async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token == null) return;
      
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/vendor/refunds/$refundId/process/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'status': 'processed',
          'admin_notes': 'Refund payment processed by vendor'
        }),
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund marked as processed'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchFreshData();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markAsDelivered(BuildContext context, Map<String, dynamic> order) async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token == null) return;
      
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/vendor/orders/${order['id']}/update-status/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'status': 'delivered'}),
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order marked as delivered'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchFreshData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update order status'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shipOrder(BuildContext context, Map<String, dynamic> order, Map<String, String> shippingData) async {
    if (shippingData['delivery_boy_phone']!.isEmpty || 
        shippingData['vehicle_number']!.isEmpty || 
        shippingData['vehicle_color']!.isEmpty || 
        shippingData['estimated_delivery_time']!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }
    
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token == null) return;
      
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/vendor/orders/${order['id']}/ship/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'status': 'out_for_delivery',
          'delivery_boy_phone': shippingData['delivery_boy_phone'],
          'vehicle_number': shippingData['vehicle_number'],
          'vehicle_color': shippingData['vehicle_color'],
          'estimated_delivery_time': int.tryParse(shippingData['estimated_delivery_time']!) ?? 2,
          'delivery_fee': double.tryParse(shippingData['delivery_fee']!) ?? 0.0,
        }),
      );
      
      if (response.statusCode == 200) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order shipped successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchFreshData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to ship order'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5, // Show 5 skeleton cards
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order number and status row
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 60,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Item count
            Container(
              height: 14,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            
            // Product items row
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 3,
                itemBuilder: (context, itemIndex) => Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 120,
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 8,
                              width: 40,
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Customer info
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Location info
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Date info
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 12,
                  width: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Actions row
            Row(
              children: [
                Container(
                  width: 80,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 40,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 40,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text('Orders', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(
            onPressed: () => _fetchFreshData(),
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFFD60A),
        backgroundColor: const Color(0xFF1E1E1E),
        onRefresh: () => _fetchFreshData(),
        child: Column(
          children: [
            Container(
              color: const Color(0xFF1E1E1E),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: const Color(0xFFFFD60A),
                unselectedLabelColor: Colors.grey,
                indicatorColor: const Color(0xFFFFD60A),
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
                onTap: (index) {
                  setState(() {
                    activeTab = ['all', 'confirmed', 'shipped', 'delivered', 'cancelled', 'returns'][index];
                  });
                },
                tabs: [
                  Tab(text: 'All (${orders.length})'),
                  Tab(text: 'Confirmed (${orders.where((o) => o['status'] == 'confirmed').length})'),
                  Tab(text: 'Shipped (${orders.where((o) => o['status'] == 'out_for_delivery').length})'),
                  Tab(text: 'Delivered (${orders.where((o) => o['status'] == 'delivered').length})'),
                  Tab(text: 'Cancelled (${orders.where((o) => o['status'] == 'cancelled').length})'),
                  Tab(text: 'Returns (${orders.where((o) => (o['refunds'] as List?)?.isNotEmpty == true).length})'),
                ],
              ),
            ),
            
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  isLoading ? _buildSkeletonLoader() : _buildOrdersList(orders),
                  isLoading ? _buildSkeletonLoader() : _buildOrdersList(orders.where((o) => o['status'] == 'confirmed').toList()),
                  isLoading ? _buildSkeletonLoader() : _buildOrdersList(orders.where((o) => o['status'] == 'out_for_delivery').toList()),
                  isLoading ? _buildSkeletonLoader() : _buildOrdersList(orders.where((o) => o['status'] == 'delivered').toList()),
                  isLoading ? _buildSkeletonLoader() : _buildOrdersList(orders.where((o) => o['status'] == 'cancelled').toList()),
                  isLoading ? _buildSkeletonLoader() : _buildOrdersList(orders.where((o) => (o['refunds'] as List?)?.isNotEmpty == true).toList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> ordersList) {
    if (ordersList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text('No orders found', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: ordersList.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == ordersList.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD60A)),
            ),
          );
        }
        
        final order = ordersList[index];
        return _buildOrderItem(order);
      },
    );
  }
  
  Widget _buildOrderItem(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    final itemCount = (order['items'] as List?)?.length ?? 0;
    final amount = double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0.0;
    final customerName = order['customer_details']?['username'] ?? order['delivery_name'] ?? 'Customer';
    final orderNumber = order['order_number'] ?? 'N/A';
    final customerPhone = order['delivery_phone'] ?? order['customer_details']?['phone_number'] ?? '';
    final hasRefunds = (order['refunds'] as List?)?.isNotEmpty == true;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: status == 'pending' ? Border.all(color: Colors.blue.withOpacity(0.5)) : 
               hasRefunds ? Border.all(color: Colors.orange.withOpacity(0.5)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  orderNumber,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (order['review'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD60A).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 10, color: Color(0xFFFFD60A)),
                          const SizedBox(width: 1),
                          Text(
                            '${order['review']['overall_rating']}',
                            style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  if (hasRefunds)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Return',
                        style: TextStyle(color: Colors.orange, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(getStatusIcon(status), size: 12, color: getStatusColor(status)),
                        const SizedBox(width: 3),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(color: getStatusColor(status), fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasRefunds) _buildReturnInfo(order['refunds'][0]),
          if (order['review'] != null) _buildReviewInfo(order['review']),
          if (itemCount > 0) ..._buildOrderItems(order),
          _buildCustomerInfo(customerName, customerPhone, orderNumber),
          const SizedBox(height: 8),
          _buildLocationInfo(order),
          const SizedBox(height: 8),
          _buildDateInfo(order),
          const SizedBox(height: 12),
          _buildActionsRow(order, status, amount),
        ],
      ),
    );
  }
  
  Widget _buildReturnInfo(Map<String, dynamic> refund) {
    final status = refund['status'] ?? 'requested';
    
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assignment_return, color: Colors.orange, size: 16),
              SizedBox(width: 8),
              Text(
                'Return Reason:',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            refund['reason'] ?? 'No reason provided',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (refund['customer_notes'] != null) ...[
            const SizedBox(height: 4),
            Text(
              '"${refund['customer_notes']}"',
              style: TextStyle(color: Colors.grey[300], fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getRefundStatusColor(status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: _getRefundStatusColor(status),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Amount: Rs ${refund['requested_amount'] ?? '0.00'}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                '${refund['refund_method']?.toUpperCase() ?? 'N/A'}',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
          if (refund['esewa_number'] != null || refund['khalti_number'] != null || refund['bank_account_number'] != null) ...[
            const SizedBox(height: 4),
            Text(
              refund['esewa_number'] != null ? 'eSewa: ${refund['esewa_number']}' : refund['khalti_number'] != null ? 'Khalti: ${refund['khalti_number']}' : 'Bank: ${refund['bank_account_number']}',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
          if (refund['evidence_photos'] != null && (refund['evidence_photos'] as List).isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Customer Evidence:', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: (refund['evidence_photos'] as List).length,
                itemBuilder: (context, index) {
                  final photo = (refund['evidence_photos'] as List)[index];
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SafeNetworkImage(
                        imageUrl: photo['file_url'] ?? '',
                        fit: BoxFit.cover,
                        errorWidget: const Icon(Icons.image, color: Colors.grey, size: 20),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (refund['vendor_supporting_docs'] != null && (refund['vendor_supporting_docs'] as List).isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Vendor Proof:', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: (refund['vendor_supporting_docs'] as List).length,
                itemBuilder: (context, index) {
                  final doc = (refund['vendor_supporting_docs'] as List)[index];
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SafeNetworkImage(
                        imageUrl: doc['file_url'] ?? '',
                        fit: BoxFit.cover,
                        errorWidget: const Icon(Icons.image, color: Colors.grey, size: 20),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (status == 'approved' && (refund['esewa_number'] != null || refund['khalti_number'] != null || refund['bank_account_number'] != null)) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Customer Payment Details:',
                    style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  if (refund['esewa_number'] != null)
                    Text(
                      'eSewa: ${refund['esewa_number']}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  if (refund['khalti_number'] != null)
                    Text(
                      'Khalti: ${refund['khalti_number']}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  if (refund['bank_account_number'] != null) ...[
                    Text(
                      'Bank: ${refund['bank_account_name'] ?? 'N/A'}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    Text(
                      'Account: ${refund['bank_account_number']}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    if (refund['bank_branch'] != null)
                      Text(
                        'Branch: ${refund['bank_branch']}',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => VendorProofUploadDialog(
                  refund: refund,
                  onProofUploaded: () => _fetchFreshData(),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text('Upload Proof & Process', style: TextStyle(fontSize: 10)),
            ),
          ],
          if (status == 'requested') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _approveRefund(refund['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    child: const Text('Approve', style: TextStyle(fontSize: 10)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _rejectRefund(refund['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    child: const Text('Reject', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
          ],
          if (refund['admin_notes'] != null) ...[
            const SizedBox(height: 6),
            Text(
              _getStatusMessage(status, refund),
              style: TextStyle(color: Colors.grey[300], fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildOrderItems(Map<String, dynamic> order) {
    final itemCount = (order['items'] as List?)?.length ?? 0;
    return [
      Text('$itemCount item${itemCount > 1 ? 's' : ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 8),
      SizedBox(
        height: 60,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: (order['items'] as List).length,
          itemBuilder: (context, index) {
            final item = (order['items'] as List)[index];
            final productImage = item['product_details']?['images']?.isNotEmpty == true ? item['product_details']['images'][0]['image_url'] : null;
            return Container(
              margin: const EdgeInsets.only(right: 8),
              width: 120,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(6)),
                    child: productImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SafeNetworkImage(imageUrl: productImage, fit: BoxFit.cover, errorWidget: const Icon(Icons.inventory, color: Colors.grey, size: 16)),
                          )
                        : const Icon(Icons.inventory, color: Colors.grey, size: 16),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item['product_name'] ?? 'Product',
                          style: TextStyle(color: Colors.grey[300], fontSize: 9),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Qty: ${item['quantity'] ?? 1}',
                          style: TextStyle(color: Colors.grey[400], fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
    ];
  }
  
  Widget _buildCustomerInfo(String customerName, String customerPhone, String orderNumber) {
    return Row(
      children: [
        const Icon(Icons.person, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(customerName, style: TextStyle(color: Colors.grey[300], fontSize: 14))),
        if (customerPhone.isNotEmpty) ..._buildCallMessageButtons(customerPhone, orderNumber),
      ],
    );
  }
  
  List<Widget> _buildCallMessageButtons(String customerPhone, String orderNumber) {
    return [
      GestureDetector(
        onTap: () => _showCallOptions(context, customerPhone),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.call, size: 16, color: Colors.green),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => _showMessageDialog(context, customerPhone, orderNumber),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.message, size: 16, color: Colors.blue),
        ),
      ),
    ];
  }
  
  Widget _buildLocationInfo(Map<String, dynamic> order) {
    return Row(
      children: [
        const Icon(Icons.location_on, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(order['delivery_address'] ?? 'Address not provided', style: TextStyle(color: Colors.grey[300], fontSize: 14))),
        if (order['delivery_latitude'] != null && order['delivery_longitude'] != null)
          GestureDetector(
            onTap: () => _showLocationDistance(context, order),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFFFD60A).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Text('View Distance', style: TextStyle(color: Color(0xFFFFD60A), fontSize: 10)),
            ),
          ),
      ],
    );
  }
  
  Widget _buildDateInfo(Map<String, dynamic> order) {
    return Row(
      children: [
        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(formatDate(order['created_at']), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      ],
    );
  }
  
  Widget _buildActionsRow(Map<String, dynamic> order, String status, double amount) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text('NPR ${amount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _showOrderDetails(order),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFFD60A)),
              foregroundColor: const Color(0xFFFFD60A),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              minimumSize: const Size(40, 24),
            ),
            child: const Text('Details', style: TextStyle(fontSize: 8)),
          ),
          const SizedBox(width: 4),
          if (status == 'confirmed')
            ElevatedButton(
              onPressed: () => _showShippingDialog(context, order),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                minimumSize: const Size(30, 24),
              ),
              child: const Text('Ship', style: TextStyle(fontSize: 8)),
            )
          else if (status == 'out_for_delivery')
            ElevatedButton(
              onPressed: () => _markAsDelivered(context, order),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                minimumSize: const Size(35, 24),
              ),
              child: const Text('Delivered', style: TextStyle(fontSize: 7)),
            ),
        ],
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['order_number'] ?? 'Order',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: getStatusColor(order['status'] ?? 'pending').withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            (order['status'] ?? 'pending').toUpperCase(),
                            style: TextStyle(
                              color: getStatusColor(order['status'] ?? 'pending'),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'NPR ${double.tryParse(order['total_amount']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFFFD60A),
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailCard(
                      'Customer Information',
                      Icons.person,
                      [
                        _buildDetailRow('Name', order['customer_details']?['username'] ?? order['delivery_name'] ?? 'N/A'),
                        _buildDetailRow('Phone', order['delivery_phone'] ?? order['customer_details']?['phone_number'] ?? 'N/A'),
                        _buildDetailRow('Address', order['delivery_address'] ?? 'N/A'),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    _buildItemsCard(order['items'] as List? ?? []),
                    
                    const SizedBox(height: 16),
                    
                    _buildDetailCard(
                      'Payment Details',
                      Icons.payment,
                      [
                        _buildDetailRow('Subtotal', 'NPR ${order['subtotal'] ?? '0.00'}'),
                        _buildDetailRow('Delivery Fee', 'NPR ${order['delivery_fee'] ?? '0.00'}'),
                        _buildDetailRow('Total', 'NPR ${order['total_amount'] ?? '0.00'}', isHighlighted: true),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    _buildDetailCard(
                      'Order Timeline',
                      Icons.schedule,
                      [
                        _buildDetailRow('Ordered', '${formatDate(order['created_at'])} at ${_formatTime(order['created_at'])}'),
                        if (order['confirmed_at'] != null)
                          _buildDetailRow('Confirmed', formatDate(order['confirmed_at'])),
                        if (order['out_for_delivery_at'] != null)
                          _buildDetailRow('Shipped', formatDate(order['out_for_delivery_at'])),
                        if (order['delivered_at'] != null)
                          _buildDetailRow('Delivered', formatDate(order['delivered_at'])),
                        _buildDetailRow('Status', (order['status'] ?? 'pending').toUpperCase(), isHighlighted: true),
                      ],
                    ),
                    
                    if (order['status'] == 'out_for_delivery' && order['delivery_boy_phone'] != null) ...[
                      const SizedBox(height: 16),
                      _buildDetailCard(
                        'Shipping Details',
                        Icons.local_shipping,
                        [
                          _buildDetailRow('Delivery Boy', order['delivery_boy_phone'] ?? 'N/A'),
                          _buildDetailRow('Vehicle', '${order['vehicle_number'] ?? 'N/A'} (${order['vehicle_color'] ?? 'N/A'})'),
                          _buildDetailRow('Est. Time', '${order['estimated_delivery_time'] ?? 'N/A'} hours'),
                        ],
                      ),
                    ],
                    
                    if (order['review'] != null) ...[
                      const SizedBox(height: 16),
                      _buildReviewCard(order['review']),
                    ],
                    
                    if ((order['refunds'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      _buildRefundCard(order['refunds']),
                    ],
                    
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatTime(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final hour = date.hour > 12 ? date.hour - 12 : date.hour;
      final period = date.hour >= 12 ? 'PM' : 'AM';
      return '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '';
    }
  }
  
  String formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  Widget _buildDetailCard(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFFFD60A), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isHighlighted ? const Color(0xFFFFD60A) : Colors.white,
                fontSize: 14,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundCard(List refunds) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_return, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Return Requests (${refunds.length})',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...refunds.map((refund) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Amount: Rs ${refund['amount'] ?? '0.00'}',
                      style: const TextStyle(
                        color: Color(0xFFFFD60A),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: refund['status'] == 'processed' ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        (refund['status'] ?? 'pending').toUpperCase(),
                        style: TextStyle(
                          color: refund['status'] == 'processed' ? Colors.green : Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDetailRow('Method', '${refund['refund_method']?.toUpperCase() ?? 'N/A'}'),
                _buildDetailRow('Reason', refund['reason'] ?? 'No reason provided'),
                _buildDetailRow('Requested At', '${formatDate(refund['requested_at'])} at ${_formatTime(refund['requested_at'])}'),
                if (refund['approved_at'] != null)
                  _buildDetailRow('Approved At', '${formatDate(refund['approved_at'])} at ${_formatTime(refund['approved_at'])}'),
                if (refund['processed_at'] != null)
                  _buildDetailRow('Processed At', '${formatDate(refund['processed_at'])} at ${_formatTime(refund['processed_at'])}'),
                if (refund['admin_notes'] != null && refund['admin_notes'].toString().isNotEmpty)
                  _buildDetailRow('Admin Notes', refund['admin_notes']),
                if (refund['customer_notes'] != null && refund['customer_notes'].toString().isNotEmpty)
                  _buildDetailRow('Customer Notes', refund['customer_notes']),
                if (refund['esewa_number'] != null)
                  _buildDetailRow('eSewa Number', refund['esewa_number']),
                if (refund['khalti_number'] != null)
                  _buildDetailRow('Khalti Number', refund['khalti_number']),
                if (refund['bank_account_number'] != null) ...[
                  _buildDetailRow('Bank Account', refund['bank_account_name'] ?? 'N/A'),
                  _buildDetailRow('Account Number', refund['bank_account_number']),
                  if (refund['bank_branch'] != null)
                    _buildDetailRow('Bank Branch', refund['bank_branch']),
                ],
                if (refund['vendor_response'] != null)
                  _buildDetailRow('Response', refund['vendor_response']),
                if (refund['processed_at'] != null)
                  _buildDetailRow('Processed', formatDate(refund['processed_at'])),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final rating = review['overall_rating'] ?? 0;
    final comment = review['review_text'] ?? '';
    final reviewDate = review['created_at'] ?? '';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: Color(0xFFFFD60A), size: 20),
              const SizedBox(width: 8),
              Text(
                'Customer Review',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ...List.generate(5, (index) => Icon(
                index < rating ? Icons.star : Icons.star_border,
                color: const Color(0xFFFFD60A),
                size: 18,
              )),
              const SizedBox(width: 8),
              Text(
                '$rating/5',
                style: const TextStyle(
                  color: Color(0xFFFFD60A),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'By ${review['customer_name']} • ${formatDate(reviewDate)}',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '"$comment"',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewInfo(Map<String, dynamic> review) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD60A).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD60A).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: Color(0xFFFFD60A), size: 16),
              const SizedBox(width: 8),
              Text(
                'Customer Review - ${review['overall_rating']}/5',
                style: const TextStyle(color: Color(0xFFFFD60A), fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          if (review['review_text'] != null && review['review_text'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '"${review['review_text']}"',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'By ${review['customer_name']} • ${formatDate(review['created_at'])}',
            style: TextStyle(color: Colors.grey[400], fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(List items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag, color: Color(0xFFFFD60A), size: 20),
              const SizedBox(width: 8),
              Text(
                'Order Items (${items.length})',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: item['product_details']?['images']?.isNotEmpty == true
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            item['product_details']['images'][0]['image_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.inventory, color: Colors.grey, size: 24);
                            },
                          ),
                        )
                      : const Icon(Icons.inventory, color: Colors.grey, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['product_name'] ?? 'Product',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['product_details']?['category'] ?? 'Category',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Qty: ${item['quantity'] ?? 1}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'NPR ${item['total_price'] ?? '0.00'}',
                  style: const TextStyle(
                    color: Color(0xFFFFD60A),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
