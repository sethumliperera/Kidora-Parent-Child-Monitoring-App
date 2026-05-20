import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'theme/kidora_scroll_behavior.dart';
import 'providers/theme_provider.dart';
import 'screens/firebase_options.dart';

import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'screens/fm_service.dart';
import 'screens/reminder_alert_screen.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (message.data['type'] == 'parent_alert') {
    final prefs = await SharedPreferences.getInstance();
    final raw = message.data['unread_count']?.toString();
    if (raw != null && int.tryParse(raw) != null) {
      await prefs.setInt('parent_unread_notification_count', int.parse(raw));
    } else {
      final cur = prefs.getInt('parent_unread_notification_count') ?? 0;
      await prefs.setInt('parent_unread_notification_count', cur + 1);
    }
  }

  // Data-only messages do not show a tray icon on Android/iOS. Initialize local
  // notifications in this isolate and display one when the app is backgrounded or killed.
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
  if (message.notification != null) return;

  try {
    await NotificationService.init();
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    final title = data['title']?.toString() ??
        (type == 'parent_alert'
            ? 'Kidora alert'
            : type == 'reminder'
                ? 'Reminder'
                : 'Kidora');
    var body = data['message']?.toString() ??
        (type == 'parent_alert'
            ? 'New alert for your child. Open Kidora to view.'
            : 'You have an update in Kidora.');
    if (body.isEmpty) body = 'Open Kidora to view details.';
    await NotificationService.showNotification(title: title, body: body);
  } catch (e) {
    debugPrint('Background FCM local notification failed: $e');
  }
}

/// Heavy init runs after [runApp] so the first frame (splash) shows immediately
/// instead of a long black / blank window.
Future<void> _bootstrapApp() async {
  try {
    await NotificationService.init();
  } catch (e) {
    debugPrint('NotificationService init: $e');
  }

  NotificationService.addListener((title, body) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
            Text(body, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        backgroundColor: AppTheme.snackBarBackground,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
      ),
    );
  });

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    if (!e.toString().contains('duplicate-app')) {
      debugPrint("Firebase init error: $e");
    }
  }

  FcmService.setOnReminderTap((data) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ReminderAlertScreen(
          title: (data['title'] ?? 'Reminder').toString(),
          message: (data['message'] ?? 'You have a reminder.').toString(),
          priority: (data['priority'] ?? 'normal').toString(),
        ),
      ),
    );
  });
  try {
    await FcmService.initGlobalHandlers();
  } catch (e) {
    debugPrint('FCM initGlobalHandlers: $e');
  }
  try {
    await FcmService.registerParentTokenIfLoggedIn();
  } catch (e) {
    debugPrint('FCM registerParentTokenIfLoggedIn: $e');
  }
  try {
    await FcmService.registerChildTokenIfLinked();
  } catch (e) {
    debugPrint('FCM registerChildTokenIfLinked: $e');
  }

  if (kIsWeb) return;
  try {
    await initializeBackgroundService();
  } catch (e) {
    debugPrint('Background service configure: $e');
  }
  // Intentionally do NOT [startBackgroundService] here: it is started from
  // [SplashScreen] (child) / [ChildDashboard] so parent & landing are not
  // blocked by a foreground service at cold start.
  debugPrint('Bootstrap (notifications, Firebase, FCM, BG config) done');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Critical: [runApp] first frame — never block the UI thread with awaits above.
  unawaited(_bootstrapApp());
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const KidoraApp(),
    ),
  );
}

class KidoraApp extends StatelessWidget {
  const KidoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Kidora',
      scrollBehavior: const KidoraScrollBehavior(),
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const SplashScreen(),
    );
  }
}
