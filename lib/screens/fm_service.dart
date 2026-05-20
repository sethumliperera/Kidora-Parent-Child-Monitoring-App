import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api.dart';
import '../services/notification_service.dart';
import '../services/parent_notification_service.dart';
import '../utils/child_identity.dart';

class FcmService {
  static void Function(Map<String, dynamic> data)? _onReminderTap;

  static void setOnReminderTap(
    void Function(Map<String, dynamic> data) callback,
  ) {
    _onReminderTap = callback;
  }

  static Map<String, dynamic> _messageToReminderData(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    return {
      'title': message.notification?.title ?? data['title'] ?? 'Reminder',
      'message':
          message.notification?.body ?? data['message'] ?? 'You have a reminder.',
      'priority': data['priority'] ?? 'normal',
      'type': data['type'] ?? 'reminder',
      ...data,
    };
  }

  static Future<void> _handleParentAlert(RemoteMessage message) async {
    final data = message.data;
    await ParentNotificationService.applyPushUnreadCount(
      data['unread_count']?.toString(),
    );
    final title =
        message.notification?.title ?? data['title']?.toString() ?? 'Kidora';
    final body = message.notification?.body ??
        data['message']?.toString() ??
        'New alert for your child';
    await NotificationService.showNotification(title: title, body: body);
  }

  static Future<void> initGlobalHandlers() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint("FCM permission status: ${permission.authorizationStatus}");

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (message.data['type'] == 'parent_alert') {
        await _handleParentAlert(message);
        return;
      }

      final title = message.notification?.title ??
          message.data['title']?.toString() ??
          'Reminder';
      final body = message.notification?.body ??
          message.data['message']?.toString() ??
          '';
      await NotificationService.showNotification(title: title, body: body);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      if (message.data['type'] == 'parent_alert') {
        await ParentNotificationService.applyPushUnreadCount(
          message.data['unread_count']?.toString(),
        );
        return;
      }
      final reminderData = _messageToReminderData(message);
      if ((reminderData['type'] ?? '').toString() == 'reminder') {
        _onReminderTap?.call(reminderData);
      }
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      if (initialMessage.data['type'] == 'parent_alert') {
        await ParentNotificationService.applyPushUnreadCount(
          initialMessage.data['unread_count']?.toString(),
        );
      } else {
        final reminderData = _messageToReminderData(initialMessage);
        if ((reminderData['type'] ?? '').toString() == 'reminder') {
          _onReminderTap?.call(reminderData);
        }
      }
    }
  }

  /// Parent phone: save FCM token so pushes work when app is closed.
  static Future<void> registerParentTokenIfLoggedIn() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    final prefs = await SharedPreferences.getInstance();
    final isLinked = prefs.getBool('is_linked') ?? false;
    if (isLinked) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      debugPrint("Parent FCM token is null/empty");
      return;
    }

    try {
      await ApiService.saveParentFcmToken(fcmToken: token);
      debugPrint("Parent FCM token saved");
    } catch (e) {
      debugPrint("Parent FCM token save failed: $e");
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      try {
        await ApiService.saveParentFcmToken(fcmToken: newToken);
      } catch (e) {
        debugPrint("Parent FCM token refresh save failed: $e");
      }
    });
  }

  static Future<void> registerChildTokenIfLinked() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    final prefs = await SharedPreferences.getInstance();
    final childId = loadChildDbIdFromPrefs(prefs);
    final childPublicId =
        prefs.getString('child_public_id') ?? prefs.getString('child_id');
    if (childId == null &&
        (childPublicId == null || childPublicId.trim().isEmpty)) {
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      debugPrint("FCM token is null/empty");
      return;
    }
    debugPrint(
      "FCM token obtained: ${token.substring(0, token.length > 20 ? 20 : token.length)}...",
    );

    try {
      await ApiService.saveChildFcmToken(
        childId: childId,
        childPublicId: childPublicId,
        fcmToken: token,
      );
      debugPrint(
        "FCM token saved for childId=$childId childPublicId=$childPublicId",
      );
    } catch (e) {
      debugPrint("FCM token save failed: $e");
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      try {
        await ApiService.saveChildFcmToken(
          childId: childId,
          childPublicId: childPublicId,
          fcmToken: newToken,
        );
      } catch (e) {
        debugPrint("FCM token refresh save failed: $e");
      }
    });
  }
}
