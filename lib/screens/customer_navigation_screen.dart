import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navigation_service.dart';
import 'home_screen.dart';
import 'products_page.dart';
import 'order_history_screen.dart';
import 'cart_screen.dart';
import 'customer_profile_screen.dart';
import 'category_detail_screen.dart';

class CustomerNavigationScreen extends StatefulWidget {
  final VoidCallback? onSwitchToVendor;
  
  const CustomerNavigationScreen({super.key, this.onSwitchToVendor});

  @override
  State<CustomerNavigationScreen> createState() => _CustomerNavigationScreenState();
}

class _CustomerNavigationScreenState extends State<CustomerNavigationScreen> with RestorationMixin {
  final NavigationService _navigationService = NavigationService();
  final RestorableString _currentPageRestoration = RestorableString('home');

  @override
  String? get restorationId => 'customer_navigation';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_currentPageRestoration, 'current_page');
    _navigationService.restoreCurrentPage(_currentPageRestoration.value);
  }

  @override
  void initState() {
    super.initState();
    _navigationService.addListener(_onPageChanged);
  }

  @override
  void dispose() {
    _navigationService.removeListener(_onPageChanged);
    super.dispose();
  }

  void _onPageChanged() {
    _currentPageRestoration.value = _navigationService.currentPage;
  }

  Widget _getCurrentScreen() {
    switch (_navigationService.currentPage) {
      case 'home':
        return HomeScreen(onSwitchToVendor: widget.onSwitchToVendor);
      case 'products':
        return const ProductsPage();
      case 'orders':
        return const OrderHistoryScreen();
      case 'cart':
        return const CartScreen();
      case 'profile':
        return CustomerProfileScreen(onSwitchToVendor: widget.onSwitchToVendor);
      case 'category':
        return CategoryDetailScreen(categoryId: _navigationService.categoryId);
      default:
        return HomeScreen(onSwitchToVendor: widget.onSwitchToVendor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _navigationService,
      child: Consumer<NavigationService>(
        builder: (context, navigationService, child) {
          return Scaffold(
            body: _getCurrentScreen(),
            bottomNavigationBar: StatefulBottomNav(
              currentPage: navigationService.currentPage,
              onSwitchToVendor: widget.onSwitchToVendor,
            ),
          );
        },
      ),
    );
  }
}

class StatefulBottomNav extends StatelessWidget {
  final String currentPage;
  final VoidCallback? onSwitchToVendor;

  const StatefulBottomNav({
    super.key,
    required this.currentPage,
    this.onSwitchToVendor,
  });

  @override
  Widget build(BuildContext context) {
    final navigationService = Provider.of<NavigationService>(context, listen: false);
    
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Color(0xFF18181B),
        border: Border(top: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem('home', Icons.home, 'Home', navigationService),
          _buildNavItem('products', Icons.restaurant_menu, 'Products', navigationService),
          _buildNavItem('orders', Icons.receipt_long, 'Orders', navigationService),
          _buildNavItem('cart', Icons.shopping_cart, 'Cart', navigationService),
          _buildNavItem('profile', Icons.person, 'Profile', navigationService),
        ],
      ),
    );
  }

  Widget _buildNavItem(String page, IconData icon, String label, NavigationService navigationService) {
    final isSelected = currentPage == page;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => navigationService.setCurrentPage(page),
        child: Container(
          height: 80,
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFFFFD60A) : const Color(0xFFA1A1AA),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? const Color(0xFFFFD60A) : const Color(0xFFA1A1AA),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}