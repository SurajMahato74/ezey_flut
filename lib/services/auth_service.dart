// lib/services/auth_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_role.dart';
import '../models/user.dart';
import '../models/login_response.dart';
import 'api_service.dart';
import '../screens/role_selection_screen.dart';

final authService = AuthService();
class AuthService extends ChangeNotifier {
  // Singleton
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    _loadFromStorage();
  }

  // State
  UserRole? _currentRole;
  bool _isLoggedIn = false;
  String? _token;
  User? _user;
  List<String> _availableRoles = [];
  bool _hasAgreedToPrivacy = false;

  // Getters
  UserRole? get currentRole => _currentRole;
  bool get isLoggedIn => _isLoggedIn;
  String? get token => _token;
  User? get user => _user;
  List<String> get availableRoles => _availableRoles;
  bool get hasAgreedToPrivacy => _hasAgreedToPrivacy;

  // Load from storage
  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');

    final userJson = prefs.getString('user');
    if (userJson != null) {
      _user = User.fromJson(jsonDecode(userJson));
    }

    final rolesList = prefs.getStringList('available_roles');
    _availableRoles = rolesList ?? [];

    _hasAgreedToPrivacy = prefs.getBool('has_agreed_privacy') ?? false;

    final lastRole = prefs.getString('last_role');
    if (lastRole != null) {
      _currentRole = lastRole == 'vendor' ? UserRole.vendor : UserRole.customer;
    }

    _isLoggedIn = _token != null && _user != null;
    notifyListeners();
  }

  // Save to storage
  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();

    if (_token != null) {
      await prefs.setString('token', _token!);
    } else {
      await prefs.remove('token');
    }

    if (_user != null) {
      await prefs.setString('user', jsonEncode(_user!.toJson()));
    } else {
      await prefs.remove('user');
    }

    await prefs.setStringList('available_roles', _availableRoles);
    await prefs.setBool('has_agreed_privacy', _hasAgreedToPrivacy);

    if (_currentRole != null) {
      await prefs.setString('last_role', _currentRole.toString().split('.').last);
    } else {
      await prefs.remove('last_role');
    }
  }

  // Normal login
  Future<LoginResponse> login(String username, String password, {UserRole? selectedRole}) async {
    final response = await ApiService().login(username, password);
    if (response is LoginResponse) {
      await _completeLogin(response, selectedRole: selectedRole);
    }
    return response is LoginResponse ? response : LoginResponse(
      token: null,
      user: null,
      availableRoles: null,
      currentRole: null,
      profileExists: null,
      isApproved: null,
      message: 'Login failed',
    );
  }

  // OTP Login
  Future<LoginResponse> loginWithOtp(String email, String otp, {UserRole? selectedRole}) async {
    final response = await ApiService().verifyOtp(email, otp);
    await _completeLogin(response, selectedRole: selectedRole);
    return response;
  }


  // Register
  Future<void> register({
    required String username,
    required String email,
    required String password,
    required String userType,
    String? phoneNumber,
  }) async {
    await ApiService().register(
      username: username,
      email: email,
      password: password,
      userType: userType,
      phoneNumber: phoneNumber,
    );
  }

  // Public method to save login data
  Future<void> saveLoginData(String token, User user, UserRole selectedRole) async {
    _token = token;
    _user = user;
    _availableRoles = ['customer', 'vendor']; // Assume both roles after approval
    _hasAgreedToPrivacy = true;
    _isLoggedIn = true;
    _currentRole = selectedRole;
    
    await _saveToStorage();
    notifyListeners();
  }

  // COMMON LOGIN SUCCESS HANDLER — FIXED NULL SAFETY
  Future<void> _completeLogin(LoginResponse response, {UserRole? selectedRole}) async {
    _token = response.token;
    _user = response.user;

    // FIX 1: Handle nullable List<String>?
    _availableRoles = response.availableRoles ?? [];

    _hasAgreedToPrivacy = true;
    _isLoggedIn = true;

    // FIX 2: Respect user's selected role first, then backend role, then default
    if (selectedRole != null) {
      final selectedRoleStr = selectedRole == UserRole.vendor ? 'vendor' : 'customer';
      if (_availableRoles.contains(selectedRoleStr)) {
        _currentRole = selectedRole;
      } else if (selectedRole == UserRole.vendor && !_availableRoles.contains('vendor')) {
        // User selected vendor but doesn't have vendor role = needs profile completion
        _currentRole = UserRole.vendor; // Set temporarily for navigation
      }
    }
    
    if (_currentRole == null) {
      final backendRole = response.currentRole ?? '';
      if (backendRole.isNotEmpty && _availableRoles.contains(backendRole)) {
        _currentRole = backendRole == 'vendor' ? UserRole.vendor : UserRole.customer;
      } else if (_availableRoles.contains('customer')) {
        _currentRole = UserRole.customer;
      } else if (_availableRoles.contains('vendor')) {
        _currentRole = UserRole.vendor;
      }
    }

    await _saveToStorage();
    notifyListeners();
  }

  // Check if vendor needs profile completion
  bool needsVendorProfileCompletion(UserRole? selectedRole) {
    // Only return true if vendor role selected AND no vendor role available AND logged in
    // This means profile doesn't exist yet
    return selectedRole == UserRole.vendor && 
           !_availableRoles.contains('vendor') && 
           _isLoggedIn;
  }
  
  // Check if vendor profile exists but not approved
  bool hasVendorProfilePending() {
    return _user?.userType == 'vendor' && 
           !_availableRoles.contains('vendor') &&
           _isLoggedIn;
  }

  // Force update available roles (for API-confirmed role switches)
  void updateAvailableRoles(List<String> roles) {
    _availableRoles = roles;
    _saveToStorage();
    notifyListeners();
  }

  // Role management
  void setRole(UserRole role) {
    final roleStr = role == UserRole.vendor ? 'vendor' : 'customer';
    // Allow setting role even if not in available roles (for API-confirmed switches)
    _currentRole = role;
    _saveToStorage();
    notifyListeners();
  }

  void switchRole() {
    if (_currentRole == UserRole.customer && _availableRoles.contains('vendor')) {
      _currentRole = UserRole.vendor;
    } else if (_currentRole == UserRole.vendor && _availableRoles.contains('customer')) {
      _currentRole = UserRole.customer;
    } else {
      // Force switch even if role not in available roles (for API-confirmed switches)
      if (_currentRole == UserRole.customer) {
        _currentRole = UserRole.vendor;
      } else {
        _currentRole = UserRole.customer;
      }
    }
    _saveToStorage();
    notifyListeners();
  }

  Future<void> loginAsGuest(UserRole role) async {
    _currentRole = role;
    _isLoggedIn = false; // Guest is not logged in
    _token = null;
    _user = null;
    await _saveToStorage();
    notifyListeners();
  }

  // Logout
  Future<void> logout(BuildContext context) async {
    bool apiSuccess = false;
    if (_token != null) {
      try {
        apiSuccess = await ApiService().logout(_token!);
      } catch (_) {}
    }

    // Full reset
    _currentRole = null;
    _isLoggedIn = false;
    _token = null;
    _user = null;
    _availableRoles = [];
    _hasAgreedToPrivacy = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    notifyListeners();

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(apiSuccess ? 'Logged out successfully' : 'Logged out locally'),
        backgroundColor: apiSuccess ? Colors.green : Colors.orange,
      ),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  // 24. UPDATE USER PROFILE
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    if (_token == null) return;
    try {
      final updatedData = await ApiService().updateProfile(_token!, data);
      
      // Merge updated data into current user
      // Since User is immutable, we create a new one from the response (which should be the full user object)
      // If the API returns the full user object:
      _user = User.fromJson(updatedData);
      await _saveToStorage();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  // 26. CHANGE PASSWORD
  Future<void> changePassword(String newPassword) async {
    if (_token == null) return;
    try {
      final response = await ApiService().changePassword(_token!, newPassword);
      
      // Response: {'token': 'new_token_key', 'message': '...'}
      if (response['token'] != null) {
        _token = response['token'];
        // Update user's plain password locally for display
        if (_user != null) {
          // We need to clone and update user because User is final
          final newUserJson = _user!.toJson();
          newUserJson['plain_password'] = newPassword;
          _user = User.fromJson(newUserJson);
        }
        await _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }
  Future<void> updateProfilePicture(XFile file) async {
    if (_token == null) return;
    try {
      final response = await ApiService().uploadProfilePicture(_token!, file);
      
      // Response is like: {"success": true, "profile_picture": "/media/..."}
      // We need to update the local user object with the new picture
      if (response['success'] == true && _user != null) {
        // Refresh the full profile to be safe and get generated URLs
        final profileData = await ApiService().getProfile(_token!);
        _user = User.fromJson(profileData);
        await _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }
}