import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Simple placeholder for old active call screen
// Now calls use the _SimpleAgoraCall in chat_screen.dart
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call, color: Colors.white, size: 64),
            SizedBox(height: 16),
            Text(
              'Call functionality moved to chat screen',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}