// lib/utils/call_utils.dart
class CallUtils {
  /// Validates if a call ID has the correct format
  /// Valid format: call_<caller_id>_<receiver_id>_<timestamp>
  /// Example: call_2_79_1768678284
  static bool isValidCallId(String callId) {
    if (callId.isEmpty || callId.length < 10) {
      return false;
    }
    
    // Should start with 'call_' and have at least 3 underscores
    if (!callId.startsWith('call_')) {
      return false;
    }
    
    final parts = callId.split('_');
    if (parts.length < 4) {
      return false;
    }
    
    // Check if the parts after 'call_' are numeric
    for (int i = 1; i < parts.length; i++) {
      if (int.tryParse(parts[i]) == null) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Generates a fallback call ID if the server returns an invalid one
  static String generateFallbackCallId(int callerId, int receiverId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 'call_${callerId}_${receiverId}_$timestamp';
  }
  
  /// Extracts user IDs from a call ID
  static Map<String, int>? parseCallId(String callId) {
    if (!isValidCallId(callId)) {
      return null;
    }
    
    final parts = callId.split('_');
    if (parts.length < 4) {
      return null;
    }
    
    try {
      return {
        'caller_id': int.parse(parts[1]),
        'receiver_id': int.parse(parts[2]),
        'timestamp': int.parse(parts[3]),
      };
    } catch (e) {
      return null;
    }
  }
}