import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/auth_service.dart';
import '../config.dart' as appConfig;
import '../theme/app_theme.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
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
  final List<String> _tags = [];
  final List<XFile> _selectedImages = [];
  final Map<String, dynamic> _dynamicFields = {};
  List<Map<String, dynamic>> _categoryParameters = [];
  List<Map<String, dynamic>> _subcategoryParameters = [];
  
  bool _freeDelivery = false;
  bool _customDeliveryEnabled = false;
  bool _isLoading = false;
  bool _loadingCategories = true;
  bool _loadingSubcategories = false;
  final bool _loadingParameters = false;
  
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchVendorProfile();
  }

  Future<void> _fetchVendorProfile() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    setState(() => _loadingCategories = true);

    try {
      // Fetch categories
      final categoriesResponse = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/categories/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      // Fetch vendor profile
      final profileResponse = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (categoriesResponse.statusCode == 200 && profileResponse.statusCode == 200) {
        final categoriesData = jsonDecode(categoriesResponse.body);
        final profileData = jsonDecode(profileResponse.body);
        
        List<String> vendorCategories = [];
        if (profileData['results']?.isNotEmpty == true) {
          vendorCategories = List<String>.from(profileData['results'][0]['categories'] ?? []);
        }
        
        List<String> allCategories = [];
        if (categoriesData['categories'] != null) {
          allCategories = (categoriesData['categories'] as List)
              .map((cat) => cat['name'].toString())
              .toList();
        }
        
        setState(() {
          _availableCategories = vendorCategories.isNotEmpty ? vendorCategories : allCategories;
          if (_availableCategories.isNotEmpty) {
            _selectedCategory = _availableCategories.first;
            _fetchSubcategories(_selectedCategory!);
          }
          _loadingCategories = false;
        });
      }
    } catch (e) {
      setState(() => _loadingCategories = false);
    }
  }

  Future<void> _fetchSubcategories(String categoryName) async {
    setState(() => _loadingSubcategories = true);
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      if (token == null) return;

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
          _selectedSubcategory = _availableSubcategories.isNotEmpty ? _availableSubcategories.first : null;
          _loadingSubcategories = false;
        });
        
        _fetchCategoryParameters(categoryName);
        if (_selectedSubcategory != null) {
          _fetchSubcategoryParameters(_selectedSubcategory!);
        }
      }
    } catch (e) {
      setState(() => _loadingSubcategories = false);
    }
  }

  Future<void> _fetchCategoryParameters(String categoryName) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      if (token == null) return;

      // Get category ID first
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
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      if (token == null) return;

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
        _selectedImages.addAll(images);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
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

  Future<void> _addProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategory == null) {
      _showSnackBar('Please select a category', Colors.red);
      return;
    }

    if (_selectedImages.isEmpty) {
      _showSnackBar('Please upload at least one product image', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      if (token == null) return;

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${appConfig.Config.baseUrl}/products/'),
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
      request.fields['status'] = 'active';
      request.fields['featured'] = 'false';
      request.fields['free_delivery'] = _freeDelivery.toString();
      request.fields['custom_delivery_fee_enabled'] = _customDeliveryEnabled.toString();
      
      if (_customDeliveryEnabled && _deliveryFeeController.text.isNotEmpty) {
        request.fields['custom_delivery_fee'] = _deliveryFeeController.text;
      }
      
      request.fields['dynamic_fields'] = jsonEncode(_dynamicFields);

      // Add images
      for (int i = 0; i < _selectedImages.length; i++) {
        final bytes = await _selectedImages[i].readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'image_files',
            bytes,
            filename: _selectedImages[i].name,
          ),
        );
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        Navigator.pop(context, true); // Return true on success
        _showSnackBar('Product added successfully! 🎉', AppTheme.primaryColor);
      } else {
        final errorData = jsonDecode(responseBody);
        _showSnackBar('Failed to add product: ${errorData.toString()}', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error adding product: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.red ? Icons.error : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD60A)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // App Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              decoration: const BoxDecoration(
                color: AppTheme.homeBackgroundDark,
                border: Border(
                  bottom: BorderSide(color: Color(0xFF4D4D4D), width: 1),
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Add New Product',
                        textAlign: TextAlign.left,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImagesSection(),
                    const SizedBox(height: 24),
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
                    _buildDetailsSection(),
                    const SizedBox(height: 24),
                    _buildTagsSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // Bottom Button
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          border: Border(
            top: BorderSide(color: Color(0xFF4D4D4D), width: 1),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _addProduct,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD60A),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.black)
                : Text(
                    'Add Product',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // Images Section
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
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4D4D4D),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_photo_alternate,
                    color: Color(0xFFFFD60A),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Click to upload images',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You can add multiple images',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFFA9A9A9),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 84,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
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
                              _selectedImages[index].path,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            )
                          : FutureBuilder<Uint8List>(
                              future: _selectedImages[index].readAsBytes(),
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
                          onTap: () => _removeImage(index),
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
                      if (index == 0)
                        Positioned(
                          bottom: 2,
                          left: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD60A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Main',
                              style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
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

  // Basic Information Section
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
          hint: 'e.g., Organic Raw Honey',
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter product name';
            }
            return null;
          },
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
                      color: Colors.transparent,
                      border: Border.all(color: const Color(0xFF4D4D4D)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _loadingCategories
                        ? const Text('Loading...', style: TextStyle(color: Colors.grey))
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedCategory,
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
                        color: Colors.transparent,
                        border: Border.all(color: const Color(0xFF4D4D4D)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _loadingSubcategories
                          ? const Text('Loading...', style: TextStyle(color: Colors.grey))
                          : DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedSubcategory,
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
        _buildFormField(
          label: 'SKU (Optional)',
          controller: _skuController,
          hint: 'e.g., HON-ORG-500',
        ),
      ],
    );
  }

  // Category Parameters Section
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

  // Subcategory Parameters Section
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

  // Parameter Field Builder
  Widget _buildParameterField(Map<String, dynamic> param) {
    final fieldName = param['name'];
    final fieldType = param['field_type'];
    final label = param['label'] ?? fieldName;
    final isRequired = param['is_required'] == true;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label${isRequired ? '*' : ''}',
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
          onChanged: (value) => _dynamicFields[fieldName] = value,
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
          decoration: _getInputDecoration(param['placeholder'] ?? 'Enter $fieldName'),
        );
      case 'number':
        return TextFormField(
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
          onChanged: (value) => _dynamicFields[fieldName] = value,
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
          decoration: _getInputDecoration(param['placeholder'] ?? 'Enter $fieldName'),
        );
    }
  }
  // Pricing & Inventory Section
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
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter selling price';
                  }
                  return null;
                },
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
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter quantity';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        // Delivery Options
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

  // Tags Section
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
  // Details Section
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
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter product description';
            }
            return null;
          },
        ),
      ],
    );
  }

  // Helper method for input decoration
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

  // Reusable Form Field
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
}