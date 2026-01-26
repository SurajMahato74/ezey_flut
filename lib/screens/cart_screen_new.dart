import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_bottom_nav.dart';
import 'checkout_screen.dart';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  Cart? cart;
  bool loading = true;
  List<int> selectedIds = [];
  List<Map<String, dynamic>> recommendedProducts = [];
  bool loadingRecommended = true;
  final CartService _cartService = CartService();
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();

  @override
  void initState() {
    super.initState();
    _loadCart();
    _loadRecommendedProducts();
  }

  Future<void> _loadCart() async {
    try {
      final token = await _authService.getToken();
      if (token != null) {
        final cartData = await _cartService.getCart(token);
        setState(() {
          cart = cartData;
          selectedIds = [];
          loading = false;
        });
      }
    } catch (e) {
      setState(() => loading = false);
    }
  }

  Future<void> _loadRecommendedProducts() async {
    try {
      final location = _locationService.getLocation();
      final response = await _apiService.searchProducts(
        latitude: location?.latitude,
        longitude: location?.longitude,
        pageSize: 6,
      );
      setState(() {
        recommendedProducts = List<Map<String, dynamic>>.from(response['results'] ?? []);
        loadingRecommended = false;
      });
    } catch (e) {
      setState(() => loadingRecommended = false);
    }
  }

  double getSelectedTotal() {
    if (cart == null) return 0.0;
    return cart!.items
        .where((item) => selectedIds.contains(item.id))
        .fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  Future<void> _updateQuantity(int itemId, int delta) async {
    final item = cart?.items.firstWhere((item) => item.id == itemId);
    if (item != null) {
      final newQuantity = item.quantity + delta;
      if (newQuantity > 0) {
        try {
          final token = await _authService.getToken();
          if (token != null) {
            await _cartService.updateCartItem(token, itemId, newQuantity);
            await _loadCart();
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update quantity')),
          );
        }
      }
    }
  }

  Future<void> _removeItem(int itemId) async {
    try {
      final token = await _authService.getToken();
      if (token != null) {
        await _cartService.removeFromCart(token, itemId);
        await _loadCart();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove item')),
      );
    }
  }

  Future<void> _addToCart(int productId) async {
    try {
      final token = await _authService.getToken();
      if (token != null) {
        await _cartService.addToCart(token, productId, 1);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to cart')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add to cart')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.homeBackgroundDark.withValues(alpha: 0.8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      'My Cart',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (loading)
                    const Center(child: CircularProgressIndicator())
                  else if (cart == null || cart!.items.isEmpty)
                    _buildEmptyCart()
                  else
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildSelectAllRow(),
                          const SizedBox(height: 16),
                          ...cart!.items.map((item) => _buildCartItem(item)),
                        ],
                      ),
                    ),
                  _buildRecommendedProducts(),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: cart != null && cart!.items.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.homeBackgroundDark.withValues(alpha: 0.95),
                border: const Border(
                  top: BorderSide(color: Color(0xFF27272A), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total (${selectedIds.length} items):',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: const Color(0xFFA1A1AA),
                          ),
                        ),
                        Text(
                          'Rs. ${getSelectedTotal().toInt()}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: selectedIds.isNotEmpty ? () {
                      final selectedItems = cart!.items
                          .where((item) => selectedIds.contains(item.id))
                          .toList();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => CheckoutScreen(selectedItems: selectedItems),
                        ),
                      );
                    } : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Checkout',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildSelectAllRow() {
    final allSelected = selectedIds.length == cart!.items.length && cart!.items.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  selectedIds = cart!.items.map((item) => item.id).toList();
                } else {
                  selectedIds.clear();
                }
              });
            },
            activeColor: AppTheme.primaryColor,
            checkColor: Colors.black,
          ),
          Text(
            'Select all (${cart!.items.length})',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (selectedIds.isNotEmpty)
            TextButton(
              onPressed: () async {
                for (final id in selectedIds) {
                  await _removeItem(id);
                }
                setState(() => selectedIds.clear());
              },
              child: Text(
                'Delete (${selectedIds.length})',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    final imageUrl = item.product.images.isNotEmpty
        ? item.product.images.first.imageUrl
        : 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&q=80&w=200&h=200';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selectedIds.contains(item.id),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  selectedIds.add(item.id);
                } else {
                  selectedIds.remove(item.id);
                }
              });
            },
            activeColor: AppTheme.primaryColor,
            checkColor: Colors.black,
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imageUrl,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 60,
                height: 60,
                color: Colors.grey[800],
                child: const Icon(Icons.image, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Sold by ${item.product.vendorName}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: const Color(0xFFA1A1AA),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rs. ${item.product.price.toInt()}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => _updateQuantity(item.id, -1),
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                  ),
                  Text(
                    item.quantity.toString(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _updateQuantity(item.id, 1),
                    icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => _removeItem(item.id),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 50),
          Icon(
            Icons.shopping_cart_outlined,
            size: 80,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            'Your Cart is Empty',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Discover products near you',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              color: const Color(0xFFA1A1AA),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedProducts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Products Near You',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (loadingRecommended)
          const Center(child: CircularProgressIndicator())
        else
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recommendedProducts.length,
              itemBuilder: (context, index) {
                final product = recommendedProducts[index];
                final primaryImage = (product['images'] as List?)?.firstWhere(
                  (img) => img['is_primary'] == true,
                  orElse: () => (product['images'] as List?)?.first,
                );
                final imageUrl = primaryImage?['image_url'] ?? 
                    'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&q=80&w=200&h=200';
                
                return Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Image.network(
                          imageUrl,
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 100,
                            color: Colors.grey[800],
                            child: const Icon(Icons.image, color: Colors.grey),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['name'] ?? 'Unknown Product',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Rs. ${(double.tryParse(product['price'].toString()) ?? 0).toInt()}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _addToCart(product['id']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryColor,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  'Add',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
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
      ],
    );
  }
}