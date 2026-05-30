import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/call.dart';
import '../theme/app_theme.dart';

class CompleteCallSystem {
  static final CompleteCallSystem _instance = CompleteCallSystem._internal();
  factory CompleteCallSystem() => _instance;
  CompleteCallSystem._internal();

  WebSocketChannel? _callWebSocket;
  StreamController<Map<String, dynamic>>? _callStatusController;
  Stream<Map<String, dynamic>>? _callStatusStream;
  
  Call? _currentCall;
  String? _currentCallId;
  
  // Track active call to prevent duplicates
  static String? _activeCallId;
  
  // Getters
  Call? get currentCall => _currentCall;
  String? get currentCallId => _currentCallId;
  Stream<Map<String, dynamic>>? get callStatusStream => _callStatusStream;
  
  // Check if call is already being handled
  static bool isCallActive(String callId) {
    return _activeCallId == callId;
  }
  
  // Set active call
  static void setActiveCall(String callId) {
    _activeCallId = callId;
  }
  
  // Clear active call
  static void clearActiveCall() {
    _activeCallId = null;
  }

  /// Initialize call system
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
      
      // Connect to call WebSocket immediately
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
        onError: (error) => print('❌ Call WebSocket error: $error'),
        onDone: () => print('🔵 Call WebSocket closed'),
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
  Future<void> acceptCall(String callId, Map<String, dynamic> callData) async {
    try {
      // Check for duplicate call
      if (isCallActive(callId)) {
        print('🚫 Call $callId already active, ignoring duplicate');
        return;
      }
      
      // Set as active call
      setActiveCall(callId);
      
      _currentCallId = callId;
      
      // Store the call data from incoming call notification
      _currentCall = Call.fromJson(callData);
      
      // Debug: Check if we have a token
      print('🔑 Token available: ${_currentCall?.agoraToken != null}');
      if (_currentCall?.agoraToken != null) {
        print('🔑 Token preview: ${_currentCall!.agoraToken!.substring(0, 20)}...');
      }
      
      // Connect to call WebSocket first
      await _connectToCallWebSocket(callId);
      
      // Send CORRECT call status format
      _sendCallMessage({
        'type': 'call_status',
        'status': 'answered',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('✅ Call accepted: $callId');
    } catch (e) {
      print('❌ Failed to accept call: $e');
      clearActiveCall();
    }
  }

  /// Decline an incoming call
  Future<void> declineCall(String callId) async {
    try {
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
    clearActiveCall(); // Clear active call tracking
  }

  /// Dispose resources
  void dispose() {
    _cleanup();
    _callStatusController?.close();
    _callStatusController = null;
    _callStatusStream = null;
  }
}

// Complete Incoming Call Screen
class CompleteIncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerName;
  final String callerImage;
  final String callType;
  final Map<String, dynamic> callData;

  const CompleteIncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.callerImage,
    required this.callType,
    required this.callData,
  });

  @override
  State<CompleteIncomingCallScreen> createState() => _CompleteIncomingCallScreenState();
}

class _CompleteIncomingCallScreenState extends State<CompleteIncomingCallScreen> {
  final CompleteCallSystem _callSystem = CompleteCallSystem();
  StreamSubscription? _callStatusSubscription;
  bool _isAnswering = false;

  @override
  void initState() {
    super.initState();
    _setupCallStatusListener();
  }

  void _setupCallStatusListener() {
    _callStatusSubscription = _callSystem.callStatusStream?.listen((data) {
      if (data['call_id'] == widget.callId) {
        final status = data['status'];
        if (status == 'ended' || status == 'cancelled') {
          if (mounted) Navigator.pop(context);
        }
      }
    });
  }

  Future<void> _acceptCall() async {
    if (_isAnswering) return;
    setState(() => _isAnswering = true);

    try {
      await _callSystem.acceptCall(widget.callId, widget.callData);
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => CompleteActiveCallScreen(
              callId: widget.callId,
              participantName: widget.callerName,
              isIncoming: true,
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Failed to accept call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept call: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnswering = false);
    }
  }

  Future<void> _declineCall() async {
    await _callSystem.declineCall(widget.callId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withOpacity(0.2),
                border: Border.all(color: AppTheme.primaryColor, width: 3),
              ),
              child: const Icon(Icons.person, size: 80, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 32),
            Text(
              widget.callerName,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Incoming ${widget.callType} call',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white70,
                fontSize: 18,
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: _declineCall,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                  ),
                ),
                GestureDetector(
                  onTap: _isAnswering ? null : _acceptCall,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: _isAnswering
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.call, color: Colors.white, size: 32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _callStatusSubscription?.cancel();
    super.dispose();
  }
}

// Complete Active Call Screen with TEMP TOKEN TEST
class CompleteActiveCallScreen extends StatefulWidget {
  final String callId;
  final String participantName;
  final bool isIncoming;

  const CompleteActiveCallScreen({
    super.key,
    required this.callId,
    required this.participantName,
    required this.isIncoming,
  });

  @override
  State<CompleteActiveCallScreen> createState() => _CompleteActiveCallScreenState();
}

class _CompleteActiveCallScreenState extends State<CompleteActiveCallScreen> {
  final CompleteCallSystem _callSystem = CompleteCallSystem();
  StreamSubscription? _callStatusSubscription;
  
  RtcEngine? _engine;
  bool _isConnected = false;
  String _connectionStatus = 'Connecting...';

  @override
  void initState() {
    super.initState();
    _initializeAgora();
    _setupCallStatusListener();
  }

  Future<void> _initializeAgora() async {
    try {
      // Request microphone permission
      final micPermission = await Permission.microphone.request();
      print('🎤 Microphone permission: $micPermission');
      
      if (micPermission != PermissionStatus.granted) {
        print('❌ Microphone permission denied!');
        if (mounted) {
          setState(() => _connectionStatus = 'Microphone permission denied');
        }
        return;
      }

      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: '9c06b7c857c14e0fa87e1d61f03c0bc7',
      ));

      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print('✅ Joined Agora channel: ${connection.channelId}');
          if (mounted) {
            setState(() {
              _connectionStatus = 'Connected';
              _isConnected = true;
            });
          }
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('✅ Remote user joined: $remoteUid');
          if (mounted) {
            setState(() {
              _connectionStatus = 'Connected - User joined';
              _isConnected = true;
            });
          }
        },
        onAudioVolumeIndication: (RtcConnection connection, List<AudioVolumeInfo> speakers, int speakerNumber, int totalVolume) {
          for (var speaker in speakers) {
            if (speaker.volume! > 0) {
              print('🔊 Audio detected from UID ${speaker.uid}: volume ${speaker.volume}');
            }
          }
        },
        onConnectionStateChanged: (RtcConnection connection, ConnectionStateType state, ConnectionChangedReasonType reason) {
          print('📞 Connection state: $state, reason: $reason');
          if (mounted) {
            switch (state) {
              case ConnectionStateType.connectionStateConnected:
                setState(() {
                  _connectionStatus = 'Connected';
                  _isConnected = true;
                });
                break;
              case ConnectionStateType.connectionStateFailed:
                setState(() {
                  _connectionStatus = 'Connection failed';
                  _isConnected = false;
                });
                break;
              default:
                break;
            }
          }
        },
      ));

      await _engine!.enableAudio();
      await _engine!.setDefaultAudioRouteToSpeakerphone(true);
      
      // Enable audio volume indication to detect microphone activity
      await _engine!.enableAudioVolumeIndication(interval: 1000, smooth: 3, reportVad: true);

      // 🔥 USE DYNAMIC CHANNEL FROM BACKEND
      final channelName = _callSystem.currentCall?.agoraChannel ?? widget.callId;
      
      // Generate unique UID for each user
      final uid = DateTime.now().millisecondsSinceEpoch % 1000000;
      
      await _engine!.joinChannel(
        token: '',
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );

      print('✅ Agora initialization complete with EMPTY TOKEN');
      print('🔑 Using empty token for new project');
      print('📺 Channel: $channelName, UID: $uid');
    } catch (e) {
      print('❌ Agora initialization failed: $e');
      if (mounted) {
        setState(() => _connectionStatus = 'Connection failed');
      }
    }
  }

  void _setupCallStatusListener() {
    _callStatusSubscription = _callSystem.callStatusStream?.listen((data) {
      if (data['call_id'] == widget.callId) {
        final status = data['status'];
        if (status == 'ended' || status == 'cancelled') {
          _endCall();
        }
      }
    });
  }

  Future<void> _endCall() async {
    try {
      await _engine?.leaveChannel();
      await _callSystem.endCall();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      print('❌ Error ending call: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _endCall,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    _connectionStatus,
                    style: GoogleFonts.plusJakartaSans(
                      color: _isConnected ? Colors.green : Colors.orange,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withOpacity(0.2),
                border: Border.all(color: AppTheme.primaryColor, width: 3),
              ),
              child: const Icon(Icons.person, size: 60, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 24),
            Text(
              widget.participantName,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _connectionStatus,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic, color: Colors.white, size: 28),
                    ),
                  ),
                  GestureDetector(
                    onTap: _endCall,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.volume_up, color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _callStatusSubscription?.cancel();
    _engine?.release();
    super.dispose();
  }
}