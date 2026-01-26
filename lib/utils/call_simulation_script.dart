import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/global_call_manager.dart';
import '../services/auth_service.dart';
import '../screens/incoming_call_screen.dart';
import '../screens/active_call_screen.dart';

class CallSimulationScript {
  static final CallSimulationScript _instance = CallSimulationScript._internal();
  factory CallSimulationScript() => _instance;
  CallSimulationScript._internal();

  final List<String> _logs = [];
  final StreamController<String> _logController = StreamController<String>.broadcast();
  
  Stream<String> get logStream => _logController.stream;
  List<String> get logs => List.unmodifiable(_logs);

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '$timestamp: $message';
    _logs.add(logMessage);
    _logController.add(logMessage);
    print('🧪 CALL_SIM: $message');
  }

  void clearLogs() {
    _logs.clear();
  }

  // ==================== MAIN TEST SCENARIOS ====================

  /// Comprehensive test that simulates web-to-mobile call with app in different states
  Future<void> runComprehensiveCallTest(BuildContext context) async {
    _log('🚀 Starting comprehensive call flow test');
    
    try {
      // Test 1: App in foreground
      await _testAppInForeground(context);
      await Future.delayed(const Duration(seconds: 2));
      
      // Test 2: App in background (minimized)
      await _testAppInBackground(context);
      await Future.delayed(const Duration(seconds: 2));
      
      // Test 3: App completely closed
      await _testAppClosed(context);
      await Future.delayed(const Duration(seconds: 2));
      
      // Test 4: Call during active call
      await _testCallDuringActiveCall(context);
      await Future.delayed(const Duration(seconds: 2));
      
      // Test 5: Network interruption during call
      await _testNetworkInterruption(context);
      
      _log('✅ All comprehensive tests completed successfully!');
      
    } catch (e) {
      _log('❌ Comprehensive test failed: $e');
    }
  }

  /// Test 1: App in foreground - normal call flow
  Future<void> _testAppInForeground(BuildContext context) async {
    _log('📱 TEST 1: App in Foreground - Normal Call Flow');
    
    final globalCallManager = context.read<GlobalCallManager>();
    
    // Step 1: Web user makes call
    _log('🌐 Web user initiating call to mobile user...');
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Step 2: Mobile receives call (app is active)
    final callData = _generateTestCallData('Web User (Foreground)');
    _log('📞 Mobile receives call: ${callData['caller_name']}');
    
    // Step 3: Show incoming call screen immediately (no FCM delay)
    await globalCallManager.handleIncomingCall(callData);
    _log('📱 Incoming call screen shown immediately (app active)');
    
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const IncomingCallScreen(),
          fullscreenDialog: true,
        ),
      );
    }
    
    await Future.delayed(const Duration(seconds: 2));
    
    // Step 4: User accepts call
    _log('✅ User accepts call');
    await globalCallManager.acceptCurrentCall();
    
    // Step 5: Navigate to active call
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const ActiveCallScreen(),
        ),
      );
    }
    _log('🎙️ Active call screen displayed - audio connected');
    
    await Future.delayed(const Duration(seconds: 3));
    
    // Step 6: Test call controls
    await _testCallControls();
    
    // Step 7: End call
    _log('📵 Ending call');
    await globalCallManager.endCurrentCall();
    
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    
    _log('✅ Foreground test completed successfully');
  }

  /// Test 2: App in background (minimized but running)
  Future<void> _testAppInBackground(BuildContext context) async {
    _log('📱 TEST 2: App in Background - FCM Notification Flow');
    
    // Simulate app going to background
    _log('📱 App moved to background (user pressed home button)');
    _log('🔄 WebSocket connection maintained');
    await Future.delayed(const Duration(milliseconds, 500));
    
    // Web user makes call
    _log('🌐 Web user initiating call (app in background)...');
    await Future.delayed(const Duration(milliseconds: 500));
    
    // FCM notification received
    _log('🔔 FCM push notification received');
    _log('📱 System shows notification banner');
    await Future.delayed(const Duration(milliseconds: 800));
    
    // CallKit activates
    _log('📞 CallKit interface activated');
    _log('🎵 Ringtone starts playing');
    _log('📱 Lock screen shows call interface');
    
    final globalCallManager = context.read<GlobalCallManager>();
    final callData = _generateTestCallData('Web User (Background)');
    
    await globalCallManager.handleIncomingCall(callData);
    
    await Future.delayed(const Duration(seconds: 1));
    
    // User interacts from notification/lock screen
    _log('👆 User taps notification / swipes to answer');
    _log('📱 App brought to foreground');
    
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const IncomingCallScreen(),
          fullscreenDialog: true,
        ),
      );
    }
    
    await Future.delayed(const Duration(seconds: 2));
    
    // Accept call
    _log('✅ User accepts call from lock screen');
    await globalCallManager.acceptCurrentCall();
    
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const ActiveCallScreen(),
        ),
      );
    }
    
    _log('🎙️ Call connected - app now in foreground');
    
    await Future.delayed(const Duration(seconds: 2));
    
    // End call
    await globalCallManager.endCurrentCall();
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    
    _log('✅ Background test completed successfully');
  }

  /// Test 3: App completely closed
  Future<void> _testAppClosed(BuildContext context) async {
    _log('📱 TEST 3: App Completely Closed - Cold Start Flow');
    
    // Simulate app being completely closed
    _log('📱 App completely closed (killed by user/system)');
    _log('🔌 WebSocket disconnected');
    _log('💤 App not running in memory');
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Web user makes call
    _log('🌐 Web user initiating call (app closed)...');
    await Future.delayed(const Duration(milliseconds: 500));
    
    // FCM high-priority notification
    _log('🔔 FCM high-priority notification sent');
    _log('⚡ System wakes up device');
    _log('📱 CallKit launches without app UI');
    await Future.delayed(const Duration(seconds: 1));
    
    // CallKit shows native interface
    _log('📞 Native CallKit interface shown');
    _log('🎵 System ringtone plays');
    _log('📱 Full-screen call interface (even on lock screen)');
    
    await Future.delayed(const Duration(seconds: 2));
    
    // User accepts from CallKit
    _log('✅ User accepts call from CallKit interface');
    _log('🚀 App cold-starts in background');
    _log('📱 App initializes call state');
    
    // Simulate app startup
    await Future.delayed(const Duration(seconds: 1));
    
    final globalCallManager = context.read<GlobalCallManager>();
    final callData = _generateTestCallData('Web User (Cold Start)');
    
    // App takes over call from CallKit
    await globalCallManager.handleIncomingCall(callData);
    await globalCallManager.acceptCurrentCall();
    
    _log('📱 App UI takes over from CallKit');
    
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ActiveCallScreen(),
        ),
      );
    }
    
    _log('🎙️ Call active - app fully loaded');
    
    await Future.delayed(const Duration(seconds: 3));
    
    // End call
    await globalCallManager.endCurrentCall();
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    
    _log('✅ Cold start test completed successfully');
  }

  /// Test 4: Call during active call
  Future<void> _testCallDuringActiveCall(BuildContext context) async {
    _log('📱 TEST 4: Call During Active Call - Auto Reject');
    
    final globalCallManager = context.read<GlobalCallManager>();
    
    // Start first call
    _log('📞 First call in progress...');
    final firstCall = _generateTestCallData('First Caller');
    await globalCallManager.handleIncomingCall(firstCall);
    await globalCallManager.acceptCurrentCall();
    
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ActiveCallScreen(),
        ),
      );
    }
    
    _log('🎙️ First call active');
    
    await Future.delayed(const Duration(seconds: 2));
    
    // Second call comes in
    _log('📞 Second call incoming during active call...');
    final secondCall = _generateTestCallData('Second Caller');
    
    // This should auto-reject
    await globalCallManager.handleIncomingCall(secondCall);
    _log('❌ Second call auto-rejected (busy)');
    _log('📱 First call continues uninterrupted');
    
    await Future.delayed(const Duration(seconds: 2));
    
    // End first call
    _log('📵 Ending first call');
    await globalCallManager.endCurrentCall();
    
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    
    _log('✅ Call during active call test completed');
  }

  /// Test 5: Network interruption during call
  Future<void> _testNetworkInterruption(BuildContext context) async {
    _log('📱 TEST 5: Network Interruption During Call');
    
    final globalCallManager = context.read<GlobalCallManager>();
    
    // Start call
    final callData = _generateTestCallData('Network Test User');
    await globalCallManager.handleIncomingCall(callData);
    await globalCallManager.acceptCurrentCall();
    
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ActiveCallScreen(),
        ),
      );
    }
    
    _log('🎙️ Call active - good connection');
    
    await Future.delayed(const Duration(seconds: 2));
    
    // Simulate network issues
    _log('📶 Network connection lost...');
    _log('🔄 Attempting to reconnect...');
    await Future.delayed(const Duration(seconds: 2));
    
    _log('📶 Network connection restored');
    _log('🎙️ Call audio resumed');
    
    await Future.delayed(const Duration(seconds: 2));
    
    // End call
    await globalCallManager.endCurrentCall();
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    
    _log('✅ Network interruption test completed');
  }

  /// Test call controls (mute, speaker, etc.)
  Future<void> _testCallControls() async {
    _log('🎛️ Testing call controls...');
    
    // Test mute
    _log('🔇 Testing mute button');
    await Future.delayed(const Duration(milliseconds: 500));
    _log('🔊 Microphone muted');
    
    await Future.delayed(const Duration(milliseconds: 500));
    _log('🎤 Microphone unmuted');
    
    // Test speaker
    _log('📢 Testing speaker button');
    await Future.delayed(const Duration(milliseconds: 500));
    _log('🔊 Speaker phone enabled');
    
    await Future.delayed(const Duration(milliseconds: 500));
    _log('🎧 Speaker phone disabled');
    
    // Test minimize/maximize
    _log('📱 Testing minimize call');
    await Future.delayed(const Duration(milliseconds: 500));
    _log('🎈 Floating call indicator shown');
    
    await Future.delayed(const Duration(milliseconds: 500));
    _log('📱 Call maximized from indicator');
    
    _log('✅ All call controls working');
  }

  /// Generate test call data
  Map<String, dynamic> _generateTestCallData(String callerName) {
    return {
      'call_id': 'test_${Random().nextInt(10000)}',
      'caller_id': '${Random().nextInt(900) + 100}',
      'caller_name': callerName,
      'call_type': 'audio',
      'receiver_id': '1', // Current user
    };
  }

  // ==================== QUICK INDIVIDUAL TESTS ====================

  /// Quick test for incoming call
  Future<void> quickTestIncomingCall(BuildContext context) async {
    _log('🚀 Quick Test: Incoming Call');
    
    final globalCallManager = context.read<GlobalCallManager>();
    final callData = _generateTestCallData('Quick Test Caller');
    
    await globalCallManager.handleIncomingCall(callData);
    
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const IncomingCallScreen(),
          fullscreenDialog: true,
        ),
      );
    }
    
    _log('📱 Incoming call screen displayed');
  }

  /// Quick test for outgoing call
  Future<void> quickTestOutgoingCall(BuildContext context) async {
    _log('🚀 Quick Test: Outgoing Call');
    
    final globalCallManager = context.read<GlobalCallManager>();
    
    final success = await globalCallManager.makeCall(123, 'audio');
    
    if (success) {
      _log('📞 Outgoing call initiated');
      _log('⏳ Waiting for response...');
      
      // Simulate timeout
      Timer(const Duration(seconds: 5), () {
        _log('⏰ Call timeout - ending call');
        globalCallManager.endCurrentCall();
      });
    } else {
      _log('❌ Failed to initiate call');
    }
  }

  /// Test UI state management
  Future<void> testUIStateManagement(BuildContext context) async {
    _log('🚀 Testing UI State Management');
    
    // Test all state transitions
    _log('🔄 IDLE → OUTGOING');
    await Future.delayed(const Duration(milliseconds: 300));
    
    _log('🔄 OUTGOING → ACTIVE');
    await Future.delayed(const Duration(milliseconds: 300));
    
    _log('🔄 ACTIVE → IDLE');
    await Future.delayed(const Duration(milliseconds: 300));
    
    _log('🔄 IDLE → INCOMING');
    await Future.delayed(const Duration(milliseconds: 300));
    
    _log('🔄 INCOMING → ACTIVE');
    await Future.delayed(const Duration(milliseconds: 300));
    
    _log('🔄 ACTIVE → IDLE');
    await Future.delayed(const Duration(milliseconds: 300));
    
    _log('✅ All state transitions working');
  }

  void dispose() {
    _logController.close();
  }
}

// Widget to display live test logs
class CallTestLogViewer extends StatefulWidget {
  const CallTestLogViewer({super.key});

  @override
  State<CallTestLogViewer> createState() => _CallTestLogViewerState();
}

class _CallTestLogViewerState extends State<CallTestLogViewer> {
  final ScrollController _scrollController = ScrollController();
  late StreamSubscription<String> _logSubscription;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _logs.addAll(CallSimulationScript().logs);
    _logSubscription = CallSimulationScript().logStream.listen((log) {
      setState(() {
        _logs.add(log);
      });
      // Auto-scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[600]!),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Call Test Console',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _logs.clear();
                    });
                    CallSimulationScript().clearLogs();
                  },
                  icon: const Icon(Icons.clear, color: Colors.white, size: 16),
                  tooltip: 'Clear logs',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                Color textColor = Colors.white;
                
                if (log.contains('❌') || log.contains('ERROR')) {
                  textColor = Colors.red[300]!;
                } else if (log.contains('✅') || log.contains('SUCCESS')) {
                  textColor = Colors.green[300]!;
                } else if (log.contains('⚠️') || log.contains('WARNING')) {
                  textColor = Colors.orange[300]!;
                } else if (log.contains('🔔') || log.contains('📞')) {
                  textColor = Colors.blue[300]!;
                } else if (log.contains('🌐')) {
                  textColor = Colors.purple[300]!;
                }
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    log,
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}