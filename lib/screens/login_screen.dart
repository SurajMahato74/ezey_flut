// lib/screens/login_screen.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_role.dart';
import '../models/login_response.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import 'main_app_screen.dart';
import 'signup_screen.dart';
import 'otp_verification_screen.dart';
import 'privacy_policy_screen.dart';
import 'vendor_profile_completion_screen.dart';
import 'role_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  final UserRole role;
  final bool shouldRemoveAllRoutes;
  const LoginScreen({super.key, required this.role, this.shouldRemoveAllRoutes = true});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  LoginMethod _selectedMethod = LoginMethod.credentials;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpEmailController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _isSendingOtp = false;
  bool _isOtpSent = false;
  bool _isPrivacyAgreed = true;




  String get _roleTitle => widget.role == UserRole.customer ? 'Customer' : 'Vendor';
  String get _roleSubtitle => widget.role == UserRole.customer
      ? 'Welcome back! Sign in to your account'
      : 'Access your vendor dashboard';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpEmailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_isPrivacyAgreed) {
      _showError('Please agree to the Privacy Policy');
      return;
    }

    setState(() {
      _isLoading = true;
      _isSendingOtp = _selectedMethod == LoginMethod.otp && !_isOtpSent;
    });

    try {
      if (_selectedMethod == LoginMethod.credentials) {
        // EMAIL + PASSWORD LOGIN
        final result = await ApiService().login(
          _emailController.text.trim(),
          _passwordController.text,
        );

        // Handle different response types
        if (result is Map<String, dynamic>) {
          // Email not verified → send to OTP screen
          if (result['needs_verification'] == true) {
            final email = _emailController.text.trim();
            _showSuccess('OTP sent to $email');
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OTPVerificationScreen(
                    email: email,
                    userType: widget.role,
                  ),
                ),
              );
            }
            return;
          }
          
          // Privacy agreement needed - auto-agree since they agreed during signup
          if (result['needs_privacy_agreement'] == true) {
            final userId = result['user_id'];
            if (userId != null) {
              try {
                // Auto-agree to privacy policy
                final loginResponse = await ApiService().agreeToPrivacyPolicy(userId);
                
                // Now complete the login with the token
                await AuthService().saveLoginData(
                  loginResponse.token!,
                  loginResponse.user!,
                  widget.role,
                );
                
                _navigateToHome();
                return;
              } catch (e) {
                _showError('Login failed. Please try again.');
                return;
              }
            }
          }
        }

        // Full successful login
        if (result is LoginResponse && result.isFullLogin) {
          await AuthService().login(_emailController.text.trim(), _passwordController.text, selectedRole: widget.role);
          _navigateToHome();
          return;
        }
      } 
      else {
        // OTP LOGIN FLOW
        final email = _otpEmailController.text.trim();

        if (!_isOtpSent) {
          await ApiService().sendOtp(email);
          setState(() => _isOtpSent = true);
          _showSuccess('OTP sent to $email');
        } else {
          if (_otpController.text.length != 6) {
            _showError('Please enter 6-digit OTP');
            return;
          }
          
          // Verify OTP directly + Complete Login
          await AuthService().loginWithOtp(email, _otpController.text, selectedRole: widget.role);
          _navigateToHome();
        }
      }
    } on Exception catch (e) {
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      _showError(errorMsg);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSendingOtp = false;
        });
      }
    }
  }

  void _navigateToHome() async {
    if (!mounted) return;

    // If should not remove all routes, just pop back
    if (!widget.shouldRemoveAllRoutes) {
      Navigator.of(context).pop();
      return;
    }

    // For vendors, check if profile exists and approval status
    if (widget.role == UserRole.vendor) {
      try {
        final token = AuthService().token;
        if (token != null) {
          final profileStatus = await ApiService().getVendorProfileStatus(token);

          if (profileStatus['exists'] == true) {
            if (profileStatus['is_approved'] == true) {
              // Profile exists and approved - go to main app
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainAppScreen()),
                  (route) => false,
                );
              }
            } else if (profileStatus['is_rejected'] == true) {
              // Profile rejected - show rejection message
              if (mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: Text('Profile Rejected', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 60),
                        const SizedBox(height: 16),
                        Text(
                          'Your vendor profile has been rejected.',
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 15),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          profileStatus['rejection_reason'] ?? 'Please contact support for more details.',
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
              }
            } else {
              // Profile exists but not approved - show pending message
              if (mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E1E),
                    title: Text('Pending Approval', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.pending, color: Colors.orange, size: 60),
                        const SizedBox(height: 16),
                        Text(
                          'Your vendor profile is pending admin approval.',
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 15),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'You will be notified once approved. Please check back later.',
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
              }
            }
            return;
          } else {
            // Profile doesn't exist - go to completion
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const VendorProfileCompletionScreen()),
                (route) => false,
              );
            }
            return;
          }
        }
      } catch (e) {
        // Error checking profile - assume pending approval
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: Text('Pending Approval', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pending, color: Colors.orange, size: 60),
                  const SizedBox(height: 16),
                  Text(
                    'Your vendor profile is pending admin approval.',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You will be notified once approved. Please check back later.',
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
        }
        return;
      }
    }

    // Default: go to home (for customers)
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainAppScreen()),
        (route) => false,
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  void _skipToHome() {
    AuthService().loginAsGuest(widget.role);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainAppScreen()),
      (route) => false,
    );
  }

  void _navigateToSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SignupScreen(role: widget.role)),
    );
  }

  void _navigateToPrivacyPolicy() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                      (route) => false,
                    ),
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                  TextButton.icon(
                    onPressed: _skipToHome,
                    icon: const Icon(Icons.home_outlined, color: AppTheme.primaryColor, size: 18),
                    label: Text('Skip', style: GoogleFonts.plusJakartaSans(color: AppTheme.primaryColor, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/images/ezeywaylogo.png', width: 70, height: 70))),
                    const SizedBox(height: 12),
                    Text('$_roleTitle Login', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(_roleSubtitle, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFFA1A1AA)), textAlign: TextAlign.center),
                    const SizedBox(height: 20),

                    // Tabs
                    Container(
                      height: 42,
                      decoration: BoxDecoration(color: const Color(0xFF18181B), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF27272A))),
                      child: Row(
                        children: [
                          Expanded(child: _buildTab('Email', LoginMethod.credentials)),
                          Expanded(child: _buildTab('Email OTP', LoginMethod.otp)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Fields
                    if (_selectedMethod == LoginMethod.credentials) ...[
                      _buildTextField(controller: _emailController, label: 'Email', hint: 'Enter your email', icon: Icons.email_outlined),
                      const SizedBox(height: 12),
                      _buildTextField(controller: _passwordController, label: 'Password', hint: 'Enter password', icon: Icons.lock_outline, isPassword: true),
                    ] else ...[
                      _buildTextField(controller: _otpEmailController, label: 'Email', hint: 'Enter your email', icon: Icons.email_outlined),
                      const SizedBox(height: 12),
                      if (_isOtpSent) _buildTextField(controller: _otpController, label: 'OTP', hint: 'Enter 6-digit OTP', icon: Icons.security_outlined),
                    ],

                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: (_isLoading || _isSendingOtp || !_isPrivacyAgreed) ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isLoading || _isSendingOtp
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : Text(
                              _selectedMethod == LoginMethod.otp
                                  ? (_isOtpSent ? 'Verify OTP' : 'Send OTP')
                                  : 'Login',
                              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                    ),

                    const SizedBox(height: 20),
                    Center(child: Text('Or continue with', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFA1A1AA), fontSize: 12))),
                    const SizedBox(height: 12),
                    Center(
                      child: GestureDetector(
                        onTap: () => _showError('Google Sign-In coming soon!'),
                        child: Container(width: 50, height: 50, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF18181B)), child: const Icon(Icons.g_mobiledata, color: Colors.red, size: 32)),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Center(
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFA1A1AA), fontSize: 13),
                          children: [
                            const TextSpan(text: 'No account? '),
                            TextSpan(
                              text: 'Sign Up',
                              style: GoogleFonts.plusJakartaSans(color: AppTheme.primaryColor, fontWeight: FontWeight.w700),
                              recognizer: TapGestureRecognizer()..onTap = _navigateToSignup,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _isPrivacyAgreed,
                            onChanged: (v) => setState(() => _isPrivacyAgreed = v ?? false),
                            activeColor: AppTheme.primaryColor,
                            checkColor: Colors.black,
                          ),
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFFA1A1AA)),
                              children: [
                                const TextSpan(text: 'I agree to the '),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: GoogleFonts.plusJakartaSans(color: AppTheme.primaryColor, decoration: TextDecoration.underline),
                                  recognizer: TapGestureRecognizer()..onTap = _navigateToPrivacyPolicy,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String title, LoginMethod method) {
    final isSelected = _selectedMethod == method;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMethod = method;
          _isOtpSent = false;
          _otpController.clear();
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.black : const Color(0xFFA1A1AA),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 6),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF18181B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF27272A)),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword && !_isPasswordVisible,
            keyboardType: isPassword ? TextInputType.visiblePassword : TextInputType.emailAddress,
            style: GoogleFonts.plusJakartaSans(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF71717A)),
              prefixIcon: Icon(icon, color: const Color(0xFFA1A1AA), size: 18),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: const Color(0xFFA1A1AA)),
                      onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

enum LoginMethod { credentials, otp }