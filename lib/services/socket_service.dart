import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:flutter/foundation.dart';
import '../utils/config.dart';
import 'notification_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  socket_io.Socket? _socket;

  final List<Function(Map<String, dynamic>)> _reminderListeners = [];

  // ✅ NEW: notification listeners
  final List<Function(Map<String, dynamic>)> _notificationListeners = [];

  final Set<String> _childRefs = <String>{};

  bool _hasJoinedRoom = false;

  /// Avoid endless Future.delayed chains when the server is unreachable.
  int _rejoinDelayCount = 0;
  static const int _maxRejoinDelays = 60;

  bool _isBackground = false;

  // ================= INIT =================
  void init({bool isBackground = false}) {
    if (_socket != null) return;
    _isBackground = isBackground;

    _socket = socket_io.io(Config.serverUrl, <String, dynamic>{
      'transports': ['polling', 'websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 999,
      'reconnectionDelay': 2000,
    });

    _socket!.onConnect((_) {
      debugPrint(
          '${_isBackground ? "BG" : "UI"} Socket connected: ${_socket!.id}');
      _rejoinDelayCount = 0;
      _hasJoinedRoom = false;
      _rejoinRoom();
    });

    _socket!.onDisconnect((_) {
      debugPrint('${_isBackground ? "BG" : "UI"} Socket disconnected');
      _hasJoinedRoom = false;
    });

    _socket!.onConnectError((err) {
      debugPrint('${_isBackground ? "BG" : "UI"} Connect error: $err');
    });

    _socket!.onError((err) {
      debugPrint('${_isBackground ? "BG" : "UI"} Socket error: $err');
    });

    // ================= REMINDER =================
    _socket!.on('reminder', (data) {
      debugPrint('${_isBackground ? "BG" : "UI"} Reminder received: $data');

      Map<String, dynamic> parsed = {};

      try {
        parsed = Map<String, dynamic>.from(data);
      } catch (e) {
        debugPrint('Reminder parse error: $e');
        return;
      }

      for (var listener in _reminderListeners) {
        listener(parsed);
      }

      if (_isBackground) {
        NotificationService.showNotification(
          title: parsed['title'] ?? 'Reminder',
          body: parsed['message'] ?? '',
        );
      }
    });

    // ================= 🔔 NEW NOTIFICATION =================
    _socket!.on('new_notification', (data) {
      debugPrint(
          '${_isBackground ? "BG" : "UI"} 🔔 Notification received: $data');

      Map<String, dynamic> parsed = {};

      try {
        parsed = Map<String, dynamic>.from(data);
      } catch (e) {
        debugPrint('Notification parse error: $e');
        return;
      }

      // Notify UI listeners
      for (var listener in _notificationListeners) {
        listener(parsed);
      }

      // Show system notification ONLY in background
      if (_isBackground) {
        NotificationService.showNotification(
          title: "New Notification",
          body: parsed['message'] ?? '',
        );
      }
    });
  }

  // ================= JOIN ROOM =================
  void joinChildRoom(String childId) {
    final normalized = childId.trim();
    if (normalized.isEmpty) return;
    _childRefs.add(normalized);
    _hasJoinedRoom = false;

    _rejoinRoom();
  }

  void ensureConnected() {
    if (_socket == null) return;
    if (!_socket!.connected) {
      _socket!.connect();
      return;
    }
    _rejoinRoom();
  }

  void _rejoinRoom() {
    if (_socket == null) return;

    if (!_socket!.connected) {
      if (_rejoinDelayCount < _maxRejoinDelays) {
        _rejoinDelayCount++;
        debugPrint("Socket not connected yet, delaying join... ($_rejoinDelayCount/$_maxRejoinDelays)");
        Future.delayed(const Duration(seconds: 1), _rejoinRoom);
      }
      return;
    }

    _rejoinDelayCount = 0;
    if (_childRefs.isEmpty) return;
    if (_hasJoinedRoom) return;

    for (final childRef in _childRefs) {
      _socket!.emit('join_child', childRef);
      debugPrint('Joined room: child_$childRef');
    }

    _hasJoinedRoom = true;
  }

  // ================= REMINDER LISTENERS =================
  void onReminder(Function(Map<String, dynamic>) callback) {
    if (!_reminderListeners.contains(callback)) {
      _reminderListeners.add(callback);
    }
  }

  void removeReminderListener(Function(Map<String, dynamic>) callback) {
    _reminderListeners.remove(callback);
  }

  // ================= 🔔 NOTIFICATION LISTENERS =================
  void onNotification(Function(Map<String, dynamic>) callback) {
    if (!_notificationListeners.contains(callback)) {
      _notificationListeners.add(callback);
    }
  }

  void removeNotificationListener(Function(Map<String, dynamic>) callback) {
    _notificationListeners.remove(callback);
  }

  // ================= CLEANUP =================
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;

    _reminderListeners.clear();

    // ✅ clear notification listeners too
    _notificationListeners.clear();

    _childRefs.clear();
    _hasJoinedRoom = false;
  }
}
