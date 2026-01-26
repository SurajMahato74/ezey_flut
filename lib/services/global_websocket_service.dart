import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter/material.dart';

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

  // Callbacks
  Function(Map<String, dynamic>)? onNewMessage;
  Function(Map<String, dynamic>)? onNotification;

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
      
    } catch (e) {
      print('❌ Failed to connect to global WebSocket: $e');
      _isConnected = false;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      print('📬 Global WebSocket message: $message');
      final data = jsonDecode(message);
      final type = data['type'];
      
      print('🔵 Message type: $type');
      print('🔵 Message data: $data');

      switch (type) {
        case 'new_message':
        case 'message':
          print('💬 New message notification');
          onNewMessage?.call(data);
          break;

        case 'typing_indicator':
        case 'typing':
          print('⌨️ Typing indicator');
          onNewMessage?.call(data);
          break;

        case 'message_read_receipt':
          print('✅ Message read receipt');
          onNewMessage?.call(data);
          break;

        case 'notification':
          print('🔔 New notification');
          onNotification?.call(data);
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