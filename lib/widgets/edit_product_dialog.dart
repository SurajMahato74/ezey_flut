import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../config.dart' as appConfig;
// SafeNetworkImage is in widgets/ but wait where is it?

class EditProductDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final VoidCallback onProductUpdated;

  const EditProductDialog({
    super.key,
    required this.product,
    required this.onProductUpdated,
  });

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _quantityController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _skuController = TextEditingController();
  
  // Form values
  String? _selectedCategory;
  String? _selectedSubcategory;
  List<String> _availableCategories = [];
  List<String> _availableSubcategories = [];
  List<String> _tags = [];
  final List<XFile> _newImages = [];
  List<Map<String, dynamic>> _existingImages = [];
  Map<String, dynamic> _dynamicFields = {};
  List<Map<String, dynamic>> _categoryParameters = [];
  List<Map<String, dynamic>> _subcategoryParameters = [];
  
  bool _freeDelivery = false;
  bool _customDeliveryEnabled = false;
  bool _isLoading = false;
  String _selectedStatus = 'active';
  
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeForm();
    _fetchCategories();
  }

  void _initializeForm() {
    _nameController.text = widget.product['name'] ?? '';
    _priceController.text = widget.product['price']?.toString() ?? '';
    _costPriceController.text = widget.product['cost_price']?.toString() ?? '';
    _quantityController.text = widget.product['quantity']?.toString() ?? '';
    _deliveryFeeController.text = widget.product['custom_delivery_fee']?.toString() ?? '';
    _descriptionController.text = _stripHtmlTags(widget.product['description'] ?? '');
    _skuController.text = widget.product['sku'] ?? '';
    
    _selectedCategory = widget.product['category'];
    _selectedSubcategory = widget.product['subcategory'];
    _freeDelivery = widget.product['free_delivery'] == true;
    _customDeliveryEnabled = widget.product['custom_delivery_fee_enabled'] == true;
    _selectedStatus = widget.product['status'] ?? 'active';
    _tags = List<String>.from(widget.product['tags'] ?? []);
    _dynamicFields = Map<String, dynamic>.from(widget.product['dynamic_fields'] ?? {});
    
    // Deduplicate and Normalize Existing Images
    final List<Map<String, dynamic>> rawImages = List<Map<String, dynamic>>.from(widget.product['images'] ?? []);
    final Set<String> seenUrls = {};
    _existingImages = [];
    
    for (var img in rawImages) {
      String url = (img['image_url'] ?? img['image'] ?? '').toString();
      if (url.isEmpty) continue;
      if (!url.startsWith('http')) {
        url = 'https://ezeyway.com$url';
      }
      if (!seenUrls.contains(url)) {
        seenUrls.add(url);
        final newImg = Map<String, dynamic>.from(img);
        newImg['image_url'] = url;
        _existingImages.add(newImg);
      }
    }
  }

  String _stripHtmlTags(String htmlString) {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlString.replaceAll(exp, '');
  }

  Future<void> _fetchCategories() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/categories/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _availableCategories = (data['categories'] as List)
              .map((cat) => cat['name'].toString())
              .toList();
        });
        
        if (_selectedCategory != null) {
          _fetchSubcategories(_selectedCategory!);
          _fetchCategoryParameters(_selectedCategory!);
        }
      }
    } catch (e) {
      print('Error fetching categories: $e');
    }
  }

  Future<void> _fetchSubcategories(String categoryName) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/categories/${Uri.encodeComponent(categoryName)}/subcategories/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _availableSubcategories = List<String>.from(data['subcategories'] ?? []);
        });
        
        if (_selectedSubcategory != null) {
          _fetchSubcategoryParameters(_selectedSubcategory!);
        }
      }
    } catch (e) {
      print('Error fetching subcategories: $e');
    }
  }

  Future<void> _fetchCategoryParameters(String categoryName) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      final categoriesResponse = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/categories/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (categoriesResponse.statusCode == 200) {
        final categoriesData = jsonDecode(categoriesResponse.body);
        final category = (categoriesData['categories'] as List)
            .firstWhere((cat) => cat['name'] == categoryName, orElse: () => null);
        
        if (category != null) {
          final response = await http.get(
            Uri.parse('${appConfig.Config.baseUrl}/accounts/categories/parameters/?target_id=${category['id']}&target_type=category'),
            headers: {
              'Authorization': 'Token $token',
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            setState(() {
              _categoryParameters = List<Map<String, dynamic>>.from(data['parameters'] ?? []);
            });
          }
        }
      }
    } catch (e) {
      print('Error fetching category parameters: $e');
    }
  }

  Future<void> _fetchSubcategoryParameters(String subcategoryName) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      final subcategoryIndex = _availableSubcategories.indexOf(subcategoryName);
      if (subcategoryIndex == -1) return;

      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/accounts/categories/parameters/?target_id=${subcategoryIndex + 1}&target_type=subcategory'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _subcategoryParameters = List<Map<String, dynamic>>.from(data['parameters'] ?? []);
        });
      }
    } catch (e) {
      print('Error fetching subcategory parameters: $e');
    }
  }

  Future<void> _pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _newImages.addAll(images);
      });
    }
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  Future<void> _removeExistingImage(int index) async {
    final image = _existingImages[index];
    final imageId = image['id'];
    final productId = widget.product['id'];

    if (imageId == null || productId == null) {
      setState(() => _existingImages.removeAt(index));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Delete Image', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this image permanently?', style: GoogleFonts.plusJakartaSans(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.plusJakartaSans(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      if (token == null) return;

      await ApiService().deleteProductImage(token, productId, imageId);
      
      setState(() {
        _existingImages.removeAt(index);
      });
      _showSnackBar('Image deleted successfully', const Color(0xFFFFD60A));
    } catch (e) {
      _showSnackBar('Error deleting image: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      if (token == null) return;

      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('${appConfig.Config.baseUrl}/products/${widget.product['id']}/'),
      );

      request.headers.addAll({
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      });

      // Add form fields
      request.fields['name'] = _nameController.text;
      request.fields['category'] = _selectedCategory!;
      if (_selectedSubcategory != null) {
        request.fields['subcategory'] = _selectedSubcategory!;
      }
      request.fields['price'] = _priceController.text;
      if (_costPriceController.text.isNotEmpty) {
        request.fields['cost_price'] = _costPriceController.text;
      }
      if (_skuController.text.isNotEmpty) {
        request.fields['sku'] = _skuController.text;
      }
      request.fields['quantity'] = _quantityController.text;
      request.fields['description'] = _descriptionController.text;
      request.fields['tags'] = jsonEncode(_tags);
      request.fields['status'] = _selectedStatus;
      request.fields['free_delivery'] = _freeDelivery.toString();
      request.fields['custom_delivery_fee_enabled'] = _customDeliveryEnabled.toString();
      
      if (_customDeliveryEnabled && _deliveryFeeController.text.isNotEmpty) {
        request.fields['custom_delivery_fee'] = _deliveryFeeController.text;
      }
      
      request.fields['dynamic_fields'] = jsonEncode(_dynamicFields);
      
      // Send existing image IDs to keep
      final keepImageIds = _existingImages.map((img) => img['id'].toString()).toList();
      request.fields['keep_image_ids'] = jsonEncode(keepImageIds);

      // Add new images
      for (int i = 0; i < _newImages.length; i++) {
        final bytes = await _newImages[i].readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'image_files',
            bytes,
            filename: _newImages[i].name,
          ),
        );
      }

      final response = await request.send();

      if (response.statusCode == 200) {
        widget.onProductUpdated();
        _showSnackBar('Product updated successfully!', const Color(0xFFFFD60A));
      } else {
        _showSnackBar('Failed to update product', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error updating product: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costPriceController.dispose();
    _quantityController.dispose();
    _deliveryFeeController.dispose();
    _descriptionController.dispose();
    _skuController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
                    'Edit Product',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBasicInfoSection(),
                    const SizedBox(height: 24),
                    if (_categoryParameters.isNotEmpty) ...[ 
                      _buildCategoryParametersSection(),
                      const SizedBox(height: 24),
                    ],
                    if (_subcategoryParameters.isNotEmpty) ...[
                      _buildSubcategoryParametersSection(), 
                      const SizedBox(height: 24),
                    ],
                    _buildPricingSection(),
                    const SizedBox(height: 24),
                    _buildImagesSection(),
                    const SizedBox(height: 24),
                    _buildDetailsSection(),
                    const SizedBox(height: 24),
                    _buildTagsSection(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border: Border(top: BorderSide(color: Color(0xFF4D4D4D), width: 1)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateProduct,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD60A),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                        'Update Product',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Basic Information',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFFFD60A),
          ),
        ),
        const SizedBox(height: 12),
        _buildFormField(
          label: 'Product Name*',
          controller: _nameController,
          hint: 'Enter product name',
          validator: (value) => value?.isEmpty == true ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category*',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFA9A9A9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF4D4D4D)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _availableCategories.contains(_selectedCategory) ? _selectedCategory : null,
                        isExpanded: true,
                        onChanged: null, // Make read-only
                        disabledHint: _selectedCategory != null 
                          ? Text(_selectedCategory!, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white))
                          : null,
                        items: _availableCategories.map((String category) {
                          return DropdownMenuItem<String>(
                            value: category,
                            child: Text(
                              category,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }).toList(),
                        dropdownColor: const Color(0xFF2C2C2C),
                        iconEnabledColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_availableSubcategories.isNotEmpty) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Subcategory',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFA9A9A9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF4D4D4D)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _availableSubcategories.contains(_selectedSubcategory) ? _selectedSubcategory : null,
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedSubcategory = newValue;
                              _subcategoryParameters.clear();
                            });
                            if (newValue != null) {
                              _fetchSubcategoryParameters(newValue);
                            }
                          },
                          items: _availableSubcategories.map((String subcategory) {
                            return DropdownMenuItem<String>(
                              value: subcategory,
                              child: Text(
                                subcategory,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }).toList(),
                          dropdownColor: const Color(0xFF2C2C2C),
                          iconEnabledColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                label: 'SKU',
                controller: _skuController,
                hint: 'Product SKU',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFA9A9A9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF4D4D4D)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedStatus,
                        isExpanded: true,
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedStatus = newValue!;
                          });
                        },
                        items: ['active', 'draft', 'archived'].map((String status) {
                          return DropdownMenuItem<String>(
                            value: status,
                            child: Text(
                              status.toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }).toList(),
                        dropdownColor: const Color(0xFF2C2C2C),
                        iconEnabledColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Images',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFFFD60A),
          ),
        ),
        const SizedBox(height: 12),
        
        // Existing Images
        if (_existingImages.isNotEmpty) ...[
          Text(
            'Current Images',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _existingImages.length,
              itemBuilder: (context, index) {
                final image = _existingImages[index];
                return Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 12),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          image['image_url'],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.image, color: Colors.grey, size: 24),
                        ),
                      ),
                      Positioned(
                        top: -2,
                        right: -2,
                        child: GestureDetector(
                          onTap: () => _removeExistingImage(index),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        GestureDetector(
          onTap: _pickImages,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFF4D4D4D),
                width: 2,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF2C2C2C),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.add_photo_alternate,
                  color: Color(0xFFFFD60A),
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  'Add More Images',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // New Images
        if (_newImages.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'New Images',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _newImages.length,
              itemBuilder: (context, index) {
                return Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 12),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: kIsWeb 
                          ? Image.network(
                              _newImages[index].path,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            )
                          : FutureBuilder<Uint8List>(
                              future: _newImages[index].readAsBytes(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  return Image.memory(
                                    snapshot.data!,
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  );
                                }
                                return Container(
                                  width: 80,
                                  height: 80,
                                  color: const Color(0xFF3A3A3A),
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              },
                            ),
                      ),
                      Positioned(
                        top: -2,
                        right: -2,
                        child: GestureDetector(
                          onTap: () => _removeNewImage(index),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Description',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFFFD60A),
          ),
        ),
        const SizedBox(height: 12),
        _buildFormField(
          label: 'Product Description*',
          controller: _descriptionController,
          hint: 'Enter a detailed description of the product...',
          maxLines: 4,
          validator: (value) => value?.isEmpty == true ? 'Required' : null,
        ),
      ],
    );
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Tags',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFFFD60A),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _tagController,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
                decoration: _getInputDecoration('Add a tag'),
                onFieldSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _addTag,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD60A),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Icon(Icons.add, size: 20),
              ),
            ),
          ],
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags.map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2C),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF4D4D4D)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tag,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _removeTag(tag),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
      ],
    );
  }

  InputDecoration _getInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        color: const Color(0xFFA9A9A9),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4D4D4D)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4D4D4D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFFD60A), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFFA9A9A9),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: Colors.white,
          ),
          decoration: _getInputDecoration(hint),
        ),
      ],
    );
  }

  Widget _buildCategoryParametersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category Details',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFFFD60A),
          ),
        ),
        const SizedBox(height: 12),
        ..._categoryParameters.map((param) => _buildParameterField(param)),
      ],
    );
  }

  Widget _buildSubcategoryParametersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subcategory Details',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFFFD60A),
          ),
        ),
        const SizedBox(height: 12),
        ..._subcategoryParameters.map((param) => _buildParameterField(param)),
      ],
    );
  }

  Widget _buildParameterField(Map<String, dynamic> param) {
    final fieldName = param['name'];
    final fieldType = param['field_type'];
    final label = param['label'] ?? fieldName;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFA9A9A9),
            ),
          ),
          const SizedBox(height: 8),
          _buildParameterInput(param),
        ],
      ),
    );
  }

  Widget _buildParameterInput(Map<String, dynamic> param) {
    final fieldName = param['name'];
    final fieldType = param['field_type'];
    final options = param['options'] as List?;
    
    switch (fieldType) {
      case 'text':
        return TextFormField(
          initialValue: _dynamicFields[fieldName]?.toString() ?? '',
          onChanged: (value) => _dynamicFields[fieldName] = value,
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
          decoration: _getInputDecoration(param['placeholder'] ?? 'Enter $fieldName'),
        );
      case 'number':
        return TextFormField(
          initialValue: _dynamicFields[fieldName]?.toString() ?? '',
          keyboardType: TextInputType.number,
          onChanged: (value) => _dynamicFields[fieldName] = double.tryParse(value),
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
          decoration: _getInputDecoration(param['placeholder'] ?? 'Enter $fieldName'),
        );
      case 'select':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF4D4D4D)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _dynamicFields[fieldName],
              isExpanded: true,
              onChanged: (value) => setState(() => _dynamicFields[fieldName] = value),
              items: options?.map((option) => DropdownMenuItem<String>(
                value: option.toString(),
                child: Text(option.toString(), style: const TextStyle(color: Colors.white)),
              )).toList() ?? [],
              dropdownColor: const Color(0xFF2C2C2C),
              iconEnabledColor: Colors.white,
            ),
          ),
        );
      case 'boolean':
        return Row(
          children: [
            Switch(
              value: _dynamicFields[fieldName] == true,
              onChanged: (value) => setState(() => _dynamicFields[fieldName] = value),
              activeThumbColor: const Color(0xFFFFD60A),
            ),
            const SizedBox(width: 8),
            Text(
              _dynamicFields[fieldName] == true ? 'Yes' : 'No',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        );
      default:
        return TextFormField(
          initialValue: _dynamicFields[fieldName]?.toString() ?? '',
          onChanged: (value) => _dynamicFields[fieldName] = value,
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
          decoration: _getInputDecoration(param['placeholder'] ?? 'Enter $fieldName'),
        );
    }
  }

  Widget _buildPricingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pricing & Inventory',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFFFD60A),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                label: 'Selling Price* (NPR)',
                controller: _priceController,
                hint: 'e.g., 850',
                keyboardType: TextInputType.number,
                validator: (value) => value?.isEmpty == true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildFormField(
                label: 'Cost Price (NPR)',
                controller: _costPriceController,
                hint: 'e.g., 600',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildFormField(
          label: 'Quantity*',
          controller: _quantityController,
          hint: 'e.g., 50',
          keyboardType: TextInputType.number,
          validator: (value) => value?.isEmpty == true ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Free Delivery',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  Switch(
                    value: _freeDelivery,
                    onChanged: (value) {
                      setState(() {
                        _freeDelivery = value;
                        if (value) _customDeliveryEnabled = false;
                      });
                    },
                    activeThumbColor: const Color(0xFFFFD60A),
                  ),
                ],
              ),
              if (!_freeDelivery) ...[
                const Divider(color: Color(0xFF4D4D4D)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Custom Delivery Fee',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    Switch(
                      value: _customDeliveryEnabled,
                      onChanged: (value) {
                        setState(() {
                          _customDeliveryEnabled = value;
                        });
                      },
                      activeThumbColor: const Color(0xFFFFD60A),
                    ),
                  ],
                ),
                if (_customDeliveryEnabled) ...[
                  const SizedBox(height: 12),
                  _buildFormField(
                    label: 'Delivery Fee Amount (NPR)',
                    controller: _deliveryFeeController,
                    hint: 'Enter delivery fee',
                    keyboardType: TextInputType.number,
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}