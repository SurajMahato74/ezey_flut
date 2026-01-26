// lib/screens/main_app_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/global_websocket_service.dart';
import '../models/user_role.dart';  
import 'customer_navigation_screen.dart';
import 'vendor_main_screen.dart';

class MainAppScreen extends StatefulWidget {
  const MainAppScreen({super.key});

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> with RestorationMixin {
  final AuthService _authService = AuthService();
  final RestorableString _currentRoleRestoration = RestorableString('customer');
  GlobalWebSocketService? _globalWebSocket;

  @override
  String? get restorationId => 'main_app';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_currentRoleRestoration, 'current_role');
  }

  @override
  void initState() {
    super.initState();
    _authService.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  void _initializeServices() {
    _globalWebSocket = Provider.of<GlobalWebSocketService>(context, listen: false);
    
    // Connect to WebSocket if user is logged in
    if (_authService.isLoggedIn && _authService.token != null) {
      print('🔵 Connecting GlobalWebSocket for user: ${_authService.user?.id}');
      _globalWebSocket?.connect(_authService.token!);
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChanged);
    _globalWebSocket?.disconnect();
    super.dispose();
  }

  void _onAuthChanged() {
    final roleString = _authService.currentRole?.toString().split('.').last ?? 'customer';
    _currentRoleRestoration.value = roleString;
    
    // Connect/disconnect WebSocket based on auth state
    if (_authService.isLoggedIn && _authService.token != null) {
      _globalWebSocket?.connect(_authService.token!);
    } else {
      _globalWebSocket?.disconnect();
    }
    
    setState(() {});
  }

  void _switchRole() {
    _authService.switchRole();
  }

  @override
  Widget build(BuildContext context) {
    Widget mainScreen;
    if (_authService.currentRole == UserRole.vendor) {
      mainScreen = const VendorMainScreen();
    } else {
      mainScreen = CustomerNavigationScreen(onSwitchToVendor: _switchRole);
    }

    return mainScreen;
  }
}