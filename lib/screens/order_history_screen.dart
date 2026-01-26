import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../widgets/unified_bottom_nav.dart';
import '../widgets/review_dialog.dart';
import '../widgets/refund_request_dialog.dart';
import '../services/data_preloader_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../config.dart' as AppConfig;
import 'order_tracking_screen.dart';
import 'notification_screen.dart';
import 'message_inbox_screen.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  String activeTab = 'all';
  List<Map<String, dynamic>> orders = [];
  bool isLoading = false;
  late TabController _tabController;
  
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  int _currentPage = 1;
  final int _pageSize = 10;
  Timer? _orderSyncTimer;
  String? _lastOrderHash;
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrdersData();
    });
    _startOrderSync();
    _fetchNotificationCount();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMoreData) {
      _loadMoreOrders();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _orderSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchNotificationCount() async {
    final token = Provider.of<AuthService>(context, listen: false).token;
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

  void _startOrderSync() {
    _orderSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _syncOrdersImmediately();
    });
  }

  String _generateOrderHash(List<Map<String, dynamic>> orders) {
    final orderData = orders.map((order) {
      final id = order['id'];
      final status = order['status'];
      final refundData = order['refunds'] as List?;
      final refundHash = refundData?.isNotEmpty == true ? 
        refundData!.map((r) => '${r['id']}_${r['status']}_${r['evidence_photos']?.length ?? 0}_${r['vendor_supporting_docs']?.length ?? 0}').join('|') : 'no_refund';
      return '$id:$status:$refundHash';
    }).join(',');
    return '${orders.length}:$orderData';
  }

  Future<void> _syncOrdersImmediately() async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token != null) {
        final response = await http.get(
          Uri.parse('${AppConfig.Config.baseUrl}/orders/?page=1&page_size=20'),
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final freshOrders = List<Map<String, dynamic>>.from(data['results'] ?? []);
          final newHash = _generateOrderHash(freshOrders);
          
          if (_lastOrderHash != null && _lastOrderHash != newHash && mounted) {
            setState(() {
              orders = freshOrders;
              _currentPage = 1;
              _hasMoreData = data['next'] != null;
            });
          }
          _lastOrderHash = newHash;
        }
      }
    } catch (e) {
      // Handle silently
    }
  }

  Future<void> _loadOrdersData() async {
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    final cachedOrders = preloader.customerOrders;
    
    if (cachedOrders != null && cachedOrders.isNotEmpty) {
      if (mounted) {
        setState(() {
          orders = cachedOrders.take(_pageSize).toList();
          _currentPage = 1;
          _hasMoreData = cachedOrders.length > _pageSize;
        });
      }
      _lastOrderHash = _generateOrderHash(cachedOrders.take(_pageSize).toList());
      // Refresh in background to get latest data
      _refreshDataInBackground();
      return;
    }
    
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
        Uri.parse('${AppConfig.Config.baseUrl}/orders/?page=$_currentPage&page_size=$_pageSize'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List ordersList = data['results'] ?? [];

        if (mounted) {
          setState(() {
            if (_currentPage == 1) {
              orders = ordersList.cast<Map<String, dynamic>>();
            } else {
              orders.addAll(ordersList.cast<Map<String, dynamic>>());
            }
            _hasMoreData = data['next'] != null;
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
        Uri.parse('${AppConfig.Config.baseUrl}/orders/?page=$_currentPage&page_size=$_pageSize'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List ordersList = data['results'] ?? [];

        if (mounted) {
          setState(() {
            orders.addAll(ordersList.cast<Map<String, dynamic>>());
            _hasMoreData = data['next'] != null;
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
              'Call Vendor',
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
            Text('Send message to vendor about order $orderNumber', 
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
                  borderSide: BorderSide(color: AppTheme.primaryColor),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('Send', style: TextStyle(color: Colors.black)),
          ),
        ],
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
        centerTitle: true,
        title: Text('My Orders', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
        actions: [
          if (Provider.of<AuthService>(context, listen: false).isLoggedIn)
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
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MessageInboxScreen(title: "Messages", isVendor: false),
              ),
            ),
            child: const Icon(Icons.message_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? _buildLoadingPlaceholder()
          : RefreshIndicator(
              color: AppTheme.primaryColor,
              backgroundColor: const Color(0xFF1E1E1E),
              onRefresh: _fetchFreshData,
              child: Column(
                children: [
                  Container(
                    color: const Color(0xFF1E1E1E),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      labelColor: AppTheme.primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: AppTheme.primaryColor,
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      unselectedLabelStyle: const TextStyle(fontSize: 12),
                      onTap: (index) {
                        setState(() {
                          activeTab = ['all', 'pending', 'confirmed', 'shipped', 'delivered', 'unreviewed', 'returned', 'cancelled'][index];
                        });
                      },
                      tabs: [
                        Tab(text: 'All (${orders.length})'),
                        Tab(text: 'Pending (${orders.where((o) => o['status'] == 'pending').length})'),
                        Tab(text: 'Confirmed (${orders.where((o) => o['status'] == 'confirmed').length})'),
                        Tab(text: 'Shipped (${orders.where((o) => o['status'] == 'out_for_delivery').length})'),
                        Tab(text: 'Delivered (${orders.where((o) => o['status'] == 'delivered').length})'),
                        Tab(text: 'Unreviewed (${orders.where((o) => o['status'] == 'delivered' && o['review'] == null).length})'),
                        Tab(text: 'Returned (${orders.where((o) => (o['refunds'] as List?)?.isNotEmpty == true).length})'),
                        Tab(text: 'Cancelled (${orders.where((o) => o['status'] == 'cancelled').length})'),
                      ],
                    ),
                  ),
                  
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOrdersList(orders),
                        _buildOrdersList(orders.where((o) => o['status'] == 'pending').toList()),
                        _buildOrdersList(orders.where((o) => o['status'] == 'confirmed').toList()),
                        _buildOrdersList(orders.where((o) => o['status'] == 'out_for_delivery').toList()),
                        _buildOrdersList(orders.where((o) => o['status'] == 'delivered').toList()),
                        _buildOrdersList(orders.where((o) => o['status'] == 'delivered' && o['review'] == null).toList()),
                        _buildOrdersList(orders.where((o) => (o['refunds'] as List?)?.isNotEmpty == true).toList()),
                        _buildOrdersList(orders.where((o) => o['status'] == 'cancelled').toList()),
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
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            ),
          );
        }
        
        final order = ordersList[index];
        return _buildOrderItem(order);
      },
    );
  }

  Widget _buildLoadingPlaceholder() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        return _buildSkeletonItem();
      },
    );
  }

  Widget _buildSkeletonItem() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 120,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                width: 80,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 150,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 100,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Container(
                width: 100,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildOrderItem(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    final itemCount = (order['items'] as List?)?.length ?? 0;
    final amount = double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0.0;
    final vendorName = order['vendor_details']?['business_name'] ?? 'Vendor';
    final orderNumber = order['order_number'] ?? 'N/A';
    final vendorPhone = order['vendor_details']?['user_info']?['phone_number'] ?? order['vendor_details']?['business_phone'] ?? '';
    final hasRefunds = (order['refunds'] as List?)?.isNotEmpty == true;
    final refundStatus = hasRefunds ? (order['refunds'] as List).first['status'] : null;
    
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                orderNumber,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(getStatusIcon(status), size: 14, color: getStatusColor(status)),
                        const SizedBox(width: 4),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(color: getStatusColor(status), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  if (hasRefunds) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getRefundStatusColor(refundStatus).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment_return, size: 14, color: _getRefundStatusColor(refundStatus)),
                          const SizedBox(width: 4),
                          Text(
                            'RETURN',
                            style: TextStyle(color: _getRefundStatusColor(refundStatus), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasRefunds) _buildReturnInfo(order['refunds'][0]),
          if (order['review'] != null) _buildReviewInfo(order['review']),
          if (itemCount > 0) ..._buildOrderItems(order),
          _buildVendorInfo(vendorName, vendorPhone, orderNumber),
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
                'Return Status:',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
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
                'Amount: Rs ${(double.tryParse(refund['requested_amount']?.toString() ?? '0') ?? 0).toInt()}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                '${refund['refund_method']?.toUpperCase() ?? 'N/A'}',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Reason:', style: TextStyle(color: Colors.grey, fontSize: 11)),
          Text(
            refund['reason'] ?? 'No reason provided',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (refund['customer_notes'] != null && refund['customer_notes'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
             Text(
              '"${refund['customer_notes']}"',
              style: TextStyle(color: Colors.grey[300], fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
          if (refund['admin_notes'] != null && refund['admin_notes'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const Text(
                    'Vendor Note:',
                    style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    refund['admin_notes'],
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
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
                      child: Image.network(
                        doc['file_url'] ?? '',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, color: Colors.grey, size: 20),
                      ),
                    ),
                  );
                },
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
                'Your Review - ${review['overall_rating']}/5',
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
            formatDate(review['created_at']),
            style: TextStyle(color: Colors.grey[400], fontSize: 10),
          ),
        ],
      ),
    );
  }

  Color _getRefundStatusColor(String? status) {
    switch (status) {
      case 'requested':
        return Colors.orange;
      case 'approved':
        return Colors.blue;
      case 'processing':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getRefundStatusText(String? status) {
    switch (status) {
      case 'requested':
        return 'RETURN REQUESTED';
      case 'approved':
        return 'RETURN APPROVED';
      case 'processing':
        return 'RETURN PROCESSING';
      case 'completed':
        return 'RETURN COMPLETED';
      case 'rejected':
        return 'RETURN REJECTED';
      default:
        return 'RETURN';
    }
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
                            child: Image.network(productImage, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.inventory, color: Colors.grey, size: 16)),
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
                          item['product_name'] ?? item['product_details']?['name'] ?? 'Product',
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
  
  Widget _buildVendorInfo(String vendorName, String vendorPhone, String orderNumber) {
    return Row(
      children: [
        const Icon(Icons.store, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(vendorName, style: TextStyle(color: Colors.grey[300], fontSize: 14))),
        if (vendorPhone.isNotEmpty) ..._buildCallMessageButtons(vendorPhone, orderNumber),
      ],
    );
  }
  
  List<Widget> _buildCallMessageButtons(String vendorPhone, String orderNumber) {
    return [
      GestureDetector(
        onTap: () => _showCallOptions(context, vendorPhone),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.call, size: 16, color: Colors.green),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => _showMessageDialog(context, vendorPhone, orderNumber),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('NPR ${amount.toInt()}', style: const TextStyle(color: AppTheme.primaryColor, fontSize: 14, fontWeight: FontWeight.bold)),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => _showOrderDetails(order),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.primaryColor),
                foregroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(60, 28),
              ),
              child: const Text('Details', style: TextStyle(fontSize: 10)),
            ),
            const SizedBox(width: 6),
            if (status == 'delivered' && order['review'] == null)
              ElevatedButton(
                onPressed: () => _rateOrder(order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(50, 28),
                ),
                child: const Text('Rate', style: TextStyle(fontSize: 10)),
              )
            else if (order['review'] != null)
              ElevatedButton(
                onPressed: () => _editReview(order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: const Size(50, 28),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 12, color: Colors.white),
                    const SizedBox(width: 2),
                    Text('${order['review']['overall_rating']}', style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            if (status == 'delivered' && (order['refunds'] as List?)?.isEmpty != false)
              const SizedBox(width: 6),
            if (status == 'delivered' && (order['refunds'] as List?)?.isEmpty != false)
              ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => RefundRequestDialog(
                    order: order,
                    onRefundRequested: () => _fetchFreshData(),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: const Size(50, 28),
                ),
                child: const Text('Return', style: TextStyle(fontSize: 10)),
              ),
          ],
        ),
      ],
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => OrderTrackingScreen(
          orderNumber: order['order_number'] ?? 'N/A',
          orderDate: formatDate(order['created_at']),
          vendor: order['vendor_details']?['business_name'] ?? 'Vendor',
          amount: double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0.0,
          orderStatus: order['status'] ?? 'pending',
          orderItems: _getOrderItemsString(order['items'] as List? ?? []),
          orderTime: _formatTime(order['created_at']),
          preloadedOrderData: order,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
  
  String _getOrderItemsString(List items) {
    if (items.isEmpty) return 'No items';
    return items.map((item) => '${item['quantity'] ?? 1}x ${item['product_name'] ?? 'Item'}').join(', ');
  }
  
  String _formatTime(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final hour = date.hour > 12 ? date.hour - 12 : date.hour;
      final period = date.hour >= 12 ? 'PM' : 'AM';
      return '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '';
    }
  }

  void _rateOrder(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => ReviewDialog(
        orderId: order['id'],
        onReviewSubmitted: () {
          _fetchFreshData();
        },
      ),
    );
  }

  void _editReview(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => ReviewDialog(
        orderId: order['id'],
        existingReview: order['review'],
        onReviewSubmitted: () {
          _fetchFreshData();
        },
      ),
    );
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
}
