import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/delivery_filter_service.dart';
import '../services/location_service.dart';
import 'vendor_profile_screen.dart';
import 'checkout_screen.dart';
import 'product_reviews_screen.dart';
import 'main_app_screen.dart';
import '../utils/delivery_utils.dart';
import '../widgets/safe_network_image.dart';
import '../config.dart' as appConfig;

class ProductDetailScreen extends StatefulWidget {
  final int? productId;
  final List<Map<String, dynamic>>? images;
  final String? restaurant;
  final String? itemName;
  final String? rating;
  final String? distance;
  final String? soldCount;
  final String? price;
  final String? deliveryFee;
  final String? description;
  final int? stock;
  final String? category;
  final int? vendorId;

  const ProductDetailScreen({
    super.key,
    this.productId,
    this.images,
    this.restaurant,
    this.itemName,
    this.rating,
    this.distance,
    this.soldCount,
    this.price,
    this.deliveryFee,
    this.description,
    this.stock,
    this.category,
    this.vendorId,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int quantity = 1;
  int currentImageIndex = 0;

  // Product images for carousel (primary + sample extras)
  List<String> productImages = [];
  
  // Related products from same category
  List<Map<String, dynamic>> _relatedProducts = [];
  bool _isLoadingRelated = true;

  // Reviews data
  Map<String, dynamic>? _reviewData;
  bool _isLoadingReviews = true;

  // Product data for vendor info
  Map<String, dynamic>? _productData;
  bool _isLoadingProduct = true;
  bool _isFavorite = false;

  Future<void> _checkIfFavorite() async {
    if (widget.productId == null) return;
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      if (auth.token == null) return;
      
      final favorites = await ApiService().getFavorites(auth.token!);
      List<dynamic> items = [];
      if (favorites is List) {
        items = favorites;
      } else if (favorites is Map && favorites['results'] != null) items = favorites['results'];
      
      if (mounted) {
        setState(() {
          _isFavorite = items.any((item) => 
            (item['product'] is Map && item['product']['id'] == widget.productId) || 
            (item['product'] == widget.productId)
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    if (widget.productId == null) return;
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to add to wishlist'), backgroundColor: Colors.red),
      );
      return;
    }

    // Toggle local state immediately for UI responsiveness
    setState(() => _isFavorite = !_isFavorite);

    try {
      await ApiService().toggleFavorite(auth.token!, widget.productId!);
      // Success
    } catch (e) {
      // Revert if failed
      if (mounted) setState(() => _isFavorite = !_isFavorite);
    }
  }

  @override
  void initState() {
    super.initState();
    // Populate product images from the images list if available
    // Populate product images from the images list if available
    if (widget.images != null) {
      productImages = widget.images!
          .map((img) => (img['image_url'] ?? img['image'] ?? '').toString())
          .where((url) => url.isNotEmpty)
          .toList();
      
      // Normalize and Deduplicate
      productImages = productImages.map((url) => url.startsWith('http') ? url : '${appConfig.Config.mediaUrl}${url.startsWith('/') ? '' : '/'}$url').toSet().toList();
      
      currentImageIndex = widget.images!.indexWhere((img) => img['is_primary'] == true);
    }
    if (currentImageIndex == -1) currentImageIndex = 0;
    
    // Defer related products fetch until we have category (if not provided)
    if (widget.category != null && widget.category!.isNotEmpty) {
      _fetchRelatedProducts();
    }
    
    if (widget.productId != null) {
      _fetchProductDetails();
      _fetchReviews();
      _checkIfFavorite();
    }
  }

  // Getters to safely access data from widget or fetched details
  String get _itemName => widget.itemName ?? _productData?['name'] ?? 'Loading...';
  String get _price => widget.price ?? 'Rs. ${_productData?['price'] ?? 0}';
  String get _description => widget.description ?? _productData?['description'] ?? '';
  String get _category => widget.category ?? _productData?['category'] ?? '';
  int get _stock => widget.stock ?? _productData?['quantity'] ?? 0;
  String get _restaurant => widget.restaurant ?? _productData?['vendor_name'] ?? _productData?['vendor']?['shop_name'] ?? 'Vendor';
  String get _deliveryFeeText {
    if (widget.deliveryFee != null && widget.deliveryFee!.isNotEmpty) {
      return widget.deliveryFee!;
    }
    if (_productData == null) return 'TBD';
    
    final deliveryInfo = getDeliveryInfo(_productData!, null);
    return deliveryInfo['isFreeDelivery'] == true 
        ? 'Free' 
        : 'NPR ${deliveryInfo['deliveryFee']?.toInt() ?? 'TBD'}';
  }
  String get _soldCount => widget.soldCount ?? '${_productData?['total_sold'] ?? _productData?['sold_quantity'] ?? 0}';
  String get _rating => widget.rating ?? '0.0';
  int? get _vendorId => widget.vendorId ?? _productData?['vendor_id'] ?? _productData?['vendor']?['id'];

  String get _distance {
    final userPos = DeliveryFilterService().userPosition;
    final venLat = _productData?['vendor_latitude'];
    final venLon = _productData?['vendor_longitude'];
    
    if (userPos != null && venLat != null && venLon != null) {
      final d = LocationService().calculateDistance(
        userPos.latitude,
        userPos.longitude,
        double.parse(venLat.toString()),
        double.parse(venLon.toString()),
      );
      return '${d.toStringAsFixed(1)} km';
    }
    return 'Location required';
  }

  Future<void> _fetchProductDetails() async {
    if (widget.productId == null) return;
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final data = await ApiService().getProductDetails(widget.productId!, token: authService.token);
      
      if (mounted) {
        setState(() {
          _productData = data;
          _isLoadingProduct = false;
          
          // Update images if not initially provided
          if (productImages.isEmpty && data['images'] != null) {
             final imgs = List<Map<String, dynamic>>.from(data['images']);
             productImages = imgs
                 .map((img) => (img['image_url'] ?? img['image'] ?? '').toString())
                 .where((url) => url.isNotEmpty)
                 .toList();
                 
             // Normalize and Deduplicate
             productImages = productImages.map((url) => url.startsWith('http') ? url : '${appConfig.Config.mediaUrl}${url.startsWith('/') ? '' : '/'}$url').toSet().toList();
          }
          
          // Trigger related products fetch if we just got the category
          if ((widget.category == null || widget.category!.isEmpty) && data['category'] != null) {
             _fetchRelatedProducts();
          }
        });
      }
    } catch (e) {
      if (mounted) { 
        setState(() {
          _isLoadingProduct = false;
        });
      }
    }
  }

  Future<void> _fetchReviews() async {
    if (widget.productId == null) return;

    try {
      final data = await ApiService().getProductReviews(widget.productId!);
      if (mounted) {
        setState(() {
          _reviewData = data;
          _isLoadingReviews = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingReviews = false;
        });
      }
    }
  }

  Future<void> _addToCart() async {
    if (widget.productId == null) return;
    
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to add items to cart'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      await CartService().addToCart(auth.token!, widget.productId!, quantity);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $quantity item(s) to cart'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add to cart'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _buyNow() {
    if (widget.productId == null) return;
    
    if (!Provider.of<AuthService>(context, listen: false).isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to buy products')),
      );
      return;
    }

    try {
      Map<String, dynamic> sourceData;

      if (_productData != null) {
        sourceData = Map<String, dynamic>.from(_productData!);
      } else {
        // Fallback to widget data if API response isn't ready
        // Attempt to clean price string (e.g. "NPR 1200" -> 1200.0)
        String priceString = widget.price ?? '0';
        String priceClean = priceString.replaceAll(RegExp(r'[^0-9.]'), '');
        double priceVal = double.tryParse(priceClean) ?? 0.0;

        sourceData = {
          'id': widget.productId,
          'name': widget.itemName ?? 'Unknown Product',
          'price': priceVal,
          'vendor_name': widget.restaurant ?? 'Unknown Vendor',
          'vendor_id': widget.vendorId ?? 0,
          'images': widget.images ?? [],
          'quantity': widget.stock ?? 0,
          // Try to infer delivery info
          'free_delivery': widget.deliveryFee?.toLowerCase().contains('free') ?? false,
        };
        
        if (widget.deliveryFee != null && !sourceData['free_delivery']) {
           String feeClean = widget.deliveryFee!.replaceAll(RegExp(r'[^0-9.]'), '');
           double? feeVal = double.tryParse(feeClean);
           if (feeVal != null) {
             sourceData['custom_delivery_price'] = feeVal;
             sourceData['custom_delivery_fee_enabled'] = true;
           }
        }
      }

      final modifiedProduct = Map<String, dynamic>.from(sourceData);
      
      // Ensure normalized fields for Product.fromJson
      if (modifiedProduct['vendor'] is Map) {
        modifiedProduct['vendor_name'] = modifiedProduct['vendor']['shop_name'];
        modifiedProduct['vendor_id'] = modifiedProduct['vendor']['id'];
      }
      
      // Ensure numeric types
      modifiedProduct['price'] = double.parse(modifiedProduct['price'].toString());
      if (modifiedProduct['custom_delivery_price'] != null) {
        modifiedProduct['custom_delivery_fee'] = double.parse(modifiedProduct['custom_delivery_price'].toString());
        modifiedProduct['custom_delivery_fee_enabled'] = true; 
      }

      final product = Product.fromJson(modifiedProduct);
      final cartItem = CartItem(
        id: 0,
        product: product,
        quantity: quantity, 
        totalPrice: product.price * quantity,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutScreen(selectedItems: [cartItem]),
        ),
      );
    } catch (e) {
      print('Error preparing buy now: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error proceeding to checkout. Please wait for details to load.')),
      );
    }
  }

  void _buyRelatedProduct(Map<String, dynamic> productData) {
    if (!Provider.of<AuthService>(context, listen: false).isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to buy products')),
      );
      return;
    }

    try {
      final modifiedProduct = Map<String, dynamic>.from(productData);
      
      // Handle vendor - related products might have vendor object or name
      if (modifiedProduct['vendor'] is Map) {
        modifiedProduct['vendor_name'] = modifiedProduct['vendor']['name'] ?? modifiedProduct['vendor']['shop_name'];
        modifiedProduct['vendor_id'] = modifiedProduct['vendor']['id'];
      } else if (modifiedProduct['vendor_name'] == null && modifiedProduct['vendor'] is String) {
        modifiedProduct['vendor_name'] = modifiedProduct['vendor'];
      }

      // Ensure numeric types
      modifiedProduct['price'] = double.parse(modifiedProduct['price'].toString());
      if (modifiedProduct['custom_delivery_price'] != null) {
        modifiedProduct['custom_delivery_fee'] = double.parse(modifiedProduct['custom_delivery_price'].toString());
        modifiedProduct['custom_delivery_fee_enabled'] = true;
      }

      final product = Product.fromJson(modifiedProduct);
      final cartItem = CartItem(
        id: 0,
        product: product,
        quantity: 1,
        totalPrice: product.price,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutScreen(selectedItems: [cartItem]),
        ),
      );
    } catch (e) {
      print('Error preparing related buy now: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error proceeding to checkout')),
      );
    }
  }

  Future<void> _fetchRelatedProducts() async {
    if (_category.isEmpty) {
      setState(() => _isLoadingRelated = false);
      return;
    }

    try {
      final locationService = LocationService();
      final position = await locationService.getCurrentPosition();

      final response = await ApiService().searchProducts(
        latitude: position?.latitude,
        longitude: position?.longitude,
        categories: [_category],
        pageSize: 10,
        page: 1,
      );

      if (response['success'] == true && response['results'] is List) {
        final allProducts = List<Map<String, dynamic>>.from(response['results']);

        // Apply same filtering as home screen
        final currentUserId = AuthService().user?.id;
        final uniqueVendorIds = allProducts.map((p) => p['vendor_id']).where((id) => id != null).toSet().cast<int>();
        final vendorStatuses = <int, bool>{};
        if (uniqueVendorIds.isNotEmpty) {
          await Future.wait(uniqueVendorIds.map((id) async {
            try {
              final vendor = await ApiService().getVendorDetails(id);
              vendorStatuses[id] = vendor['is_active'] == true;
            } catch (e) {
              vendorStatuses[id] = false;
            }
          }));
        }
        final filteredProducts = <Map<String, dynamic>>[];
        for (final product in allProducts) {
          // Exclude out of stock products
          if ((product['quantity'] ?? 0) <= 0) continue;

          // Exclude products from vendors that are inactive
          final vendorId = product['vendor_id'];
          if (vendorId != null && vendorStatuses[vendorId] == true) {
            // Exclude own products if logged in
            if (vendorId != null && currentUserId != null && vendorId == currentUserId) continue;

            filteredProducts.add(product);
          }
        }

        if (mounted) {
          setState(() {
            _relatedProducts = filteredProducts;
            _isLoadingRelated = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingRelated = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRelated = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.homeBackgroundDark.withOpacity(0.9),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      // If no route to pop, navigate back to main app screen
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const MainAppScreen()),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      _itemName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.red : Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main Product Image
                  Container(
                    height: 320,
                    width: double.infinity,
                    color: Colors.white,
                    child: productImages.isNotEmpty 
                      ? SafeNetworkImage(
                          imageUrl: productImages[currentImageIndex],
                          fit: BoxFit.contain,
                          errorWidget: Container(height: 320, width: double.infinity, color: Colors.grey[800], child: const Icon(Icons.image_not_supported, color: Colors.white54, size: 64)),
                        )
                      : Container(height: 320, width: double.infinity, color: Colors.grey[800], child: const Icon(Icons.image, color: Colors.white54, size: 64)),
                  ),

                  // Image Thumbnails
                  if (productImages.length > 1)
                    Container(
                      height: 60,
                      margin: const EdgeInsets.only(top: 16),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: productImages.length,
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                currentImageIndex = index;
                              });
                            },
                            child: Container(
                              width: 60,
                              height: 60,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: currentImageIndex == index ? AppTheme.primaryColor : Colors.transparent,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SafeNetworkImage(
                                  imageUrl: productImages[index],
                                  fit: BoxFit.cover,
                                  errorWidget: Container(height: 60, width: 60, color: Colors.grey[800], child: const Icon(Icons.image_not_supported, color: Colors.white54, size: 24)),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Title, Category, Price & Quantity
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _itemName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _category.isNotEmpty ? _category : 'General',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            color: const Color(0xFFA1A1AA),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _price,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            Row(
                              children: [
                                _buildQuantityButton(Icons.remove, () {
                                  if (quantity > 1) setState(() => quantity--);
                                }),
                                SizedBox(
                                  width: 60,
                                  child: Center(
                                    child: Text(
                                      quantity.toString(),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                _buildQuantityButton(Icons.add, () {
                                  setState(() => quantity++);
                                }),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Delivery, Sold, Stock Info
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildInfoRow(Icons.directions_car, '', _deliveryFeeText),
                          const SizedBox(width: 16),
                          _buildDivider(),
                          const SizedBox(width: 16),
                          _buildInfoRow(Icons.location_on, '', _distance),
                          const SizedBox(width: 16),
                          _buildDivider(),
                          const SizedBox(width: 16),
                          _buildInfoRow(Icons.local_fire_department, '', '$_soldCount sold'),
                          const SizedBox(width: 16),
                          _buildDivider(),
                          const SizedBox(width: 16),
                          _buildInfoRow(
                            Icons.inventory_2,
                            '',
                            _stock > 0 ? 'In Stock ($_stock)' : 'Out of Stock',
                            color: _stock > 0 ? Colors.white : Colors.red,
                            iconColor: _stock > 0 ? AppTheme.primaryColor : Colors.red,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Description
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Description',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _stripHtml(_description.isNotEmpty
                              ? _description
                              : 'No description available for this product.'),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: const Color(0xFFA1A1AA),
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Vendor Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InkWell(
                      onTap: () {
                        if (_vendorId != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VendorProfileScreen(vendorId: _vendorId!),
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF18181B),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                image: const DecorationImage(
                                  image: NetworkImage(
                                    'https://lh3.googleusercontent.com/aida-public/AB6AXuAwh-QBgkwVqkefxPezrBd4U4pxAnLap2pGLYwuOLNpzQz_1GYR2i4_d7Ep_Nc1nP1GTPHYb94cUykNa-Rpbw7eJC7IA1l5H2RaNQ6MS2GcBPiNk7fbhY-uhD6jqPRSvx1HFwp9tOOt0Cac60hVo5-CN8sUpy8mGOfA4d9WWVNMv_Rrq8B3bpba8fbBuIE-rpMTsXE3oY_CymEq-TSxtKdQGQwgCPXPL-cCxQO4Y6HU7Ws72GQjZFVcvSjLQbTo1gIpuWWWJTsHVpwi',
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _restaurant,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, color: AppTheme.primaryColor, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$_rating (125+ ratings)',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14,
                                          color: const Color(0xFFA1A1AA),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, color: Color(0xFFA1A1AA), size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Ratings & Reviews Placeholder
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Ratings & Reviews',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            TextButton(
                              onPressed: widget.productId != null
                                  ? () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ProductReviewsScreen(
                                            productId: widget.productId!,
                                            productName: _itemName,
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                              child: Text(
                                'See All',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _isLoadingReviews
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              )
                            : _buildReviewsSummary(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // You Might Also Like
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'You Might Also Like',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _isLoadingRelated
                      ? const SizedBox(
                          height: 260,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        )
                      : _relatedProducts.isEmpty
                          ? SizedBox(
                              height: 260,
                              child: Center(
                                child: Text(
                                  'No related products found',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: const Color(0xFFA1A1AA),
                                  ),
                                ),
                              ),
                            )
                          : SizedBox(
                              height: 260,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: (_relatedProducts.length / 2).ceil(),
                                itemBuilder: (context, index) {
                                  int firstIndex = index * 2;
                                  int secondIndex = firstIndex + 1;
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (firstIndex < _relatedProducts.length) Container(
                                        width: 160,
                                        margin: const EdgeInsets.only(right: 12),
                                        child: _buildRelatedProductCard(context, _relatedProducts[firstIndex]),
                                      ),
                                      if (secondIndex < _relatedProducts.length) Container(
                                        width: 160,
                                        margin: const EdgeInsets.only(right: 12),
                                        child: _buildRelatedProductCard(context, _relatedProducts[secondIndex]),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),

                  const SizedBox(height: 100), // Space for bottom bar
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom Action Buttons
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.homeBackgroundDark.withOpacity(0.95),
          border: const Border(top: BorderSide(color: Color(0xFF27272A))),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _stock > 0 ? _addToCart : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27272A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _stock > 0 ? 'Add to Cart' : 'Out of Stock',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _stock > 0 ? _buyNow : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Buy Now',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper Widgets
  Widget _buildQuantityButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF27272A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: AppTheme.primaryColor, size: 20),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? color, Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, color: iconColor ?? AppTheme.primaryColor, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFFA1A1AA)),
        ),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color ?? Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider({double height = 20}) {
    return Container(width: 1, height: height, color: const Color(0xFF27272A));
  }

  Widget _buildReviewsSummary() {
    if (_reviewData == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No reviews available',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: const Color(0xFFA1A1AA),
            ),
          ),
        ),
      );
    }

    final aggregate = _reviewData!['aggregate'] as Map<String, dynamic>?;
    final reviews = _reviewData!['recent_reviews'] as List<dynamic>? ?? [];

    final averageRating = aggregate?['average_rating']?.toDouble() ?? 0.0;
    final totalReviews = aggregate?['total_reviews'] ?? 0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF18181B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    averageRating.toStringAsFixed(1),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'out of 5',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFFA1A1AA),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              _buildDivider(height: 60),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          Icons.star,
                          color: i < averageRating.round()
                              ? AppTheme.primaryColor
                              : AppTheme.primaryColor.withOpacity(0.3),
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Based on $totalReviews ${totalReviews == 1 ? 'review' : 'reviews'}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: const Color(0xFFA1A1AA),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (reviews.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...reviews.take(2).map((review) => _buildReviewPreview(review)),
        ],
      ],
    );
  }

  Widget _buildReviewPreview(Map<String, dynamic> review) {
    final rating = review['rating'] ?? 0;
    final comment = review['comment'] ?? '';
    final customerName = review['customer_name'] ?? 'Anonymous';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    customerName.isNotEmpty ? customerName[0].toUpperCase() : 'A',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  customerName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    Icons.star,
                    color: i < rating
                        ? AppTheme.primaryColor
                        : AppTheme.primaryColor.withOpacity(0.3),
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFFE4E4E7),
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRelatedProductCard(BuildContext context, Map<String, dynamic> product) {
    // Handle images - API returns array of objects with image_url field
    List<Map<String, dynamic>> productImages = [];
    final images = product['images'];
    if (images is List && images.isNotEmpty) {
      productImages = List<Map<String, dynamic>>.from(images);
    }
    // Fallback if no images
    if (productImages.isEmpty) {
      productImages = [{'image_url': 'https://via.placeholder.com/160', 'is_primary': true}];
    }
    final primaryImage = productImages.firstWhere((img) => img['is_primary'] == true, orElse: () => productImages.isNotEmpty ? productImages.first : {'image_url': 'https://via.placeholder.com/160'});
    final imageUrl = primaryImage['image_url'] as String? ?? 'https://via.placeholder.com/160';
    
    final title = product['name']?.toString() ?? 'Unknown Product';
    
    // Handle price - could be string or number
    final priceValue = product['price'];
    final priceStr = priceValue is num 
        ? priceValue.toInt().toString()
        : (double.tryParse(priceValue?.toString() ?? '0') ?? 0).toInt().toString();
    final price = 'NPR $priceStr';
    
    // Handle vendor - could be string or object
    String vendor = 'Unknown Vendor';
    final vendorData = product['vendor_name'] ?? product['vendor'];
    if (vendorData is String) {
      vendor = vendorData;
    } else if (vendorData is Map && vendorData['name'] != null) {
      vendor = vendorData['name'].toString();
    }
    
    // Handle distance - calculate dynamically like home screen
    final distance = DeliveryFilterService().userPosition != null
        ? '${LocationService().calculateDistance(
            DeliveryFilterService().userPosition!.latitude,
            DeliveryFilterService().userPosition!.longitude,
            product['vendor_latitude'] ?? 0.0,
            product['vendor_longitude'] ?? 0.0,
          ).toStringAsFixed(1)} km'
        : 'Location required';
    
    // Handle delivery fee
    final deliveryInfo = getDeliveryInfo(product, null);
    final deliveryFee = deliveryInfo['isFreeDelivery'] == true 
        ? 'Free' 
        : 'NPR ${deliveryInfo['deliveryFee']?.toInt() ?? '0'}';
    
    // Handle category - could be string or object
    String category = '';
    final categoryData = product['category'];
    if (categoryData is String) {
      category = categoryData;
    } else if (categoryData is Map && categoryData['name'] != null) {
      category = categoryData['name'].toString();
    }
    
    final description = product['description']?.toString() ?? '';
    final stock = product['quantity'] is int ? product['quantity'] as int : 0;
    final soldCount = product['sold_quantity']?.toString() ?? '0';
    final rating = product['average_rating']?.toString() ?? '0.0';
    final productId = product['id'] is int ? product['id'] as int : null;
    final vendorId = product['vendor_id'] is int ? product['vendor_id'] as int : null;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(
              productId: productId,
              images: productImages,
              restaurant: vendor,
              itemName: title,
              rating: rating,
              distance: distance,
              soldCount: soldCount,
              price: price,
              deliveryFee: deliveryFee,
              description: description,
              stock: stock,
              category: category,
              vendorId: vendorId,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Image.network(
                      imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(height: 120, width: double.infinity, color: Colors.grey[800], child: const Icon(Icons.image_not_supported, color: Colors.white54)),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                              // Add to cart logic for related product
                              if (productId == null) return;
                              final auth = Provider.of<AuthService>(context, listen: false);
                               if (!auth.isLoggedIn) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login to add to cart')));
                                return;
                              }
                              try {
                                await CartService().addToCart(auth.token!, productId, 1);
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to cart'), backgroundColor: AppTheme.primaryColor));
                              } catch (_) {}
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.shopping_cart, color: AppTheme.primaryColor, size: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                         GestureDetector(
                          onTap: () => _buyRelatedProduct(product),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.shopping_bag, color: Colors.black, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: const Color(0xFFA1A1AA),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.directions_car, color: AppTheme.primaryColor, size: 10),
                        const SizedBox(width: 4),
                        Text(
                          deliveryFee,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10, color: Colors.white),
                        ),
                        const SizedBox(width: 4),
                        const Text('•', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 10)),
                        const SizedBox(width: 4),
                        const Icon(Icons.location_on, color: Color(0xFFA1A1AA), size: 10),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            distance,
                            style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFFA1A1AA)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      price,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),

                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, {Color? background, Color? iconColor}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: background ?? Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: iconColor ?? AppTheme.primaryColor, size: 16),
    );
  }

  String _stripHtml(String htmlString) {
    final exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlString.replaceAll(exp, '');
  }
}
