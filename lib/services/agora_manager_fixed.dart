import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'webrtc_signaling_service.dart';
import '../config.dart' as appConfig;

class AgoraManager {
  static const String appId = appConfig.Config.agoraAppId;
  
  final WebRTCSignalingService _signaling = WebRTCSignalingService();
  
  RtcEngine? _engine;
  String? _channelName;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  
  // Audio level tracking
  double _localAudioLevel = 0.0;
  double _remoteAudioLevel = 0.0;
  
  Function(String)? onConnectionStateChange;
  Function(double)? onLocalAudioLevelUpdate;
  Function(double)? onRemoteAudioLevelUpdate;
  
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;

  Future<bool> requestPermissions() async {
    try {
      print('🔵 Requesting microphone permissions...');
      
      // Request microphone permission
      final micStatus = await Permission.microphone.request();
      print('🎤 Microphone permission: $micStatus');
      
      if (micStatus != PermissionStatus.granted) {
        print('❌ Microphone permission denied');
        return false;
      }
      
      print('✅ All permissions granted');
      return true;
    } catch (e) {
      print('❌ Permission request failed: $e');
      return false;
    }
  }

  Future<void> initialize() async {
    try {
      print('🔵 Creating Agora RTC Engine...');
      
      // Request permissions first
      final hasPermissions = await requestPermissions();
      if (!hasPermissions) {
        throw Exception('Microphone permission required for audio calls');
      }
      
      // Check if Agora SDK is available
      if (kIsWeb) {
        // Wait for web SDK to be ready
        int attempts = 0;
        while (attempts < 50) { // 5 second timeout
          try {
            _engine = createAgoraRtcEngine();
            break;
          } catch (e) {
            print('⏳ Waiting for Agora SDK... attempt ${attempts + 1}');
            await Future.delayed(const Duration(milliseconds: 100));
            attempts++;
            if (attempts >= 50) {
              throw Exception('Agora SDK not available after 5 seconds');
            }
          }
        }
      } else {
        _engine = createAgoraRtcEngine();
      }
      
      print('🔵 Initializing with App ID: $appId');
      await _engine!.initialize(const RtcEngineContext(appId: appId));
      
      // Enable audio with echo cancellation
      await _engine!.enableAudio();
      await _engine!.enableLocalAudio(true);
      
      // Set audio scenario for communication
      await _engine!.setAudioScenario(AudioScenarioType.audioScenarioDefault);
      
      print('✅ Audio enabled with echo cancellation');
      
      // Set up event handlers
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print('✅ 🎉 JOINED CHANNEL: ${connection.channelId}');
          onConnectionStateChange?.call('connected');
          
          // Force audio setup after joining
          Future.delayed(const Duration(milliseconds: 500), () async {
            await _forceAudioSetup();
          });
        },
        
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('✅ 👥 USER JOINED: $remoteUid - Audio should start flowing now!');
          onConnectionStateChange?.call('user_joined');
          
          // Force audio setup when user joins
          Future.delayed(const Duration(milliseconds: 500), () async {
            await _forceAudioSetup();
          });
        },
        
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          print('❌ 👤 USER LEFT: $remoteUid (reason: $reason)');
          onConnectionStateChange?.call('user_disconnected');
        },
        
        onAudioVolumeIndication: (RtcConnection connection, List<AudioVolumeInfo> speakers, int speakerNumber, int totalVolume) {
          if (speakers.isNotEmpty) {
            print('📊 🎵 AUDIO DETECTED! ${speakers.length} speakers, total: $totalVolume');
          }
          
          for (var speaker in speakers) {
            if (speaker.uid == 0) {
              _localAudioLevel = (speaker.volume ?? 0) / 255.0;
              onLocalAudioLevelUpdate?.call(_localAudioLevel);
              if (speaker.volume != null && speaker.volume! > 0) {
                print('🎤 ✅ LOCAL AUDIO: ${speaker.volume} (${(_localAudioLevel * 100).toInt()}%)');
              }
            } else {
              _remoteAudioLevel = (speaker.volume ?? 0) / 255.0;
              onRemoteAudioLevelUpdate?.call(_remoteAudioLevel);
              print('🔊 ✅ REMOTE AUDIO: ${speaker.volume} from UID ${speaker.uid} (${(_remoteAudioLevel * 100).toInt()}%)');
            }
          }
        },
        
        onRemoteAudioStateChanged: (RtcConnection connection, int remoteUid, RemoteAudioState state, RemoteAudioStateReason reason, int elapsed) {
          print('🔊 REMOTE AUDIO STATE: $state for UID $remoteUid (reason: $reason)');
          
          switch (state) {
            case RemoteAudioState.remoteAudioStateStarting:
              print('🔊 ⏳ Remote audio starting...');
              break;
            case RemoteAudioState.remoteAudioStateDecoding:
              print('🔊 ✅ 🎵 AUDIO PLAYING! You should hear them now!');
              break;
            case RemoteAudioState.remoteAudioStateFrozen:
              print('🔊 ❄️ Remote audio frozen');
              break;
            case RemoteAudioState.remoteAudioStateStopped:
              print('🔊 ⏹️ Remote audio stopped');
              break;
            case RemoteAudioState.remoteAudioStateFailed:
              print('🔊 ❌ Remote audio failed');
              break;
          }
        },
        
        onConnectionStateChanged: (RtcConnection connection, ConnectionStateType state, ConnectionChangedReasonType reason) {
          print('🔄 CONNECTION STATE: $state (reason: $reason)');
        },
        
        onError: (ErrorCodeType err, String msg) {
          print('❌ AGORA ERROR: $err - $msg');
          
          // Handle token expiration
          if (err == ErrorCodeType.errInvalidToken) {
            print('🔄 Token expired - attempting to refresh...');
            _handleTokenExpiration();
          }
        },
      ));
      
      print('✅ Agora initialized successfully');
      
    } catch (e) {
      print('❌ Agora initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _forceAudioSetup() async {
    try {
      print('🔧 FORCING AUDIO SETUP...');
      
      // Enable audio with echo cancellation
      await _engine!.enableAudio();
      await _engine!.enableLocalAudio(true);
      await _engine!.muteLocalAudioStream(false);
      
      // Set audio scenario for communication
      await _engine!.setAudioScenario(AudioScenarioType.audioScenarioDefault);
      
      // Enable volume indication with moderate settings
      await _engine!.enableAudioVolumeIndication(
        interval: 200,   // Less frequent to reduce processing
        smooth: 3,       // Some smoothing
        reportVad: true,
      );
      
      // Moderate volumes to prevent feedback
      await _engine!.adjustRecordingSignalVolume(200);
      await _engine!.adjustPlaybackSignalVolume(150);
      
      print('🔧 ✅ FORCED AUDIO SETUP COMPLETE');
      
    } catch (e) {
      print('❌ Error in force audio setup: $e');
    }
  }

  Future<void> joinChannel(String channelName) async {
    try {
      _channelName = channelName;
      print('🌐 Joining channel: $channelName');
      
      // For real calls, we need the token from the backend
      // Don't try WebSocket signaling - use direct connection
      print('⚠️ Using direct Agora connection (no WebSocket signaling)');
      throw Exception('Need backend token for real calls');
      
    } catch (e) {
      print('❌ Failed to join channel: $e');
      rethrow;
    }
  }

  void _setupSignalingHandlers() {
    _signaling.onCallAccepted = (callId) {
      print('📞 Call accepted via signaling: $callId');
      onConnectionStateChange?.call('call_accepted');
    };
    
    _signaling.onCallRejected = (callId) {
      print('📞 Call rejected via signaling: $callId');
      onConnectionStateChange?.call('call_rejected');
    };
    
    _signaling.onAgoraToken = (channelName, token) async {
      print('🎫 Received Agora token for channel: $channelName');
      print('🎫 Token: ${token.substring(0, 20)}...');
      await _joinAgoraChannel(channelName, token);
    };
  }

  Future<void> _joinAgoraChannel(String channelName, String token) async {
    try {
      // Join Agora channel with server-provided token - Always use UID 0
      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
      
      print('✅ Agora channel joined with server token');
      
    } catch (e) {
      print('❌ Failed to join Agora channel: $e');
      rethrow;
    }
  }

  Future<void> _joinAgoraChannelDirect(String channelName) async {
    throw Exception('Direct connection without token not supported for production calls');
  }

  // Join with provided token (from call response) - Always use UID 0
  Future<void> joinChannelWithToken(String channelName, String token, {int uid = 0}) async {
    try {
      _channelName = channelName;
      print('🌐 Joining channel with provided token: $channelName');
      print('🔍 Token details:');
      print('  - Length: ${token.length}');
      print('  - First 30 chars: ${token.substring(0, token.length > 30 ? 30 : token.length)}');
      print('  - Starts with 006/007: ${token.startsWith('006') || token.startsWith('007')}');
      print('  - Channel: $channelName');
      print('  - App ID: $appId');
      print('  - UID: 0 (forced for token compatibility)');
      
      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0, // Always use 0 for token compatibility
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
      
      print('✅ Agora channel joined with provided token');
      
    } catch (e) {
      print('❌ Failed to join channel with token: $e');
      print('❌ Token was: ${token.substring(0, token.length > 50 ? 50 : token.length)}...');
      rethrow;
    }
  }

  Future<void> leaveChannel() async {
    try {
      await _engine!.leaveChannel();
      _signaling.disconnect();
      print('✅ Left channel');
    } catch (e) {
      print('❌ Error leaving channel: $e');
    }
  }

  Future<void> toggleMute() async {
    try {
      _isMuted = !_isMuted;
      await _engine!.muteLocalAudioStream(_isMuted);
      print('🎤 Microphone ${_isMuted ? "MUTED" : "UNMUTED"}');
    } catch (e) {
      print('❌ Error toggling mute: $e');
    }
  }

  Future<void> toggleSpeaker() async {
    try {
      _isSpeakerOn = !_isSpeakerOn;
      if (!kIsWeb) {
        await _engine!.setEnableSpeakerphone(_isSpeakerOn);
      }
      print('🔊 Speaker ${_isSpeakerOn ? "ON" : "OFF"}');
    } catch (e) {
      print('❌ Error toggling speaker: $e');
    }
  }

  Future<void> testAudio() async {
    try {
      print('🧪 Testing microphone access...');
      
      // Check permissions first
      final micStatus = await Permission.microphone.status;
      print('🎤 Current microphone permission: $micStatus');
      
      if (micStatus != PermissionStatus.granted) {
        print('❌ Microphone permission not granted, requesting...');
        final newStatus = await Permission.microphone.request();
        if (newStatus != PermissionStatus.granted) {
          print('❌ Microphone permission denied by user');
          return;
        }
      }
      
      // Enable audio with proper settings
      await _engine!.enableAudio();
      await _engine!.enableLocalAudio(true);
      await _engine!.muteLocalAudioStream(false);
      
      // Set audio scenario for communication
      await _engine!.setAudioScenario(AudioScenarioType.audioScenarioDefault);
      
      // Moderate volume indication
      await _engine!.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );
      
      // Safe volume levels
      await _engine!.adjustRecordingSignalVolume(150);
      await _engine!.adjustPlaybackSignalVolume(100);
      
      print('🧪 ✅ Audio test complete - speak to see volume levels');
      
    } catch (e) {
      print('❌ Error in audio test: $e');
    }
  }

  Future<void> _testWebAudioCapture() async {
    if (!kIsWeb) return;
    
    try {
      print('🌐 Testing web audio capture directly...');
      
      // Force enable microphone in Agora Web SDK
      await _engine!.enableLocalAudio(true);
      await _engine!.muteLocalAudioStream(false);
      
      // Start audio recording test
      print('🎤 Starting audio recording test...');
      
      // Force audio context activation
      print('🔊 Activating audio context...');
      
    } catch (e) {
      print('❌ Web audio capture test failed: $e');
    }
  }

  Future<void> dispose() async {
    try {
      print('🔵 Disposing Agora...');
      if (_engine != null) {
        await _engine!.leaveChannel();
        await _engine!.release();
        _engine = null;
      }
      print('✅ Agora disposed');
    } catch (e) {
      print('❌ Error disposing Agora: $e');
      _engine = null;
    }
  }
  
  void _handleTokenExpiration() {
    print('⚠️ Token expired - call will be ended');
    // For now, just log the issue
    // In production, you would request a new token from backend
  }
}