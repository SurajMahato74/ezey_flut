// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
    });
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