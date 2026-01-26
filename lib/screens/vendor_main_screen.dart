// lib/screens/vendor_main_screen.dart
import 'package:flutter/material.dart';
import 'vendor_dashboard_screen.dart';
import 'product_management_screen.dart';
import 'vendor_orders_screen.dart';
import 'vendor_menu_screen.dart';
import 'add_product_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/vendor_page_controller.dart';

class VendorMainScreen extends StatefulWidget {
  const VendorMainScreen({super.key});

  @override
  State<VendorMainScreen> createState() => _VendorMainScreenState();
}

class _VendorMainScreenState extends State<VendorMainScreen> 
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  int currentIndex = 0;
  late PageController _pageController;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  PageController get pageController => _pageController;

  final List<Widget> pages = [
    const VendorDashboardScreen(),
    const ProductManagementScreen(),
    const VendorOrdersScreen(),
    const VendorMenuScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.homeBackgroundDark,
      resizeToAvoidBottomInset: false, // Prevent resizing when keyboard appears
      body: VendorPageController(
        pageController: _pageController,
        child: PageView(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() => currentIndex = index);
            _animationController.forward().then((_) => _animationController.reverse());
          },
          children: pages,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        elevation: 8,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddProductScreen(),
            ),
          );
        },
        child: const Icon(Icons.add, size: 32, color: Colors.black),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 70,
        color: const Color(0xFF1E1E1E),
        shape: const CircularNotchedRectangle(),
        notchMargin: 12,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home_filled, "Home", 0),
            _navItem(Icons.inventory_2_outlined, "Products", 1),
            const SizedBox(width: 50),
            _navItem(Icons.receipt_long_outlined, "Orders", 2),
            _navItem(Icons.menu, "Menu", 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final bool isActive = currentIndex == index;
    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.ease,
        );
      },
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 26,
                color: isActive ? AppTheme.primaryColor : Colors.grey[600],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: isActive ? AppTheme.primaryColor : Colors.grey[600],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}