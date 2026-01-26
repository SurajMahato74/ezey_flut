class Call {
  final String callId;
  final String callType; // 'audio' or 'video'
  final int callerId;
  final String callerName;
  final int? receiverId;
  final String? receiverName;
  final List<int> participants;
  final String status; // 'initiated', 'ringing', 'answered', 'ended', 'declined', 'missed'
  final DateTime? initiatedAt;
  final DateTime? answeredAt;
  final double? duration;
  final String? agoraToken;
  final String? agoraChannel;

  Call({
    required this.callId,
    required this.callType,
    required this.callerId,
    required this.callerName,
    this.receiverId,
    this.receiverName,
    required this.participants,
    required this.status,
    this.initiatedAt,
    this.answeredAt,
    this.duration,
    this.agoraToken,
    this.agoraChannel,
  });

  factory Call.fromJson(Map<String, dynamic> json) {
    // Handle different response formats from server
    String callId;
    if (json['call_id'] != null) {
      callId = json['call_id'].toString();
    } else if (json['id'] != null) {
      callId = json['id'].toString();
    } else {
      callId = 'unknown';
    }

    // Handle caller information
    Map<String, dynamic>? caller = json['caller'];
    int callerId = 0;
    String callerName = 'Unknown';
    
    if (caller != null) {
      callerId = caller['id'] ?? 0;
      callerName = caller['display_name'] ?? caller['username'] ?? caller['name'] ?? 'Unknown';
    }

    // Handle receiver/callee information
    Map<String, dynamic>? receiver = json['receiver'] ?? json['callee'];
    int? receiverId;
    String? receiverName;
    
    if (receiver != null) {
      receiverId = receiver['id'];
      receiverName = receiver['display_name'] ?? receiver['username'] ?? receiver['name'];
    }

    return Call(
      callId: callId,
      callType: json['call_type'] ?? 'audio',
      callerId: callerId,
      callerName: callerName,
      receiverId: receiverId,
      receiverName: receiverName,
      participants: List<int>.from(json['participants'] ?? []),
      status: json['status'] ?? 'initiated',
      initiatedAt: json['started_at'] != null ? DateTime.parse(json['started_at']) : null,
      answeredAt: json['answered_at'] != null ? DateTime.parse(json['answered_at']) : null,
      duration: json['duration']?.toDouble(),
      agoraToken: json['agora_token'],
      agoraChannel: json['agora_channel'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'call_id': callId,
      'call_type': callType,
      'caller': {'id': callerId, 'name': callerName},
      'callee': receiverId != null ? {'id': receiverId, 'name': receiverName} : null,
      'participants': participants,
      'status': status,
      'initiated_at': initiatedAt?.toIso8601String(),
      'answered_at': answeredAt?.toIso8601String(),
      'duration': duration,
    };
  }
}

enum CallState {
  idle,
  connecting,   // Trying to reach the other user
  initiated,    // Call created (backend status)
  ringing,      // Both sides show ringing when connected
  answered,     // Call accepted (backend status)
  connected,    // Call active with timer running
  ended,        // Call ended
  declined,     // Call declined
  missed,       // Call missed
}

class CallParticipant {
  final int userId;
  final String name;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isConnected;

  CallParticipant({
    required this.userId,
    required this.name,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isConnected = false,
  });
}