// lib/screens/vendor_notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VendorNotificationsScreen extends StatefulWidget {
  const VendorNotificationsScreen({super.key});

  @override
  State<VendorNotificationsScreen> createState() => _VendorNotificationsScreenState();
}

class _VendorNotificationsScreenState extends State<VendorNotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: Text(
          "Notifications",
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFFD60A),
        backgroundColor: const Color(0xFF1E1E1E),
        onRefresh: () async {
          await Future.delayed(const Duration(seconds: 1));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _notificationItem(
                "New Order Received",
                "Order #EZ5892 - Customer placed order for Organic Honey",
                "2 hours ago",
                true,
              ),
              _notificationItem(
                "Payment Received",
                "NPR 1,100 credited to your wallet",
                "4 hours ago",
                true,
              ),
              _notificationItem(
                "Order Completed",
                "Order #EZ5891 has been marked as completed",
                "1 day ago",
                false,
              ),
              _notificationItem(
                "Low Stock Alert",
                "Organic Honey stock is below 5 units",
                "2 days ago",
                false,
              ),
              _notificationItem(
                "Customer Review",
                "Received 5-star review for Pink Salt",
                "3 days ago",
                true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notificationItem(String title, String subtitle, String time, bool hasAction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: hasAction ? const Color(0xFFFFD60A) : Colors.grey[700]!,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasAction ? Icons.notifications : Icons.notifications_outlined,
              color: Colors.black,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      time,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const Spacer(),
                    if (hasAction)
                      TextButton(
                        onPressed: () {},
                        child: const Text(
                          "View",
                          style: TextStyle(color: Color(0xFFFFD60A)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}