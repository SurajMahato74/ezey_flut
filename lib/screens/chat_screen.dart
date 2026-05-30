import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/global_websocket_service.dart';
import '../services/complete_call_system.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../widgets/safe_network_image.dart';
import '../config.dart' as appConfig;
import 'location_map_screen.dart';

// Helper class to store location data
class _LocationData {
  final double latitude;
  final double longitude;
  
  _LocationData(this.latitude, this.longitude);
}

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String participantName;
  final String participantImage;
  final String? allowedEmail; // If set, only show messages from this email + me
  final int? participantId; // For call functionality

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.participantName,
    required this.participantImage,
    this.allowedEmail,
    this.participantId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isLoadingMore = false;
  bool _hasMorePages = true;
  int _currentPage = 1;
  Timer? _pollingTimer;
  SharedPreferences? _prefs;
  StreamSubscription? _globalWebSocketSubscription;
  String get _cacheKey => 'chat_messages_${widget.conversationId}';
  Set<int> _typingUsers = {};
  Timer? _typingTimer;
  bool _isTyping = false;
  GlobalWebSocketService? _globalWs; // Store reference to avoid dispose issues

  @override
  void initState() {
    super.initState();
    _globalWs = Provider.of<GlobalWebSocketService>(context, listen: false);
    CompleteCallSystem().initialize(); // Initialize complete call system
    _initPrefs();
    _scrollController.addListener(_onScroll);
    _subscribeToGlobalWebSocket();
    _subscribeToIncomingCalls();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _pollingTimer?.cancel();
    _typingTimer?.cancel();
    _readDebounceTimer?.cancel();
    _globalWebSocketSubscription?.cancel();
    CompleteCallSystem().dispose(); // Dispose complete call system
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    // Load cached messages after prefs are ready
    await _loadCachedMessages();
  }

  void _subscribeToGlobalWebSocket() {
    // Subscribe to new message notifications
    _globalWs?.onNewMessage = (data) {
      _handleWebSocketMessage(data);
    };
  }

  void _subscribeToIncomingCalls() {
    // Subscribe to incoming call notifications
    _globalWs?.onNotification = (data) {
      if (data['type'] == 'incoming_call') {
        _handleIncomingCall(data);
      }
    };
  }

  void _handleIncomingCall(Map<String, dynamic> data) {
    final call = data['call'];
    if (call != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CompleteIncomingCallScreen(
            callId: call['call_id'] ?? call['id'].toString(),
            callerName: call['caller']?['display_name'] ?? 'Unknown',
            callerImage: call['caller']?['profile_picture_url'] ?? '',
            callType: call['call_type'] ?? 'audio',
            callData: call, // Pass the complete call data
          ),
        ),
      );
    }
  }

  void _sendTypingEvent(bool isTyping) {
    if (_globalWs?.isConnected != true) return;

    final messageData = {
      'type': 'typing',
      'conversation_id': widget.conversationId,
      'is_typing': isTyping,
    };
    _globalWs!.sendMessage(messageData);
  }

  void _startTyping() {
    if (_isTyping) return;
    _isTyping = true;
    _sendTypingEvent(true);
    _resetTypingTimer();
  }

  void _stopTyping() {
    if (!_isTyping) return;
    _isTyping = false;
    _sendTypingEvent(false);
    _typingTimer?.cancel();
  }

  void _resetTypingTimer() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _stopTyping();
    });
  }

  Timer? _readDebounceTimer;
  Set<int> _sentReadReceipts = {};
  
  void _sendReadReceipt(int messageId) {
    final currentUser = AuthService().user;
    if (currentUser == null || _sentReadReceipts.contains(messageId)) return;
    
    _sentReadReceipts.add(messageId);
    
    // Send WebSocket notification
    if (_globalWs?.isConnected == true) {
      final messageData = {
        'type': 'message_read',
        'message_id': messageId,
        'conversation_id': widget.conversationId,
        'user_id': currentUser.id,
        'user_type': currentUser.userType,
        'timestamp': DateTime.now().toIso8601String(),
      };
      _globalWs!.sendMessage(messageData);
    }
    
    // Also call API to mark as read in backend
    _markMessageReadAPI(messageId);
  }
  
  Future<void> _markMessageReadAPI(int messageId) async {
    final token = AuthService().token;
    if (token == null) return;
    
    try {
      await ApiService().markMessageAsRead(token, messageId);
    } catch (e) {
      // Ignore API errors for read receipts
    }
  }

  void _tryMarkConversationAsRead() {
    // Only consider marking if user is near the bottom (seeing latest messages)
    if (_scrollController.hasClients &&
        _scrollController.offset <= 400 && // adjust 300–600 depending on your UI
        _scrollController.position.maxScrollExtent > 100) { // avoid calling when list is tiny

      // Cancel previous timer
      _readDebounceTimer?.cancel();

      // Debounce: wait a bit so user doesn't see flickering
      _readDebounceTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted) return;

        // Only proceed if still near bottom
        if (_scrollController.offset <= 400) {
          _reallyMarkAsRead();
        }
      });
    }
  }

  void _reallyMarkAsRead() {
    final currentUser = AuthService().user;
    if (currentUser == null) return;

    bool hasNewReads = false;
    DateTime? mostRecentMessageTime;
    
    // Find the most recent message timestamp that user can see
    for (final msg in _messages) {
      final senderId = msg['sender']?['id'] ?? msg['sender_id'];
      if (senderId == currentUser.id) continue; // skip own messages
      
      final messageTime = DateTime.tryParse(msg['created_at'] ?? '');
      if (messageTime != null && (mostRecentMessageTime == null || messageTime.isAfter(mostRecentMessageTime))) {
        mostRecentMessageTime = messageTime;
      }
    }

    // Mark all messages as read up to the most recent visible message
    for (final msg in _messages) {
      final senderId = msg['sender']?['id'] ?? msg['sender_id'];
      if (senderId == currentUser.id) continue; // skip own messages

      final messageTime = DateTime.tryParse(msg['created_at'] ?? '');
      
      // If this message is older than or equal to the most recent visible message, mark as read
      if (msg['status'] != 'read' && messageTime != null && mostRecentMessageTime != null && 
          !messageTime.isAfter(mostRecentMessageTime)) {
        _sendReadReceipt(msg['id']);
        msg['status'] = 'read';
        hasNewReads = true;
      }
    }

    if (hasNewReads) {
      _saveMessagesToCache();

      // Tell everyone this conversation is now read
      _globalWs?.sendMessage({
        'type': 'conversation_read',
        'conversation_id': widget.conversationId,
        'timestamp': DateTime.now().toIso8601String(),
        'user_id': currentUser.id,
      });
      
      // Also update conversation timestamp
      _globalWs?.sendMessage({
        'type': 'conversation_updated',
        'conversation_id': widget.conversationId,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  void _handleWebSocketMessage(dynamic messageData) {
    try {
      Map<String, dynamic> data;
      if (messageData is String) {
        data = jsonDecode(messageData);
      } else {
        data = messageData as Map<String, dynamic>;
      }
      final type = data['type'];

      if (type == 'new_message' || type == 'message') {
        final newMessage = data['message'];
        final transformedMessage = {
          ...newMessage,
          'sender': {
            'id': newMessage['sender_id'],
            'display_name': newMessage['sender_name'],
            'email': newMessage['sender_email'],
            'profile_picture_url': newMessage['sender_profile_picture_url'],
          },
          'status': 'delivered',
        };
        
        if (transformedMessage['conversation_id'] == widget.conversationId) {
          if (!mounted) return; // Check if widget is still mounted
          setState(() {
            final exists = _messages.any((msg) => msg['id'] == transformedMessage['id']);
            if (!exists) {
              _messages.insert(0, transformedMessage);
              _saveMessagesToCache();
            }
          });
        }
      } else if (type == 'typing_indicator' || type == 'typing') {
        final userId = data['user_id'];
        final conversationId = data['conversation_id'];
        final isTyping = data['is_typing'] ?? false;
        if (conversationId == widget.conversationId && userId != AuthService().user?.id) {
          if (!mounted) return; // Check if widget is still mounted
          setState(() {
            _typingUsers ??= {};
            if (isTyping) {
              _typingUsers.add(userId);
            } else {
              _typingUsers.remove(userId);
            }
          });
        }
      } else if (type == 'message_read_receipt') {
        final messageId = data['message_id'];
        final readBy = data['read_by'];
        if (readBy != AuthService().user?.id) {
          if (!mounted) return; // Check if widget is still mounted
          setState(() {
            final messageIndex = _messages.indexWhere((msg) => msg['id'] == messageId);
            if (messageIndex != -1) {
              _messages[messageIndex]['status'] = 'read';
              _saveMessagesToCache();
            }
          });
        }
      }
    } catch (e) {
      // Ignore errors for disposed widgets
    }
  }

  Future<void> _loadCachedMessages() async {
    if (_prefs == null) return;
    final cached = _prefs!.getString(_cacheKey);
    if (cached != null) {
      try {
        final List<dynamic> cachedMessages = List.from(jsonDecode(cached));
        setState(() {
          _messages = cachedMessages;
          _isLoading = false;
        });
        print('✅ Loaded ${cachedMessages.length} cached messages');
        // Immediately mark as read when opening chat
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _reallyMarkAsRead();
        });
      } catch (e) {
        print('❌ Error loading cached messages: $e');
      }
    }
    // Only sync if we have no cached messages
    if (_messages.isEmpty) {
      _syncNewMessages();
    }
  }

  Future<void> _syncNewMessages() async {
    final token = AuthService().token;
    if (token == null) return;

    try {
      final response = await ApiService().getMessages(token, widget.conversationId, page: 1);
      final results = response['results'] as List;

      setState(() {
        // Merge new messages, assuming results are newest first
        final newMessages = results.where((newMsg) =>
          !_messages.any((cachedMsg) => cachedMsg['id'] == newMsg['id'])).toList();

        // Set status for loaded messages
        for (final msg in newMessages) {
          final currentUser = AuthService().user;
          final senderId = msg['sender'] != null ? msg['sender']['id'] : msg['sender_id'];
          final isCurrentUser = currentUser?.id == senderId;

          if (isCurrentUser) {
            // Sent messages - assume delivered if loaded from server
            msg['status'] = msg['status'] ?? 'delivered';
          } else {
            // Received messages - will be marked as read
            msg['status'] = msg['status'] ?? 'delivered';
          }
        }

        _messages.insertAll(0, newMessages); // Prepend new messages
        _isLoading = false;
      });
      _saveMessagesToCache();
      // Immediately mark as read when opening chat
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reallyMarkAsRead();
      });
    } catch (e) {
      // If no cache and fetch fails, set loading false
      if (_messages.isEmpty) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onScroll() {
    // Load more when user scrolls to 80% of the way to the end
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingMore && _hasMorePages) {
      _loadMoreMessages();
    }
    // Try to mark as read when scrolling
    _tryMarkConversationAsRead();
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMorePages) return;

    setState(() => _isLoadingMore = true);

    final token = AuthService().token;
    if (token == null) {
      setState(() => _isLoadingMore = false);
      return;
    }

    try {
      final nextPage = _currentPage + 1;
      final response = await ApiService().getMessages(token, widget.conversationId, page: nextPage);
      final results = response['results'] as List;

      if (results.isEmpty) {
        setState(() => _hasMorePages = false);
      } else {
        setState(() {
          _messages.addAll(results);
          _currentPage = nextPage;
        });
        _saveMessagesToCache();
      }
    } catch (e) {
      print('❌ Error loading more messages: $e');
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  void _saveMessagesToCache() {
    if (_prefs != null) {
      _prefs!.setString(_cacheKey, jsonEncode(_messages));
    }
  }

  Future<void> _fetchMessages({bool isPolling = false}) async {
    final token = AuthService().token;
    if (token == null) return;

    if (!isPolling) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await ApiService().getMessages(token, widget.conversationId);
      final results = response['results'] as List; // Recent messages first usually?
      
      // API normally returns newest first for pagination. 
      // We want to display oldest at top (ListView) or reverse it.
      // Let's reverse them so index 0 is oldest (top) if we build normally,
      // or keep them and reverse ListView. 
      // Let's see... usually chat APIs return standard paginated list (newest first).
      
      if (mounted) {
        setState(() {
          _messages = results.toList(); // Keep newest first (index 0)
          _isLoading = false;
        });
        // If not polling, scroll to bottom (which is top of list if reverse: true)
      }
    } catch (e) {
      if (mounted && !isPolling) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load messages: $e')),
        );
      }
    }
  }

  Future<void> _sendMessage({String? content, XFile? file}) async {
    if ((content == null || content.trim().isEmpty) && file == null) return;

    final token = AuthService().token;
    if (token == null) {
      print('Debug: No token available for sending message');
      return;
    }

    // Create temporary message for optimistic UI update
    final tempMessage = {
      'id': DateTime.now().millisecondsSinceEpoch, // Temporary ID
      'conversation_id': widget.conversationId,
      'sender': {
        'id': AuthService().user?.id,
        'display_name': AuthService().user?.displayName ?? 'You',
        'email': AuthService().user?.email,
      },
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'message_type': file != null ? 'image' : 'text',
      'status': 'sending',
    };

    setState(() {
      _messages.insert(0, tempMessage); // Add to top
      _isSending = true;
    });

    try {
      if (file != null) {
        print('Debug: Sending file message via HTTP');
        // Send file via HTTP API
        await ApiService().sendMessage(
          token,
          widget.conversationId,
          content: content,
          file: file
        );
      } else {
        print('Debug: Sending text message via WebSocket');
        // Send text message via WebSocket
        final messageData = {
          'type': 'message',
          'conversation_id': widget.conversationId,
          'content': content,
        };
        if (_globalWs?.isConnected != true) {
          throw Exception('WebSocket not connected');
        }
        _globalWs!.sendMessage(messageData);
      }

      // Update status to sent
      setState(() {
        tempMessage['status'] = 'sent';
      });

      _messageController.clear();
      _stopTyping(); // Stop typing when message is sent
      
      // Update conversation timestamp
      _globalWs?.sendMessage({
        'type': 'conversation_updated',
        'conversation_id': widget.conversationId,
        'timestamp': DateTime.now().toIso8601String(),
      });

    } catch (e) {
      print('Debug: Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);
    if (image != null) {
      await _sendMessage(file: image);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true, // Show newest at bottom (index 0)
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(color: AppTheme.primaryColor),
                              ),
                            );
                          }
                          final message = _messages[index];
                          return _buildMessageBubble(message);
                        },
                      ),
          ),
          _buildTypingIndicator(),
          _buildMessageComposer(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_chat_unread_outlined, size: 80, color: AppTheme.primaryColor.withOpacity(0.5)),
            const SizedBox(height: 24),
            Text(
              'Start a conversation with ${widget.participantName}',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
             const SizedBox(height: 8),
            Text(
              'Say hello! 👋',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFA1A1AA),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // COMPLETE FIXED CALL IMPLEMENTATION
  Future<void> _initiateCall() async {
    if (widget.participantId == null) return;

    final currentUser = AuthService().user;
    if (currentUser?.id == widget.participantId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot call yourself')),
      );
      return;
    }

    try {
      final callSystem = CompleteCallSystem();
      final call = await callSystem.createCall(widget.participantId!, 'audio');
      
      if (call != null && mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => CompleteActiveCallScreen(
            callId: call.callId,
            participantName: widget.participantName,
            isIncoming: false,
          ),
        ));
      } else {
        throw Exception('Failed to create call');
      }
    } catch (e) {
      print('❌ Call failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 16),
      decoration: const BoxDecoration(
        color: AppTheme.homeBackgroundDark,
        border: Border(
          bottom: BorderSide(color: Color(0xFF27272A)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3), width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SafeNetworkImage(
                imageUrl: widget.participantImage,
                fit: BoxFit.cover,
                errorWidget: const Icon(Icons.person, color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.participantName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Online',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (widget.participantId != null)
            IconButton(
              onPressed: _initiateCall,
              icon: const Icon(Icons.call, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(dynamic message) {
    final currentUser = AuthService().user;
    final senderId = message['sender'] != null ? message['sender']['id'] : message['sender_id'];
    final isCurrentUser = currentUser?.id == senderId;

    // Virtual Split Filtering - improved logic for vendor/customer message visibility
    if (!isCurrentUser && widget.allowedEmail != null) {
      final senderEmail = (message['sender'] != null ? message['sender']['email'] : message['sender_email'])?.toString().toLowerCase();
      if (senderEmail != null && senderEmail != widget.allowedEmail!.toLowerCase()) {
        return const SizedBox.shrink();
      }
    }

    final content = message['content'];
    final messageType = message['message_type'];
    final fileUrl = message['file_url']; 
    final timestamp = message['created_at'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isCurrentUser)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      (message['sender'] != null ? message['sender']['display_name'] : message['sender_name']) ?? 'Unknown',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFFA1A1AA),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Container(
                  padding: (messageType == 'image' && (content == null || content.toString().isEmpty))
                      ? const EdgeInsets.all(4)
                      : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isCurrentUser ? AppTheme.primaryColor : const Color(0xFF27272A),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: isCurrentUser ? const Radius.circular(20) : const Radius.circular(4),
                      bottomRight: !isCurrentUser ? const Radius.circular(20) : const Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (messageType == 'image' || (fileUrl != null && fileUrl.toString().isNotEmpty))
                        Padding(
                          padding: EdgeInsets.only(bottom: (content != null && content.toString().isNotEmpty) ? 8 : 0),
                          child: GestureDetector(
                            onTap: () => _showFullScreenImage(_normalizeUrl(fileUrl)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SafeNetworkImage(
                                imageUrl: _normalizeUrl(fileUrl),
                                 width: 240,
                                 fit: BoxFit.cover,
                                 errorWidget: const Icon(Icons.broken_image, color: Colors.white24, size: 48),
                              ),
                            ),
                          ),
                        ),
                      if (content != null && content.toString().isNotEmpty)
                        _buildMessageContent(content, isCurrentUser),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(timestamp),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: isCurrentUser ? Colors.black54 : Colors.white38,
                            ),
                          ),
                          if (isCurrentUser) ...[
                            const SizedBox(width: 6),
                            _buildMessageStatus(message),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(String content, bool isCurrentUser) {
    // Check if this is a location message
    final locationData = _parseLocationFromMessage(content);
    
    if (locationData != null) {
      return _buildLocationMessage(content, locationData, isCurrentUser);
    }
    
    // Regular text message
    return Text(
      content,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        color: isCurrentUser ? Colors.black : Colors.white,
      ),
    );
  }

  Widget _buildLocationMessage(String content, _LocationData locationData, bool isCurrentUser) {
    return Container(
      decoration: BoxDecoration(
        color: isCurrentUser ? AppTheme.primaryColor.withOpacity(0.1) : const Color(0xFF27272A).withOpacity(0.8),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: isCurrentUser ? const Radius.circular(20) : const Radius.circular(4),
          bottomRight: !isCurrentUser ? const Radius.circular(20) : const Radius.circular(4),
        ),
        border: Border.all(color: Colors.red.withOpacity(0.3), width: 1),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location icon and text
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Text(
                'Shared Location',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isCurrentUser ? Colors.black : Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Coordinates
          Text(
            '${locationData.latitude.toStringAsFixed(6)}, ${locationData.longitude.toStringAsFixed(6)}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: isCurrentUser ? Colors.black87 : Colors.grey[300],
            ),
          ),
          const SizedBox(height: 8),
          
          // Map preview with clickable overlay
          Stack(
            children: [
              _buildRealMapPreview(locationData.latitude, locationData.longitude, isCurrentUser),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showLocationOnMap(locationData.latitude, locationData.longitude, 'Shared Location'),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.1),
                          ],
                        ),
                      ),
                      child: const Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(Icons.open_in_new, color: Colors.white70, size: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // View on Map button
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showLocationOnMap(locationData.latitude, locationData.longitude, 'Shared Location'),
              icon: const Icon(Icons.map, size: 14, color: Colors.red),
              label: Text(
                'View on Map',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Colors.red, width: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeUrl(dynamic url) {
    if (url == null || url.toString().isEmpty) return '';
    String urlString = url.toString();
    if (urlString.startsWith('http')) return urlString;
    // For chat messages, the path is often messages/... so prepend mediaUrl
    if (urlString.startsWith('/')) return '${appConfig.Config.mediaUrl}$urlString';
    return '${appConfig.Config.mediaUrl}/$urlString';
  }

  void _showFullScreenImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black45,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                onPressed: () {
                   // Optional: Implement download
                },
              ),
            ],
          ),
          body: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: SafeNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                placeholder: const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
                errorWidget: const Icon(Icons.broken_image, color: Colors.white24, size: 64),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final date = DateTime.parse(timestamp).toLocal();
      return DateFormat('h:mm a').format(date);
    } catch (_) {
      return '';
    }
  }

  _LocationData? _parseLocationFromMessage(String content) {
    // Look for latitude and longitude in the message
    // Pattern: "Shared Location: lat, lng" or just "lat, lng"
    final regex = RegExp(r'(-?\d+\.\d+),\s*(-?\d+\.\d+)', caseSensitive: false);
    final match = regex.firstMatch(content);
    
    if (match != null) {
      try {
        final latitude = double.parse(match.group(1)!);
        final longitude = double.parse(match.group(2)!);
        
        // Validate coordinates
        if (latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180) {
          return _LocationData(latitude, longitude);
        }
      } catch (e) {
        // Parsing failed
      }
    }
    
    return null;
  }

  void _showLocationOnMap(double latitude, double longitude, String address) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LocationMapScreen(
          latitude: latitude,
          longitude: longitude,
          address: address,
          vendorShopLatitude: null,
          vendorShopLongitude: null,
          vendorCurrentLatitude: null,
          vendorCurrentLongitude: null,
        ),
      ),
    );
  }

  Widget _buildMessageStatus(dynamic message) {
    final status = message['status'] ?? 'sent';

    String statusText;
    Color statusColor;

    switch (status) {
      case 'sending':
        statusText = 'Sending';
        statusColor = Colors.grey;
        break;
      case 'sent':
        statusText = 'Sent';
        statusColor = Colors.grey;
        break;
      case 'delivered':
        statusText = 'Delivered';
        statusColor = Colors.grey;
        break;
      case 'read':
      case 'seen':
        statusText = 'Seen';
        statusColor = Colors.blue;
        break;
      default:
        statusText = 'Sent';
        statusColor = Colors.grey;
        break;
    }

    return Text(
      statusText,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 9,
        color: statusColor,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTypingIndicator() {
    if (_typingUsers.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.more_horiz,
              color: AppTheme.primaryColor,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'typing...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppTheme.homeBackgroundDark,
        border: Border(top: BorderSide(color: Color(0xFF27272A))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              onPressed: _showAttachmentOptions,
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFFA1A1AA)),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF27272A),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFA1A1AA)),
                    fillColor: Colors.transparent,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (value) {
                    if (value.trim().isNotEmpty) {
                      _startTyping();
                    } else {
                      _stopTyping();
                    }
                  },
                  onSubmitted: (value) => _sendMessage(content: value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _sendMessage(content: _messageController.text),
              icon: _isSending 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor))
                : const Icon(Icons.send, color: AppTheme.primaryColor),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.white),
              title: const Text('Share Location', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _shareCurrentLocation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Gallery', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareCurrentLocation() async {
    try {
      final hasPermission = await LocationService().requestLocationPermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to share your location')),
        );
        return;
      }

      final position = await LocationService().getCurrentPosition();
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to get your current location')),
        );
        return;
      }

      // Create a Google Maps link
      final locationLink = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      final locationText = '📍 Shared Location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}\n$locationLink';

      await _sendMessage(content: locationText);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share location: $e')),
      );
    }
  }

  Future<void> _markConversationAsRead() async {
    // Just use WebSocket notification - no API call needed
    _notifyConversationRead();
  }
  
  void _notifyConversationRead() {
    // Send WebSocket message to notify conversation was read
    if (_globalWs?.isConnected == true) {
      _globalWs!.sendMessage({
        'type': 'conversation_read',
        'conversation_id': widget.conversationId,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  Widget _buildRealMapPreview(double latitude, double longitude, bool isCurrentUser) {
    return GestureDetector(
      onTap: () => _showLocationOnMap(latitude, longitude, 'Shared Location'),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[600]!),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FlutterMap(
            options: MapOptions(
              center: LatLng(latitude, longitude),
              zoom: 15.0,
              interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate, // Disable rotation
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ezeyway.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(latitude, longitude),
                    width: 32,
                    height: 32,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}



// Custom painter for map grid lines
class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw horizontal grid lines
    for (int i = 0; i <= 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }

    // Draw vertical grid lines
    for (int i = 0; i <= 5; i++) {
      final x = size.width * i / 5;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // Draw diagonal lines for more map-like appearance
    final diagonalPaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Diagonal lines from top-left to bottom-right
    for (int i = -5; i <= 5; i++) {
      final startX = i * size.width / 5;
      const startY = 0.0;
      final endX = startX + size.height;
      final endY = size.height;
      
      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        diagonalPaint,
      );
    }

    // Diagonal lines from top-right to bottom-left
    for (int i = -5; i <= 5; i++) {
      final startX = size.width + (i * size.width / 5);
      const startY = 0.0;
      final endX = startX - size.height;
      final endY = size.height;
      
      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        diagonalPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
