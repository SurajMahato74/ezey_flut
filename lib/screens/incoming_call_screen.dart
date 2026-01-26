import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Simple placeholder for old incoming call screen
// Now calls use the _SimpleAgoraCall in chat_screen.dart
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call_received, color: Colors.white, size: 64),
            SizedBox(height: 16),
            Text(
              'Incoming calls now handled in chat screen',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}