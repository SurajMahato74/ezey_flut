# Call Flow Implementation

## New Call States and Flow

### Call States
1. **`connecting`** - Trying to reach the other user (user not online)
2. **`calling`** - Outgoing call initiated (caller side)  
3. **`ringing`** - Both sides show ringing when connected
4. **`answered`** - Call accepted, establishing connection
5. **`connected`** - Call active with timer running
6. **`ended`** - Call ended
7. **`declined`** - Call declined
8. **`missed`** - Call missed

### Call Flow

#### For Caller:
1. **Start Call** → `connecting` state (checking if receiver is online)
2. **User Offline** → Stay in `connecting` state showing "Connecting..."
3. **User Online** → Transition to `calling` then `ringing` state
4. **Call Answered** → Transition to `connected` state, **timer starts here**
5. **Call Ended** → Either party can end, both go to `ended` state

#### For Receiver:
1. **Incoming Call** → `ringing` state showing "Ringing..."
2. **Accept Call** → `answered` state briefly, then `connected` state, **timer starts here**
3. **Decline Call** → `declined` state, call ends
4. **Call Ended** → Either party can end, both go to `ended` state

### Key Features Implemented

#### Timer Management
- Timer **only starts when call is answered** (`connected` state)
- Timer shows `00:00` until call is actually connected
- Both caller and receiver see the same timer once connected

#### State Synchronization  
- Both sides show "Ringing..." when call is active and receiver is online
- Both sides show "Connected" when call is answered
- Proper hangup handling - when one person ends call, other person's call ends immediately

#### User Experience
- **Connecting** - Shows when trying to reach offline user
- **Ringing** - Shows when both users are online and call is active
- **Connected** - Shows when call is answered and audio is flowing
- **Proper Hangup** - Either party can end call, both sides handle it gracefully

### Files Modified

1. **`lib/models/call.dart`** - Updated CallState enum
2. **`lib/services/call_state_manager.dart`** - New call flow logic
3. **`lib/services/call_websocket_service.dart`** - Enhanced message handling
4. **`lib/screens/active_call_screen.dart`** - Dynamic status display
5. **`lib/screens/incoming_call_screen.dart`** - State-aware ringing text
6. **`lib/widgets/floating_call_indicator.dart`** - Multi-state support

### Usage

The call system now properly handles:
- ✅ Offline users (shows "Connecting...")
- ✅ Online users (shows "Ringing..." on both sides)
- ✅ Timer starts only when call is answered
- ✅ Proper hangup from either side
- ✅ State synchronization between caller and receiver

### Testing

To test the new flow:
1. Make a call when receiver is offline → Should show "Connecting..."
2. Make a call when receiver is online → Should show "Ringing..." on both sides
3. Accept call → Timer should start at 00:00 and count up
4. End call from either side → Both sides should end immediately