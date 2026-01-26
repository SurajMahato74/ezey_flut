import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../config.dart' as appConfig;
import '../utils/permission_helper.dart';

class VendorProfileScreen extends StatefulWidget {
   final int vendorId;

   const VendorProfileScreen({
     super.key,
     required this.vendorId,
   });

  @override
  State<VendorProfileScreen> createState() => _VendorProfileScreenState();
}

class _VendorProfileScreenState extends State<VendorProfileScreen>
    with SingleTickerProviderStateMixin {
    late TabController _tabController;
    int _selectedTabIndex = 0;

    Map<String, dynamic>? _vendorData;
    bool _isLoading = true;
    List<Map<String, dynamic>> _vendorProducts = [];
    bool _isLoadingProducts = true;
    bool _isEditing = false;
    bool _isSaving = false;

    String? vendorName;
    String? vendorType;

    late MapController _mapController;
    final bool _headerImageError = false;
    final ImagePicker _picker = ImagePicker();
    
    // Form controllers
    final TextEditingController _businessNameController = TextEditingController();
    final TextEditingController _ownerNameController = TextEditingController();
    final TextEditingController _emailController = TextEditingController();
    final TextEditingController _phoneController = TextEditingController();
    final TextEditingController _addressController = TextEditingController();
    final TextEditingController _cityController = TextEditingController();
    final TextEditingController _stateController = TextEditingController();
    final TextEditingController _pincodeController = TextEditingController();
    final TextEditingController _descriptionController = TextEditingController();
    final TextEditingController _deliveryRadiusController = TextEditingController();
    final TextEditingController _minOrderAmountController = TextEditingController();
    final TextEditingController _bankNameController = TextEditingController();
    final TextEditingController _accountNumberController = TextEditingController();
    final TextEditingController _ifscCodeController = TextEditingController();
    final TextEditingController _accountHolderNameController = TextEditingController();
    final TextEditingController _gstNumberController = TextEditingController();
    final TextEditingController _panNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _mapController = MapController();
    _tabController.addListener(() {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
    });
    _fetchVendorData();
  }

  Future<void> _fetchVendorData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      
      if (token == null) {
        // If no token, fetch public vendor data
        final data = await ApiService().getVendorDetails(widget.vendorId);
        if (mounted) _updateVendorData(data);
      } else {
        // If token exists, fetch vendor profile data
        final response = await http.get(
          Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/'),
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['results'] != null && data['results'].isNotEmpty) {
            final vendorProfile = data['results'][0];
            if (mounted) _updateVendorData(vendorProfile);
            _populateFormControllers(vendorProfile);
          }
        } else {
          // Fallback to public data
          final data = await ApiService().getVendorDetails(widget.vendorId);
          if (mounted) _updateVendorData(data);
        }
      }
      
      // Fetch products after vendor data is loaded
      if ((_vendorData!['is_active'] as bool? ?? false)) {
        _fetchVendorProducts();
      } else {
        if (mounted) setState(() => _isLoadingProducts = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _isLoading = false;
        _isLoadingProducts = false;
      });
      }
    }
  }
  
  void _updateVendorData(Map<String, dynamic> data) {
    setState(() {
      _vendorData = data;
      vendorName = data['business_name'] ?? 'Unknown Vendor';
      vendorType = data['business_type'] ?? 'Business';
      _isLoading = false;
    });
  }
  
  void _populateFormControllers(Map<String, dynamic> data) {
    _businessNameController.text = data['business_name'] ?? '';
    _ownerNameController.text = data['owner_name'] ?? '';
    _emailController.text = data['business_email'] ?? '';
    _phoneController.text = data['business_phone'] ?? '';
    _addressController.text = data['business_address'] ?? '';
    _cityController.text = data['city'] ?? '';
    _stateController.text = data['state'] ?? '';
    _pincodeController.text = data['pincode'] ?? '';
    _descriptionController.text = data['description'] ?? '';
    _deliveryRadiusController.text = data['delivery_radius']?.toString() ?? '';
    _minOrderAmountController.text = data['min_order_amount']?.toString() ?? '';
    _bankNameController.text = data['bank_name'] ?? '';
    _accountNumberController.text = data['account_number'] ?? '';
    _ifscCodeController.text = data['ifsc_code'] ?? '';
    _accountHolderNameController.text = data['account_holder_name'] ?? '';
    _gstNumberController.text = data['gst_number'] ?? '';
    _panNumberController.text = data['pan_number'] ?? '';
  }

  Future<void> _fetchVendorProducts() async {
    try {
      final response = await ApiService().searchProducts(pageSize: 50);
      if (response['success'] == true && response['results'] is List) {
        final allProducts = List<Map<String, dynamic>>.from(response['results']);
        final vendorProducts = allProducts.where((p) => p['vendor_id'] == widget.vendorId).toList();
        if (mounted) {
          setState(() {
          _vendorProducts = vendorProducts;
          _isLoadingProducts = false;
        });
        }
      } else {
        if (mounted) setState(() => _isLoadingProducts = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mapController.dispose();
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _descriptionController.dispose();
    _deliveryRadiusController.dispose();
    _minOrderAmountController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _ifscCodeController.dispose();
    _accountHolderNameController.dispose();
    _gstNumberController.dispose();
    _panNumberController.dispose();
    super.dispose();
  }

  void _openMap() {
    final latitude = _vendorData!['latitude'] as double?;
    final longitude = _vendorData!['longitude'] as double?;

    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location data not available'), backgroundColor: Colors.red),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          height: 400,
          decoration: BoxDecoration(
            color: AppTheme.homeBackgroundDark,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppTheme.homeBackgroundDark,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Store Location',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(latitude, longitude),
                      initialZoom: 15,
                      minZoom: 5,
                      maxZoom: 18,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.ezeyway.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(latitude, longitude),
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: Color(0xFFF5EA47), size: 40),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppTheme.homeBackgroundDark,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _navigateToLocation(latitude, longitude);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Navigate to Location',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveVendorProfile() async {
    if (_isSaving) return;
    
    setState(() => _isSaving = true);
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      
      if (token == null) {
        throw Exception('Authentication required');
      }
      
      final updateData = {
        'business_name': _businessNameController.text,
        'owner_name': _ownerNameController.text,
        'business_email': _emailController.text,
        'business_phone': _phoneController.text,
        'business_address': _addressController.text,
        'city': _cityController.text,
        'state': _stateController.text,
        'pincode': _pincodeController.text,
        'description': _descriptionController.text,
        'delivery_radius': double.tryParse(_deliveryRadiusController.text),
        'min_order_amount': _minOrderAmountController.text,
        'bank_name': _bankNameController.text,
        'account_number': _accountNumberController.text,
        'ifsc_code': _ifscCodeController.text,
        'account_holder_name': _accountHolderNameController.text,
        'gst_number': _gstNumberController.text,
        'pan_number': _panNumberController.text,
      };
      
      final response = await http.patch(
        Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/${_vendorData!['id']}/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode(updateData),
      );
      
      if (response.statusCode == 200) {
        final updatedData = jsonDecode(response.body);
        setState(() {
          _vendorData = updatedData;
          vendorName = updatedData['business_name'] ?? 'Unknown Vendor';
          vendorType = updatedData['business_type'] ?? 'Business';
          _isEditing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Color(0xFFFFD60A),
          ),
        );
      } else {
        throw Exception('Failed to update profile');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }
  
  Future<void> _uploadProfileImage() async {
    try {
      final ImageSource? source = await _showImageSourceDialog();
      if (source == null) return;
      
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image == null) return;
      
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      
      if (token == null) {
        throw Exception('Authentication required');
      }
      
      print('Uploading profile image: ${image.path}');
      print('Vendor ID: ${_vendorData!['id']}');
      
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 16),
              Text('Uploading profile image...'),
            ],
          ),
          backgroundColor: Color(0xFF333333),
          duration: Duration(seconds: 30),
        ),
      );
      
      // Upload as vendor profile header image
      final request = http.MultipartRequest(
        'PATCH',
        Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/${_vendorData!['id']}/'),
      );
      
      request.headers.addAll({
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      });
      
      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'profile_image',
        bytes,
        filename: image.name,
      ));
      
      print('Sending profile image request to: ${request.url}');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      print('Profile image response status: ${response.statusCode}');
      print('Profile image response body: $responseBody');
      
      // Hide loading indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile image updated successfully!'),
            backgroundColor: Color(0xFFFFD60A),
          ),
        );
        _fetchVendorData(); // Refresh data
      } else {
        throw Exception('Failed to update profile image: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      print('Error updating profile image: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating image: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        title: Text(
          'Select Image Source',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFFD60A)),
              title: Text(
                'Camera',
                style: GoogleFonts.plusJakartaSans(color: Colors.white),
              ),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFFFD60A)),
              title: Text(
                'Gallery',
                style: GoogleFonts.plusJakartaSans(color: Colors.white),
              ),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFbab89c),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToLocation(double latitude, double longitude) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      // Fallback to Apple Maps on iOS
      final appleUrl = 'http://maps.apple.com/?daddr=$latitude,$longitude';
      if (await canLaunchUrl(Uri.parse(appleUrl))) {
        await launchUrl(Uri.parse(appleUrl));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open map application'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addGalleryImage() async {
    try {
      final ImageSource? source = await _showImageSourceDialog();
      if (source == null) return;
      
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image == null) return;
      
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      
      if (token == null) {
        throw Exception('Authentication required');
      }
      
      print('Uploading gallery image: ${image.name}');
      print('Vendor ID: ${_vendorData!['id']}');
      
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 16),
              Text('Uploading image...'),
            ],
          ),
          backgroundColor: Color(0xFF333333),
          duration: Duration(seconds: 30),
        ),
      );
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/${_vendorData!['id']}/shop-images/'),
      );
      
      request.headers.addAll({
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      });
      
      request.fields['vendor_profile'] = _vendorData!['id'].toString();
      
      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: image.name.isNotEmpty ? image.name : 'image.jpg',
      ));
      
      print('Sending request to: ${request.url}');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      print('Response status: ${response.statusCode}');
      print('Response body: $responseBody');
      
      // Hide loading indicator
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image added successfully!'),
            backgroundColor: Color(0xFFFFD60A),
          ),
        );
        _fetchVendorData(); // Refresh data
      } else {
        throw Exception('Failed to add image: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      print('Error adding gallery image: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding image: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _deleteGalleryImage(int imageId, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        title: Text(
          'Delete Image',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this image?',
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFFbab89c),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFbab89c),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;
      
      if (token == null) {
        throw Exception('Authentication required');
      }
      
      final response = await http.delete(
        Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/shop-images/$imageId/'),
        headers: {
          'Authorization': 'Token $token',
          'ngrok-skip-browser-warning': 'true',
        },
      );
      
      if (response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image deleted successfully!'),
            backgroundColor: Color(0xFFFFD60A),
          ),
        );
        _fetchVendorData(); // Refresh data
      } else {
        throw Exception('Failed to delete image');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.homeBackgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (_vendorData == null) {
      return const Scaffold(
        backgroundColor: AppTheme.homeBackgroundDark,
        body: Center(
          child: Text('Failed to load vendor data', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final shopImages = _vendorData!['shop_images'] as List<dynamic>? ?? [];
    final primaryImage = shopImages.isNotEmpty ? shopImages.first['image_url'] : null;

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
                  onPressed: () async {
                    debugPrint('Back button pressed in VendorProfileScreen');
                    final popped = await Navigator.maybePop(context);
                    if (!popped) {
                      debugPrint('No route to pop in VendorProfileScreen, navigating to dashboard');
                      // Fallback navigation if needed
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cannot go back further'),
                          backgroundColor: Color(0xFFFFD60A),
                        ),
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Vendor Profile',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Image with Overlay
                  Stack(
                    children: [
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: primaryImage != null
                              ? Image.network(
                                  primaryImage,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.store, color: Colors.white54, size: 64),
                                    );
                                  },
                                )
                              : Container(
                                  color: Colors.grey[800],
                                  child: const Icon(Icons.store, color: Colors.white54, size: 64),
                                ),
                        ),
                      ),
                      // Gradient Overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Profile Header & Actions
                  Transform.translate(
                    offset: const Offset(0, -50),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                // Profile Image
                                Consumer<AuthService>(
                                  builder: (context, authService, child) {
                                    return GestureDetector(
                                      onTap: _uploadProfileImage,
                                      child: Stack(
                                        children: [
                                          CircleAvatar(
                                            radius: 30,
                                            backgroundColor: Colors.grey[800],
                                            backgroundImage: authService.user?.profilePicture != null
                                                ? NetworkImage('https://ezeyway.com/media/${authService.user!.profilePicture!}')
                                                : null,
                                            child: authService.user?.profilePicture == null
                                                ? const Icon(Icons.person, color: Colors.white54, size: 30)
                                                : null,
                                          ),
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryColor,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.black, width: 1),
                                              ),
                                              child: const Icon(
                                                Icons.edit,
                                                size: 12,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 16),
                                // Vendor Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        vendorName ?? 'Unknown Vendor',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        vendorType ?? 'Business',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14,
                                          color: const Color(0xFFbab89c),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: (_vendorData!['is_active'] as bool? ?? false) ? Colors.green : Colors.red,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              (_vendorData!['is_active'] as bool? ?? false) ? 'Online' : 'Offline',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: (_vendorData!['is_active'] as bool? ?? false) ? Colors.green : Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Action Buttons
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: IconButton(
                                    onPressed: _openMap,
                                    icon: const Icon(
                                      Icons.location_on,
                                      color: Colors.black,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Stats Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF18181B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF54533b),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.timer,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Avg. Delivery',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFFbab89c),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  (_vendorData!['estimated_delivery_time'] as String? ?? '25 mins'),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF18181B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF54533b),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.shopping_bag,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Min. Order',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFFbab89c),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Rs. ${_vendorData!['min_order_amount'] ?? '500'}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Tabs Navigation
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.homeBackgroundDark.withValues(alpha: 0.9),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTab('About', 0),
                        ),
                        Expanded(
                          child: _buildTab('Gallery', 1),
                        ),
                      ],
                    ),
                  ),

                  // Tab Content
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _selectedTabIndex == 0
                        ? _buildAboutContent()
                        : _buildGalleryContent(),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: IconButton(
        onPressed: icon == Icons.location_on ? _openMap : () {},
        icon: Icon(
          icon,
          color: Colors.black,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildTab(String title, int index) {
    final bool isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppTheme.primaryColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppTheme.primaryColor : const Color(0xFFbab89c),
          ),
        ),
      ),
    );
  }

  Widget _buildProductsGrid() {
    if (_isLoadingProducts) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    if (_vendorProducts.isEmpty) {
      return const Center(
        child: Text('No products available', style: TextStyle(color: Colors.white)),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: _vendorProducts.length,
      itemBuilder: (context, index) {
        final product = _vendorProducts[index];
        final images = product['images'] as List<dynamic>? ?? [];
        final productImages = List<Map<String, dynamic>>.from(images);
        final primaryImage = productImages.firstWhere((img) => img['is_primary'] == true, orElse: () => productImages.isNotEmpty ? productImages.first : {'image_url': 'https://via.placeholder.com/160'});
        final imageUrl = primaryImage['image_url'] ?? 'https://via.placeholder.com/160';
        final name = product['name'] ?? 'Unknown Product';
        final price = 'NPR ${product['price'] ?? 0}';

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF18181B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF393828),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Image.network(
                      imageUrl,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => SizedBox.expand(
                        child: Container(
                          color: Colors.grey[800],
                          child: const Icon(Icons.image_not_supported, color: Colors.white54, size: 32),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: const Color(0xFFbab89c),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          'Add to Cart',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
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
    );
  }

  Widget _buildAboutContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'About ${vendorName ?? 'Unknown Vendor'}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Consumer<AuthService>(
                builder: (context, authService, child) {
                  final isOwner = authService.isLoggedIn && _vendorData != null;
                  if (!isOwner) return const SizedBox();
                  
                  return Row(
                    children: [
                      IconButton(
                        onPressed: _uploadProfileImage,
                        icon: const Icon(
                          Icons.add_a_photo,
                          color: Color(0xFFFFD60A),
                          size: 20,
                        ),
                        tooltip: 'Update Profile Image',
                      ),
                      IconButton(
                        onPressed: _isEditing ? _saveVendorProfile : () => setState(() => _isEditing = true),
                        icon: _isSaving 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Color(0xFFFFD60A),
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _isEditing ? Icons.save : Icons.edit,
                                color: const Color(0xFFFFD60A),
                                size: 20,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (_isEditing) ..._buildEditableFields() else ..._buildReadOnlyFields(),
        ],
      ),
    );
  }
  
  List<Widget> _buildEditableFields() {
    return [
      _buildEditField('Business Name', _businessNameController),
      _buildEditField('Owner Name', _ownerNameController),
      _buildEditField('Email', _emailController),
      _buildEditField('Phone', _phoneController),
      _buildEditField('Address', _addressController, maxLines: 3),
      _buildEditField('City', _cityController),
      _buildEditField('State', _stateController),
      _buildEditField('Pincode', _pincodeController),
      _buildEditField('Description', _descriptionController, maxLines: 4),
      _buildEditField('Delivery Radius (km)', _deliveryRadiusController),
      _buildEditField('Min Order Amount', _minOrderAmountController),
      const SizedBox(height: 16),
      Text(
        'Banking Details',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 8),
      _buildEditField('Bank Name', _bankNameController),
      _buildEditField('Account Number', _accountNumberController),
      _buildEditField('IFSC Code', _ifscCodeController),
      _buildEditField('Account Holder Name', _accountHolderNameController),
      _buildEditField('GST Number', _gstNumberController),
      _buildEditField('PAN Number', _panNumberController),
    ];
  }
  
  List<Widget> _buildReadOnlyFields() {
    final description = _vendorData!['description'] ?? 'No description available.';
    final address = _vendorData!['location_address'] ?? _vendorData!['business_address'] ?? 'Address not available';
    final phone = _vendorData!['business_phone'] ?? 'Phone not available';
    final email = _vendorData!['business_email'] ?? 'Email not available';
    final deliverySlots = _vendorData!['delivery_slots'] as List<dynamic>? ?? [];
    final ownerName = _vendorData!['owner_name'] ?? '';
    final city = _vendorData!['city'] ?? '';
    final state = _vendorData!['state'] ?? '';
    final pincode = _vendorData!['pincode'] ?? '';
    final deliveryRadius = _vendorData!['delivery_radius']?.toString() ?? '';
    final minOrderAmount = _vendorData!['min_order_amount']?.toString() ?? '';
    final businessType = _vendorData!['business_type'] ?? '';
    final avgDeliveryTime = _vendorData!['estimated_delivery_time'] ?? '25 mins';
    
    return [
      Text(
        description.isNotEmpty ? description : 'Welcome to ${vendorName ?? 'Unknown Vendor'}! We are a ${vendorType ?? 'Business'} dedicated to serving you the finest quality products with exceptional service.',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: const Color(0xFFbab89c),
          height: 1.6,
        ),
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 16),
      Text(
        'Business Information',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 8),
      if (ownerName.isNotEmpty) _buildContactInfo('👤', 'Owner: $ownerName'),
      if (businessType.isNotEmpty) _buildContactInfo('🏢', 'Type: $businessType'),
      _buildContactInfo('⏱️', 'Avg Delivery: $avgDeliveryTime'),
      if (minOrderAmount.isNotEmpty) _buildContactInfo('💰', 'Min Order: Rs. $minOrderAmount'),
      if (deliveryRadius.isNotEmpty) _buildContactInfo('📍', 'Delivery Radius: ${deliveryRadius}km'),
      const SizedBox(height: 16),
      Text(
        'Contact Information',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 8),
      _buildContactInfo('📍', address),
      if (city.isNotEmpty || state.isNotEmpty || pincode.isNotEmpty)
        _buildContactInfo('🏙️', '${city.isNotEmpty ? city : ''}${state.isNotEmpty ? ', $state' : ''}${pincode.isNotEmpty ? ' - $pincode' : ''}'),
      _buildContactInfo('📞', phone),
      _buildContactInfo('✉️', email),
      if (deliverySlots.isNotEmpty)
        _buildContactInfo('🕒', deliverySlots.join(', '))
      else
        _buildContactInfo('🕒', 'Delivery hours not specified'),
    ];
  }
  
  Widget _buildEditField(String label, TextEditingController controller, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            maxLines: maxLines,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF54533b)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF54533b)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFFD60A)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryContent() {
    final shopImages = _vendorData!['shop_images'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Gallery',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Consumer<AuthService>(
              builder: (context, authService, child) {
                final isOwner = authService.isLoggedIn && _vendorData != null;
                if (!isOwner) return const SizedBox();
                
                return IconButton(
                  onPressed: _addGalleryImage,
                  icon: const Icon(
                    Icons.add_photo_alternate,
                    color: Color(0xFFFFD60A),
                    size: 24,
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (shopImages.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            child: const Center(
              child: Text('No gallery images available', style: TextStyle(color: Colors.white)),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2,
            ),
            itemCount: shopImages.length,
            itemBuilder: (context, index) {
              final imageUrl = shopImages[index]['image_url'] ?? '';
              final imageId = shopImages[index]['id'];
              
              return Consumer<AuthService>(
                builder: (context, authService, child) {
                  final isOwner = authService.isLoggedIn && _vendorData != null;
                  
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => SizedBox.expand(
                              child: Container(
                                color: Colors.grey[800],
                                child: const Icon(Icons.image_not_supported, color: Colors.white54, size: 32),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (isOwner)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: IconButton(
                              onPressed: () => _deleteGalleryImage(imageId, index),
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.red,
                                size: 20,
                              ),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildContactInfo(String icon, String info) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              info,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: const Color(0xFFbab89c),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}