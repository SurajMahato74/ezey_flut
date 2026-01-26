import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class VendorProfileCompletionScreen extends StatefulWidget {
  const VendorProfileCompletionScreen({super.key});

  @override
  State<VendorProfileCompletionScreen> createState() => _VendorProfileCompletionScreenState();
}

class _VendorProfileCompletionScreenState extends State<VendorProfileCompletionScreen> {
  int _currentStep = 0;
  final PageController _pageController = PageController();
  bool _isLoading = false;
  
  // Controllers
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _panController = TextEditingController();
  final TextEditingController _accountNumberController = TextEditingController();
  final TextEditingController _accountHolderController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _ifscController = TextEditingController();
  final TextEditingController _gstController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _referralCodeController = TextEditingController();
  
  // Files
  final List<XFile> _shopImages = [];
  XFile? _panDocument;
  XFile? _citizenshipFront;
  XFile? _citizenshipBack;
  final ImagePicker _picker = ImagePicker();
  
  // Business Type
  String? _selectedBusinessType;
  final Map<String, String> _businessTypes = {
    'retailer': 'Retailer',
    'wholesaler': 'Wholesaler',
    'manufacturer': 'Manufacturer',
    'service_provider': 'Service Provider',
    'grocery': 'Grocery Store',
    'restaurant': 'Restaurant',
    'pharmacy': 'Pharmacy',
    'electronics': 'Electronics',
    'clothing': 'Clothing',
    'bakery': 'Bakery',
  };
  
  // Categories
  final List<String> _allCategories = [
    'Food & Beverages',
    'Electronics',
    'Clothing',
    'Groceries',
    'Home & Kitchen',
    'Beauty & Personal Care',
    'Sports & Fitness',
    'Books & Stationery',
  ];
  String? _selectedCategory;
  
  double _latitude = 27.7172;
  double _longitude = 85.3240;
  bool _isLoadingLocation = false;
  final MapController _mapController = MapController();
  LatLng? _selectedLocation;

  @override
  void dispose() {
    _pageController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _shopNameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _panController.dispose();
    _accountNumberController.dispose();
    _accountHolderController.dispose();
    _bankNameController.dispose();
    _ifscController.dispose();
    _gstController.dispose();
    _descriptionController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  Future<void> _onMapTap(TapPosition tapPosition, LatLng position) async {
    setState(() {
      _latitude = position.latitude;
      _longitude = position.longitude;
      _selectedLocation = position;
    });

    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] ?? {};
        
        setState(() {
          String road = address['road'] ?? '';
          String neighbourhood = address['neighbourhood'] ?? '';
          String suburb = address['suburb'] ?? '';
          
          String streetAddress = road.isNotEmpty ? road : (neighbourhood.isNotEmpty ? neighbourhood : suburb);
          
          _addressController.text = streetAddress.isNotEmpty ? streetAddress : 'Selected Location';
          _cityController.text = address['city'] ?? address['town'] ?? address['village'] ?? 'Kathmandu';
          _stateController.text = address['state'] ?? 'Bagmati';
          _pincodeController.text = address['postcode'] ?? '';
        });
      }
    } catch (e) {
      print('Reverse geocode error: $e');
    }
  }

  Future<void> _pickImage(ImageSource source, Function(XFile) onPicked) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      onPicked(image);
    }
  }

  Future<void> _pickMultipleImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty && _shopImages.length + images.length <= 10) {
      setState(() {
        _shopImages.addAll(images);
      });
    }
  }

  void _nextStep() {
    if (_currentStep < 6) {
      setState(() => _currentStep++);
      _pageController.animateToPage(_currentStep, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _submitProfile();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.animateToPage(_currentStep, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Future<void> _submitProfile() async {
    if (_shopImages.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least 4 shop images'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = AuthService().token;
      if (token == null) throw Exception('Not authenticated');

      List<http.MultipartFile> shopImageFiles = [];
      for (var i = 0; i < _shopImages.length; i++) {
        final bytes = await _shopImages[i].readAsBytes();
        shopImageFiles.add(http.MultipartFile.fromBytes(
          'shop_image_$i',
          bytes,
          filename: _shopImages[i].name,
        ));
      }

      http.MultipartFile? panDocFile;
      if (_panDocument != null) {
        final bytes = await _panDocument!.readAsBytes();
        panDocFile = http.MultipartFile.fromBytes(
          'business_license_file',
          bytes,
          filename: _panDocument!.name,
        );
      }

      http.MultipartFile? citizenshipFrontFile;
      if (_citizenshipFront != null) {
        final bytes = await _citizenshipFront!.readAsBytes();
        citizenshipFrontFile = http.MultipartFile.fromBytes(
          'citizenship_front',
          bytes,
          filename: _citizenshipFront!.name,
        );
      }

      http.MultipartFile? citizenshipBackFile;
      if (_citizenshipBack != null) {
        final bytes = await _citizenshipBack!.readAsBytes();
        citizenshipBackFile = http.MultipartFile.fromBytes(
          'citizenship_back',
          bytes,
          filename: _citizenshipBack!.name,
        );
      }

      final data = <String, dynamic>{
        'business_name': _shopNameController.text,
        'owner_name': _ownerNameController.text,
        'business_email': _emailController.text,
        'business_phone': _phoneController.text,
        'business_address': _addressController.text,
        'location_address': _addressController.text,
        'city': _cityController.text,
        'state': _stateController.text,
        'latitude': _latitude.toString(),
        'longitude': _longitude.toString(),
        'business_type': _selectedBusinessType ?? 'retailer',
        'categories': _selectedCategory != null ? [_selectedCategory!] : [],
        'pan_number': _panController.text,
        'account_number': _accountNumberController.text,
        'account_holder_name': _accountHolderController.text,
        'bank_name': _bankNameController.text,
        'delivery_radius': '5.0',
        'min_order_amount': '0',
        'delivery_fee': '0',
        'free_delivery_above': '0',
        'online_ordering': 'true',
        'home_delivery': 'true',
        'pickup_service': 'true',
        'bulk_orders': 'false',
        'subscription_service': 'false',
        'loyalty_program': 'false',
      };
      
      if (_pincodeController.text.isNotEmpty) data['pincode'] = _pincodeController.text;
      if (_gstController.text.isNotEmpty) data['gst_number'] = _gstController.text;
      if (_ifscController.text.isNotEmpty) data['ifsc_code'] = _ifscController.text;
      if (_descriptionController.text.isNotEmpty) data['description'] = _descriptionController.text;
      if (_referralCodeController.text.isNotEmpty) data['referral_code'] = _referralCodeController.text;

      await ApiService().completeVendorOnboarding(
        token: token,
        data: data,
        shopImages: shopImageFiles,
        panDoc: panDocFile,
        citizenshipFront: citizenshipFrontFile,
        citizenshipBack: citizenshipBackFile,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('Profile Submitted!', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 60),
              const SizedBox(height: 16),
              Text(
                'Your vendor profile has been submitted for approval.',
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You will be notified once admin approves your profile. Please check back later.',
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFFA1A1AA), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await AuthService().logout(context);
              },
              child: const Text('OK', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildLocationStep(),
                  _buildShopInfoStep(),
                  _buildDocumentsStep(),
                  _buildPaymentInfoStep(),
                  _buildBusinessTypeStep(),
                  _buildCategoriesStep(),
                  _buildPreviewStep(),
                ],
              ),
            ),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final steps = ['Location', 'Shop Info', 'Documents', 'Payment', 'Business', 'Categories', 'Preview'];
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Complete Your Profile', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('${_currentStep + 1}/7', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(7, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index < 6 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: index <= _currentStep ? AppTheme.primaryColor : const Color(0xFF27272A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(steps[_currentStep], style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFFA1A1AA))),
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _selectedLocation = LatLng(position.latitude, position.longitude);
      });
      
      _mapController.move(LatLng(position.latitude, position.longitude), 16);

      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] ?? {};
        
        setState(() {
          String road = address['road'] ?? '';
          String neighbourhood = address['neighbourhood'] ?? '';
          String suburb = address['suburb'] ?? '';
          
          String streetAddress = road.isNotEmpty ? road : (neighbourhood.isNotEmpty ? neighbourhood : suburb);
          
          _addressController.text = streetAddress.isNotEmpty ? streetAddress : 'Current Location';
          _cityController.text = address['city'] ?? address['town'] ?? address['village'] ?? 'Kathmandu';
          _stateController.text = address['state'] ?? 'Bagmati';
          _pincodeController.text = address['postcode'] ?? '';
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location fetched successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Widget _buildLocationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text('Store Location', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 8),
          Text('Tap on the map to select your store location', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFFA1A1AA))),
          const SizedBox(height: 16),
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF27272A)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(_latitude, _longitude),
                      initialZoom: 14,
                      minZoom: 5,
                      maxZoom: 18,
                      onTap: _onMapTap,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.ezeyway.app',
                      ),
                      if (_selectedLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedLocation!,
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_on, color: Color(0xFFF5EA47), size: 40),
                            ),
                          ],
                        ),
                    ],
                  ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.add, color: Colors.black87),
                            onPressed: () {
                              final zoom = _mapController.camera.zoom;
                              _mapController.move(_mapController.camera.center, zoom + 1);
                            },
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.remove, color: Colors.black87),
                            onPressed: () {
                              final zoom = _mapController.camera.zoom;
                              _mapController.move(_mapController.camera.center, zoom - 1);
                            },
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          ElevatedButton.icon(
            onPressed: _isLoadingLocation ? null : _getCurrentLocation,
            icon: _isLoadingLocation 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.my_location),
            label: Text(_isLoadingLocation ? 'Fetching Location...' : 'Use Current Location'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFF5EA47), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selected: ${_latitude.toStringAsFixed(6)}, ${_longitude.toStringAsFixed(6)}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFFA1A1AA)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(controller: _addressController, label: 'Street Address', hint: 'Enter your street address', icon: Icons.location_on_outlined),
          const SizedBox(height: 16),
          _buildTextField(controller: _cityController, label: 'City', hint: 'Enter city', icon: Icons.location_city_outlined),
          const SizedBox(height: 16),
          _buildTextField(controller: _stateController, label: 'State/Province', hint: 'Enter state or province', icon: Icons.map_outlined),
          const SizedBox(height: 16),
          _buildTextField(controller: _pincodeController, label: 'PIN Code', hint: 'Enter PIN code', icon: Icons.pin_outlined),
        ],
      ),
    );
  }

  Widget _buildShopInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text('Shop Information', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 24),
          Text('Shop Images (${_shopImages.length}/10)', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _pickMultipleImages,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Add Shop Images'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.black),
          ),
          const SizedBox(height: 12),
          if (_shopImages.isNotEmpty)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _shopImages.asMap().entries.map((entry) {
                return Stack(
                  children: [
                    Container(
                      width: (MediaQuery.of(context).size.width - 60) / 2,
                      height: 100,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF27272A))),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb
                            ? Image.network(entry.value.path, fit: BoxFit.cover)
                            : FutureBuilder<Uint8List>(
                                future: entry.value.readAsBytes(),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData) {
                                    return Image.memory(snapshot.data!, fit: BoxFit.cover);
                                  }
                                  return const Center(child: CircularProgressIndicator());
                                },
                              ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _shopImages.removeAt(entry.key)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          if (_shopImages.length < 4) Text('Please add at least 4 shop images', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.orange)),
          const SizedBox(height: 24),
          _buildTextField(controller: _shopNameController, label: 'Shop Name', hint: 'Enter shop name', icon: Icons.store_outlined),
          const SizedBox(height: 16),
          _buildTextField(controller: _ownerNameController, label: 'Owner Name', hint: 'Enter owner name', icon: Icons.person_outline),
          const SizedBox(height: 16),
          _buildTextField(controller: _phoneController, label: 'Phone Number', hint: 'Enter phone number', icon: Icons.phone_outlined),
          const SizedBox(height: 16),
          _buildTextField(controller: _emailController, label: 'Email Address', hint: 'Enter email', icon: Icons.email_outlined),
          const SizedBox(height: 16),
          _buildTextField(controller: _panController, label: 'PAN Number (9 digits)', hint: 'Enter 9-digit PAN', icon: Icons.credit_card_outlined, maxLength: 9),
          const SizedBox(height: 16),
          _buildTextField(controller: _gstController, label: 'GST Number (Optional)', hint: 'Enter GST number', icon: Icons.receipt_outlined),
          const SizedBox(height: 16),
          _buildTextField(controller: _referralCodeController, label: 'Referral Code (Optional)', hint: 'Enter referral code', icon: Icons.card_giftcard_outlined),
        ],
      ),
    );
  }

  Widget _buildDocumentsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text('Upload Documents', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 24),
          _buildDocumentUpload('PAN Document', _panDocument, () async {
            await _pickImage(ImageSource.gallery, (file) => setState(() => _panDocument = file));
          }),
          const SizedBox(height: 16),
          _buildDocumentUpload('Citizenship (Front)', _citizenshipFront, () async {
            await _pickImage(ImageSource.gallery, (file) => setState(() => _citizenshipFront = file));
          }),
          const SizedBox(height: 16),
          _buildDocumentUpload('Citizenship (Back)', _citizenshipBack, () async {
            await _pickImage(ImageSource.gallery, (file) => setState(() => _citizenshipBack = file));
          }),
        ],
      ),
    );
  }

  Widget _buildPaymentInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text('Payment Information', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 24),
          _buildTextField(controller: _accountNumberController, label: 'Account Number', hint: 'Enter account number', icon: Icons.account_balance_outlined),
          const SizedBox(height: 16),
          _buildTextField(controller: _accountHolderController, label: 'Account Holder Name', hint: 'Enter account holder name', icon: Icons.person_outline),
          const SizedBox(height: 16),
          _buildTextField(controller: _bankNameController, label: 'Bank Name', hint: 'Enter bank name', icon: Icons.account_balance_outlined),
          const SizedBox(height: 16),
          _buildTextField(controller: _ifscController, label: 'IFSC Code (Optional)', hint: 'Enter IFSC code', icon: Icons.code_outlined),
        ],
      ),
    );
  }

  Widget _buildBusinessTypeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text('Business Type', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 24),
          ..._businessTypes.entries.map((entry) {
            final isSelected = _selectedBusinessType == entry.key;
            return GestureDetector(
              onTap: () => setState(() => _selectedBusinessType = entry.key),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryColor.withOpacity(0.15) : const Color(0xFF18181B),
                  border: Border.all(color: isSelected ? AppTheme.primaryColor : const Color(0xFF27272A), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isSelected ? AppTheme.primaryColor : const Color(0xFF71717A), size: 20),
                    const SizedBox(width: 12),
                    Text(entry.value, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : const Color(0xFFA1A1AA))),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoriesStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text('Product Categories', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 24),
          _buildTextField(controller: _descriptionController, label: 'Business Description (Optional)', hint: 'Describe your business', icon: Icons.description_outlined),
          const SizedBox(height: 24),
          ..._allCategories.map((category) {
            final isSelected = _selectedCategory == category;
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = category),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryColor.withOpacity(0.15) : const Color(0xFF18181B),
                  border: Border.all(color: isSelected ? AppTheme.primaryColor : const Color(0xFF27272A), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isSelected ? AppTheme.primaryColor : const Color(0xFF71717A), size: 20),
                    const SizedBox(width: 12),
                    Text(category, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : const Color(0xFFA1A1AA))),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPreviewStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text('Review Your Information', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 24),
          _buildPreviewSection('Location', [
            'Address: ${_addressController.text}',
            'City: ${_cityController.text}',
            'State: ${_stateController.text}',
            'PIN: ${_pincodeController.text}',
          ]),
          _buildPreviewSection('Shop Information', [
            'Shop Name: ${_shopNameController.text}',
            'Owner: ${_ownerNameController.text}',
            'Phone: ${_phoneController.text}',
            'Email: ${_emailController.text}',
            'PAN: ${_panController.text}',
            'GST: ${_gstController.text.isEmpty ? "N/A" : _gstController.text}',
            'Referral: ${_referralCodeController.text.isEmpty ? "None" : _referralCodeController.text}',
            'Images: ${_shopImages.length} uploaded',
          ]),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF18181B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF27272A))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Documents', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                const SizedBox(height: 12),
                if (_panDocument != null) ...[
                  Text('PAN Document:', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF27272A))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.network(_panDocument!.path, fit: BoxFit.cover)
                          : FutureBuilder<Uint8List>(
                              future: _panDocument!.readAsBytes(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) return Image.memory(snapshot.data!, fit: BoxFit.cover);
                                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('PAN: Not uploaded', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFFA1A1AA))),
                  ),
                if (_citizenshipFront != null) ...[
                  Text('Citizenship Front:', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF27272A))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.network(_citizenshipFront!.path, fit: BoxFit.cover)
                          : FutureBuilder<Uint8List>(
                              future: _citizenshipFront!.readAsBytes(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) return Image.memory(snapshot.data!, fit: BoxFit.cover);
                                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('Citizenship Front: Not uploaded', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFFA1A1AA))),
                  ),
                if (_citizenshipBack != null) ...[
                  Text('Citizenship Back:', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF27272A))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.network(_citizenshipBack!.path, fit: BoxFit.cover)
                          : FutureBuilder<Uint8List>(
                              future: _citizenshipBack!.readAsBytes(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) return Image.memory(snapshot.data!, fit: BoxFit.cover);
                                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                              },
                            ),
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 0),
                    child: Text('Citizenship Back: Not uploaded', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFFA1A1AA))),
                  ),
              ],
            ),
          ),
          _buildPreviewSection('Payment Info', [
            'Account: ${_accountNumberController.text}',
            'Holder: ${_accountHolderController.text}',
            'Bank: ${_bankNameController.text}',
            'IFSC: ${_ifscController.text.isEmpty ? "N/A" : _ifscController.text}',
          ]),
          _buildPreviewSection('Business', [
            'Type: ${_businessTypes[_selectedBusinessType] ?? "Not selected"}',
            'Category: ${_selectedCategory ?? "Not selected"}',
            'Description: ${_descriptionController.text.isEmpty ? "N/A" : _descriptionController.text}',
          ]),
          if (_shopImages.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF18181B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF27272A))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shop Images Preview', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _shopImages.take(6).map((img) {
                      return Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF27272A))),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: kIsWeb
                              ? Image.network(img.path, fit: BoxFit.cover)
                              : FutureBuilder<Uint8List>(
                                  future: img.readAsBytes(),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) return Image.memory(snapshot.data!, fit: BoxFit.cover);
                                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                  },
                                ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_shopImages.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('+${_shopImages.length - 6} more', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFFA1A1AA))),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(String title, List<String> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF18181B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF27272A))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(item, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFFA1A1AA))),
          )),
        ],
      ),
    );
  }

  Widget _buildDocumentUpload(String label, XFile? document, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: document != null ? AppTheme.primaryColor : const Color(0xFF27272A), width: 1),
            ),
            child: Row(
              children: [
                Icon(document != null ? Icons.check_circle : Icons.upload_file, color: document != null ? AppTheme.primaryColor : const Color(0xFF71717A), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      Text(document != null ? 'Uploaded - Tap to change' : 'Tap to upload', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF71717A))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (document != null) ...[
          const SizedBox(height: 8),
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF27272A)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? Image.network(document.path, fit: BoxFit.cover)
                  : FutureBuilder<Uint8List>(
                      future: document.readAsBytes(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Image.memory(snapshot.data!, fit: BoxFit.cover);
                        }
                        return const Center(child: CircularProgressIndicator());
                      },
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF27272A), width: 1))),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _isLoading ? null : _previousStep,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: AppTheme.primaryColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: Text('Back', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _nextStep,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text(_currentStep == 6 ? 'Complete' : 'Next', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required String hint, required IconData icon, int? maxLength}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 6),
        Container(
          height: 52,
          decoration: BoxDecoration(color: const Color(0xFF18181B), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF27272A), width: 1)),
          child: TextField(
            controller: controller,
            maxLength: maxLength,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF71717A)),
              prefixIcon: Icon(icon, color: const Color(0xFFA1A1AA), size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              counterText: '',
            ),
          ),
        ),
      ],
    );
  }
}
