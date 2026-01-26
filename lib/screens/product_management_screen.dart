// lib/screens/product_management_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import '../config.dart' as appConfig;
import 'add_product_screen.dart';
import '../widgets/edit_product_dialog.dart';
import '../widgets/safe_network_image.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() => _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  int _currentPage = 1;
  final int _pageSize = 20;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMoreData) {
        _loadMoreProducts();
      }
    }
  }

  Future<void> _fetchProducts({bool isRefresh = false}) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    if (isRefresh) {
      if (mounted) {
        setState(() {
          _currentPage = 1;
          _hasMoreData = true;
          _products.clear();
        });
      }
    }

    if (mounted) {
      setState(() => _isLoading = isRefresh || _currentPage == 1);
    }

    try {
      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/products/?page=$_currentPage&page_size=$_pageSize'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List productsList = [];
        
        if (data is Map<String, dynamic>) {
          productsList = data['results'] ?? data['data'] ?? [];
          // Check if there's more data
          _hasMoreData = data['next'] != null;
        } else if (data is List) {
          productsList = data;
          _hasMoreData = productsList.length == _pageSize;
        }

        if (mounted) {
          setState(() {
            if (isRefresh || _currentPage == 1) {
              _products = productsList.cast<Map<String, dynamic>>();
            } else {
              _products.addAll(productsList.cast<Map<String, dynamic>>());
            }
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreProducts() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null || _isLoadingMore || !_hasMoreData) return;

    if (mounted) {
      setState(() => _isLoadingMore = true);
    }

    try {
      final nextPage = _currentPage + 1;
      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/products/?page=$nextPage&page_size=$_pageSize'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List productsList = [];
        
        if (data is Map<String, dynamic>) {
          productsList = data['results'] ?? data['data'] ?? [];
          _hasMoreData = data['next'] != null;
        } else if (data is List) {
          productsList = data;
          _hasMoreData = productsList.length == _pageSize;
        }

        if (mounted) {
          setState(() {
            _products.addAll(productsList.cast<Map<String, dynamic>>());
            _currentPage = nextPage;
            _isLoadingMore = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingMore = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    var filtered = _products;
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((p) => 
          (p['name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    
    // Apply status filter
    switch (_selectedFilter) {
      case 'active':
        filtered = filtered.where((p) => p['status'] == 'active').toList();
        break;
      case 'draft':
        filtered = filtered.where((p) => p['status'] == 'draft').toList();
        break;
      case 'featured':
        filtered = filtered.where((p) => p['featured'] == true).toList();
        break;
      case 'low_stock':
        filtered = filtered.where((p) => (p['quantity'] ?? 0) < 10).toList();
        break;
    }
    
    return filtered;
  }

  void _showEditDialog(Map<String, dynamic> product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditProductDialog(
        product: product,
        onProductUpdated: () {
          Navigator.pop(context);
          _fetchProducts();
        },
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Product', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${product['name']}"? This action cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteProduct(product);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      final response = await http.delete(
        Uri.parse('${appConfig.Config.baseUrl}/products/${product['id']}/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        _showSnackBar('Product deleted successfully');
        await _fetchProducts();
      } else {
        _showSnackBar('Failed to delete product', isError: true);
      }
    } catch (e) {
      _showSnackBar('Failed to delete product', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : const Color(0xFFFFD60A),
          behavior: SnackBarBehavior.fixed, // Changed to fixed to avoid pushing FAB
          margin: EdgeInsets.zero,
        ),
      );
    }
  }

  void _showProductDetails(Map<String, dynamic> product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Product Details',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close', style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildProductDetailsContent(product),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductDetailsContent(Map<String, dynamic> product) {
    final List<Map<String, dynamic>> rawImages = List<Map<String, dynamic>>.from(product['images'] ?? []);
    final Set<String> seenUrls = {};
    final List<Map<String, dynamic>> images = [];
    
    for (var img in rawImages) {
      String url = (img['image_url'] ?? img['image'] ?? '').toString();
      if (url.isEmpty) continue;
      if (!url.startsWith('http')) {
        url = '${appConfig.Config.mediaUrl}${url.startsWith('/') ? '' : '/'}$url';
      }
      if (!seenUrls.contains(url)) {
        seenUrls.add(url);
        final newImg = Map<String, dynamic>.from(img);
        newImg['image_url'] = url;
        images.add(newImg);
      }
    }
    
    final dynamicFields = product['dynamic_fields'] as Map<String, dynamic>? ?? {};
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product Images
        if (images.isNotEmpty) ...[
          const Text('Product Images', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              itemBuilder: (context, index) {
                final image = images[index];
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SafeNetworkImage(
                      imageUrl: image['image_url'] ?? '',
                      fit: BoxFit.cover,
                      placeholder: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      errorWidget: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Product Info
        _buildDetailRow('Product Name', product['name'] ?? 'N/A'),
        _buildDetailRow('Selling Price', 'Rs ${product['price'] ?? '0.00'}'),
        _buildDetailRow('Stock Quantity', '${product['quantity'] ?? 0}'),
        _buildDetailRow('Category', product['category'] ?? 'N/A'),
        _buildDetailRow('Subcategory', product['subcategory'] ?? 'N/A'),
        if (product['cost_price'] != null)
          _buildDetailRow('Cost Price', 'Rs ${product['cost_price']}'),
        if (product['sku'] != null)
          _buildDetailRow('SKU', product['sku']),
        _buildDetailRow('Status', (product['status'] ?? 'active').toUpperCase()),

        const SizedBox(height: 16),
        
        // Description
        if (product['description'] != null) ...[
          const Text('Description', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _stripHtmlTags(product['description']),
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Delivery Info
        Row(
          children: [
            if (product['free_delivery'] == true)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Free Delivery', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            if (product['custom_delivery_fee_enabled'] == true && product['custom_delivery_fee'] != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Delivery Fee: Rs ${product['custom_delivery_fee']}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Product Parameters
        if (dynamicFields.isNotEmpty) ...[
          const Text('Product Parameters', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...dynamicFields.entries.map((entry) {
            final value = entry.value is List 
                ? (entry.value as List).join(', ')
                : entry.value.toString();
            return _buildDetailRow(entry.key.toUpperCase(), value);
          }),
          const SizedBox(height: 16),
        ],

        // Sales Info
        _buildDetailRow('Total Sold', '${product['total_sold'] ?? 0} units'),
        _buildDetailRow('Created', _formatDate(product['created_at'])),
        _buildDetailRow('Updated', _formatDate(product['updated_at'])),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stripHtmlTags(String htmlString) {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlString.replaceAll(exp, '');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: Text(
          'Product Management',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddProductScreen()),
              ).then((result) {
                if (result == true) {
                  _fetchProducts(isRefresh: true);
                }
              });
            },
            icon: const Icon(Icons.add, color: Color(0xFFFFD60A)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD60A)))
          : Column(
              children: [
                // Search and Filter Bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Search Bar
                      TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _searchQuery = value),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search products...',
                          hintStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF1E1E1E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', 'all'),
                            _buildFilterChip('Active', 'active'),
                            _buildFilterChip('Draft', 'draft'),
                            _buildFilterChip('Featured', 'featured'),
                            _buildFilterChip('Low Stock', 'low_stock'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Products List
                Expanded(
                  child: RefreshIndicator(
                    color: const Color(0xFFFFD60A),
                    backgroundColor: const Color(0xFF1E1E1E),
                    onRefresh: () => _fetchProducts(isRefresh: true),
                    child: _isLoading 
                      ? _buildSkeletonList()
                      : _filteredProducts.isEmpty
                        ? const Center(
                            child: Text(
                              'No products found',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: _filteredProducts.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _filteredProducts.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(color: Color(0xFFFFD60A)),
                                  ),
                                );
                              }
                              return _buildProductCard(_filteredProducts[index]);
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) => setState(() => _selectedFilter = value),
        backgroundColor: const Color(0xFF1E1E1E),
        selectedColor: const Color(0xFFFFD60A),
        labelStyle: TextStyle(
          color: isSelected ? Colors.black : Colors.white,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(
          color: isSelected ? const Color(0xFFFFD60A) : Colors.grey[600]!,
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final name = product['name'] ?? 'Product';
    final price = product['price'] ?? '0.00';
    final quantity = product['quantity'] ?? 0;
    final totalSold = product['total_sold'] ?? 0;
    final imageUrl = product['images']?.isNotEmpty == true 
        ? product['images'][0]['image_url'] 
        : 'https://via.placeholder.com/150';
    final featured = product['featured'] == true;
    final status = product['status'] ?? 'active';

    return GestureDetector(
      onTap: () => _showProductDetails(product),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: featured ? const Color(0xFFFFD60A).withOpacity(0.3) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Product Image
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF2C2C2C),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SafeNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      color: const Color(0xFF2C2C2C),
                      child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (featured)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD60A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'FEATURED',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'NPR $price',
                      style: const TextStyle(
                        color: Color(0xFFFFD60A),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Stock: $quantity',
                          style: TextStyle(
                            color: quantity > 0 ? Colors.green : Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Sold: $totalSold',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _getStatusColor(status).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _showEditDialog(product),
                        icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        onPressed: () => _showDeleteDialog(product),
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (context, index) => _buildSkeletonCard(),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Image Placeholder
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          // Info Placeholder
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 140,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 50,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Status Placeholder
          Container(
            width: 60,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'draft':
        return Colors.orange;
      case 'archived':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}