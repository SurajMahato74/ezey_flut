import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../screens/home_screen.dart';
import '../screens/products_page.dart';
import '../screens/order_history_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/customer_profile_screen.dart';

class UnifiedBottomNav extends StatelessWidget {
  final String currentPage;
  final VoidCallback? onSwitchToVendor;

  const UnifiedBottomNav({
    super.key,
    required this.currentPage,
    this.onSwitchToVendor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Color(0xFF18181B),
        border: Border(top: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(
            context,
            Icons.home,
            'Home',
            currentPage == 'home',
            () => _navigateToPage(context, 'home'),
          ),
          _buildNavItem(
            context,
            Icons.restaurant_menu,
            'Products',
            currentPage == 'products',
            () => _navigateToPage(context, 'products'),
          ),
          _buildNavItem(
            context,
            Icons.receipt_long,
            'Orders',
            currentPage == 'orders',
            () => _navigateToPage(context, 'orders'),
          ),
          _buildNavItem(
            context,
            Icons.shopping_cart,
            'Cart',
            currentPage == 'cart',
            () => _navigateToPage(context, 'cart'),
          ),
          _buildNavItem(
            context,
            Icons.person,
            'Profile',
            currentPage == 'profile',
            () => _navigateToPage(context, 'profile'),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    IconData icon,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 80,
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? AppTheme.primaryColor : const Color(0xFFA1A1AA),
                size: 24,
              ),
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
        ),
      ),
    );
  }

  void _navigateToPage(BuildContext context, String page) {
    if (currentPage == page) return;

    Widget destination;
    switch (page) {
      case 'home':
        destination = HomeScreen(onSwitchToVendor: onSwitchToVendor);
        break;
      case 'products':
        destination = const ProductsPage();
        break;
      case 'orders':
        destination = const OrderHistoryScreen();
        break;
      case 'cart':
        destination = const CartScreen();
        break;
      case 'profile':
        destination = CustomerProfileScreen(onSwitchToVendor: onSwitchToVendor);
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}