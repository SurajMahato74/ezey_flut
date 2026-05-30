import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_theme.dart';
import '../services/call_service.dart';
import '../config.dart' as appConfig;
import 'dart:async';

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerName;
  final String callerImage;
  final String callType;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.callerImage,
    required this.callType,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final CallService _callService = CallService();
  StreamSubscription? _callStatusSubscription;
  bool _isAnswering = false;

  @override
  void initState() {
    super.initState();
    _setupCallStatusListener();
  }

  void _setupCallStatusListener() {
    _callStatusSubscription = _callService.callStatusStream?.listen((data) {
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
      // Accept call via service
      await _callService.acceptCall(widget.callId);
      
      // Navigate to active call screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveCallScreen(
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
    await _callService.declineCall(widget.callId);
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
            
            // Caller avatar
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withOpacity(0.2),
                border: Border.all(
                  color: AppTheme.primaryColor,
                  width: 3,
                ),
              ),
              child: const Icon(
                Icons.person,
                size: 80,
                color: AppTheme.primaryColor,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Caller name
            Text(
              widget.callerName,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Incoming call text
            Text(
              'Incoming ${widget.callType} call',
              style: GoogleFonts.plusJakartaSans(
                color: AppTheme.primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            
            const Spacer(),
            
            // Call action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                    child: IconButton(
                      onPressed: _declineCall,
                      icon: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  
                  // Accept button
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                    ),
                    child: IconButton(
                      onPressed: _isAnswering ? null : _acceptCall,
                      icon: _isAnswering
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.call,
                              color: Colors.white,
                              size: 30,
                            ),
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
    super.dispose();
  }
}

class ActiveCallScreen extends StatefulWidget {
  final String callId;
  final String participantName;
  final bool isIncoming;

  const ActiveCallScreen({
    super.key,
    required this.callId,
    required this.participantName,
    this.isIncoming = false,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  final CallService _callService = CallService();
  RtcEngine? _engine;
  bool _muted = false;
  bool _connected = false;
  bool _userJoined = false;
  String _callStatus = 'Connecting...';
  StreamSubscription? _callStatusSubscription;
  Timer? _callTimer;
  int _callDuration = 0;

  @override
  void initState() {
    super.initState();
    _initializeCall();
    _setupCallStatusListener();
    _startCallTimer();
  }

  void _setupCallStatusListener() {
    _callStatusSubscription = _callService.callStatusStream?.listen((data) {
      if (data['call_id'] == widget.callId) {
        final status = data['status'];
        if (mounted) {
          setState(() {
            switch (status) {
              case 'answered':
                _callStatus = 'Call connected';
                _connected = true;
                break;
              case 'ended':
                _callStatus = 'Call ended';
                Future.delayed(const Duration(seconds: 1), () {
                  if (mounted) Navigator.pop(context);
                });
                break;
              case 'declined':
                _callStatus = 'Call declined';
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) Navigator.pop(context);
                });
                break;
            }
          });
        }
      }
    });
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_connected && mounted) {
        setState(() => _callDuration++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _initializeCall() async {
    try {
      if (kIsWeb) {
        setState(() {
          _connected = true;
          _callStatus = 'Call connected (Web Demo)';
        });
        return;
      }

      // Request permissions
      await Permission.microphone.request();

      // Initialize Agora
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(appId: appConfig.Config.agoraAppId));
      await _engine!.enableAudio();

      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          print('✅ Joined Agora channel: ${connection.channelId}');
          setState(() {
            _connected = true;
            _callStatus = widget.isIncoming ? 'Call connected' : 'Waiting for answer...';
          });
        },
        onUserJoined: (connection, uid, elapsed) {
          print('✅ User joined Agora: $uid');
          setState(() {
            _userJoined = true;
            _callStatus = 'Call connected';
          });
        },
        onUserOffline: (connection, uid, reason) {
          print('❌ User left Agora: $uid');
          setState(() {
            _userJoined = false;
            _callStatus = 'User left the call';
          });
        },
      ));

      // Join channel with call ID
      await _engine!.joinChannel(
        token: '', // Use empty token for now
        channelId: widget.callId,
        uid: 0,
        options: const ChannelMediaOptions(
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
    } catch (e) {
      print('❌ Failed to initialize call: $e');
      setState(() => _callStatus = 'Connection failed');
    }
  }

  Future<void> _endCall() async {
    await _callService.endCall();
    if (!kIsWeb && _engine != null) {
      await _engine!.leaveChannel();
    }
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
            
            // Participant avatar
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withOpacity(0.2),
              ),
              child: const Icon(
                Icons.person,
                size: 60,
                color: AppTheme.primaryColor,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Participant name
            Text(
              widget.participantName,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Call status
            Text(
              _callStatus,
              style: GoogleFonts.plusJakartaSans(
                color: _connected ? Colors.green : AppTheme.primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Call duration
            if (_connected && _callDuration > 0)
              Text(
                _formatDuration(_callDuration),
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            
            const Spacer(),
            
            // Call controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Mute button
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _muted ? Colors.red : Colors.white,
                  ),
                  child: IconButton(
                    onPressed: () {
                      setState(() => _muted = !_muted);
                      if (!kIsWeb) {
                        _engine?.muteLocalAudioStream(_muted);
                      }
                    },
                    icon: Icon(
                      _muted ? Icons.mic_off : Icons.mic,
                      color: _muted ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                
                // End call button
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                  ),
                  child: IconButton(
                    onPressed: _endCall,
                    icon: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 30,
                    ),
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
    _callTimer?.cancel();
    if (!kIsWeb) {
      _engine?.release();
    }
    super.dispose();
  }
}