import 'dart:async';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class BackgroundService {
  static const MethodChannel _channel = MethodChannel('background_service');
  static WebSocketChannel? _wsChannel;
  static Timer? _heartbeatTimer;
  static bool _isActive = false;

  static Future<void> startService() async {
    if (_isActive) return;
    
    try {
      await _channel.invokeMethod('startForegroundService');
      await WakelockPlus.enable();
      _isActive = true;
      _startHeartbeat();
    } catch (e) {
      print('❌ Failed to start background service: $e');
    }
  }

  static Future<void> stopService() async {
    if (!_isActive) return;
    
    try {
      await _channel.invokeMethod('stopForegroundService');
      await WakelockPlus.disable();
      _wsChannel?.sink.close();
      _heartbeatTimer?.cancel();
      _isActive = false;
    } catch (e) {
      print('❌ Failed to stop background service: $e');
    }
  }

  static void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_wsChannel != null) {
        _wsChannel!.sink.add('{"type": "heartbeat"}');
      }
    });
  }

  static void connectWebSocket(String wsUrl) {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    } catch (e) {
      print('❌ WebSocket connection failed: $e');
    }
  }
}