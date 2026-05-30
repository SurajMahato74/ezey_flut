import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'auth_service.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'complete_call_system.dart';

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static BuildContext? _context;

  static Future<void> initialize(BuildContext context) async {
    _context = context;
    
    // Initialize notification service
    await NotificationService.initialize();
    
    // Request permissions
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Get FCM token
    final token = await _messaging.getToken();
    print('📱 FCM Token: $token');
    
    // Send token to backend
    if (token != null) {
      await _sendTokenToBackend(token);
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) {
      print('📱 FCM Token refreshed: $newToken');
      _sendTokenToBackend(newToken);
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background message taps
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);
    
    // Handle app launch from notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleBackgroundMessageTap(initialMessage);
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      final authService = AuthService();
      if (authService.token != null) {
        print('🔄 Sending FCM token to backend...');
        final apiService = ApiService();
        await apiService.updateFCMToken(authService.token!, token);
        print('✅ FCM token sent to backend successfully');
      }
    } catch (e) {
      print('❌ Failed to send FCM token: $e');
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📱 Foreground FCM message received');
    print('📱 Message data: ${message.data}');
    print('📱 Message notification: ${message.notification?.toMap()}');
    
    // Handle incoming call notifications
    if (message.data['type'] == 'incoming_call') {
      final callerName = message.data['caller_name'] ?? 'Unknown';
      final callId = message.data['call_id'] ?? '';
      
      // Check for duplicate call
      if (CompleteCallSystem.isCallActive(callId)) {
        print('🚫 Call already active, ignoring duplicate FCM');
        return;
      }
      
      // Set as active before showing call screen
      CompleteCallSystem.setActiveCall(callId);
      
      await _showCallKitUI(callerName, callId);
      return;
    }
    
    // Show local notification for non-call messages
    if (message.notification != null) {
      try {
        await NotificationService.showLocalNotification(
          title: message.notification!.title ?? 'New Message',
          body: message.notification!.body ?? '',
          payload: message.data.toString(),
        );
      } catch (e) {
        print('❌ Failed to show notification: $e');
      }
    }
  }

  static Future<void> _handleBackgroundMessageTap(RemoteMessage message) async {
    print('📱 Background message tap');
    print('📱 Message data: ${message.data}');
  }
  static Future<void> _showCallKitUI(String callerName, String callId) async {
    await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Ezeyway',
      avatar: '',
      handle: '',
      type: 0,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: <String, dynamic>{'callId': callId},
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
      ),
    ));
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📱 Background FCM message received');
  print('📱 Message data: ${message.data}');
  
  // Handle incoming call in background
  if (message.data['type'] == 'incoming_call') {
    final callerName = message.data['caller_name'] ?? 'Unknown';
    final callId = message.data['call_id'] ?? '';
    
    // Check for duplicate call
    if (CompleteCallSystem.isCallActive(callId)) {
      print('🚫 Call already active, ignoring duplicate FCM background');
      return;
    }
    
    // Set as active before showing call screen
    CompleteCallSystem.setActiveCall(callId);
    
    await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Ezeyway',
      avatar: '',
      handle: '',
      type: 0,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: <String, dynamic>{'callId': callId},
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
      ),
    ));
  }
}