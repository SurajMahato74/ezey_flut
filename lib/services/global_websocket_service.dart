import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'call_service.dart';
import 'complete_call_system.dart';

class GlobalWebSocketService {
  static final GlobalWebSocketService _instance = GlobalWebSocketService._internal();
  factory GlobalWebSocketService() => _instance;
  GlobalWebSocketService._internal();

  WebSocketChannel? _channel;
  String? _token;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // Broadcast streams for different message types
  final StreamController<Map<String, dynamic>> _messageStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _callStatusStreamController = StreamController<Map<String, dynamic>>.broadcast();

  // Legacy callbacks for backward compatibility
  Function(Map<String, dynamic>)? onNewMessage;
  Function(Map<String, dynamic>)? onNotification;

  // Stream getters
  Stream<Map<String, dynamic>> get messageStream => _messageStreamController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationStreamController.stream;
  Stream<Map<String, dynamic>> get callStatusStream => _callStatusStreamController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect(String token) async {
    if (_isConnected && _token == token) {
      print('🔵 GlobalWebSocket already connected with same token');
      return;
    }
    
    _token = token;
    await _disconnect();
    
    try {
      final wsUrl = 'wss://ezeyway.com/ws/messages/?token=$token';
      print('🔵 Connecting to global WebSocket: $wsUrl');
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
      );
      
      _isConnected = true;
      _reconnectAttempts = 0;
      print('✅ Global WebSocket connected successfully');
      
      // Send a ping to confirm connection
      sendMessage({'type': 'ping', 'timestamp': DateTime.now().toIso8601String()});
      // Set up CallKit event listener
      _setupCallKitListener();
      
    } catch (e) {
      print('❌ Failed to connect to global WebSocket: $e');
      _isConnected = false;
    }
  }

  void _setupCallKitListener() {
    FlutterCallkitIncoming.onEvent.listen((event) {
      switch (event!.event) {
        case Event.actionCallAccept:
          print('📞 CallKit: Call accepted');
          final callId = event.body['extra']?['callId'];
          if (callId != null) {
            CallService().acceptCall(callId);
          }
          break;
        case Event.actionCallDecline:
          print('📞 CallKit: Call declined');
          final callId = event.body['extra']?['callId'];
          if (callId != null) {
            CallService().declineCall(callId);
          }
          break;
        case Event.actionCallEnded:
          print('📞 CallKit: Call ended');
          CallService().endCall();
          break;
        default:
          print('📞 CallKit: Unhandled event: ${event.event}');
      }
    });
  }

  void _handleMessage(dynamic message) {
    try {
      print('📬 Global WebSocket message: $message');
      final data = jsonDecode(message);
      final type = data['type'];
      
      print('🔵 Message type: $type');
      print('🔵 Message data: $data');
      print('🔵 Current listeners - onNewMessage: ${onNewMessage != null}, onNotification: ${onNotification != null}');
      print('🔵 Stream listeners - message: ${_messageStreamController.hasListener}, notification: ${_notificationStreamController.hasListener}, callStatus: ${_callStatusStreamController.hasListener}');

      switch (type) {
        case 'new_message':
        case 'message':
          print('💬 New message notification');
          _messageStreamController.add(data);
          onNewMessage?.call(data);
          break;

        case 'typing_indicator':
        case 'typing':
          print('⌨️ Typing indicator');
          _messageStreamController.add(data);
          onNewMessage?.call(data);
          break;

        case 'message_read_receipt':
          print('✅ Message read receipt');
          _messageStreamController.add(data);
          onNewMessage?.call(data);
          break;

        case 'incoming_call':
          print('📞 Incoming call via WebSocket');
          
          // Check for duplicate call
          final callId = data['call']?['call_id'];
          if (callId != null && CompleteCallSystem.isCallActive(callId)) {
            print('🚫 Call already active, ignoring duplicate');
            return;
          }
          
          // Set as active before showing call screen
          if (callId != null) {
            CompleteCallSystem.setActiveCall(callId);
          }
          
          _notificationStreamController.add(data);
          onNotification?.call(data);
          break;

        case 'call_accepted':
          print('✅ Call accepted notification');
          print('🔵 Call accepted data: $data');
          // Notify both callbacks to ensure the calling screen gets the update
          final callStatusData = {
            'type': 'call_status_update',
            'status': 'accepted',
            'call_id': data['call_id'] ?? data['call']?['call_id'],
            'call_data': data['call'],
          };
          print('🔵 Broadcasting call status update: $callStatusData');
          _callStatusStreamController.add(callStatusData);
          _notificationStreamController.add(callStatusData);
          // Legacy callback support
          onNotification?.call(callStatusData);
          onNewMessage?.call(callStatusData);
          break;

        case 'call_declined':
          print('❌ Call declined notification');
          print('🔵 Call declined data: $data');
          final callDeclinedData = {
            'type': 'call_status_update', 
            'status': 'declined',
            'call_id': data['call_id'] ?? data['call']?['call_id'],
            'call_data': data['call'],
          };
          print('🔵 Broadcasting call status update: $callDeclinedData');
          _callStatusStreamController.add(callDeclinedData);
          _notificationStreamController.add(callDeclinedData);
          // Legacy callback support
          onNotification?.call(callDeclinedData);
          onNewMessage?.call(callDeclinedData);
          break;

        case 'call_ended':
          print('🔴 Call ended notification');
          print('🔵 Call ended data: $data');
          final callEndedData = {
            'type': 'call_status_update',
            'status': 'ended', 
            'call_id': data['call_id'] ?? data['call']?['call_id'],
            'call_data': data['call'],
          };
          print('🔵 Broadcasting call status update: $callEndedData');
          _callStatusStreamController.add(callEndedData);
          _notificationStreamController.add(callEndedData);
          // Legacy callback support
          onNotification?.call(callEndedData);
          onNewMessage?.call(callEndedData);
          break;

        case 'notification':
          print('🔔 New notification');
          _notificationStreamController.add(data);
          onNotification?.call(data);
          break;

        case 'test_call_connection':
          print('🔵 Test call connection message received');
          break;

        case 'test_call_status':
          print('🔵 Test call status message received - simulating call_accepted');
          // Simulate a call_accepted message for testing
          final testCallStatusData = {
            'type': 'call_status_update',
            'status': 'test_accepted',
            'call_id': data['call_id'],
          };
          print('🔵 Broadcasting test call status: $testCallStatusData');
          _callStatusStreamController.add(testCallStatusData);
          _notificationStreamController.add(testCallStatusData);
          break;

        case 'pong':
          print('🏓 Received pong from server');
          break;

        case 'ping':
          print('🏓 Received ping from server, sending pong');
          sendMessage({'type': 'pong', 'timestamp': DateTime.now().toIso8601String()});
          break;

        default:
          print('🔵 Unhandled message type: $type');
          print('🔵 Full message: $data');
      }
    } catch (e) {
      print('❌ Error handling global WebSocket message: $e');
      print('❌ Raw message: $message');
    }
  }

  void _handleError(error) {
    print('❌ Global WebSocket error: $error');
    _isConnected = false;
    
    // Only reconnect if it's not a network/DNS error (app likely backgrounded)
    if (!error.toString().contains('Failed host lookup') && 
        !error.toString().contains('No address associated with hostname')) {
      _scheduleReconnect();
    }
  }

  void _handleDisconnection() {
    print('🔴 Global WebSocket disconnected');
    _isConnected = false;
    
    // For web platform, always try to reconnect when disconnected
    if (_token != null) {
      print('🔄 Web platform - scheduling immediate reconnect');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('❌ Max reconnection attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    // Shorter delay for web platform
    final delay = Duration(milliseconds: 500 + (1000 * _reconnectAttempts));
    
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      print('🔄 Attempting to reconnect ($_reconnectAttempts/$_maxReconnectAttempts)');
      if (_token != null) {
        connect(_token!);
      }
    });
  }

  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    if (_channel != null) {
      await _channel!.sink.close(status.normalClosure);
      _channel = null;
    }
    _isConnected = false;
  }

  Future<void> disconnect() async {
    _token = null;
    await _disconnect();
  }
  
  // Method to properly dispose of the service (should only be called when app is closing)
  void dispose() {
    _messageStreamController.close();
    _notificationStreamController.close();
    _callStatusStreamController.close();
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      try {
        final messageStr = jsonEncode(message);
        _channel!.sink.add(messageStr);
        print('📤 Sent WebSocket message: ${message['type']}');
      } catch (e) {
        print('❌ Failed to send WebSocket message: $e');
      }
    } else {
      print('⚠️ Cannot send message - WebSocket not connected');
    }
  }

  // Method to test WebSocket connectivity
  void testConnection() {
    if (_isConnected) {
      sendMessage({
        'type': 'test_message',
        'timestamp': DateTime.now().toIso8601String(),
        'message': 'Testing WebSocket connectivity'
      });
    } else {
      print('❌ WebSocket not connected - cannot test');
    }
  }


}