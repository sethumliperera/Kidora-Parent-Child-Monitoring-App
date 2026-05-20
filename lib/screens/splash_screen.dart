import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'landing_screen.dart';
import 'child_dashboard.dart';
import 'parent_dashboard.dart';

import '../widgets/modern_background.dart';
import '../theme/app_theme.dart';
import '../services/background_service.dart' show startBackgroundService;
import '../services/socket_service.dart';
import '../services/notification_service.dart' show NotificationService;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _controller.forward();
    _navigateToNext();
  }

  /// Avoid navigating before [Firebase.initializeApp] (runs in [main] bootstrap).
  Future<void> _waitForFirebase() async {
    for (var i = 0; i < 200; i++) {
      if (Firebase.apps.isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    debugPrint('Splash: Firebase not ready in time, continuing');
  }

  Future<void> _navigateToNext() async {
    // Wait for bootstrap + short branded splash; both in parallel.
    await Future.wait<void>([
      _waitForFirebase(),
      Future<void>.delayed(const Duration(milliseconds: 800)),
    ]);

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final isLinked = prefs.getBool('is_linked') ?? false;

    final currentUser = FirebaseAuth.instance.currentUser;

    // Idempotent: safe if [main] bootstrap already initialized.
    await NotificationService.init();
    SocketService().init();

    Widget nextScreen;

    if (isLinked) {
      await startBackgroundService();
      nextScreen = const ChildDashboard();
    } else if (currentUser != null && currentUser.emailVerified) {
      nextScreen = ParentDashboard(token: currentUser.uid);
    } else {
      nextScreen = const LandingScreen();
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final taglineColor =
        brightness == Brightness.dark
            ? AppTheme.darkTextPrimary
            : AppTheme.lightTextPrimary;

    return Scaffold(
      body: ModernBackground(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'logo',
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: theme.primaryColor.withValues(alpha: 0.15),
                                blurRadius: 40,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/kidora_logo.jpeg',
                            width: 120,
                            height: 120,
                          ),
                        ),
                      ),

                      const SizedBox(height: 48),

                      Text(
                        'Smart Parenting Starts Here',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: taglineColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),

                      const SizedBox(height: 80),

                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            brightness == Brightness.dark
                                ? AppTheme.darkPrimaryColor
                                : theme.colorScheme.primary,
                          ),
                        ),
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
  }
}
