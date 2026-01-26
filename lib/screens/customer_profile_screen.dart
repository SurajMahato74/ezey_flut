import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../screens/role_selection_screen.dart';
import '../screens/main_app_screen.dart';
import '../main.dart';
import '../models/user_role.dart';
import '../config.dart' as appConfig;
import '../widgets/unified_bottom_nav.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'products_page.dart';
import 'order_history_screen.dart';
import 'cart_screen.dart';
import 'message_inbox_screen.dart' hide UserRole;
import 'vendor_profile_completion_screen.dart';
import 'personal_information_screen.dart';
import 'privacy_security_screen.dart';
import 'wishlist_screen.dart';
import 'notification_screen.dart';
import '../services/api_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CustomerProfileScreen extends StatefulWidget {
  final VoidCallback? onSwitchToVendor;
  const CustomerProfileScreen({super.key, this.onSwitchToVendor});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  int _notificationCount = 0;
  static const String _defaultBgImage = 'https://lh3.googleusercontent.com/aida-public/AB6AXuCbo_bhMXyXGEFotmoD-1a2kWTx35J1h6pkdf5qx9wjtuCQ1aJpTStkbegDqvWMq--X_CucQ6eT9Qk3icjsxHX8uvZZdvI1ifXDGM0mS3HtALIv7k4sIYwWU61NmwYBj5ir8CH-1kCH_l0CQVUFUP8N_0zfrLpharNdNR1PJGcUBiZgGhXhn9gdNG1q68YKQ5Cfh10QR6ZjwdOmyYJh9DZtHh-WSvbrR7dge2b7ZM0XYAgulzsFGRSbbVp_K-IO0M0vWbFQMaKHQcsI';
  static const String _defaultProfileImage = 'https://lh3.googleusercontent.com/aida-public/AB6AXuA0kI0LRPCd362lnEBvHFYKKatvUcbMrqL0XNuBrFi9-McmQ3x3w80qsXJahZZTPv7R57vM9g1li2ZURvLWJXCO3cCJp6ZyIJ4duKoa_6HosGiKPWpNnsc2NGPlNDXrHikNJKLrW9wWNIqlf2SITSnCKLq0ZbJyTKlAcsWHzuejD4oY_S2iviSF6BIGE8f4mypk7jLVAf4Efmocx5UVB3cUcOqWk_7TyXr2iIHEr_7mPuPEoOTciXCE-PNiC4uuFX2nJ9BwM5fECm17';

  @override
  void initState() {
    super.initState();
    _fetchNotificationCount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadImages();
    });
  }

  void _preloadImages() {
    precacheImage(const CachedNetworkImageProvider(_defaultBgImage), context);
    if (AuthService().user?.fullProfilePictureUrl != null) {
      precacheImage(CachedNetworkImageProvider(AuthService().user!.fullProfilePictureUrl!), context);
    } else {
      precacheImage(const CachedNetworkImageProvider(_defaultProfileImage), context);
    }
  }

  Future<void> _fetchNotificationCount() async {
    final token = AuthService().token;
    if (token == null) return;

    try {
      final response = await ApiService().getNotifications(token, page: 1);
      List<dynamic> notifications = [];
      if (response is List) {
        notifications = response;
      } else if (response is Map && response['results'] != null) {
        notifications = response['results'];
      }
      
      // Filter by current role
      final currentRole = AuthService().currentRole;
      final currentRoleString = currentRole?.toString().split('.').last ?? 'customer';
      
      final filteredNotifications = notifications.where((notification) {
        final notificationRole = notification['role'] ?? 'customer';
        return notificationRole == currentRoleString && notification['is_read'] != true;
      }).toList();
      
      if (mounted) {
        setState(() {
          _notificationCount = filteredNotifications.length;
        });
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _switchToVendor(BuildContext context) async {
    final authService = AuthService();
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
        body: jsonEncode({'role': 'vendor'}),
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
            content: Text(data['message'] ?? 'Switched to vendor successfully'),
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService(),
      builder: (context, _) {
        final isLoggedIn = AuthService().isLoggedIn;

        return Scaffold(
          backgroundColor: AppTheme.homeBackgroundDark,
          body: SafeArea(
            child: Column(
              children: [
                // Top App Bar
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  decoration: BoxDecoration(
                    color: AppTheme.homeBackgroundDark.withValues(alpha: 0.8),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 48), // Spacer to balance icons
                      Expanded(
                          child: Text(
                          'Profile',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.015,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (AuthService().isLoggedIn)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const NotificationScreen()),
                              );
                              _fetchNotificationCount();
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.notifications_outlined, color: Colors.white, size: 20),
                                if (_notificationCount > 0)
                                  Positioned(
                                    right: -4,
                                    top: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 14,
                                        minHeight: 14,
                                      ),
                                      child: Text(
                                        _notificationCount > 9 ? '9+' : _notificationCount.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MessageInboxScreen(title: "Messages", isVendor: false),
                              ),
                            ),
                            child: const Icon(Icons.message_outlined, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: isLoggedIn ? _buildProfileContent() : _buildLoginPrompt(),
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_circle,
            size: 80,
            color: AppTheme.primaryColor.withOpacity(0.7),
          ),
          const SizedBox(height: 24),
          Text(
            'Please login to view profile',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(
                    role: UserRole.customer,
                    shouldRemoveAllRoutes: false,
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Sign In',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Header with Cover
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: _defaultBgImage,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  memCacheHeight: 240,
                  memCacheWidth: 800,
                  placeholder: (context, url) => Container(
                    height: 120,
                    color: const Color(0xFF2A2A2A),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 120,
                    color: const Color(0xFF2A2A2A),
                  ),
                ),
              ),
              Positioned(
                bottom: -30,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: AppTheme.homeBackgroundDark, width: 4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: CachedNetworkImage(
                        imageUrl: AuthService().user?.fullProfilePictureUrl ?? _defaultProfileImage,
                        fit: BoxFit.cover,
                        memCacheHeight: 160,
                        memCacheWidth: 160,
                        placeholder: (context, url) => Container(
                          color: const Color(0xFF2A2A2A),
                          child: const Icon(Icons.person, color: Colors.grey, size: 40),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFF2A2A2A),
                          child: const Icon(Icons.person, color: Colors.grey, size: 40),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // User Info + Buttons
          Center(
            child: Column(
              children: [
                Text(
                  AuthService().user?.displayName ?? 'User',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AuthService().user?.email ?? '',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    color: const Color(0xFFA0A0A0),
                  ),
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 24),

                // Switch Account Section (Vendor Style)
                _buildVendorLikeSection(
                  'Account Type',
                  'Switch between your Customer and Vendor accounts',
                  [
                    Builder(
                      builder: (context) {
                        final hasVendorRole = AuthService().availableRoles.contains('vendor');
                        return _buildVendorLikeMenuOption(
                          icon: hasVendorRole ? Icons.storefront : Icons.verified_user,
                          title: hasVendorRole ? 'Switch to Vendor' : 'Become a Vendor',
                          subtitle: hasVendorRole 
                              ? 'Access your vendor dashboard' 
                              : 'Start selling on the platform',
                          onTap: () async {
                            if (hasVendorRole) {
                              // Switch to Vendor with API call
                              await _switchToVendor(context);
                            } else {
                              // Become a Vendor
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const VendorProfileCompletionScreen(),
                                ),
                              );
                            }
                          },
                        );
                      }
                    ),
                    _buildVendorLikeMenuOption(
                      icon: Icons.logout,
                      title: 'Logout',
                      isRed: true,
                      onTap: () => _showLogoutDialog(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Simplified Menu Sections
          _buildSection('General', [
            _buildProfileOption(
              icon: Icons.receipt_long, 
              title: 'My Orders', 
              onTap: () {
                 Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const OrderHistoryScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            ),
            _buildProfileOption(
              icon: Icons.favorite_border, 
              title: 'Wishlist', 
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const WishlistScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            ),
            _buildProfileOption(
              icon: Icons.person_outline, 
              title: 'Personal Information', 
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const PersonalInformationScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            ),
            _buildProfileOption(
              icon: Icons.lock_outline, 
              title: 'Privacy & Security', 
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const PrivacySecurityScreen(),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            ),
          ]),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Header Skeleton
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Positioned(
                bottom: -30,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: AppTheme.homeBackgroundDark, width: 4),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // User Info Skeleton
          Center(
            child: Column(
              children: [
                Container(
                  width: 120,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 160,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 24),

                // Account Type Section Skeleton
                _buildSkeletonSection(
                  'Account Type',
                  'Switch between your Customer and Vendor accounts',
                  2,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Menu Sections Skeleton
          _buildSkeletonSection('General', 'Profile options', 4),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSkeletonSection(String title, String subtitle, int itemCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8, top: 16),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFA0A0A0),
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: List.generate(itemCount, (index) => _buildSkeletonOption()),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonOption() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 80,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Helper Widgets (fully implemented)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8, top: 16),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFA0A0A0),
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: children.asMap().entries.map((entry) {
              int index = entry.key;
              Widget option = entry.value;
              return Column(
                children: [
                  option,
                  if (index < children.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 80),
                      child: Divider(color: Color(0x1AFFFFFF), height: 1),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFA0A0A0), size: 24),
          ],
        ),
      ),
    );
  }



  // ─────────────────────────────────────────────────────────────────────
  // Helper Widgets (Vendor Style)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildVendorLikeSection(String title, String subtitle, List<Widget> children) {
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

  Widget _buildVendorLikeMenuOption({
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
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: AppTheme.primaryColor,
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

  // ─────────────────────────────────────────────────────────────────────
  // LOGOUT DIALOG – REAL & WORKING
  // ─────────────────────────────────────────────────────────────────────
  static void _showLogoutDialog(BuildContext context) {
    final authService = AuthService();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Logout', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to logout?', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFA0A0A0))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFA0A0A0))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              authService.logout(context); // This does everything
            },
            child: Text('Logout', style: GoogleFonts.plusJakartaSans(color: Colors.red[500], fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
