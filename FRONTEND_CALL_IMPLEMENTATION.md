# Frontend Call Implementation Summary

## What Frontend Expects from Backend

### 1. Call Creation API
**Endpoint:** `POST /api/messaging/create-call/`
**Expected Response:**
```json
{
  "call": {
    "id": 100,
    "call_id": "call_79_2_1768929679", 
    "caller": {"id": 79, "display_name": "caller name"},
    "receiver": {"id": 2, "display_name": "receiver name"},
    "call_type": "audio",
    "status": "ringing",
    "started_at": "2026-01-20T17:21:19.897005+00:00"
  }
}
```

### 2. WebSocket Connections
Frontend creates TWO WebSocket connections:

#### A. Global WebSocket (for incoming calls)
- **URL:** `wss://ezeyway.com/ws/messages/?token=TOKEN`
- **Purpose:** Receives incoming call notifications
- **Expected Messages:**
```json
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

#### B. Call-Specific WebSocket (for call signaling)
- **URL:** `wss://ezeyway.com/ws/calls/CALL_ID/?token=TOKEN`
- **Purpose:** Handle call state changes and signaling

## Frontend Call Flow Implementation

### 1. Caller Side Flow
```
1. User clicks call button
2. Frontend calls API: POST /api/messaging/create-call/
3. Frontend connects to: wss://ezeyway.com/ws/calls/CALL_ID/
4. Frontend joins Agora channel
5. Frontend sends: {"type": "call_status", "status": "calling"}
6. Frontend waits for receiver to respond with "ringing"
7. When receiver answers: status becomes "answered" → "connected"
8. Timer starts only when status = "connected"
```

### 2. Receiver Side Flow
```
1. Receives message on global WebSocket: {"type": "incoming_call"}
2. Shows incoming call screen
3. When user accepts:
   - Connects to call WebSocket: wss://ezeyway.com/ws/calls/CALL_ID/
   - Joins Agora channel
   - Sends: {"type": "call_status", "status": "answered"}
   - Status becomes "connected"
   - Timer starts
```

## WebSocket Messages Frontend Sends

### Call Status Updates
```json
{"type": "call_status", "status": "calling"}
{"type": "call_status", "status": "ringing"}  
{"type": "call_status", "status": "answered"}
{"type": "call_status", "status": "ended"}
{"type": "call_status", "status": "declined"}
```

### Call Actions
```json
{"type": "join_call", "call_type": "audio"}
{"type": "leave_call"}
{"type": "toggle_media", "media_type": "audio", "enabled": true}
```

## WebSocket Messages Frontend Expects

### Call State Updates
```json
{
  "type": "call_state",
  "call": {
    "call_id": "call_79_2_1768929679",
    "status": "ringing",
    "caller": {"id": 79, "name": "caller"},
    "callee": {"id": 2, "name": "receiver"}
  }
}
```

### Status Updates
```json
{"type": "call_status", "status": "ringing", "user_id": 79}
{"type": "call_status", "status": "answered", "user_id": 2}
{"type": "call_status", "status": "ended", "user_id": 79}
```

## Current Issues Based on Logs

### 1. State Synchronization Problem
- **Issue:** Caller stays in "calling" state, doesn't transition to "ringing"
- **Expected:** When receiver gets call, backend should send "ringing" status to caller
- **Current:** Receiver sends "ringing" but caller doesn't receive it properly

### 2. Duplicate Call Handling
- **Issue:** Same call appears multiple times in logs
- **Cause:** Both global WebSocket and call WebSocket receive same messages
- **Fix Applied:** Frontend now handles duplicates properly

### 3. Timer Sync Issue  
- **Issue:** Timer starts at different times for caller/receiver
- **Expected:** Timer starts only when status = "connected" for both sides
- **Current:** Working correctly in frontend

## Backend Requirements for Proper Call Flow

### 1. When Call is Created
```
1. Create call record in database
2. Send incoming_call message to receiver via global WebSocket
3. Set up call-specific WebSocket room for both users
```

### 2. When Receiver Connects to Call WebSocket
```
1. Send current call state to receiver
2. Broadcast "ringing" status to caller
3. Update call status in database
```

### 3. When Receiver Accepts Call
```
1. Update call status to "answered" in database  
2. Broadcast "answered" status to caller
3. Set answered_at timestamp
```

### 4. When Either User Ends Call
```
1. Update call status to "ended" in database
2. Broadcast "ended" status to other user
3. Close call WebSocket room
```

## Questions for Backend Team

1. **Is the call WebSocket room properly created for both users?**
2. **Are status updates being broadcast to both participants?**
3. **Is the global WebSocket sending incoming_call messages correctly?**
4. **Are call state changes being persisted in database?**
5. **Is there proper error handling for offline users?**

## Frontend Debug Commands

To test if backend is working:
1. Check browser console for WebSocket messages
2. Look for "📞" and "📶" log messages
3. Verify both WebSocket connections are established
4. Check if status updates are received by both sides

## Expected Backend Behavior

When user A calls user B:
1. User A creates call → Backend sends incoming_call to User B
2. User B connects to call WebSocket → Backend sends "ringing" to User A  
3. User B accepts → Backend sends "answered" to User A
4. Both users see "connected" status and timer starts
5. Either user ends → Backend sends "ended" to other user