import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

class ParentNotificationService {
  static const _prefsKey = 'parent_unread_notification_count';

  static int _unreadCount = 0;
  static final List<VoidCallback> _listeners = [];

  static int get unreadCount => _unreadCount;

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }

  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _unreadCount = prefs.getInt(_prefsKey) ?? 0;
    _notifyListeners();
  }

  static Future<void> setCount(int count) async {
    _unreadCount = count < 0 ? 0 : count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, _unreadCount);
    _notifyListeners();
  }

  static Future<void> applyPushUnreadCount(String? raw) async {
    if (raw == null || raw.isEmpty) {
      await increment();
      return;
    }
    final parsed = int.tryParse(raw);
    if (parsed != null) {
      await setCount(parsed);
    } else {
      await increment();
    }
  }

  static Future<void> increment() async {
    await setCount(_unreadCount + 1);
  }

  static Future<void> refreshFromApi() async {
    try {
      final count = await ApiService.getParentUnreadCount();
      await setCount(count);
    } catch (e) {
      debugPrint('ParentNotificationService refresh: $e');
    }
  }

  static Future<void> markAllRead({int? childId}) async {
    try {
      final count =
          await ApiService.markParentNotificationsRead(childId: childId);
      await setCount(count);
    } catch (e) {
      debugPrint('ParentNotificationService markAllRead: $e');
      await setCount(0);
    }
  }
}
