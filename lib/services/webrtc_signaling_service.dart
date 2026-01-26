import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class WebRTCSignalingService {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  
  // Callbacks
  Function(String)? onCallAccepted;
  Function(String)? onCallRejected;
  Function(String, String)? onAgoraToken; // (channelName, token)
  
  bool get isConnected => _isConnected;
  
  Future<void> connect(String token) async {
    try {
      final wsUrl = 'wss://ezeyway.com/ws/calls/?token=$token';
      print('🔵 Connecting to call signaling WebSocket: $wsUrl');
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
      );
      
      _isConnected = true;
      print('✅ Call signaling WebSocket connected');
      
    } catch (e) {
      print('❌ Failed to connect to call signaling WebSocket: $e');
      _isConnected = false;
    }
  }
  
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];
      
      switch (type) {
        case 'call_accepted':
          final callId = data['call_id'];
          onCallAccepted?.call(callId);
          break;
          
        case 'call_rejected':
          final callId = data['call_id'];
          onCallRejected?.call(callId);
          break;
          
        case 'agora_token':
          final channelName = data['channel_name'];
          final token = data['token'];
          onAgoraToken?.call(channelName, token);
          break;
          
        default:
          print('🔵 Unhandled signaling message type: $type');
      }
    } catch (e) {
      print('❌ Error handling signaling message: $e');
    }
  }
  
  void _handleError(error) {
    print('❌ Call signaling WebSocket error: $error');
    _isConnected = false;
  }
  
  void _handleDisconnection() {
    print('🔴 Call signaling WebSocket disconnected');
    _isConnected = false;
  }
  
  void sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      try {
        final messageStr = jsonEncode(message);
        _channel!.sink.add(messageStr);
        print('📤 Sent signaling message: ${message['type']}');
      } catch (e) {
        print('❌ Failed to send signaling message: $e');
      }
    } else {
      print('⚠️ Cannot send signaling message - WebSocket not connected');
    }
  }
  
  Future<void> disconnect() async {
    if (_channel != null) {
      await _channel!.sink.close(status.normalClosure);
      _channel = null;
    }
    _isConnected = false;
  }
}