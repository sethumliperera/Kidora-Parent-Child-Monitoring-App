import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static final _notificationListeners =
      <void Function(String title, String body)>[];

  /// Per-isolate flag so `init()` is safe from the FCM background isolate too.
  static bool _initialized = false;

  static Future<void> init() async {
    if (kIsWeb) {
      debugPrint("NotificationService: Initialized for Web");
      return;
    }
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
      linux: linuxSettings,
    );

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint("Notification tapped: ${response.payload}");
      },
    );

    // ✅ Request permissions
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    // ✅ Create channel (Android)
    const channel = AndroidNotificationChannel(
      'kidora_channel',
      'Kidora Notifications',
      description: 'Reminders and parental alerts',
      importance: Importance.max,
    );

    await androidPlugin?.createNotificationChannel(channel);

    _initialized = true;
    debugPrint("NotificationService initialized");
  }

  static void addListener(void Function(String title, String body) listener) {
    _notificationListeners.add(listener);
  }

  static void removeListener(
    void Function(String title, String body) listener,
  ) {
    _notificationListeners.remove(listener);
  }

  static Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    debugPrint("Showing notification: $title");

    // Always notify listeners
    for (var listener in _notificationListeners) {
      listener(title, body);
    }

    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
      const androidDetails = AndroidNotificationDetails(
        'kidora_channel',
        'Kidora Notifications',
        channelDescription: 'Reminders and parental alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );

      const iosDetails = DarwinNotificationDetails();

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: iosDetails,
      );

      await _notifications.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: title,
        body: body,
        notificationDetails: details,
      );
    }
  }
}
