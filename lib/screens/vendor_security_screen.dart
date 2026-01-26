import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/data_preloader_service.dart';
import '../config.dart' as appConfig;

class VendorSecurityScreen extends StatefulWidget {
  const VendorSecurityScreen({super.key});

  @override
  State<VendorSecurityScreen> createState() => _VendorSecurityScreenState();
}

class _VendorSecurityScreenState extends State<VendorSecurityScreen> {
  bool _showPassword = true;
  String _savedPassword = '';
  bool _isChangingPassword = false;
  String _newPassword = '';
  bool _isLoading = false;
  bool _isLoadingPassword = true;
  final _newPasswordController = TextEditingController();
  final _passwordController = TextEditingController(); // Add controller for password field

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    // Set a timeout to prevent infinite loading
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isLoadingPassword) {
        setState(() {
          _savedPassword = 'Loading timeout - please try again';
          _passwordController.text = _savedPassword;
          _isLoadingPassword = false;
        });
      }
    });
    
    // Try to use preloaded data first
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    if (preloader.userProfile != null) {
      final plainPassword = preloader.userProfile!['plain_password'];
      if (plainPassword != null && plainPassword.isNotEmpty) {
        setState(() {
          _savedPassword = plainPassword;
          _passwordController.text = _showPassword ? plainPassword : '••••••••';
          _isLoadingPassword = false;
        });
        return;
      }
    }
    
    // If no preloaded data, fetch from API
    _fetchVendorProfile();
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _fetchVendorProfile() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) {
      if (mounted) {
        setState(() {
          _savedPassword = 'Not authenticated';
          _passwordController.text = _savedPassword;
          _isLoadingPassword = false;
        });
      }
      return;
    }

    try {
      print('Fetching password from API...');
      
      // Try profile endpoint first (simpler)
      final profileResponse = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/profile/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );
      
      print('Profile API response: ${profileResponse.statusCode}');
      
      if (profileResponse.statusCode == 200) {
        final profileData = jsonDecode(profileResponse.body);
        final plainPassword = profileData['plain_password'] ?? 'Password not available';
        
        if (mounted) {
          setState(() {
            _savedPassword = plainPassword;
            _passwordController.text = _showPassword ? _savedPassword : '••••••••';
            _isLoadingPassword = false;
          });
        }
        return;
      }
      
      // Fallback: show error message
      if (mounted) {
        setState(() {
          _savedPassword = 'Unable to load password';
          _passwordController.text = _savedPassword;
          _isLoadingPassword = false;
        });
      }
      
    } catch (e) {
      print('Error fetching password: $e');
      if (mounted) {
        setState(() {
          _savedPassword = 'Error: ${e.toString()}';
          _passwordController.text = _savedPassword;
          _isLoadingPassword = false;
        });
      }
    }
  }

  Future<void> _handlePasswordChange() async {
    if (_newPassword.isEmpty) {
      _showSnackBar('New password is required', Colors.red);
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/change-password/simple/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'new_password': _newPassword}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _savedPassword = _newPassword;
            _newPassword = '';
            _newPasswordController.clear();
            _isChangingPassword = false;
          });
          _showSnackBar('Password changed successfully', Colors.green);
        }
      } else {
        throw Exception(data['error'] ?? 'Failed to change password');
      }
    } catch (e) {
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.fixed,
        margin: EdgeInsets.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Security & Login',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.security, color: Color(0xFFFFD60A), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Password',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (!_isChangingPassword) ...[
                    Text(
                      'Your Password',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _isLoadingPassword
                              ? Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2A2A2A),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD60A)),
                                      ),
                                    ),
                                  ),
                                )
                              : TextFormField(
                                  controller: _passwordController,
                                  enabled: false,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFF2A2A2A),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _isLoadingPassword ? null : () {
                            setState(() {
                              _showPassword = !_showPassword;
                              _passwordController.text = _showPassword ? _savedPassword : '••••••••';
                            });
                          },
                          icon: Icon(
                            _showPassword ? Icons.visibility_off : Icons.visibility,
                            color: _isLoadingPassword ? Colors.grey[600] : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_isLoading || _isLoadingPassword) ? null : () => setState(() => _isChangingPassword = true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD60A),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'Change Password',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'New Password',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _newPasswordController,
                      onChanged: (value) => _newPassword = value,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        hintText: 'Enter new password',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handlePasswordChange,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD60A),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                    ),
                                  )
                                : Text(
                                    'Save',
                                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : () {
                              setState(() {
                                _isChangingPassword = false;
                                _newPassword = '';
                                _newPasswordController.clear();
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF3A3A3A)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}