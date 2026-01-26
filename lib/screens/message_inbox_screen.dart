import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/global_websocket_service.dart';
import '../models/user_role.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

class MessageInboxScreen extends StatefulWidget {
  final String title;
  final bool isVendor;

  const MessageInboxScreen({
    super.key,
    this.title = "Messages",
    this.isVendor = false,
  });

  @override
  State<MessageInboxScreen> createState() => _MessageInboxScreenState();
}

class _MessageInboxScreenState extends State<MessageInboxScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  bool _hasError = false;
  GlobalWebSocketService? _globalWs;

  @override
  void initState() {
    super.initState();
    _globalWs = Provider.of<GlobalWebSocketService>(context, listen: false);
    _subscribeToWebSocket();
    _fetchConversations();
  }

  @override
  void dispose() {
    _globalWs?.onNewMessage = null;
    super.dispose();
  }

  void _subscribeToWebSocket() {
    _globalWs?.onNewMessage = (data) {
      final type = data['type'];
      if (type == 'new_message' || type == 'message' || type == 'conversation_updated') {
        // Refresh conversations when new message arrives or conversation is updated
        _fetchConversations();
      }
    };
  }

  Future<void> _fetchConversations() async {
    final authService = AuthService();
    
    if (!authService.isLoggedIn) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // Don't show loading if we already have conversations (for background refresh)
    final showLoading = _conversations.isEmpty;

    final token = authService.token;
    if (token == null) {
      print('❌ No token available for fetching conversations');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      print('🔵 Fetching conversations with token: ${token.substring(0, 10)}...');
      final response = await ApiService().getConversations(token);
      print('🔵 Conversations response: $response');
      
      List<dynamic> results = [];
      if (response is List) {
        results = response;
      } else if (response is Map<String, dynamic>) {
        results = response['results'] ?? [];
      }

      print('🔵 Found ${results.length} conversations');

      // Filter conversations based on current role to separate "Buyer" vs "Seller" activities
      final currentRole = authService.currentRole;
      final currentRoleString = currentRole?.toString().split('.').last ?? 'customer';
      print('🔵 Current role: $currentRoleString');
      
      final List<Map<String, dynamic>> processedList = [];

      for (var conversation in results) {
        final participants = conversation['participants'];
        if (participants is! List) continue;

        // 1. Identify Support User
        final supportUser = participants.firstWhere(
           (p) => p['email']?.toString().toLowerCase() == 'ezeyway@gmail.com',
           orElse: () => null
        );

        // 2. Check for Pure Support Chat (1-on-1)
        // Participants length should be 2 (Me + Support)
        // Note: Sometimes length might be > 2 if historical/inactive? using length==2 is strict.
        final isPureSupportChat = participants.length == 2 && supportUser != null;

        if (isPureSupportChat) {
           final item = Map<String, dynamic>.from(conversation);
           item['other_participant'] = supportUser;
           item['filter_email'] = 'ezeyway@gmail.com';
           processedList.add(item);
           continue; // Skip checking for others in this conversation
        }

        // 3. Handle Normal Chats (Vendor/Customer) - Skip Support
        bool added = false;
        for (var p in participants) {
           // Skip Me
           if (p['id'] == authService.user?.id) continue;
           // Skip Support (in mixed chats, we don't list as Support)
           if (p['email']?.toString().toLowerCase() == 'ezeyway@gmail.com') continue;

           final userType = p['user_type'] ?? 'customer';
           bool show = false;
           
           if (currentRoleString == 'customer') {
               // Customer sees Vendor/Admin - also show other customers for group chats
               if (userType == 'vendor' || userType == 'admin' || userType == 'customer') show = true;
           } else if (currentRoleString == 'vendor') {
               // Vendor sees Customer/Admin - also show other vendors for group chats
               if (userType == 'customer' || userType == 'admin' || userType == 'vendor') show = true;
           }

           if (show && !added) {
              final item = Map<String, dynamic>.from(conversation);
              item['other_participant'] = p;
              item['filter_email'] = p['email'];
              processedList.add(item);
              added = true; // Only add once per conversation context
           }
        }
      }

      // 3. Sort: Support threads at the top
      processedList.sort((a, b) {
        final aIsSupport = a['filter_email'] == 'ezeyway@gmail.com';
        final bIsSupport = b['filter_email'] == 'ezeyway@gmail.com';

        if (aIsSupport && !bIsSupport) return -1; // a comes first
        if (!aIsSupport && bIsSupport) return 1;  // b comes first
        
        // Default sort by updated_at (assuming API returns sorted, otherwise parse date)
        return 0;
      });

      final filteredConversations = processedList;
      print('✅ Processed ${filteredConversations.length} conversations');

      if (mounted) {
        setState(() {
          _conversations = List<Map<String, dynamic>>.from(filteredConversations);
          if (showLoading) _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error fetching conversations: $e');
      
      // Handle token expiration
      if (e.toString().contains('401') || e.toString().contains('Invalid token')) {
        print('🔄 Token expired, logging out user');
        if (mounted) {
          await authService.logout(context);
        }
        return;
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _contactSupport() async {
    final authService = AuthService();
    final token = authService.token;
    if (token == null) return;

    setState(() => _isLoading = true);
    try {
      // Create pure support conversation (1-on-1)
      final response = await ApiService().createSupportConversation(token, initialMessage: "Hi, I need support.");
      
      if (mounted) {
        setState(() => _isLoading = false);
        
        final conversationId = response['conversation_id'];
        if (conversationId != null) {
           Navigator.of(context).push(
             MaterialPageRoute(
               builder: (_) => ChatScreen(
                 participantName: "EzeyWay Support",
                 participantImage: "https://ezeyway.com/images/support-avatar.png", // Fallback/Placeholder
                 conversationId: conversationId,
                 allowedEmail: 'ezeyway@gmail.com', // Ensure we only see support msgs
                 participantId: null, // Support calls not implemented yet
               ),
             ),
           ).then((_) => _fetchConversations());
        } else {
           _fetchConversations();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to contact support: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService(),
      builder: (context, _) {
        final isLoggedIn = AuthService().isLoggedIn;

        return Scaffold(
        backgroundColor: AppTheme.homeBackgroundDark,
        floatingActionButton: isLoggedIn ? FloatingActionButton.extended(
          onPressed: _contactSupport,
          backgroundColor: AppTheme.primaryColor,
          icon: const Icon(Icons.support_agent, color: Colors.black),
          label: Text(
            'Support',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
        ) : null,
        body: Column(
            children: [
              // Top App Bar
              Container(
                padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.homeBackgroundDark.withOpacity(0.8),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.015,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: isLoggedIn ? _buildMessageList() : _buildLoginPrompt(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.message_outlined,
            size: 80,
            color: AppTheme.primaryColor.withOpacity(0.7),
          ),
          const SizedBox(height: 24),
          Text(
            'Please login to view messages',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(
                    role: UserRole.customer,
                    shouldRemoveAllRoutes: false,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Sign In',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              'Failed to load messages',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your internet connection',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchConversations,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.plusJakartaSans(color: Colors.black),
              ),
            ),
          ],
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 64),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a conversation with vendors or support',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primaryColor,
      backgroundColor: const Color(0xFF1E1E1E),
      onRefresh: _fetchConversations,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conversation = _conversations[index];
          return _buildConversationItem(conversation);
        },
      ),
    );
  }

  Widget _buildConversationItem(Map<String, dynamic> conversation) {
    // We already set the correct 'other_participant' in _fetchConversations processing
    final otherParticipant = conversation['other_participant'] ?? {};
    final lastMessage = conversation['last_message'];
    final unreadCount = conversation['unread_count'] ?? 0;

    final displayName = otherParticipant['display_name'] ?? 'Unknown';
    final userType = otherParticipant['user_type'] ?? '';
    final profilePicture = otherParticipant['profile_picture'];
    final profilePictureUrl = otherParticipant['profile_picture_url'];
    
    // Determine image URL (prioritize uploaded picture)
    String? imageUrl;
    if (profilePicture != null && profilePicture.isNotEmpty) {
      imageUrl = profilePicture.startsWith('http') 
          ? profilePicture 
          : 'https://ezeyway.com/media/$profilePicture';
    } else if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
      imageUrl = profilePictureUrl;
    }

    final messageContent = lastMessage?['content'] ?? 'No messages yet';
    // Use last message timestamp if available, otherwise conversation updated_at
    final createdAt = lastMessage?['created_at'] ?? conversation['updated_at'] ?? conversation['created_at'];

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              participantName: displayName,
              participantImage: imageUrl ?? 'https://via.placeholder.com/150',
              conversationId: conversation['id'],
              allowedEmail: conversation['filter_email'], // Virtual Split Filter
              participantId: otherParticipant['id'],
            ),
          ),
        ).then((_) => _fetchConversations()); // Refresh after returning
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(16),
          border: unreadCount > 0
              ? Border.all(color: AppTheme.primaryColor.withOpacity(0.3))
              : null,
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: unreadCount > 0 ? AppTheme.primaryColor : Colors.grey,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.person,
                          color: Colors.grey,
                          size: 32,
                        ),
                      )
                    : const Icon(
                        Icons.person,
                        color: Colors.grey,
                        size: 32,
                      ),
              ),
            ),
            const SizedBox(width: 16),

            // Message Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unreadCount.toString(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    messageContent,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: unreadCount > 0 ? Colors.white : Colors.grey,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(createdAt),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 7) {
        return '${date.day}/${date.month}/${date.year}';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (_) {
      return '';
    }
  }
}