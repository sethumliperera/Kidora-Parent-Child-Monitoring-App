import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'api.dart';
import '../utils/child_identity.dart';
import '../utils/config.dart';

class UsageService {
  static final UsageService _instance = UsageService._internal();
  factory UsageService() => _instance;
  UsageService._internal();

  static const platform = MethodChannel('app.channel');

  static Future<void> requestUsagePermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await platform.invokeMethod('openUsageSettings');
    } catch (e) {
      debugPrint("UsageService: Failed to open usage settings: $e");
    }
  }

  List<dynamic> _appControls = [];
  List<Map<String, String>> _filteredApps = []; 
  Set<String> _blockedPackages = {}; 
  Timer? _syncTimer;
  Timer? _pollTimer;
  int _syncCycle = 0;
  bool _pollInFlight = false;
  bool _syncTickInFlight = false;
  String? _activeApp;
  String? _activePackage; 
  DateTime? _activeAppStartTime;
  String? _activeSessionDay;
  int? _childId;
  int _globalLimit = 120;
  List<dynamic> _schedules = []; // NEW: Per-app time-based schedules

  static const Map<String, String> _packageMap = {
    'com.google.android.youtube': 'YouTube',
    'com.android.chrome': 'Chrome',
    'com.google.android.googlequicksearchbox': 'Google',
    'com.facebook.katana': 'Facebook',
    'com.facebook.orca': 'Messenger',
    'com.instagram.android': 'Instagram',
    'com.snapchat.android': 'Snapchat',
    'com.zhiliaoapp.musically': 'TikTok',
    'com.ss.android.ugc.trill': 'TikTok',
    'com.android.settings': 'Settings',
    'com.google.android.apps.messaging': 'Messages',
    'com.google.android.contacts': 'Contacts',
    'com.google.android.gm': 'Gmail',
    'com.google.android.apps.photos': 'Photos',
    'com.android.vending': 'Play Store',
  };

  Function(String appName, String reason)? onRestrictionTriggered;

  void debugSetActiveApp(String? appName, [String? packageName]) {
    _handleAppTransition(appName, packageName);
    debugPrint(
        "UsageService [DEBUG]: Active app set to $appName ($packageName)");
  }

  Future<void> _handleAppTransition(String? newApp,
      [String? newPackage]) async {
    if (_activeApp == newApp && _activePackage == newPackage) return;

    if (_activeApp != null && _activeAppStartTime != null && _childId != null) {
      final endTime = DateTime.now();
      final durationSeconds =
          endTime.difference(_activeAppStartTime!).inSeconds;

      if (durationSeconds > 0) {
        try {
          await ApiService.trackDetailedUsage(
            _childId!,
            _activeApp!,
            _activeAppStartTime!,
            endTime,
            durationSeconds,
          );
        } catch (e) {
          debugPrint("UsageService: Failed to log detailed usage: $e");
        }
      }
    }

    _activeApp = newApp;
    _activePackage = newPackage;
    _activeAppStartTime = newApp != null ? DateTime.now() : null;

    if (newApp != null) {
      _checkAndEnforce(newApp, newPackage);
    }
  }

  /// Close the segment that fell on the previous local day; continue the same app with a fresh start time for today.
  Future<void> _flushActiveSessionForDayChange() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    if (_childId != null &&
        _activeApp != null &&
        _activeAppStartTime != null &&
        _activeAppStartTime!.isBefore(startOfToday)) {
      final prevEnd = startOfToday.subtract(const Duration(milliseconds: 1));
      final durationSeconds = prevEnd.difference(_activeAppStartTime!).inSeconds;
      if (durationSeconds > 0) {
        try {
          await ApiService.trackDetailedUsage(
            _childId!,
            _activeApp!,
            _activeAppStartTime!,
            prevEnd,
            durationSeconds,
          );
        } catch (e) {
          debugPrint("UsageService: Failed to log day-boundary usage: $e");
        }
      }
      _activeAppStartTime = now;
    }

    _activeSessionDay = ApiService.localDateString();
  }

  bool get isInitialized => _childId != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _childId = loadChildDbIdFromPrefs(prefs);

    if (_childId != null) {
      await _syncKidoraNativeDeviceContext();
      await syncControls();
      await scanAndUploadApps();
      _startTimers();
    }
  }

  /// Writes child DB id + API base URL into `kidora_prefs` for native code (e.g. accessibility search alerts).
  Future<void> _syncKidoraNativeDeviceContext() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_childId == null) return;
    try {
      await platform.invokeMethod('syncKidoraDeviceContext', <String, dynamic>{
        'child_db_id': _childId,
        'server_base_url': Config.baseUrl,
      });
    } catch (e) {
      debugPrint('UsageService: syncKidoraDeviceContext failed: $e');
    }
  }

  Future<void> _pollDeviceStats() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final bool hasPermission =
          await platform.invokeMethod('checkUsagePermission') ?? false;

      if (!hasPermission) {
        debugPrint("UsageService: Missing Usage Access permission.");
        return;
      }

      final today = ApiService.localDateString();
      if (_activeSessionDay != null && _activeSessionDay != today) {
        await _flushActiveSessionForDayChange();
      }
      _activeSessionDay = today;

      final String packageName =
          await platform.invokeMethod('getCurrentApp') ?? '';
      if (packageName == 'Unknown' || packageName.isEmpty) return;

      String friendlyName = _packageMap[packageName] ?? packageName;

      // Auto-register managed apps if seen for the first time
      final isManaged = _appControls.any((a) => a['app_name'] == friendlyName);
      if (!isManaged && isMonitoredApp(packageName, friendlyName)) {
        try {
          await ApiService.updateAppControl(_childId!, friendlyName,
              timeLimit: 60);
          await syncControls();
        } catch (e) {
          debugPrint("Auto-registration failed: $e");
        }
      }

      await _handleAppTransition(friendlyName, packageName);
      debugPrint("Active app: $friendlyName ($packageName)");
    } catch (e) {
      debugPrint("Polling failed: $e");
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> syncControls() async {
    if (_childId == null) return;

    try {
      // 1️⃣ Refresh native usage first
      await refreshNativeUsage();

      final data = await ApiService.getAppControls(_childId!);
      _appControls = data['controls'] ?? [];
      _blockedPackages = Set<String>.from(data['blocked_packages'] ?? []);

      // 2️⃣ Fetch schedules
      try {
        _schedules = await ApiService.getSchedules(_childId!);
      } catch (e) {
        debugPrint("UsageService: Failed to fetch schedules: $e");
      }

      final prefs = await SharedPreferences.getInstance();

      // 🔥 SYNC GLOBAL LIMIT FROM BACKEND
      if (data.containsKey('screen_time_limit')) {
        _globalLimit = data['screen_time_limit'];
        await prefs.setInt('screen_time_limit', _globalLimit);
      } else {
        _globalLimit = prefs.getInt('screen_time_limit') ?? 120;
      }

      if (_activeApp != null) {
        _checkAndEnforce(_activeApp!, _activePackage);
      }

      // 🔥 ADD THIS PART HERE
      final usageData = await getUsageStatsFromDevice();

      for (var usage in usageData) {
        String package = usage['packageName']?.toString() ?? '';
        if (package.isEmpty) continue;
        final timeMillis = (usage['timeInForeground'] as num?)?.toInt() ?? 0;

        String appName = _packageMap[package] ?? package;
        int minutesUsed = timeMillis ~/ 60000;

        final index = _appControls.indexWhere((a) => a['app_name'] == appName);

        if (index != -1) {
          _appControls[index]['time_used'] = minutesUsed;
        }
      }
    } catch (e) {
      debugPrint("Sync failed: $e");
    }
  }

  void _startTimers() {
    _syncTimer?.cancel();
    _pollTimer?.cancel();

    _syncTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (_syncTickInFlight) return;
      _syncTickInFlight = true;
      try {
        await syncControls();
        _syncCycle++;
        if (_syncCycle % 2 == 0) {
          await scanAndUploadApps();
        }
      } finally {
        _syncTickInFlight = false;
      }
    });
    _pollTimer =
        Timer.periodic(const Duration(seconds: 12), (_) => _pollDeviceStats());
    // Minute-level usage is reported by the Android foreground background isolate to avoid
    // double-counting with this service while still keeping syncControls fresh for limits.
  }

  bool _checkAndEnforce(String appName, [String? packageName]) {
    // 1️⃣ Check Strict Blocks by Package Name
    if (packageName != null && _blockedPackages.contains(packageName)) {
      _triggerBlock(appName, "Blocked (Strict)");
      return false;
    }

    // 1.5 Check Active Schedules
    if (packageName != null) {
      for (var schedule in _schedules) {
        if (_isScheduleActive(schedule)) {
          final List<dynamic> blocked = schedule['blocked_packages'] ?? [];
          if (blocked.contains(packageName)) {
            _triggerBlock(appName, "Schedule: ${schedule['name']}");
            return false;
          }
        }
      }
    }

    if (Config.enforceDailyScreenTimeLimit) {
      int totalUsed = 0;
      for (var app in _appControls) {
        totalUsed += (app['time_used'] ?? 0) as int;
      }
      if (totalUsed >= _globalLimit) {
        // Track only — do not send the child home when the daily screen cap is reached.
        return true;
      }
    }

    final matchingApps =
        _appControls.where((a) => a['app_name'] == appName).toList();

    final app = matchingApps.isNotEmpty ? matchingApps.first : null;

    if (app == null) return true;

    if (app['is_blocked'] == 1) {
      _triggerBlock(appName, "Blocked");
      return false;
    }

    // Per-app time limits from the parent are tracked for reporting only — do not block here.
    return true;
  }

  void _triggerBlock(String appName, String reason) {
    debugPrint("UsageService: TRIGGER BLOCK for $appName due to $reason");
    // Force minimize the blocked app immediately
    platform
        .invokeMethod('goHome')
        .catchError((e) => debugPrint("goHome failed: $e"));
    onRestrictionTriggered?.call(appName, reason);
  }

  List<Map<String, String>> get filteredApps => _filteredApps;

  int getTotalUsedMinutes() {
    return getTotalUsedMinutesToday();
  }

  /// Calculates total screen time used today across all monitored apps
  /// using the native UsageStatsManager data.
  int getTotalUsedMinutesToday() {
    // We'll calculate this directly from the last fetched native stats
    // to ensure it's always "actual".
    return _lastTotalNativeMinutes;
  }

  int _lastTotalNativeMinutes = 0;

  Future<void> refreshNativeUsage() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final usageData = await getUsageStatsFromDevice();
      int totalMs = 0;
      for (var usage in usageData) {
        final pkg = '${usage['packageName'] ?? ''}';
        if (pkg.isEmpty || pkg.toLowerCase().contains('kidora')) continue;

        final inList =
            _filteredApps.any((a) => '${a['package_name'] ?? ''}' == pkg);
        if (!inList && !isMonitoredApp(pkg, pkg)) continue;

        final ms = (usage['timeInForeground'] as num?)?.toInt() ?? 0;
        totalMs += ms;
      }
      _lastTotalNativeMinutes = totalMs ~/ 60000;
    } catch (e) {
      debugPrint("UsageService: Failed to refresh native usage: $e");
    }
  }

  int getTotalRemainingMinutes() {
    return (_globalLimit - getTotalUsedMinutesToday()).clamp(0, _globalLimit);
  }

  int getGlobalLimit() => _globalLimit;

  void stop() {
    _syncTimer?.cancel();
    _pollTimer?.cancel();
  }

  Future<void> scanAndUploadApps() async {
    if (_childId == null) return;

    try {
      debugPrint("UsageService: Scanning installed apps...");
      List<AppInfo> apps = await InstalledApps.getInstalledApps();

      // Deduplicate by package name (split APKs or system duplicates)
      final seen = <String>{};
      List<Map<String, String>> appList = [];
      for (var app in apps) {
        if (seen.contains(app.packageName)) {
          continue; // skip duplicate
        }
        if (_shouldSyncInstalledAppToServer(app.packageName, app.name)) {
          seen.add(app.packageName);
          appList.add({
            "package_name": app.packageName,
            "app_name": app.name,
          });
        }
      }

      if (appList.isEmpty) {
        debugPrint("UsageService: No apps to sync after filtering.");
        return;
      }

      _filteredApps = List<Map<String, String>>.from(appList);
      await ApiService.uploadInstalledAppsWithRetry(_childId!, appList);
      debugPrint(
          "UsageService: Uploaded ${appList.length} apps to backend for parent.");
    } catch (e) {
      debugPrint("UsageService: Failed to scan/upload apps: $e");
    }
  }

  /// Apps sent to the parent for blocking — include all user-relevant packages, not a small allowlist.
  bool _shouldSyncInstalledAppToServer(String pkg, String name) {
    if (pkg.toLowerCase().contains("com.example.kidora_app")) {
      return false;
    }
    return isMonitoredApp(pkg, name);
  }

  /// Returns true if the app should be monitored (shown to parent).
  /// Allows all user apps (including all games and social media),
  /// but explicitly EXCLUDES shopping apps, photos, files, and core system utilities.
  bool isMonitoredApp(String pkg, String name) {
    final p = pkg.toLowerCase();
    final n = name.toLowerCase();

    // 1. Exclude Shopping Apps
    final shopping = [
      "shop",
      "store",
      "amazon",
      "flipkart",
      "ebay",
      "walmart",
      "target",
      "myntra",
      "alibaba",
      "aliexpress",
      "shein",
      "meesho",
      "ajio"
    ];
    // Exception: Allow Play Store so it can be controlled
    if (p == "com.android.vending") {
      return true;
    }

    if (shopping.any((s) => p.contains(s) || n.contains(s))) {
      return false;
    }

    // 2. Exclude Photos and Files Apps
    final mediaAndFiles = [
      "photo",
      "gallery",
      "camera",
      "files",
      "file manager",
      "file explorer",
      "archive",
      "drive",
      "my files",
      "onedrive",
      "dropbox"
    ];
    if (mediaAndFiles.any((m) => p.contains(m) || n.contains(m))) {
      return false;
    }

    // 3. Exclude Core System Utilities / Irrelevant Apps
    final systemUtilities = [
      "settings",
      "calculator",
      "clock",
      "calendar",
      "weather",
      "contacts",
      "phone",
      "dialer",
      "launcher",
      "wallpaper",
      "theme",
      "keyboard",
      "input",
      "system",
      "com.android.",
      "com.samsung.",
      "com.miui.",
      "com.coloros.",
      "com.sec.",
      "com.huawei.",
      "com.google.android.ext.services"
    ];

    // Ensure essential system apps (like YouTube, Chrome) that overlap with system naming aren't blocked
    final essentialSystem = [
      "youtube",
      "com.android.chrome",
      "googlequicksearchbox",
      "gm",
      "maps",
      "com.google.android.youtube",
      "chrome"
    ];

    if (essentialSystem.any((e) => p.contains(e) || n.contains(e))) {
      return true;
    }

    if (systemUtilities.any((u) => p.contains(u) || n.contains(u))) {
      return false;
    }

    // Default to true to allow ALL OTHER apps, ensuring every game & social media app is shown.
    return true;
  }

  Future<List<dynamic>> getUsageStatsFromDevice() async {
    try {
      final result = await platform.invokeMethod('getUsageStats');
      return result;
    } catch (e) {
      debugPrint("UsageService: Error getting usage stats: $e");
      return [];
    }
  }

  List<Map<String, dynamic>> getAppUsageList() {
    List<Map<String, dynamic>> list = [];

    for (var app in _appControls) {
      list.add({
        "name": app['app_name'],
        "time": app['time_used'] ?? 0,
      });
    }

    // Sort highest usage first
    list.sort((a, b) => b['time'].compareTo(a['time']));

    return list;
  }

  bool _isScheduleActive(Map<String, dynamic> s) {
    if ((s['is_enabled'] ?? 1) == 0) return false;

    final now = DateTime.now();
    final dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    final currentDay = dayNames[now.weekday - 1];

    final List<dynamic> days = s['days'] ?? [];
    if (!days.contains(currentDay)) return false;

    final startTimeStr = s['start_time'] ?? "00:00";
    final endTimeStr = s['end_time'] ?? "23:59";

    final start = _parseTime(startTimeStr, now);
    final end = _parseTime(endTimeStr, now);

    // Handle normal range (e.g. 14:00 - 16:00)
    if (start.isBefore(end)) {
      return now.isAfter(start) && now.isBefore(end);
    } 
    // Handle overnight range (e.g. 22:00 - 02:00)
    else {
      return now.isAfter(start) || now.isBefore(end);
    }
  }

  DateTime _parseTime(String t, DateTime reference) {
    try {
      final parts = t.split(':');
      return DateTime(
        reference.year,
        reference.month,
        reference.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    } catch (_) {
      return reference;
    }
  }
}
