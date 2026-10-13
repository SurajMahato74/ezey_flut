import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/user_role.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'main_app_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole? _selectedRole;
  bool _isContinuing = false;

  Future<void> _continue() async {
    final role = _selectedRole;
    if (role == null || _isContinuing) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isContinuing = true);
    try {
      if (role == UserRole.customer) {
        await Provider.of<AuthService>(context, listen: false).loginAsGuest(role);
        if (navigator.mounted) {
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainAppScreen()), (_) => false);
        }
      } else {
        await navigator.push(MaterialPageRoute(builder: (_) => LoginScreen(role: role)));
      }
    } catch (error) {
      if (messenger.mounted) messenger.showSnackBar(SnackBar(content: Text('Could not continue: $error')));
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              
              // App Logo
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/ezeywaylogo.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Welcome Text
              Text(
                'Welcome to Ezeyway!',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.015,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              Text(
                'Choose how you\'d like to use our app',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFA1A1AA),
                ),
                textAlign: TextAlign.center,
              ),
              
              const Spacer(),
              
              // Role Selection Cards - Vertical Layout
              Column(
                children: [
                  // Customer Role Card
                  GestureDetector(
                    onTap: _isContinuing ? null : () {
                      setState(() {
                        _selectedRole = UserRole.customer;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: _selectedRole == UserRole.customer
                            ? AppTheme.primaryColor.withOpacity(0.15)
                            : const Color(0xFF18181B),
                        border: Border.all(
                          color: _selectedRole == UserRole.customer
                              ? AppTheme.primaryColor
                              : const Color(0xFF27272A),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          // Icon Container
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _selectedRole == UserRole.customer
                                  ? AppTheme.primaryColor.withOpacity(0.3)
                                  : AppTheme.primaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(
                              Icons.person,
                              size: 24,
                              color: _selectedRole == UserRole.customer
                                  ? AppTheme.primaryColor
                                  : const Color(0xFFA1A1AA),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Customer',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _selectedRole == UserRole.customer
                                    ? Colors.white
                                    : const Color(0xFFA1A1AA),
                              ),
                            ),
                          ),
                          if (_selectedRole == UserRole.customer)
                            const Icon(
                              Icons.check_circle,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Vendor Role Card
                  GestureDetector(
                    onTap: _isContinuing ? null : () {
                      setState(() {
                        _selectedRole = UserRole.vendor;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: _selectedRole == UserRole.vendor
                            ? AppTheme.primaryColor.withOpacity(0.15)
                            : const Color(0xFF18181B),
                        border: Border.all(
                          color: _selectedRole == UserRole.vendor
                              ? AppTheme.primaryColor
                              : const Color(0xFF27272A),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          // Icon Container
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _selectedRole == UserRole.vendor
                                  ? AppTheme.primaryColor.withOpacity(0.3)
                                  : AppTheme.primaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(
                              Icons.storefront,
                              size: 24,
                              color: _selectedRole == UserRole.vendor
                                  ? AppTheme.primaryColor
                                  : const Color(0xFFA1A1AA),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Vendor',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _selectedRole == UserRole.vendor
                                    ? Colors.white
                                    : const Color(0xFFA1A1AA),
                              ),
                            ),
                          ),
                          if (_selectedRole == UserRole.vendor)
                            const Icon(
                              Icons.check_circle,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              const Spacer(),
              
              // Continue Button
              ElevatedButton(
                onPressed: _selectedRole != null && !_isContinuing ? _continue : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  disabledBackgroundColor: const Color(0xFF27272A),
                  disabledForegroundColor: const Color(0xFFA1A1AA),
                ),
                child: _isContinuing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.primaryColor,
                          semanticsLabel: 'Continuing',
                        ),
                      )
                    : Text(
                        'Continue',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
