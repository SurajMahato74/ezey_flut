import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'screens/splash_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/main_app_screen.dart';
import 'services/auth_service.dart';
import 'services/data_preloader_service.dart';
import 'services/navigation_service.dart';
import 'services/global_websocket_service.dart';
import 'services/fcm_service.dart';
import 'services/background_service.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Set background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  runApp(const EzeywayApp());
}

class EzeywayApp extends StatelessWidget {
  const EzeywayApp({super.key});
  
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<DataPreloaderService>(create: (_) => DataPreloaderService()),
        ChangeNotifierProvider<NavigationService>(create: (_) => NavigationService()),
        Provider<GlobalWebSocketService>(create: (_) => GlobalWebSocketService()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Ezeyway',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        restorationScopeId: 'app',
        home: const AppEntryWithRefresh(),
      ),
    );
  }
}

// Wrapper providing splash, pull‑to‑refresh and auto‑login navigation.
class AppEntryWithRefresh extends StatefulWidget {
  const AppEntryWithRefresh({super.key});

  @override
  State<AppEntryWithRefresh> createState() => _AppEntryWithRefreshState();
}

class _AppEntryWithRefreshState extends State<AppEntryWithRefresh> with WidgetsBindingObserver, RestorationMixin {
  bool _splashFinished = false;
  final RestorableBool _splashFinishedRestoration = RestorableBool(false);

  @override
  String? get restorationId => 'app_entry';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_splashFinishedRestoration, 'splash_finished');
    _splashFinished = _splashFinishedRestoration.value;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Start background service
    BackgroundService.startService();
    
    // Initialize FCM after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FCMService.initialize(context);
      _initCallKit();
    });
  }

  void _initCallKit() {
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event?.event == Event.actionCallAccept) {
        print('📞 Call accepted: ${event?.body['id']}');
        final callId = event?.body['id'];
        final callerName = event?.body['nameCaller'] ?? 'Unknown';
        
        // Send WebSocket message to notify caller that call was accepted
        final globalWs = Provider.of<GlobalWebSocketService>(EzeywayApp.navigatorKey.currentContext!, listen: false);
        final acceptMessage = {
          'type': 'call_accepted',
          'call_id': callId,
          'timestamp': DateTime.now().toIso8601String(),
        };
        print('📤 Sending call_accepted message: $acceptMessage');
        globalWs.sendMessage(acceptMessage);
        
        _navigateToCallScreen(callId, callerName);
      } else if (event?.event == Event.actionCallDecline) {
        print('📞 Call declined: ${event?.body['id']}');
        final callId = event?.body['id'];
        
        // Send WebSocket message to notify caller that call was declined
        final globalWs = Provider.of<GlobalWebSocketService>(EzeywayApp.navigatorKey.currentContext!, listen: false);
        final declineMessage = {
          'type': 'call_declined',
          'call_id': callId,
          'timestamp': DateTime.now().toIso8601String(),
        };
        print('📤 Sending call_declined message: $declineMessage');
        globalWs.sendMessage(declineMessage);
        
        FlutterCallkitIncoming.endAllCalls();
      } else if (event?.event == Event.actionCallEnded) {
        print('📞 Call ended: ${event?.body['id']}');
        final callId = event?.body['id'];
        
        // Send WebSocket message to notify caller that call was ended
        final globalWs = Provider.of<GlobalWebSocketService>(EzeywayApp.navigatorKey.currentContext!, listen: false);
        final endMessage = {
          'type': 'call_ended',
          'call_id': callId,
          'timestamp': DateTime.now().toIso8601String(),
        };
        print('📤 Sending call_ended message: $endMessage');
        globalWs.sendMessage(endMessage);
        
        FlutterCallkitIncoming.endAllCalls();
      }
    });
  }

  void _navigateToCallScreen(String callId, String callerName) {
    // Navigate to active call screen
    Navigator.of(EzeywayApp.navigatorKey.currentContext!).push(
      MaterialPageRoute(
        builder: (context) => _ActiveCallScreen(
          callId: callId,
          callerName: callerName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final globalWs = Provider.of<GlobalWebSocketService>(context, listen: false);
    
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground
      print('🔄 App resumed - checking connections');
      
      // Reconnect WebSocket if needed
      if (authService.isLoggedIn && authService.token != null && !globalWs.isConnected) {
        print('🔄 App resumed - reconnecting WebSocket');
        globalWs.connect(authService.token!);
      }
      
      Provider.of<DataPreloaderService>(context, listen: false).preloadAppData();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App going to background - WebSocket will naturally disconnect
      print('🟡 App backgrounded - WebSocket will disconnect naturally');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final authService = Provider.of<AuthService>(context, listen: false);
        if (_splashFinished) {
          if (authService.isLoggedIn) {
            return const MainAppScreen();
          } else {
            return const RoleSelectionScreen();
          }
        } else {
          return SplashScreen(
            onSplashComplete: () {
              setState(() {
                _splashFinished = true;
                _splashFinishedRestoration.value = true;
              });
            },
          );
        }
      },
    );
  }
}

// Simple active call screen
class _ActiveCallScreen extends StatefulWidget {
  final String callId;
  final String callerName;
  
  const _ActiveCallScreen({
    required this.callId,
    required this.callerName,
  });
  
  @override
  State<_ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<_ActiveCallScreen> {
  bool _muted = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF5EA47).withOpacity(0.2),
              ),
              child: const Icon(
                Icons.person,
                size: 60,
                color: Color(0xFFF5EA47),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connected',
              style: TextStyle(
                color: Colors.green,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _muted ? Colors.red : Colors.white,
                  ),
                  child: IconButton(
                    onPressed: () => setState(() => _muted = !_muted),
                    icon: Icon(
                      _muted ? Icons.mic_off : Icons.mic,
                      color: _muted ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                  ),
                  child: IconButton(
                    onPressed: () {
                      FlutterCallkitIncoming.endAllCalls();
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}