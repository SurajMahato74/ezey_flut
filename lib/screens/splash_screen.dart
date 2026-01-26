// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/data_preloader_service.dart';

class SplashScreen extends StatefulWidget {
  // This callback tells the parent: "Splash is done, go to main app"
  final VoidCallback? onSplashComplete;

  const SplashScreen({super.key, this.onSplashComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  double _progress = 0.0;
  bool _showContent = false;
  String _currentTask = 'Initializing app...';

  late AnimationController _logoController;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoFadeAnimation;

  late AnimationController _textController;

  String _displayedText = '';
  final String _fullText = 'EZEYWAY';
  int _currentCharIndex = 0;
  
  final DataPreloaderService _preloader = DataPreloaderService();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startSplashSequence();
    _setupPreloaderListener();
  }

  void _initializeAnimations() {
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _logoScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );

    _textController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
  }

  void _setupPreloaderListener() {
    _preloader.addListener(() {
      if (mounted) {
        setState(() {
          _progress = _preloader.progress;
          _currentTask = _preloader.currentTask;
        });
      }
    });
  }

  void _startSplashSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _showContent = true);

    _logoController.forward();

    // Typing animation: E → EZ → EZE → EZEY → EZEYWAY
    await Future.delayed(const Duration(milliseconds: 800));
    for (int i = 0; i < _fullText.length; i++) {
      await Future.delayed(const Duration(milliseconds: 110));
      if (!mounted) return;
      setState(() {
        _currentCharIndex = i + 1;
        _displayedText = _fullText.substring(0, _currentCharIndex);
      });
    }

    await Future.delayed(const Duration(milliseconds: 500));

    // Start background data preloading
    _preloader.preloadAppData();

    // Wait for preloading to complete or minimum splash time
    final minimumSplashTime = Future.delayed(const Duration(milliseconds: 1500)); // Reduced from 2000ms
    final preloadingComplete = _waitForPreloadingComplete();
    
    await Future.wait([minimumSplashTime, preloadingComplete]);

    await Future.delayed(const Duration(milliseconds: 200)); // Reduced from 400ms

    // SPLASH IS DONE → Tell parent to go to MainAppScreen
    widget.onSplashComplete?.call();
  }

  Future<void> _waitForPreloadingComplete() async {
    while (_preloader.isPreloading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  void dispose() {
    _preloader.removeListener(() {});
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated EZEYWAY Text
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, (1 - _logoScaleAnimation.value) * -120),
                        child: Transform.scale(
                          scale: _logoScaleAnimation.value,
                          child: Opacity(
                            opacity: _logoFadeAnimation.value,
                            child: AnimatedBuilder(
                              animation: _textController,
                              builder: (context, child) {
                                return ShaderMask(
                                  shaderCallback: (bounds) => const LinearGradient(
                                    colors: [
                                      Colors.white,
                                      AppTheme.primaryColor,
                                      Colors.white,
                                      AppTheme.primaryColor,
                                    ],
                                    stops: [0.0, 0.4, 0.6, 1.0],
                                  ).createShader(bounds),
                                  child: Text(
                                    _displayedText,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 52,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 8,
                                      shadows: [
                                        Shadow(
                                          color: AppTheme.primaryColor.withOpacity(0.6),
                                          blurRadius: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  AnimatedOpacity(
                    opacity: _currentCharIndex >= _fullText.length ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 600),
                    child: Text(
                      'Instant Delivery, Simplified.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[400],
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Progress Bar + Loading Text
            AnimatedOpacity(
              opacity: _showContent ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentTask,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${(_progress * 100).toInt()}%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 7,
                        backgroundColor: const Color(0xFF27272A),
                        valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Version
            AnimatedOpacity(
              opacity: _showContent ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: Text(
                'v1.0.0',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}