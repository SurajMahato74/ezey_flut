# Backend Call System Verification Checklist

## 1. API Endpoints Required

### Call Creation
```
POST /api/messaging/create-call/
Headers: Authorization: Token YOUR_TOKEN
Body: {
  "recipient_id": 123,
  "call_type": "audio"
}

Expected Response:
{
  "call": {
    "id": 100,
    "call_id": "call_79_2_1768929679",
    "caller": {"id": 79, "display_name": "caller name"},
    "receiver": {"id": 2, "display_name": "receiver name"}, 
    "call_type": "audio",
    "status": "initiated",
    "started_at": "2026-01-20T17:21:19.897005+00:00"
  }
}
```

### Call Management (Optional - Frontend doesn't use these)
```
POST /api/messaging/calls/{id}/answer/
POST /api/messaging/calls/{id}/end/
POST /api/messaging/calls/{id}/decline/
GET  /api/messaging/calls/incoming/
```

## 2. WebSocket Consumers Required

### A. MessageConsumer
```
URL: wss://ezeyway.com/ws/messages/?token=TOKEN
Purpose: Send incoming call notifications
Must Send:
{
  "type": "incoming_call",
  "call": {
    "id": 100,
    "call_id": "call_79_2_1768929679",
    "caller": {"id": 79, "display_name": "caller name"},
    "receiver": {"id": 2, "display_name": "receiver name"},
    "status": "ringing"
  }
}
```

### B. CallConsumer  
```
URL: wss://ezeyway.com/ws/calls/{call_id}/?token=TOKEN
Purpose: Handle call signaling and status updates + WebRTC audio signaling

Auto-behaviors:
1. When receiver connects → Update status to "ringing" → Broadcast to caller
2. When status message received → Update DB → Broadcast to other user
3. Handle WebRTC signaling for audio transmission

Receives from Frontend:
{"type": "call_status", "status": "answered"}
{"type": "call_status", "status": "ended"}
{"type": "call_status", "status": "declined"}
{"type": "webrtc_offer", "offer": {...}, "call_type": "audio"}
{"type": "webrtc_answer", "answer": {...}}
{"type": "ice_candidate", "candidate": {...}}

Must Send to Frontend:
{"type": "call_status", "status": "ringing", "user_id": 79}
{"type": "call_status", "status": "answered", "user_id": 2}
{"type": "call_status", "status": "ended", "user_id": 79}
{"type": "webrtc_offer", "offer": {...}, "sender_id": 79}
{"type": "webrtc_answer", "answer": {...}, "sender_id": 2}
{"type": "ice_candidate", "candidate": {...}, "sender_id": 79}
```

## 3. Database Models Required

### Call Model
```python
class Call(models.Model):
    id = models.AutoField(primary_key=True)
    call_id = models.CharField(max_length=100, unique=True)  # "call_79_2_1768929679"
    caller = models.ForeignKey(User, related_name='outgoing_calls')
    receiver = models.ForeignKey(User, related_name='incoming_calls') 
    call_type = models.CharField(max_length=10, default='audio')
    status = models.CharField(max_length=20, default='initiated')
    started_at = models.DateTimeField(auto_now_add=True)
    answered_at = models.DateTimeField(null=True, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    duration = models.IntegerField(default=0)
```

### Status Values
```
- initiated (when call is created)
- ringing (when receiver connects to WebSocket)
- answered (when receiver accepts)
- ended (when either user ends)
- declined (when receiver declines)
- missed (auto after 50 seconds)
```

## 4. Critical Backend Logic

### When Call is Created (POST /api/messaging/create-call/)
```python
1. Create Call object with status='initiated'
2. Generate unique call_id (e.g., "call_79_2_1768929679")
3. Send WebSocket message to receiver:
   - Target: user_{receiver_id} group via MessageConsumer
   - Message: {"type": "incoming_call", "call": {...}}
4. Return call data to caller
```

### When Receiver Connects to CallConsumer
```python
1. Check if user is receiver of the call
2. If status='initiated' and user is receiver:
   - Update call.status = 'ringing'
   - Update call.save()
   - Broadcast to caller: {"type": "call_status", "status": "ringing"}
3. Send current call state to receiver
```

### When Status Message Received
```python
def receive(self, text_data):
    data = json.loads(text_data)
    
    if data['type'] == 'call_status':
        status = data['status']
        
        # Update database
        call.status = status
        if status == 'answered':
            call.answered_at = timezone.now()
        elif status in ['ended', 'declined']:
            call.ended_at = timezone.now()
        call.save()
        
        # Broadcast to other user
        self.channel_layer.group_send(
            f"call_{call.call_id}",
            {
                "type": "call_status_update",
                "status": status,
                "user_id": self.user.id
            }
        )
    
    elif data['type'] == 'webrtc_offer':
        # Forward WebRTC offer for audio negotiation
        self.channel_layer.group_send(
            f"call_{call.call_id}",
            {
                "type": "webrtc_offer",
                "offer": data.get('offer'),
                "sender_id": self.user.id,
                "call_type": data.get('call_type', 'audio')
            }
        )
    
    elif data['type'] == 'webrtc_answer':
        # Forward WebRTC answer for audio connection
        self.channel_layer.group_send(
            f"call_{call.call_id}",
            {
                "type": "webrtc_answer",
                "answer": data.get('answer'),
                "sender_id": self.user.id
            }
        )
    
    elif data['type'] == 'ice_candidate':
        # Forward ICE candidates for connection establishment
        self.channel_layer.group_send(
            f"call_{call.call_id}",
            {
                "type": "ice_candidate",
                "candidate": data.get('candidate'),
                "sender_id": self.user.id
            }
        )
```

## 5. WebSocket Group Management

### Group Names
```python
# For incoming calls
f"user_{user_id}"  # MessageConsumer

# For call signaling  
f"call_{call_id}"  # CallConsumer
```

### Group Membership
```python
# MessageConsumer - user joins their own group
async def connect(self):
    await self.channel_layer.group_add(f"user_{self.user.id}", self.channel_name)

# CallConsumer - both users join call group
async def connect(self):
    await self.channel_layer.group_add(f"call_{self.call_id}", self.channel_name)
```

## 6. Testing Checklist

### Test 1: Call Creation
```bash
curl -X POST https://ezeyway.com/api/messaging/create-call/ \
  -H "Authorization: Token YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"recipient_id": 123, "call_type": "audio"}'

Expected: 200 OK with call data
Check: Receiver gets incoming_call WebSocket message
```

### Test 2: WebSocket Connections
```javascript
// Test global WebSocket
const ws1 = new WebSocket('wss://ezeyway.com/ws/messages/?token=TOKEN');
ws1.onmessage = (e) => console.log('Global:', e.data);

// Test call WebSocket  
const ws2 = new WebSocket('wss://ezeyway.com/ws/calls/CALL_ID/?token=TOKEN');
ws2.onmessage = (e) => console.log('Call:', e.data);

Expected: Both connect successfully (status 101)
```

### Test 3: Status Broadcasting
```javascript
// Receiver sends answered
ws2.send(JSON.stringify({
  "type": "call_status", 
  "status": "answered"
}));

Expected: Caller receives {"type": "call_status", "status": "answered"}
Check: Database call.status updated to "answered"
```

### Test 4: Audio WebRTC Signaling
```javascript
// Test WebRTC offer forwarding
ws2.send(JSON.stringify({
  "type": "webrtc_offer",
  "offer": {"sdp": "...", "type": "offer"},
  "call_type": "audio"
}));

// Test WebRTC answer forwarding  
ws2.send(JSON.stringify({
  "type": "webrtc_answer",
  "answer": {"sdp": "...", "type": "answer"}
}));

// Test ICE candidate forwarding
ws2.send(JSON.stringify({
  "type": "ice_candidate",
  "candidate": {"candidate": "...", "sdpMid": "0"}
}));

Expected: Other user receives all WebRTC messages with sender_id
Check: Audio connection establishes between users
```

## 7. Common Issues to Check

### WebSocket Authentication
```python
# Ensure token authentication works
class CallConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        token = self.scope['query_string'].decode().split('token=')[1]
        # Validate token and set self.user
```

### Channel Layer Configuration
```python
# settings.py
CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {
            "hosts": [('127.0.0.1', 6379)],
        },
    },
}
```

### CORS Settings
```python
# For WebSocket connections
ALLOWED_HOSTS = ['ezeyway.com', 'localhost']
CORS_ALLOWED_ORIGINS = ['https://ezeyway.com']
```

## 8. Deployment Requirements

### Redis Server
```bash
# Must be running for WebSocket groups
redis-server
```

### ASGI Server
```bash
# Use Daphne or Uvicorn for WebSocket support
daphne -b 0.0.0.0 -p 8000 myproject.asgi:application
```

### SSL Certificate
```bash
# WebSocket connections require HTTPS in production
wss://ezeyway.com/ws/... (not ws://)
```

## 9. Debug Commands

### Check WebSocket Connection
```bash
# Test WebSocket endpoint
wscat -c "wss://ezeyway.com/ws/messages/?token=TOKEN"
```

### Check Redis
```bash
redis-cli
> KEYS *
> MONITOR  # Watch real-time commands
```

### Check Database
```sql
SELECT * FROM messaging_call ORDER BY started_at DESC LIMIT 10;
```

## 10. Expected Log Messages

### Backend Logs Should Show
```
[INFO] Call created: call_79_2_1768929679
[INFO] User 2 connected to call WebSocket
[INFO] Call status updated: initiated -> ringing
[INFO] Broadcasting ringing status to caller
[INFO] Call status updated: ringing -> answered
[INFO] Broadcasting answered status to caller
```

### Frontend Logs Should Show
```
✅ Call created successfully with ID: 100
🔵 Connecting to WebSocket with call ID: call_79_2_1768929679
📞 Call status update received: ringing
📞 Call status update received: answered
```

## 11. Audio System Requirements

### Agora Configuration
```javascript
// Frontend must have Agora App ID and tokens
const AGORA_APP_ID = "your_agora_app_id";
const agoraClient = AgoraRTC.createClient({ mode: "rtc", codec: "vp8" });

// Audio track creation with quality settings
const audioTrack = await AgoraRTC.createMicrophoneAudioTrack({
  echoCancellation: true,
  noiseSuppression: true,
  autoGainControl: true
});
```

### WebRTC + Backend Integration
```javascript
// Backend handles signaling, Agora handles audio transmission
1. Backend WebSocket: Call status and WebRTC signaling
2. Agora SDK: Actual audio stream transmission (P2P)
3. Frontend: Connects both systems for complete audio calls
```

### Audio Quality Verification
```bash
# Test audio transmission
1. Both users join call
2. Check microphone access granted
3. Verify audio levels in browser dev tools
4. Test echo cancellation and noise suppression
5. Monitor network quality indicators
```

### Required Permissions
```javascript
// Browser must grant microphone access
navigator.mediaDevices.getUserMedia({ audio: true })
  .then(stream => console.log('Microphone access granted'))
  .catch(err => console.error('Microphone access denied'));
```

This checklist covers everything needed for the call system to work properly!