import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/config.dart';
import '../utils/child_identity.dart';

// ===================================================================
// PUBLIC: Initialize the background service
// ===================================================================
Future<void> initializeBackgroundService() async {
  if (kIsWeb || !Platform.isAndroid) return;
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'kidora_foreground_channel',
    'Kidora Protection',
    description: 'Kidora is actively monitoring to keep your child safe.',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: 'kidora_foreground_channel',
      initialNotificationTitle: 'Kidora Protection ON',
      initialNotificationContent: 'Monitoring app usage...',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundServiceStart,
      onBackground: iosBackgroundFetch,
    ),
  );
}

Future<void> startBackgroundService() async {
  if (kIsWeb || !Platform.isAndroid) return;
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
  }
}

Future<void> stopBackgroundService() async {
  if (kIsWeb || !Platform.isAndroid) return;
  final service = FlutterBackgroundService();
  service.invoke('stopService');
}

// ===================================================================
@pragma('vm:entry-point')
Future<bool> iosBackgroundFetch(ServiceInstance service) async {
  return true;
}

// ===================================================================
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  const platform = MethodChannel('app.channel');

  int todaySeconds = 0;

  // ✅ NEW: App usage tracking
  Map<String, int> appUsageMap = {};
  int? cachedDailyLimit;
  DateTime? lastLimitFetch;

  // Was 5s: usage stats + HTTP competed with the UI isolate; 15s matches dashboard cadence.
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final childId = loadChildDbIdFromPrefs(prefs);
      final firebaseToken = prefs.getString('firebase_token');
      if (childId == null) {
        debugPrint("⚠️ BG: No child ID yet. Skipping sync.");
        return;
      }
      if (!Platform.isAndroid) return;

      try {
        await platform.invokeMethod('syncKidoraDeviceContext', <String, dynamic>{
          'child_db_id': '$childId',
          'server_base_url': Config.baseUrl,
        });
      } catch (e) {
        debugPrint('BG: syncKidoraDeviceContext failed: $e');
      }

      debugPrint("🚀 BG: Checking usage for child $childId");

      bool hasPermission =
          await platform.invokeMethod('checkUsagePermission') ?? false;
      if (!hasPermission) {
        debugPrint("⚠️ BG: No usage permission.");
        return;
      }

      // 1. System usage: per-app rounded seconds for payload; total = round(sum ms) to avoid inflated totals.
      final List<dynamic> systemStats =
          await platform.invokeMethod('getUsageStats') ?? [];

      var totalMsRaw = 0;
      final Map<String, int> systemUsageMap = {};

      for (var stat in systemStats) {
        final pkg = stat['packageName']?.toString() ?? '';
        if (pkg.isEmpty || pkg.toLowerCase().contains('kidora')) continue;
        final ms = (stat['timeInForeground'] as num?)?.toInt() ?? 0;
        if (ms <= 0) continue;
        totalMsRaw += ms;
        systemUsageMap[pkg] = (ms / 1000.0).round();
      }

      final totalSecondsFromSystem = (totalMsRaw / 1000.0).round();
      todaySeconds = totalSecondsFromSystem;
      appUsageMap = systemUsageMap;
      await prefs.setInt('rt_today_seconds', todaySeconds);

      // current app for presence/logging
      String packageName = await platform.invokeMethod('getCurrentApp') ?? '';
      final friendlyName = _resolveAppName(packageName);

      final screenData = {
        "total": todaySeconds,
        "apps": appUsageMap,
      };

      await _sendScreenTimeData(
        childId,
        screenData,
        firebaseToken,
      );

      // notification
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Kidora Protection ON',
          content: 'Watching: $friendlyName',
        );
      }

      // ================= DAILY LIMIT (optional enforcement) =================
      if (Config.enforceDailyScreenTimeLimit) {
        final headers = {'Content-Type': 'application/json'};
        if (firebaseToken != null) {
          headers['Authorization'] = 'Bearer $firebaseToken';
        }

        if (lastLimitFetch == null ||
            DateTime.now().difference(lastLimitFetch!) >
                const Duration(seconds: 60)) {
          try {
            final limitRes = await http
                .get(
                  Uri.parse('${Config.baseUrl}/children/$childId/limit'),
                  headers: headers,
                )
                .timeout(const Duration(seconds: 5));

            if (limitRes.statusCode == 200) {
              final data = jsonDecode(limitRes.body);
              cachedDailyLimit = (data['daily_limit'] is int)
                  ? data['daily_limit']
                  : (int.tryParse(data['daily_limit']?.toString() ?? '') ??
                      999999);
              lastLimitFetch = DateTime.now();
              debugPrint(
                  "✅ BG: Fetched daily limit selection: $cachedDailyLimit");
            }
          } catch (e) {
            debugPrint("❌ BG: Limit fetch error: $e");
          }
        }

        if (cachedDailyLimit != null) {
          if (todaySeconds >= cachedDailyLimit!) {
            debugPrint(
                "🚫 LIMIT REACHED (${todaySeconds}s >= ${cachedDailyLimit}s) — blocking device");
            try {
              await platform.invokeMethod('goHome');
            } catch (e) {
              debugPrint("Failed to goHome: $e");
            }
          } else if (todaySeconds >= cachedDailyLimit! - 300) {
            debugPrint(
                "⚠️ Warning: Almost reached limit ($todaySeconds / $cachedDailyLimit)");
          }
        }
      }
    } catch (e) {
      debugPrint('BG ERROR: $e');
    }
  });
}

// ===================================================================
// SEND SCREEN TIME
// ===================================================================
Future<void> _sendScreenTimeData(
  int childId,
  Map<String, dynamic> data,
  String? token,
) async {
  try {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    // Per-app keys must stay as package names so they match `installed_apps` and reset per calendar day.
    List<Map<String, dynamic>> usageList = [];
    data['apps'].forEach((package, time) {
      usageList.add({
        "app_name": package,
        "duration": time, // seconds
      });
    });

    final n = DateTime.now();
    final localDay =
        '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

    final body = jsonEncode({
      "child_id": childId,
      "local_date": localDay,
      "total_screen_time": data['total'],
      "usage": usageList,
    });

    debugPrint("🚀 Sending request to /screen-time/save-usage");
    debugPrint("📦 Data: $body");

    final response = await http.post(
      Uri.parse('${Config.baseUrl}/screen-time/save-usage'),
      headers: headers,
      body: body,
    );

    debugPrint("📥 Response: ${response.statusCode} ${response.body}");
  } catch (e) {
    debugPrint("❌ Error sending usage: $e");
  }
}

// ===================================================================
String _resolveAppName(String packageName) {
  const packageMap = {
    'com.google.android.youtube': 'YouTube',
    'com.android.chrome': 'Chrome',
    'com.facebook.katana': 'Facebook',
    'com.instagram.android': 'Instagram',
  };
  return packageMap[packageName] ?? packageName;
}
