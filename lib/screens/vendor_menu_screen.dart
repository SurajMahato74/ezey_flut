// lib/screens/vendor_menu_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'vendor_profile_screen.dart';
import 'product_management_screen.dart';
import 'vendor_earnings_screen.dart';
import 'company_information_screen.dart';
import 'vendor_security_screen.dart';
import '../services/auth_service.dart';
import '../services/data_preloader_service.dart';
import '../config.dart' as appConfig;
import 'main_app_screen.dart';

class VendorMenuScreen extends StatefulWidget {
  const VendorMenuScreen({super.key});

  @override
  State<VendorMenuScreen> createState() => _VendorMenuScreenState();
}

class _VendorMenuScreenState extends State<VendorMenuScreen> {
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _vendorProfile;
  bool _isLoading = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeWithPreloadedData();
  }

  Future<void> _initializeWithPreloadedData() async {
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    
    // Use preloaded data if available
    if (preloader.userProfile != null) {
      setState(() {
        _userProfile = preloader.userProfile;
        _isLoading = false;
      });
    }
    
    if (preloader.vendorProfile != null) {
      setState(() {
        _vendorProfile = preloader.vendorProfile;
        _isLoading = false;
      });
    }
    
    // Always fetch fresh data to ensure images are loaded
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      // Fetch user profile
      final userResponse = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/profile/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      // Fetch vendor profile
      final vendorResponse = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (userResponse.statusCode == 200 && vendorResponse.statusCode == 200) {
        final userData = jsonDecode(userResponse.body);
        final vendorData = jsonDecode(vendorResponse.body);
        
        setState(() {
          _userProfile = userData;
          _vendorProfile = vendorData['results']?.isNotEmpty == true 
              ? vendorData['results'][0] 
              : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _switchRole(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD60A)),
      ),
    );

    try {
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/switch-role/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'role': 'customer'}),
      );

      if (mounted) Navigator.pop(context); // Remove loading dialog

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Force update the role directly and trigger navigation
        authService.switchRole();
        
        // Update available roles to ensure both roles are available
        authService.updateAvailableRoles(['customer', 'vendor']);
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Switched to customer successfully'),
            backgroundColor: const Color(0xFFFFD60A),
          ),
        );

        // Navigate to main app screen to trigger rebuild
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainAppScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to switch role'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Remove loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error switching role'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateProfilePicture() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final authService = Provider.of<AuthService>(context, listen: false);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD60A)),
      ),
    );

    try {
      await authService.updateProfilePicture(image);
      
      if (mounted) {
        Navigator.pop(context); // Remove loading dialog
        _fetchProfileData(); // Refresh data
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully!'),
            backgroundColor: Color(0xFFFFD60A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Remove loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile picture: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          // Top App Bar
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF121212).withOpacity(0.9),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => _fetchProfileData(),
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
              ],
            ),
          ),
          
          // Main Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Header
                  Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: _vendorProfile?['shop_images']?.isNotEmpty == true
                          ? DecorationImage(
                              image: NetworkImage(_vendorProfile!['shop_images'][0]['image_url']),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: _vendorProfile?['shop_images']?.isEmpty == true 
                          ? const Color(0xFF1E1E1E) 
                          : null,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.3),
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Avatar with edit functionality
                          GestureDetector(
                            onTap: _updateProfilePicture,
                            child: Stack(
                              children: [
                                Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFFFFD60A), width: 2),
                                    image: _userProfile?['profile_picture'] != null
                                        ? DecorationImage(
                                            image: NetworkImage('https://ezeyway.com/media/${_userProfile!['profile_picture']}'),
                                            fit: BoxFit.cover,
                                          )
                                        : (_userProfile?['profile_picture_url'] != null
                                            ? DecorationImage(
                                                image: NetworkImage(_userProfile!['profile_picture_url']),
                                                fit: BoxFit.cover,
                                              )
                                            : null),
                                    color: (_userProfile?['profile_picture'] == null && _userProfile?['profile_picture_url'] == null)
                                        ? const Color(0xFF2C2C2C) 
                                        : null,
                                  ),
                                  child: (_userProfile?['profile_picture'] == null && _userProfile?['profile_picture_url'] == null)
                                      ? const Icon(Icons.person, color: Colors.grey, size: 35)
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFFD60A),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      color: Colors.black,
                                      size: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Vendor Info
                          Text(
                            _isLoading 
                                ? 'Loading...' 
                                : (_vendorProfile?['business_name'] ?? _userProfile?['display_name'] ?? _userProfile?['username'] ?? 'Vendor'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isLoading 
                                ? 'Loading...' 
                                : (_userProfile?['email'] ?? AuthService().user?.email ?? 'email@gmail.com'),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.circle, 
                                  color: _vendorProfile?['is_active'] == true ? Colors.green : Colors.red, 
                                  size: 8
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _vendorProfile?['is_active'] == true ? 'Online' : 'Offline',
                                  style: TextStyle(
                                    color: _vendorProfile?['is_active'] == true ? Colors.green : Colors.red,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Switch Account Section
                  _buildSection(
                    'Account Type',
                    'Switch between your Customer and Vendor accounts',
                    [
                      _buildMenuOption(
                        icon: Icons.swap_horiz,
                        title: 'Switch to Customer',
                        onTap: () => _switchRole(context),
                      ),
                      _buildMenuOption(
                        icon: Icons.logout,
                        title: 'Logout',
                        isRed: true,
                        onTap: () => _showLogoutDialog(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Account Section
                  _buildSection(
                    'Account',
                    'Manage your account settings',
                    [
                      _buildMenuOption(
                        icon: Icons.person,
                        title: 'Profile Management',
                        subtitle: 'Complete profile setup and management',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const VendorProfileScreen(vendorId: 1), // TODO: Use actual vendor ID
                            ),
                          );
                        },
                      ),
                      _buildMenuOption(
                        icon: Icons.business,
                        title: 'Company Information',
                        subtitle: 'Business details and verification',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CompanyInformationScreen()),
                          );
                        },
                      ),
                      _buildMenuOption(
                        icon: Icons.security,
                        title: 'Security & Login',
                        subtitle: 'Password and authentication',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const VendorSecurityScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Business Section
                  _buildSection(
                    'Business',
                    'Manage your business operations',
                    [
                      _buildMenuOption(
                        icon: Icons.inventory_2,
                        title: 'Product Management',
                        subtitle: 'Inventory, pricing, and catalog',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ProductManagementScreen()),
                          );
                        },
                      ),
                      _buildMenuOption(
                        icon: Icons.analytics,
                        title: 'Business Analytics',
                        subtitle: 'Sales reports and insights',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const VendorEarningsScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String subtitle, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: children,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isRed = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: isRed ? const Color(0xFF1E1E1E) : null,
          border: isRed
              ? Border(
                  bottom: BorderSide(color: Colors.red.withOpacity(0.1)),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD60A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: const Color(0xFFFFD60A),
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[600],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final authService = AuthService(); // Import this at the top!

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Logout',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Are you sure you want to logout?',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                authService.logout(context);   // This does EVERYTHING now
              },
              child: const Text(
                'Logout',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}