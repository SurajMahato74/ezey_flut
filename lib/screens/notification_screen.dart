import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (_hasMore && !_isLoading && !_isLoadingMore) {
          _fetchNotifications(page: _currentPage + 1);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchNotifications({int page = 1}) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    if (page == 1) {
      if (mounted) setState(() => _isLoading = true);
      _isLoadingMore = false;
    } else {
      if (mounted) setState(() => _isLoadingMore = true);
    }

    try {
      final response = await ApiService().getNotifications(token, page: page);

      List<dynamic> results = [];
      bool hasNext = false;

      if (response is List) {
        results = response;
        hasNext = false;
      } else if (response is Map<String, dynamic>) {
        results = response['results'] ?? [];
        hasNext = response['next'] != null;
      }

      final currentRoleString = authService.currentRole?.toString().split('.').last ?? 'customer';

      final filteredResults = results.where((notification) {
        final notificationRole = notification['role'] ?? 'customer';
        return notificationRole == currentRoleString;
      }).toList();

      if (mounted) {
        setState(() {
          if (page == 1) {
            _notifications = filteredResults;
          } else {
            _notifications.addAll(filteredResults);
          }
          _currentPage = page;

          // Only continue paginating if we got some results AND backend has more
          _hasMore = filteredResults.isNotEmpty && hasNext;

          _isLoading = false;
          _isLoadingMore = false;  // Always stop loading more indicator

          if (page == 1) {
            _unreadCount = _notifications
                .where((n) => n['is_read'] != true)
                .length;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _markAsRead(int id, int index) async {
    final token = Provider.of<AuthService>(context, listen: false).token;
    if (token == null) return;

    try {
      await ApiService().markNotificationRead(token, id);
      if (mounted) {
        setState(() {
          _notifications[index]['is_read'] = true;
          if (_unreadCount > 0) _unreadCount--;
        });
      }
    } catch (e) {
      // Handle silently or show snackbar
    }
  }

  Future<void> _markAllAsRead() async {
    final token = Provider.of<AuthService>(context, listen: false).token;
    if (token == null || _unreadCount == 0) return;

    setState(() => _isLoading = true);
    try {
      await ApiService().markAllNotificationsRead(token);
      if (mounted) {
        setState(() {
          for (var n in _notifications) {
            n['is_read'] = true;
          }
          _unreadCount = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.homeBackgroundDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                'Mark all read',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading && _notifications.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_off_outlined,
                          color: Colors.grey, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.primaryColor,
                  backgroundColor: const Color(0xFF1E1E1E),
                  onRefresh: () => _fetchNotifications(page: 1),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Loading indicator for pagination
                      if (index == _notifications.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(
                                color: AppTheme.primaryColor),
                          ),
                        );
                      }

                      final notification = _notifications[index];
                      final bool isRead = notification['is_read'] == true;
                      final String role = notification['role'] ?? 'customer';
                      final String orderNumber =
                          notification['order_number'] ?? 'Unknown Order';
                      final String customerName =
                          notification['customer_username'] ?? 'Customer';
                      final String vendorName =
                          notification['vendor_business_name'] ?? 'Vendor';

                      // Contextual subtitle based on role
                      String subtitle = notification['message'] ?? '';
                      if (role == 'vendor') {
                        subtitle = "Order #$orderNumber from $customerName";
                      } else {
                        subtitle = "Order #$orderNumber • $vendorName";
                      }

                      return Dismissible(
                        key: Key(notification['id'].toString()),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          setState(() {
                            _notifications.removeAt(index);
                          });
                          // Optional: Call delete API
                        },
                        child: InkWell(
                          onTap: () {
                            if (!isRead) {
                              _markAsRead(notification['id'], index);
                            }
                            // TODO: Navigate to order details (customer or vendor view)
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isRead
                                  ? const Color(0xFF18181B)
                                  : const Color(0xFF27272A),
                              borderRadius: BorderRadius.circular(16),
                              border: isRead
                                  ? null
                                  : Border.all(
                                      color: role == 'vendor'
                                          ? Colors.green.withOpacity(0.5)
                                          : AppTheme.primaryColor
                                              .withOpacity(0.4),
                                    ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildIcon(
                                    notification['notification_type'] ??
                                        'general',
                                    role),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (role == 'vendor')
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.green
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'VENDOR',
                                                style:
                                                    GoogleFonts.plusJakartaSans(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.green,
                                                ),
                                              ),
                                            ),
                                          if (role == 'vendor')
                                            const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              notification['title'] ??
                                                  'Notification',
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                color: Colors.white,
                                                fontWeight: isRead
                                                    ? FontWeight.w600
                                                    : FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          if (!isRead)
                                            Container(
                                              width: 10,
                                              height: 10,
                                              decoration: const BoxDecoration(
                                                color: AppTheme.primaryColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        subtitle,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: isRead
                                              ? Colors.grey[400]
                                              : Colors.grey[200],
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _formatTime(
                                            notification['created_at'] as String?),
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildIcon(String notificationType, String role) {
    IconData icon = Icons.notifications;
    Color color;

    // Base color by role
    if (role == 'vendor') {
      color = Colors.green;
    } else {
      color = AppTheme.primaryColor;
    }

    // Icon & color override by notification type
    switch (notificationType) {
      case 'order_placed':
        icon = role == 'vendor'
            ? Icons.shopping_bag_outlined
            : Icons.receipt_long;
        break;
      case 'order_confirmed':
      case 'order_preparing':
      case 'order_ready':
      case 'order_out_for_delivery':
        icon = Icons.local_shipping;
        break;
      case 'order_delivered':
        icon = Icons.check_circle;
        break;
      case 'order_cancelled':
        icon = Icons.cancel;
        color = Colors.red;
        break;
      case 'payment_received':
        icon = Icons.payment;
        break;
      case 'refund_processed':
        icon = Icons.money_off;
        color = Colors.orange;
        break;
      default:
        icon = Icons.notifications;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final date = DateTime.parse(timestamp);
      return timeago.format(date);
    } catch (_) {
      return '';
    }
  }
}