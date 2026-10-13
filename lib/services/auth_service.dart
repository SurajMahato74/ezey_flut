import 'dart:async';
// lib/services/auth_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_role.dart';
import '../models/user.dart';
import '../models/login_response.dart';
import 'api_service.dart';
import 'navigation_service.dart';
import '../screens/role_selection_screen.dart';

final authService = AuthService();
class AuthService extends ChangeNotifier {
  // Singleton
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    _initialization = _loadFromStorage();
  }

  @visibleForTesting
  AuthService.forTesting() { _initialization = _loadFromStorage(); }

  late Future<void> _initialization;
  Future<void> get initialized => _initialization;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  String? _initializationError;
  String? get initializationError => _initializationError;
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;
  Future<void> _storageWrite = Future<void>.value();

  Future<void> retrySessionRestore() {
    _initializationError = null;
    _isInitialized = false;
    _initialization = _loadFromStorage();
    notifyListeners();
    return _initialization;
  }

  // State
  UserRole? _currentRole;
  bool _isLoggedIn = false;
  String? _token;
  User? _user;
  List<String> _availableRoles = [];
  bool _hasAgreedToPrivacy = false;
  bool? _vendorProfileExists;
  bool? _vendorProfileApproved;
  bool _switchingRole = false;

  bool? get vendorProfileExists => _vendorProfileExists;

  // Getters
  UserRole? get currentRole => _currentRole;
  bool get isLoggedIn => _isLoggedIn;
  String? get token => _token;
  User? get user => _user;
  List<String> get availableRoles => _availableRoles;
  bool get hasAgreedToPrivacy => _hasAgreedToPrivacy;

  // Restore only a server-validated session. A late response cannot undo logout.
  Future<void> _loadFromStorage() async {
    final revision = _sessionRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (revision != _sessionRevision) return;
      final savedToken = prefs.getString('token');
      if (savedToken == null || savedToken.isEmpty) {
        await clearSession(guestRole: prefs.getBool('guest_session') == true
            ? UserRole.customer : null);
        return;
      }
      final profile = await ApiService().getProfile(savedToken);
      if (revision != _sessionRevision) return;
      final restoredUser = User.fromJson(profile);
      final vendor = await ApiService().getVendorProfileStatus(savedToken);
      if (revision != _sessionRevision) return;
      _token = savedToken;
      _user = restoredUser;
      _isLoggedIn = true;
      _availableRoles = ['customer', if (vendor['is_approved'] == true) 'vendor'];
      _vendorProfileExists = vendor['exists'] == true;
      _vendorProfileApproved = vendor['is_approved'] == true;
      _hasAgreedToPrivacy = restoredUser.privacyPolicyAgreed;
      _currentRole = prefs.getString('last_role') == 'vendor' && _vendorProfileApproved == true
          ? UserRole.vendor : UserRole.customer;
      await _saveToStorage();
    } on SessionExpiredException {
      if (revision == _sessionRevision) await clearSession();
    } catch (_) {
      if (revision == _sessionRevision) {
        _initializationError = 'Could not verify your saved session. Check your connection and retry, or continue as a guest.';
      }
    } finally {
      if (revision == _sessionRevision) {
        _isInitialized = true;
        notifyListeners();
      }
    }
  }

  // Serialize snapshots so an older login write cannot finish after logout.
  Future<void> _saveToStorage() {
    final snapshot = <String, Object?>{
      'token': _token,
      'user': _user == null ? null : jsonEncode(_user!.toJson()),
      'available_roles': List<String>.from(_availableRoles),
      'has_agreed_privacy': _hasAgreedToPrivacy,
      'last_role': _currentRole?.name,
      'guest_session': !_isLoggedIn && _currentRole == UserRole.customer,
      'vendor_profile_exists': _vendorProfileExists,
      'vendor_profile_approved': _vendorProfileApproved,
    };
    final write = _storageWrite.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in snapshot.entries) {
        final value = entry.value;
        if (value == null) {
          await prefs.remove(entry.key);
        } else if (value is String) {
          await prefs.setString(entry.key, value);
        } else if (value is bool) {
          await prefs.setBool(entry.key, value);
        } else if (value is List<String>) {
          await prefs.setStringList(entry.key, value);
        }
      }
    });
    _storageWrite = write.catchError((Object _) {});
    return write;
  }

  // Normal login
  Future<LoginResponse> login(String username, String password, {UserRole? selectedRole}) async {
    final revision = _sessionRevision;
    final response = await ApiService().login(username, password);
    if (revision != _sessionRevision) throw Exception('Login cancelled because your session changed.');
    if (response is LoginResponse) {
      await completeLogin(response, selectedRole: selectedRole);
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
    final revision = _sessionRevision;
    final response = await ApiService().verifyOtp(email, otp);
    if (revision != _sessionRevision) throw Exception('Login cancelled because your session changed.');
    await completeLogin(response, selectedRole: selectedRole);
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
    _sessionRevision++;
    _isInitialized = true;
    _initializationError = null;
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
  Future<void> completeLogin(LoginResponse response, {UserRole? selectedRole}) async {
    if (!response.isFullLogin) {
      throw Exception('Login did not complete. Please try again.');
    }
    _sessionRevision++;
    _isInitialized = true;
    _initializationError = null;
    _vendorProfileExists = response.profileExists;
    _vendorProfileApproved = response.isApproved;
    _currentRole = null;
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
        // Keep the selected role while routing by profile and approval status.
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
    // Only a confirmed absent profile needs onboarding. Approval is separate.
    return selectedRole == UserRole.vendor && 
           _vendorProfileExists == false &&
           _isLoggedIn;
  }
  
  // Check if vendor profile exists but not approved
  bool hasVendorProfilePending() {
    return _vendorProfileExists == true &&
           _vendorProfileApproved == false &&
           _isLoggedIn;
  }

  // Force update available roles (for API-confirmed role switches)
  void updateAvailableRoles(List<String> roles) {
    _availableRoles = roles;
    _saveToStorage();
    notifyListeners();
  }

  Future<Map<String, dynamic>> refreshVendorProfileStatus() async {
    final sessionToken = _token;
    if (!_isLoggedIn || sessionToken == null || _user == null) {
      throw Exception('Please sign in before switching accounts.');
    }
    final status = await ApiService().getVendorProfileStatus(sessionToken);
    if (_token != sessionToken) throw Exception('Your session changed. Please try again.');
    _vendorProfileExists = status['exists'] == true;
    _vendorProfileApproved = status['is_approved'] == true;
    await _saveToStorage();
    notifyListeners();
    return status;
  }

  /// Returns false only when the server confirms a vendor profile is absent.
  /// Local roles are updated only after the server accepts the requested role.
  Future<bool> switchToRole(UserRole role) async {
    if (_switchingRole) throw Exception('An account switch is already in progress.');
    final sessionToken = _token;
    if (!_isLoggedIn || sessionToken == null || _user == null) {
      throw Exception('Please sign in before switching accounts.');
    }
    _switchingRole = true;
    try {
      if (role == UserRole.vendor) {
        final profile = await refreshVendorProfileStatus();
        if (profile['exists'] == false) return false;
        if (profile['is_rejected'] == true) {
          final reason = profile['rejection_reason'];
          throw Exception('Your vendor profile was rejected. ${reason ?? 'Please contact support.'}');
        }
        if (profile['is_approved'] != true) {
          throw Exception('Your vendor profile is pending admin approval. You do not need to submit it again.');
        }
      }
      final roleName = role == UserRole.vendor ? 'vendor' : 'customer';
      final data = await ApiService().switchAccountRole(sessionToken, roleName);
      if (_token != sessionToken) throw Exception('Your session changed. Please sign in again.');
      final roles = List<String>.from(data['available_roles'] ?? []);
      if (data['current_role'] != roleName || !roles.contains(roleName) || data['user'] == null) {
        throw Exception('The server did not confirm the requested account mode. Please try again.');
      }
      final updatedUser = User.fromJson(data['user']);
      if (updatedUser.id != _user?.id) throw Exception('The account response did not match your session. Please sign in again.');
      _user = updatedUser;
      _availableRoles = roles;
      _currentRole = role;
      await _saveToStorage();
      notifyListeners();
      return true;
    } finally {
      _switchingRole = false;
    }
  }

  Future<void> loginAsGuest(UserRole role) => clearSession(guestRole: UserRole.customer);

  Future<void> clearSession({UserRole? guestRole}) async {
    _sessionRevision++;
    _currentRole = guestRole;
    _isLoggedIn = false;
    _token = null;
    _user = null;
    _availableRoles = [];
    _hasAgreedToPrivacy = false;
    _vendorProfileExists = null;
    _vendorProfileApproved = null;
    _initializationError = null;
    _isInitialized = true;
    NavigationService().setCurrentPage('home');
    final saved = _saveToStorage();
    notifyListeners();
    await saved;
  }

  Future<void> logout(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final previousToken = _token;
    // Clear locally first; an offline logout must not leave an active account.
    final clearing = clearSession();
    if (previousToken != null) unawaited(ApiService().logout(previousToken));
    await clearing;
    if (!navigator.mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (_) => false,
    );
  }

  // 24. UPDATE USER PROFILE
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    if (_token == null) return;
    final revision = _sessionRevision;
    try {
      final updatedData = await ApiService().updateProfile(_token!, data);
      if (revision != _sessionRevision) return;
      
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
    final revision = _sessionRevision;
    try {
      final response = await ApiService().changePassword(_token!, newPassword);
      if (revision != _sessionRevision) return;
      
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
    final revision = _sessionRevision;
    try {
      final response = await ApiService().uploadProfilePicture(_token!, file);
      if (revision != _sessionRevision) return;
      
      // Response is like: {"success": true, "profile_picture": "/media/..."}
      // We need to update the local user object with the new picture
      if (response['success'] == true && _user != null) {
        // Refresh the full profile to be safe and get generated URLs
        final profileData = await ApiService().getProfile(_token!);
        if (revision != _sessionRevision) return;
        _user = User.fromJson(profileData);
        await _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }
}