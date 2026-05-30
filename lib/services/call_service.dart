import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/call.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  WebSocketChannel? _callWebSocket;
  StreamController<Map<String, dynamic>>? _callStatusController;
  Stream<Map<String, dynamic>>? _callStatusStream;
  
  Call? _currentCall;
  String? _currentCallId;
  
  // Getters
  Call? get currentCall => _currentCall;
  String? get currentCallId => _currentCallId;
  Stream<Map<String, dynamic>>? get callStatusStream => _callStatusStream;

  /// Initialize call service
  void initialize() {
    _callStatusController = StreamController<Map<String, dynamic>>.broadcast();
    _callStatusStream = _callStatusController!.stream;
  }

  /// Create and initiate a call
  Future<Call?> createCall(int receiverId, String callType) async {
    try {
      final token = AuthService().token;
      if (token == null) throw Exception('Not authenticated');

      print('🔵 Creating call via API...');
      final response = await ApiService().createCall(token, receiverId, callType);
      final callData = response['call'];
      
      _currentCall = Call.fromJson(callData);
      _currentCallId = _currentCall!.callId;
      
      print('✅ Call created - Channel: ${_currentCall!.callId}');
      
      // Connect to call WebSocket immediately after creating call
      await _connectToCallWebSocket(_currentCall!.callId);
      
      return _currentCall;
    } catch (e) {
      print('❌ Call creation failed: $e');
      return null;
    }
  }

  /// Connect to call-specific WebSocket
  Future<void> _connectToCallWebSocket(String callId) async {
    try {
      final token = AuthService().token;
      if (token == null) return;

      final wsUrl = 'wss://ezeyway.com/ws/calls/$callId/?token=$token';
      print('🔵 Connecting to call WebSocket: $wsUrl');
      
      _callWebSocket = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      // Listen for messages
      _callWebSocket!.stream.listen(
        (data) {
          try {
            final message = jsonDecode(data);
            print('📞 Call WebSocket message: $message');
            _callStatusController?.add(message);
          } catch (e) {
            print('❌ Error parsing call WebSocket message: $e');
          }
        },
        onError: (error) {
          print('❌ Call WebSocket error: $error');
        },
        onDone: () {
          print('🔵 Call WebSocket closed');
        },
      );

      // Send join_call message
      await Future.delayed(const Duration(milliseconds: 500));
      _sendCallMessage({
        'type': 'join_call',
        'call_id': callId,
        'call_type': 'audio'
      });

      print('✅ Connected to call WebSocket');
    } catch (e) {
      print('❌ Failed to connect to call WebSocket: $e');
    }
  }

  /// Accept an incoming call
  Future<void> acceptCall(String callId) async {
    try {
      _currentCallId = callId;
      
      // Connect to call WebSocket first
      await _connectToCallWebSocket(callId);
      
      // Send call accepted status
      _sendCallMessage({
        'type': 'call_status',
        'status': 'answered',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('✅ Call accepted: $callId');
    } catch (e) {
      print('❌ Failed to accept call: $e');
    }
  }

  /// Decline an incoming call
  Future<void> declineCall(String callId) async {
    try {
      // Connect briefly to send decline message
      await _connectToCallWebSocket(callId);
      
      _sendCallMessage({
        'type': 'call_status',
        'status': 'declined',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('✅ Call declined: $callId');
      await Future.delayed(const Duration(milliseconds: 500));
      _disconnectCallWebSocket();
    } catch (e) {
      print('❌ Failed to decline call: $e');
    }
  }

  /// End the current call
  Future<void> endCall() async {
    if (_currentCallId == null) return;

    try {
      _sendCallMessage({
        'type': 'call_status',
        'status': 'ended',
        'call_id': _currentCallId!,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('✅ Call ended: $_currentCallId');
      
      await Future.delayed(const Duration(milliseconds: 500));
      _cleanup();
    } catch (e) {
      print('❌ Failed to end call: $e');
      _cleanup();
    }
  }

  /// Send message to call WebSocket
  void _sendCallMessage(Map<String, dynamic> message) {
    if (_callWebSocket?.sink != null) {
      _callWebSocket!.sink.add(jsonEncode(message));
      print('📤 Sent call message: $message');
    } else {
      print('❌ Call WebSocket not connected, cannot send: $message');
    }
  }

  /// Disconnect call WebSocket
  void _disconnectCallWebSocket() {
    _callWebSocket?.sink.close();
    _callWebSocket = null;
  }

  /// Cleanup call resources
  void _cleanup() {
    _disconnectCallWebSocket();
    _currentCall = null;
    _currentCallId = null;
  }

  /// Dispose resources
  void dispose() {
    _cleanup();
    _callStatusController?.close();
    _callStatusController = null;
    _callStatusStream = null;
  }
}