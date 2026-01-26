import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class OrderConfirmationScreen extends StatefulWidget {
  final String? orderId;
  
  const OrderConfirmationScreen({super.key, this.orderId});

  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class OrderItem {
  final String id;
  final String name;
  final String description;
  final String price;
  final String imageUrl;
  int quantity;

  OrderItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    this.quantity = 1,
  });
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  late List<OrderItem> orderItems;
  String deliveryAddress = '123 Main Street, Kathmandu, Nepal';
  String deliveryLocation = 'Home';
  double deliveryFee = 50.00;

  @override
  void initState() {
    super.initState();
    orderItems = [
      OrderItem(
        id: '1',
        name: 'Classic Cheeseburger',
        description: 'Size: Regular',
        price: 'Rs. 450',
        imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBOusdip4CvzNx0m9hTkBcrAGRzojT3Ld-khyaW54ywWSUbRYnXKVJ7t_rItvcldNBj6Hh9cluiAFEofCLu3odGrvSJBlR4uJ-pUoG6gdUg15i7aPE6YUUAE1WCxfWrV3PCSOIs8hXhFQnfCosGs1lnCRdwB9zyMoPf5uhwxlxLWY2Al0tyuXIb-_8ZE246q5LJ0z0tJl-qhOiDJEcz8RMXgnim5MhUkaLtzZMO8wirCclUemniS87e70GBT3Z_WrsGAx25ALLo3aHp',
        quantity: 1,
      ),
      OrderItem(
        id: '2',
        name: 'Iced Lemon Tea',
        description: 'Sugar: Regular',
        price: 'Rs. 150',
        imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuA6yjSGsXSVbIO5LAGXPt7HcC1B7TUUYnH93L7ydNka3vrtzvm0HKxiXtsgfKLDbRwtHdUQz9tkH62sRJu0qI3rGNKia7YsDu5n3KqlUpdBJGEEenB5CgnTdI6VrK_ELuDoYXm4VRUaDYJJrWqef7291G1NxSuTi0AmoOSR2vHKhxUw-xCMwqORiScP3HNvBZZHAQrA5ecB_RY6SRlzbcG2ICd4YlS2j5vOhrF1noBc4R_qXMUBYNkAyQ7l7FICISZs7vjqnSxtBvyt',
        quantity: 2,
      ),
    ];
  }

  double getSubtotal() {
    return orderItems.fold(0.0, (sum, item) => 
        sum + (double.parse(item.price.replaceAll('Rs. ', '').replaceAll(',', '')) * item.quantity));
  }

  double getGrandTotal() {
    return getSubtotal() + deliveryFee;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Column(
        children: [
          // Top App Bar
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.homeBackgroundDark.withValues(alpha: 0.8),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Review & Confirm',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 48), // Spacer for centering
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order Items Section
                  _buildSectionTitle('Your Items'),
                  const SizedBox(height: 12),
                  ...orderItems.map((item) => _buildOrderItem(item)),
                  const SizedBox(height: 24),

                  // Delivery Details Section
                  _buildSectionTitle('Delivery To'),
                  const SizedBox(height: 12),
                  _buildDeliveryDetails(),
                  const SizedBox(height: 24),

                  // Bill Details Section
                  _buildSectionTitle('Bill Details'),
                  const SizedBox(height: 12),
                  _buildBillDetails(),
                  const SizedBox(height: 120), // Space for fixed bottom bar
                ],
              ),
            ),
          ),
        ],
      ),

      // Fixed Bottom Action Bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.homeBackgroundDark.withValues(alpha: 0.95),
          border: const Border(
            top: BorderSide(color: Color(0xFF27272A), width: 1),
          ),
        ),
        child: ElevatedButton(
          onPressed: _confirmOrder,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Confirm Order',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }

  Widget _buildOrderItem(OrderItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: NetworkImage(item.imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.price,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),

          // Quantity Controls
          Container(
            width: 80,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (item.quantity > 1) {
                        item.quantity--;
                      }
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.remove,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
                Text(
                  item.quantity.toString(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      item.quantity++;
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.black,
                      size: 16,
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

  Widget _buildDeliveryDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Location Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.location_on,
              color: AppTheme.primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),

          // Address Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deliveryLocation,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  deliveryAddress,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Change Button
          TextButton(
            onPressed: () {
              // TODO: Implement address change functionality
            },
            child: Text(
              'Change',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Subtotal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              Text(
                'Rs. ${getSubtotal().toInt()}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Delivery Fee
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Delivery Fee',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              Text(
                'Rs. ${deliveryFee.toInt()}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Divider
          Divider(
            color: Colors.white.withValues(alpha: 0.1),
            thickness: 1,
          ),
          const SizedBox(height: 12),

          // Grand Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Grand Total',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                'Rs. ${getGrandTotal().toInt()}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmOrder() {
    // Navigate back to home or show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.orderId != null 
          ? 'Order #${widget.orderId} confirmed successfully!' 
          : 'Order confirmed! Total: Rs. ${getGrandTotal().toInt()}'),
        backgroundColor: AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    // Navigate back to home after a delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }
}