# WhatsApp-Style Audio Call System Implementation Plan

## Overview
Implement a complete audio calling system using WebRTC with the same WebSocket infrastructure, featuring minimize, speaker, mute, and hangup controls like WhatsApp.

## Backend Analysis (Django Channels)
- **CallConsumer** already implemented with WebRTC signaling
- Supports: offer/answer/ICE candidates, call status, media toggle
- Uses call_id routing: `wss://ezeyway.com/ws/calls/{call_id}/`
- Has FCM notifications for missed calls

## Flutter Implementation Plan

### Phase 1: Dependencies & Models
- Add `flutter_webrtc: ^0.9.36` for WebRTC
- Add `permission_handler: ^11.0.1` for mic/camera permissions
- Create call data models:
  - `Call` model (id, participants, status, type)
  - `CallState` enum (idle, calling, ringing, connected, ended)

### Phase 2: Call Service Layer
- **CallWebSocketService**: Manages WebRTC signaling via existing WebSocket
- **WebRTCManager**: Handles peer connection, audio streams
- **CallStateManager**: Global call state using Provider

### Phase 3: UI Screens
1. **IncomingCallScreen**: Full-screen incoming call with accept/reject
2. **OutgoingCallScreen**: Calling screen with cancel
3. **ActiveCallScreen**: In-call controls (mute, speaker, hangup, minimize)
4. **MinimizedCallOverlay**: Floating call widget when minimized

### Phase 4: Call Flow
1. **Initiate Call**: Create call via API, navigate to OutgoingCallScreen
2. **Receive Call**: Show IncomingCallScreen via WebSocket notification
3. **WebRTC Connection**:
   - Create RTCPeerConnection
   - Get user media (audio only)
   - Exchange offer/answer via WebSocket
   - Handle ICE candidates
4. **Call Controls**:
   - Mute: `setLocalAudioEnabled(false)`
   - Speaker: Route audio to speaker
   - Hangup: Close connection, update status
   - Minimize: Show overlay, keep call active

### Phase 5: Integration Points
- **Chat Integration**: Add call button to chat screen
- **Navigation**: Handle call screens over existing navigation
- **Background**: Keep call active when app minimized
- **Notifications**: Handle incoming calls when app closed

## Technical Architecture

```
CallSystem/
├── models/
│   ├── call.dart
│   └── call_participant.dart
├── services/
│   ├── call_websocket_service.dart
│   ├── webrtc_manager.dart
│   └── call_state_manager.dart
├── screens/
│   ├── incoming_call_screen.dart
│   ├── outgoing_call_screen.dart
│   ├── active_call_screen.dart
│   └── minimized_call_overlay.dart
└── widgets/
    ├── call_button.dart
    └── call_controls.dart
```

## Key Challenges
1. **WebRTC Complexity**: Proper signaling sequence
2. **Audio Routing**: Speaker vs earpiece switching
3. **Background Calls**: Keep active when minimized
4. **Permission Handling**: Mic access on all platforms
5. **State Management**: Global call state across screens

## Success Criteria
- ✅ Audio calls work between users
- ✅ All controls functional (mute, speaker, hangup, minimize)
- ✅ Proper call state management
- ✅ Background call support
- ✅ Call history tracking
- ✅ Missed call notifications