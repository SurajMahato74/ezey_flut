import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/data_preloader_service.dart';
import '../widgets/review_dialog.dart';
import '../widgets/refund_request_dialog.dart';
import '../config.dart' as appConfig;

class OrderTrackingScreen extends StatefulWidget {
  final int? orderId;
  final String orderNumber;
  final String orderDate;
  final String vendor;
  final double amount;
  final String orderStatus;
  final String orderItems;
  final String orderTime;
  final Map<String, dynamic>? preloadedOrderData;

  const OrderTrackingScreen({
    super.key,
    this.orderId,
    this.orderNumber = '',
    this.orderDate = '',
    this.vendor = '',
    this.amount = 0.0,
    this.orderStatus = '',
    this.orderItems = '',
    this.orderTime = '',
    this.preloadedOrderData,
  });

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? orderDetails;
  bool loading = true;
  Timer? _syncTimer;
  String? _lastStatusHash;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOrderDetails();
    _startStatusSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncOrderStatus();
    }
  }

  void _startStatusSync() {
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _syncOrderStatus();
    });
  }

  String _generateStatusHash(Map<String, dynamic>? order) {
    if (order == null) return '';
    final reviewData = order['review'];
    final reviewHash = reviewData != null ? '${reviewData['overall_rating']}_${reviewData['review_text']}_${reviewData['created_at']}' : 'no_review';
    return '${order['status']}:${order['payment_status']}:${order['delivery_boy_phone'] ?? ''}:$reviewHash';
  }

  Future<void> _syncOrderStatus() async {
    try {
      final token = AuthService().token;
      if (token != null) {
        final response = await http.get(
          Uri.parse('${appConfig.Config.baseUrl}/orders/?page=1&page_size=100&_t=${DateTime.now().millisecondsSinceEpoch}'),
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
            'Cache-Control': 'no-cache',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final orders = List<Map<String, dynamic>>.from(data['results'] ?? []);
          final order = orders.firstWhere(
            (o) {
              if (widget.orderId != null) return o['id'] == widget.orderId;
              if (widget.orderNumber.isNotEmpty) return o['order_number'] == widget.orderNumber;
              return false;
            },
            orElse: () => <String, dynamic>{},
          );

          if (order.isNotEmpty) {
            final newHash = _generateStatusHash(order);
            if (_lastStatusHash != newHash && mounted) {
              setState(() {
                orderDetails = order;
              });
            }
            _lastStatusHash = newHash;
          }
        }
      }
    } catch (e) {
      // Handle silently
    }
  }

  Future<void> _loadOrderDetails() async {
    // Use preloaded data first for instant display
    if (widget.preloadedOrderData != null) {
      if (mounted) {
        setState(() {
          orderDetails = widget.preloadedOrderData;
          loading = false;
        });
      }
      _lastStatusHash = _generateStatusHash(widget.preloadedOrderData);
      
      // Background refresh
      _refreshOrderInBackground();
      return;
    }
    
    // Check cached orders from preloader
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    final cachedOrders = preloader.customerOrders;
    
    if (cachedOrders != null && cachedOrders.isNotEmpty) {
      final cachedOrder = cachedOrders.firstWhere(
        (o) {
          if (widget.orderId != null) return o['id'] == widget.orderId;
          if (widget.orderNumber.isNotEmpty) return o['order_number'] == widget.orderNumber;
          return false;
        },
        orElse: () => <String, dynamic>{},
      );
      
      if (cachedOrder.isNotEmpty) {
        if (mounted) {
          setState(() {
            orderDetails = cachedOrder;
            loading = false;
          });
        }
        _lastStatusHash = _generateStatusHash(cachedOrder);
        
        // Background refresh
        _refreshOrderInBackground();
        return;
      }
    }
    
    // Fallback to API call
    await _fetchOrderFromAPI();
  }
  
  Future<void> _refreshOrderInBackground() async {
    try {
      await _fetchOrderFromAPI(showLoading: false);
    } catch (e) {
      // Handle silently for background refresh
    }
  }
  
  Future<void> _fetchOrderFromAPI({bool showLoading = true}) async {
    try {
      final token = AuthService().token;
      if (token != null) {
        final response = await http.get(
          Uri.parse('${appConfig.Config.baseUrl}/orders/?page=1&page_size=100'),
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final orders = List<Map<String, dynamic>>.from(data['results'] ?? []);
          final order = orders.firstWhere(
            (o) {
              if (widget.orderId != null) return o['id'] == widget.orderId;
              if (widget.orderNumber.isNotEmpty) return o['order_number'] == widget.orderNumber;
              return false;
            },
            orElse: () => <String, dynamic>{},
          );

          if (mounted) {
            setState(() {
              orderDetails = order.isNotEmpty ? order : null;
              if (showLoading) loading = false;
            });
          }
          _lastStatusHash = _generateStatusHash(order.isNotEmpty ? order : null);
        }
      }
    } catch (e) {
      if (mounted && showLoading) setState(() => loading = false);
    }
  }

  Future<void> _cancelOrder() async {
    try {
      final token = AuthService().token;
      if (token != null && orderDetails != null) {
        final response = await http.patch(
          Uri.parse('${appConfig.Config.baseUrl}/orders/${orderDetails!['id']}/'),
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode({'status': 'cancelled'}),
        );

        if (response.statusCode == 200) {
          _loadOrderDetails();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order cancelled successfully')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to cancel order')),
      );
    }
  }

  void _showReviewDialog() {
    if (orderDetails == null) return;
    
    showDialog(
      context: context,
      builder: (context) => ReviewDialog(
        orderId: orderDetails!['id'],
        existingReview: orderDetails!['review'],
        onReviewSubmitted: () {
          _fetchOrderFromAPI(); // Force fresh data fetch
        },
      ),
    );
  }

  void _showReturnDialog() {
    if (orderDetails == null) return;
    
    showDialog(
      context: context,
      builder: (context) => RefundRequestDialog(
        order: orderDetails!,
        onRefundRequested: () {
          _fetchOrderFromAPI(); // Force fresh data fetch
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF121212),
          title: Text('Order Details', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      );
    }

    if (orderDetails == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF121212),
          title: Text('Order Details', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text('Order not found', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final order = orderDetails!;
    final status = order['status'] ?? 'pending';
    final items = List<Map<String, dynamic>>.from(order['items'] ?? []);
    final statusHistory = List<Map<String, dynamic>>.from(order['status_history'] ?? []);
    final canCancel = order['can_be_cancelled'] ?? false;
    final canReview = order['can_be_reviewed'] ?? false;
    final hasRefunds = (order['refunds'] as List?)?.isNotEmpty == true;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: Text('Order ${order['order_number']}', 
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderHeader(order, status),
            const SizedBox(height: 24),
            _buildOrderItems(items),
            const SizedBox(height: 24),
            _buildDeliveryInfo(order),
            const SizedBox(height: 24),
            _buildStatusTimeline(statusHistory),
            const SizedBox(height: 24),
            _buildOrderSummary(order),
            const SizedBox(height: 24),
            if (hasRefunds) _buildRefundSection(order['refunds']),
            if (hasRefunds) const SizedBox(height: 24),
            _buildActionButtons(status, canCancel, canReview, hasRefunds),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderHeader(Map<String, dynamic> order, String status) {
    Color statusColor = _getStatusColor(status);
    IconData statusIcon = _getStatusIcon(status);
    final hasReview = order['review'] != null;

    return Container(
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
              Text(
                'Order ${order['order_number']}',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  if (hasReview)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD60A).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 14, color: Color(0xFFFFD60A)),
                          const SizedBox(width: 4),
                          Text(
                            '${order['review']['overall_rating']}',
                            style: const TextStyle(
                              color: Color(0xFFFFD60A),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Vendor: ${order['vendor_details']?['business_name'] ?? 'Unknown'}',
            style: GoogleFonts.plusJakartaSans(color: Colors.grey[300]),
          ),
          Text(
            'Ordered: ${_formatDate(order['created_at'])}',
            style: GoogleFonts.plusJakartaSans(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItems(List<Map<String, dynamic>> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Items (${items.length})',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) => _buildOrderItem(item)),
        ],
      ),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> item) {
    final productDetails = item['product_details'] ?? {};
    final images = productDetails['images'] as List? ?? [];
    final imageUrl = images.isNotEmpty ? images[0]['image_url'] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null
                ? Image.network(
                    imageUrl,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[700],
                      child: const Icon(Icons.image, color: Colors.grey),
                    ),
                  )
                : Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey[700],
                    child: const Icon(Icons.image, color: Colors.grey),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['product_name'] ?? 'Unknown Product',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Qty: ${item['quantity']} × Rs ${item['unit_price']}',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Rs ${item['total_price']}',
            style: GoogleFonts.plusJakartaSans(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryInfo(Map<String, dynamic> order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delivery Information',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.person, 'Name', order['delivery_name'] ?? 'N/A'),
          _buildInfoRow(Icons.phone, 'Phone', order['delivery_phone'] ?? 'N/A'),
          _buildInfoRow(Icons.location_on, 'Address', order['delivery_address'] ?? 'N/A'),
          if (order['delivery_boy_phone'] != null)
            _buildInfoRow(Icons.delivery_dining, 'Delivery Boy', order['delivery_boy_phone']),
          if (order['vehicle_number'] != null)
            _buildInfoRow(Icons.directions_car, 'Vehicle', '${order['vehicle_number']} (${order['vehicle_color'] ?? 'N/A'})'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: GoogleFonts.plusJakartaSans(color: Colors.grey[400], fontSize: 12),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(List<Map<String, dynamic>> statusHistory) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Timeline',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...statusHistory.reversed.map((history) => _buildTimelineItem(history)),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> history) {
    final status = history['status'] ?? '';
    final date = _formatDateTime(history['changed_at']);
    final notes = history['notes'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _getStatusColor(status),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  date,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.grey[400],
                    fontSize: 10,
                  ),
                ),
                if (notes.isNotEmpty)
                  Text(
                    notes,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.grey[300],
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(Map<String, dynamic> order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Summary',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildSummaryRow('Subtotal', 'Rs ${order['subtotal']}'),
          _buildSummaryRow('Delivery Fee', 'Rs ${order['delivery_fee']}'),
          _buildSummaryRow('Tax', 'Rs ${order['tax_amount']}'),
          if (double.parse(order['discount_amount']?.toString() ?? '0') > 0)
            _buildSummaryRow('Discount', '- Rs ${order['discount_amount']}'),
          const Divider(color: Colors.grey),
          _buildSummaryRow('Total', 'Rs ${order['total_amount']}', isTotal: true),
          _buildSummaryRow('Payment Method', order['payment_method']?.toString().replaceAll('_', ' ').toUpperCase() ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: isTotal ? Colors.white : Colors.grey[400],
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              color: isTotal ? AppTheme.primaryColor : Colors.white,
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(String status, bool canCancel, bool canReview, bool hasRefunds) {
    final hasReview = orderDetails?['review'] != null;
    
    return Column(
      children: [
        if (canCancel)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _cancelOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Cancel Order', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
            ),
          ),
        if (status == 'delivered') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _showReviewDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasReview ? Colors.orange : AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    hasReview ? 'Edit Review' : 'Rate Order', 
                    style: GoogleFonts.plusJakartaSans(color: hasReview ? Colors.white : Colors.black)
                  ),
                ),
              ),
              if (!hasRefunds) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _showReturnDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Return Item', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildRefundSection(List refunds) {
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
                'Return Request',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...refunds.map((refund) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
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
                          'Amount: Rs ${refund['requested_amount'] ?? '0.00'}',
                          style: const TextStyle(
                            color: Color(0xFFFFD60A),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getRefundStatusColor(refund['status'] ?? 'pending').withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            (refund['status'] ?? 'pending').toUpperCase(),
                            style: TextStyle(
                              color: _getRefundStatusColor(refund['status'] ?? 'pending'),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.category, 'Return Reason', refund['reason'] ?? 'N/A'),
                    _buildInfoRow(Icons.payment, 'Refund Method', refund['refund_method']?.toString().toUpperCase() ?? 'N/A'),
                    
                    const Divider(color: Colors.grey),
                    
                    if (refund['customer_notes'] != null && refund['customer_notes'].toString().isNotEmpty)
                      _buildInfoRow(Icons.note, 'Your Note', refund['customer_notes']),
                      
                    if (refund['admin_notes'] != null && refund['admin_notes'].toString().isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
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
                      
                    const SizedBox(height: 8),
                    _buildInfoRow(Icons.calendar_today, 'Requested', _formatDateTime(refund['requested_at'])),
                    if (refund['approved_at'] != null)
                      _buildInfoRow(Icons.check_circle, 'Approved', _formatDateTime(refund['approved_at'])),
                    if (refund['processed_at'] != null)
                      _buildInfoRow(Icons.check_circle, 'Processed', _formatDateTime(refund['processed_at'])),
                    if (refund['rejected_at'] != null)
                      _buildInfoRow(Icons.cancel, 'Rejected', _formatDateTime(refund['rejected_at'])),
                      
                    if (refund['evidence_photos'] != null && (refund['evidence_photos'] as List).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Your Supporting Documents:', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: (refund['evidence_photos'] as List).length,
                          itemBuilder: (context, index) {
                            final photo = (refund['evidence_photos'] as List)[index];
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.withOpacity(0.3)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  photo['file_url'] ?? '',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, color: Colors.grey),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    
                    if (refund['vendor_supporting_docs'] != null && (refund['vendor_supporting_docs'] as List).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Vendor Proof Documents:', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: (refund['vendor_supporting_docs'] as List).length,
                          itemBuilder: (context, index) {
                            final doc = (refund['vendor_supporting_docs'] as List)[index];
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withOpacity(0.3)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  doc['file_url'] ?? '',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, color: Colors.grey),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          )),
        ],
      ),
    );
  }

  Color _getRefundStatusColor(String status) {
    switch (status) {
      case 'requested': return Colors.orange;
      case 'approved': return Colors.blue;
      case 'processed': return Colors.green;
      case 'rejected': return Colors.red;
      default: return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.blue;
      case 'confirmed': return Colors.orange;
      case 'out_for_delivery': return Colors.purple;
      case 'delivered': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending': return Icons.access_time;
      case 'confirmed': return Icons.check_circle_outline;
      case 'out_for_delivery': return Icons.local_shipping;
      case 'delivered': return Icons.check_circle;
      case 'cancelled': return Icons.cancel;
      default: return Icons.receipt;
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  String _formatDateTime(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      final hour = date.hour > 12 ? date.hour - 12 : date.hour;
      final period = date.hour >= 12 ? 'PM' : 'AM';
      return '${date.month}/${date.day}/${date.year} ${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return 'N/A';
    }
  }
}