import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/usage_service.dart';
import '../services/background_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';
import 'landing_screen.dart';
import 'restriction_screen.dart';
import 'permission_request_screen.dart';
import 'fm_service.dart';
import '../utils/config.dart' show Config;
import '../utils/child_identity.dart';
import '../services/api.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:intl/intl.dart';
import '../utils/app_icon_helper.dart';

class ChildDashboard extends StatefulWidget {
  const ChildDashboard({super.key});

  @override
  State<ChildDashboard> createState() => _ChildDashboardState();
}

class _ChildDashboardState extends State<ChildDashboard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String _childName = "Little One";
  String? _childPhoto;
  String? _childGender;
  bool _hasPermission = true;
  int _streakDays = 5;
  final String _bedtime = "8:30 PM";

  final UsageService _usageService = UsageService();
  List<dynamic> _realUsageList = [];
  /// Merged ms-in-foreground per package (all relevant apps — drives accurate grid labels).
  Map<String, int> _usageMsByPackage = {};
  String? _lastTrackedPkg;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  /// Per-app totals last synced via [sendUsageToBackend]; must reset when the local calendar day changes.
  final Map<String, int> _lastSentUsage = {};
  String? _usageTrackingDate;

  Function(Map<String, dynamic>)? _onReminderFromSocket;
  List<Map<String, dynamic>> _notifications = [];
  bool _isReminderOverlayVisible = false;
  final Set<int> _seenReminderIds = <int>{};

  Timer? _heartbeatTimer;
  Timer? _appUsageTimer;
  Timer? _usageRefreshTimer;
  Timer? _realtimeTimer;
  Timer? _midnightRolloverTimer;
  Timer? _reminderSyncTimer;
  Timer? _remainingTimeTimer;

  bool _loadRealUsageInFlight = false;
  bool _loadRealUsagePending = false;
  bool _syncRemindersInFlight = false;
  bool _syncBlockedInFlight = false;
  DateTime? _lastScreenTimeApiCheck;
  int totalSeconds = 0;
  DateTime _usageOverviewDate = DateTime.now();

  bool _parentPinDialogActive = false;

  bool get _isUsageOverviewToday {
    final n = DateTime.now();
    return _usageOverviewDate.year == n.year &&
        _usageOverviewDate.month == n.month &&
        _usageOverviewDate.day == n.day;
  }

  /// Today: sum only **installed + monitored** apps (same set as the grid). Summing every OS
  /// package inflates vs Samsung “Screen time” (~2×). Other days: API total.
  int get _heroTotalSeconds {
    if (!_isUsageOverviewToday) return totalSeconds;
    return (_trackedUsageMsForTodayHero() / 1000.0).round();
  }

  int _trackedUsageMsForTodayHero() {
    final filteredPkgs = _usageService.filteredApps
        .map((a) => '${a['package_name'] ?? ''}')
        .where((p) => p.isNotEmpty)
        .toSet();
    var totalMs = 0;
    for (final e in _usageMsByPackage.entries) {
      if (filteredPkgs.contains(e.key) ||
          _usageService.isMonitoredApp(e.key, e.key)) {
        totalMs += e.value;
      }
    }
    return totalMs;
  }

  Future<void> syncBlockedAppsFromParent() async {
    if (_syncBlockedInFlight) return;
    _syncBlockedInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final childId = loadChildDbIdFromPrefs(prefs);
      if (childId == null) return;

      final blockedApps = await ApiService.getBlockedApps(childId);

      await platform.invokeMethod('setBlockedApps', blockedApps);
    } catch (e) {
      debugPrint("Sync error: $e");
    } finally {
      _syncBlockedInFlight = false;
    }
  }

  static const platform = MethodChannel('app.channel');

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // FCM: register / refresh token when child is linked (needed for push when app is closed)
    FcmService.registerChildTokenIfLinked();

    // Block list sync — was 5s (too heavy); 30s keeps UI responsive
    _realtimeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncBlockedAppsFromParent();
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _loadChildData();
    _initSocket();
    _loadNotifications();
    _checkPermission();
    _initUsageService();
    _startHeartbeat();
    _startAppTracking();

    _animationController.forward();

    startBackgroundService();

    // Defer heavy native + network work so first frames paint (reduces ANR / “stuck”)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        await syncBlockedAppsFromParent();
        if (!mounted) return;
        await _usageService.syncControls();
        if (!mounted) return;
        await _loadRealUsage();
        if (!mounted) return;
        await fetchScreenTime();
        if (!mounted) return;
        _maybeShowUninstallPinGate();
      });
    });

    _usageRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _loadRealUsage();
      fetchScreenTime();
    });

    _reminderSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _syncRemindersFromApi();
    });

    _scheduleMidnightRollover();
  }

  /// Android usage stats reset at local midnight — clear caches and UI totals for the new calendar day.
  void _ensureUsageTrackingDay() {
    final today = ApiService.localDateString();
    if (_usageTrackingDate != today) {
      _usageTrackingDate = today;
      _lastSentUsage.clear();
      _usageMsByPackage = {};
      _realUsageList = [];
      totalSeconds = 0;
      final n = DateTime.now();
      _usageOverviewDate = DateTime(n.year, n.month, n.day);
      if (mounted) {
        setState(() {});
      }
      debugPrint("📅 Usage sync baseline reset for $today (per-app UI cleared until refresh)");
    }
  }

  void _scheduleMidnightRollover() {
    _midnightRolloverTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final wait = nextMidnight.difference(now);
    _midnightRolloverTimer = Timer(wait, () {
      _ensureUsageTrackingDay();
      if (mounted) {
        _loadRealUsage();
        fetchScreenTime();
      }
      _scheduleMidnightRollover();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _heartbeatTimer?.cancel();
    _appUsageTimer?.cancel();
    _usageRefreshTimer?.cancel();
    _realtimeTimer?.cancel();
    _midnightRolloverTimer?.cancel();
    _reminderSyncTimer?.cancel();
    _remainingTimeTimer?.cancel();
    final r = _onReminderFromSocket;
    if (r != null) SocketService().removeReminderListener(r);
    _sendPresence('offline');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensureUsageTrackingDay();
      _checkPermission(); // 🔥 refresh permission
      _loadRealUsage();
      fetchScreenTime();
      _usageService.syncControls();
      _sendPresence('online');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeShowUninstallPinGate();
      });
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _sendPresence('background');
    } else if (state == AppLifecycleState.detached) {
      _sendPresence('offline');
    }
  }

  // ===== HEARTBEAT =====
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _sendPresence('online');
    });
  }

  Future<void> _sendPresence(String status, [String? appName]) async {
    final prefs = await SharedPreferences.getInstance();
    final id = loadChildDbIdFromPrefs(prefs);
    if (id != null) {
      await ApiService.updatePresence(id, status, appName);
    }
  }

  // ===== APP TRACKING =====
  Future<String> _getCurrentApp() async {
    try {
      return await platform.invokeMethod('getCurrentApp');
    } catch (_) {
      return 'Unknown';
    }
  }

  void _startAppTracking() {
    _appUsageTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final app = await _getCurrentApp();
      if (app != _lastTrackedPkg) {
        _lastTrackedPkg = app;
        await _loadRealUsage();
        if (mounted) fetchScreenTime();
      }
      await _sendPresence('online', app);
    });
  }

  //load real usage
  Future<void> _loadRealUsage() async {
    if (_loadRealUsageInFlight) {
      _loadRealUsagePending = true;
      return;
    }
    _loadRealUsageInFlight = true;
    try {
      _ensureUsageTrackingDay();
      final raw = await platform.invokeMethod('getUsageStats');
      final result = raw is List<dynamic> ? raw : <dynamic>[];

      final merged = <String, int>{};
      for (final app in result) {
        final map = app is Map ? Map<String, dynamic>.from(app) : null;
        if (map == null) continue;
        final pkg = map['packageName']?.toString() ?? '';
        if (pkg.isEmpty || pkg.toLowerCase().contains('kidora')) continue;
        final ms = (map['timeInForeground'] as num?)?.toInt() ?? 0;
        if (ms <= 0) continue;
        merged.update(pkg, (v) => ms > v ? ms : v, ifAbsent: () => ms);
      }

      final filteredPkgs = _usageService.filteredApps
          .map((a) => a['package_name'] ?? '')
          .where((p) => p.isNotEmpty)
          .toSet();

      final forSync = merged.entries
          .where((e) =>
              e.value >= 1000 &&
              (filteredPkgs.contains(e.key) ||
                  _usageService.isMonitoredApp(e.key, e.key)))
          .map((e) => {
                'packageName': e.key,
                'timeInForeground': e.value,
              })
          .toList();

      if (mounted) {
        setState(() {
          _usageMsByPackage = merged;
          _realUsageList = forSync;
        });
      } else {
        _usageMsByPackage = merged;
        _realUsageList = forSync;
      }

      final prefs = await SharedPreferences.getInstance();
      final childIdSave = loadChildDbIdFromPrefs(prefs);
      if (childIdSave != null) {
        final secsByPkg = <String, int>{};
        var totalMs = 0;
        for (final e in merged.entries) {
          if (!filteredPkgs.contains(e.key) &&
              !_usageService.isMonitoredApp(e.key, e.key)) {
            continue;
          }
          totalMs += e.value;
          secsByPkg[e.key] = (e.value / 1000.0).round();
        }
        final totalSec = (totalMs / 1000.0).round();
        await ApiService.saveScreenTimeUsageBatch(
          childId: childIdSave,
          localDate: ApiService.localDateString(),
          totalScreenTimeSeconds: totalSec,
          packageToDurationSeconds: secsByPkg,
        );
      }

      // Sync usage to backend for history tracking
      await sendUsageToBackend();

      // Just check screen time limits locally
      await checkScreenTimeFromBackend();
    } catch (e) {
      debugPrint("Usage error: $e");
    } finally {
      _loadRealUsageInFlight = false;
      if (_loadRealUsagePending) {
        _loadRealUsagePending = false;
        scheduleMicrotask(() {
          if (mounted) _loadRealUsage();
        });
      }
    }
  }

  Future<void> sendUsageToBackend() async {
    _ensureUsageTrackingDay();
    try {
      final prefs = await SharedPreferences.getInstance();
      final childId = loadChildDbIdFromPrefs(prefs);
      if (childId == null) {
        debugPrint("⚠️ SYNC: No child database ID found in prefs. Skipping sync.");
        return;
      }

      debugPrint("🚀 SYNC: Starting sync for child $childId with ${_realUsageList.length} apps");

      var n = 0;
      for (var entry in _realUsageList) {
        final pkg = entry['packageName']?.toString() ?? '';
        final ms = (entry['timeInForeground'] as num?)?.toInt() ?? 0;

        if (ms >= 1000 && pkg.isNotEmpty) {
          final seconds = (ms / 1000).floor();
          final last = _lastSentUsage[pkg] ?? 0;
          final diff = seconds - last;

          if (diff > 0) {
            debugPrint("📡 SYNC: Sending ${diff}s for $pkg");
            await ApiService.trackDetailedUsage(
              childId,
              pkg,
              DateTime.now().subtract(Duration(seconds: diff)),
              DateTime.now(),
              diff,
            );
            // Yield so the UI isolate can process frames (many apps = long sequential awaits).
            if (++n % 3 == 0) await Future<void>.delayed(Duration.zero);
          }

          _lastSentUsage[pkg] = seconds;
        }
      }
      debugPrint("✅ SYNC: All pending usage updates sent.");
    } catch (e) {
      debugPrint("❌ SYNC ERROR: $e");
    }
  }

  Future<void> checkScreenTimeFromBackend() async {
    final now = DateTime.now();
    if (_lastScreenTimeApiCheck != null &&
        now.difference(_lastScreenTimeApiCheck!) < const Duration(seconds: 90)) {
      return;
    }
    _lastScreenTimeApiCheck = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      final childId = loadChildDbIdFromPrefs(prefs);
      if (childId == null) return;

      // Call the checkScreenTime method we added to ApiService
      final data = await ApiService.checkScreenTime(
        childId,
        date: ApiService.localDateString(),
      );

      int total = data['total_usage'] ?? 0;
      int limit = data['limit'] ?? 0;
      String status = data['status'] ?? "OK";

      debugPrint("🔥 ScreenTime: $total/$limit | Status: $status");

      if (Config.enforceDailyScreenTimeLimit && status == "BLOCK") {
        _showRestriction("All Apps", "Screen time limit reached");
      }
    } catch (e) {
      debugPrint("❌ Check ScreenTime error: $e");
    }
    // Limits/schedules: UsageService._syncTimer already calls syncControls (do not stack here).
  }

  Future<void> fetchScreenTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final childId = loadChildDbIdFromPrefs(prefs);
      if (childId == null) return;

      final day = ApiService.localDateString(_usageOverviewDate);
      final usageData = await ApiService.getScreenTimeUsage(childId, date: day);

      if (mounted) {
        setState(() {
          totalSeconds =
              ((usageData['total_screen_time'] as num?) ?? 0).toInt();
        });
      }
    } catch (e) {
      debugPrint("Error fetching screentime: $e");
    }
  }

  void _changeUsageOverviewDay(int delta) {
    final next = _usageOverviewDate.add(Duration(days: delta));
    if (next.isAfter(DateTime.now())) return;
    setState(() {
      _usageOverviewDate = DateTime(next.year, next.month, next.day);
    });
    fetchScreenTime();
  }

  Future<void> _pickUsageOverviewDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _usageOverviewDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _usageOverviewDate = picked);
      fetchScreenTime();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReceivedReminders(int childId) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseUrl}/reminders/received/$childId'),
      );
      if (response.statusCode != 200) return [];
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['data'] is List) {
        return (decoded['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (decoded is List) {
        return decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      debugPrint("fetchReceivedReminders: $e");
    }
    return [];
  }

  Future<void> _initSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final childDbId = loadChildDbIdFromPrefs(prefs);
    final publicChildId = prefs.getString('child_id')?.trim();
    final childId = childDbId?.toString() ?? publicChildId;

    if (childId == null || childId.isEmpty) {
      debugPrint("No childId for socket");
      return;
    }

    SocketService().init();
    // Stock [SocketService] only joins one room; `childId` is already DB or public.
    SocketService().joinChildRoom(childId);

    final previous = _onReminderFromSocket;
    if (previous != null) {
      SocketService().removeReminderListener(previous);
    }

    _onReminderFromSocket = (data) {
      if (!mounted) return;
      setState(() {
        _notifications.insert(0, Map<String, dynamic>.from(data));
      });
      NotificationService.showNotification(
        title: (data['title'] ?? 'Reminder').toString(),
        body: (data['message'] ?? 'New reminder').toString(),
      );
      _showReminderFullScreen(data);
      _loadRealUsage();
    };

    SocketService().onReminder(_onReminderFromSocket!);
  }

  Future<void> _loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final childId = loadChildDbIdFromPrefs(prefs);
      if (childId == null) return;

      final list = await _fetchReceivedReminders(childId);
      if (!mounted) return;
      final dueOnly = list.where(_isReminderDue).toList();
      setState(() => _notifications = dueOnly);
      for (final reminder in dueOnly) {
        final id = reminder['id'];
        if (id is int) _seenReminderIds.add(id);
        if (id is String) {
          final p = int.tryParse(id);
          if (p != null) _seenReminderIds.add(p);
        }
      }
    } catch (e) {
      debugPrint("Failed to load notifications: $e");
    }
  }

  Future<void> _syncRemindersFromApi() async {
    if (!mounted || _syncRemindersInFlight) return;
    _syncRemindersInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final childId = loadChildDbIdFromPrefs(prefs);
      if (childId == null) return;

      final fetched = await _fetchReceivedReminders(childId);
      final dueOnly = fetched.where(_isReminderDue).toList();

      final unseen = <Map<String, dynamic>>[];
      for (final reminder in fetched) {
        final rawId = reminder['id'] ?? reminder['reminder_id'];
        int? reminderId;
        if (rawId is int) reminderId = rawId;
        if (rawId is String) reminderId = int.tryParse(rawId);

        final dueNow = _isReminderDue(reminder);
        if (reminderId != null &&
            !_seenReminderIds.contains(reminderId) &&
            dueNow) {
          _seenReminderIds.add(reminderId);
          unseen.add(reminder);
        }
      }

      if (!mounted) return;
      setState(() => _notifications = dueOnly);

      if (unseen.isNotEmpty) {
        await _showReminderFullScreen(unseen.first);
      }
    } catch (e) {
      debugPrint("Reminder sync failed: $e");
    } finally {
      _syncRemindersInFlight = false;
    }
  }

  bool _isReminderDue(Map<String, dynamic> reminder) {
    final sent = reminder['is_sent'];
    if (sent is num && sent == 1) return true;
    if (sent is String && sent == '1') return true;

    final rawSchedule = reminder['scheduled_at'];
    if (rawSchedule == null) return true;

    final scheduleText = rawSchedule.toString().trim();
    if (scheduleText.isEmpty) return true;

    final parsed = DateTime.tryParse(scheduleText.replaceFirst(' ', 'T'));
    if (parsed == null) return true;

    return !parsed.toUtc().isAfter(DateTime.now().toUtc());
  }

  Future<void> _showReminderFullScreen(Map<String, dynamic> data) async {
    if (!mounted || _isReminderOverlayVisible) return;
    _isReminderOverlayVisible = true;
    try {
      final title = (data['title'] ?? 'Reminder').toString();
      final message = (data['message'] ?? 'New reminder').toString();
      final priority = (data['priority'] ?? 'normal').toString();
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _ChildReminderFullScreen(
            title: title,
            message: message,
            priority: priority,
          ),
        ),
      );
    } finally {
      if (mounted) _isReminderOverlayVisible = false;
    }
  }

  // ===== PERMISSION =====
  Future<void> _checkPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final bool granted =
          await platform.invokeMethod('checkUsagePermission') ?? false;
      if (mounted) {
        setState(() {
          _hasPermission = granted;
          if (!granted) {
            _usageMsByPackage = {};
            _realUsageList = [];
          }
        });
      }
    } catch (e) {
      debugPrint("Error checking permission: $e");
    }
  }


  // ===== OTHER =====
  Future<void> _initUsageService() async {
    await _usageService.init();
    _usageService.onRestrictionTriggered = _showRestriction;
    // Initial sync
    await _updateRemainingTime();
    _remainingTimeTimer?.cancel();
    _remainingTimeTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _updateRemainingTime();
    });
  }

  // Removing naive realtime timer to avoid conflicts with native OS stats
  // void _startRealtimeScreenTime() { ... }

  void _showRestriction(String appName, String reason) {
    if (!mounted) return;

    // Avoid multiple dialogs
    if (Navigator.of(context).canPop() &&
        ModalRoute.of(context)!.settings.name == '/restriction') {
      return;
    }

    // Call native Go Home to minimize current blocked app
    try {
      platform.invokeMethod('goHome');
    } catch (e) {
      debugPrint("Failed to invoke goHome: $e");
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/restriction'),
        builder: (context) =>
            RestrictionScreen(appName: appName, reason: reason),
      ),
    );
  }

  Future<void> _updateRemainingTime() async {
    await _usageService.syncControls();
  }

  void _openUsageSettings() async {
    if (!Platform.isAndroid) return;

    final intent = AndroidIntent(
      action: 'android.settings.USAGE_ACCESS_SETTINGS',
    );

    await intent.launch();

    // 🔥 Wait and re-check permission after returning
    await Future.delayed(const Duration(seconds: 2));
    _checkPermission();
  }

  Future<void> _loadChildData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _childName = prefs.getString('child_name') ?? "Little One";
      _childPhoto = prefs.getString('photo_url');
      _childGender = prefs.getString('child_gender');
      _streakDays = 0;
    });
  }

  Future<String?> _promptParentPinDialog({
    required String title,
    required String subtitle,
  }) async {
    if (_parentPinDialogActive) return null;
    _parentPinDialogActive = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final bodyColor = isDark ? Colors.white70 : AppTheme.lightTextSecondary;
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: titleColor,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle,
                  style: TextStyle(color: bodyColor, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    labelText: '4-digit PIN',
                    border: OutlineInputBorder(),
                  ),
                  style: TextStyle(
                    fontSize: 22,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                  onSubmitted: (v) {
                    if (v.trim().length == 4) {
                      Navigator.pop(dialogContext, v.trim());
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, null),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final p = controller.text.trim();
                  if (p.length == 4) Navigator.pop(dialogContext, p);
                },
                child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
      _parentPinDialogActive = false;
    }
  }

  Future<void> _maybeShowUninstallPinGate() async {
    if (!mounted || kIsWeb || !Platform.isAndroid) return;
    if (_parentPinDialogActive) return;
    bool pending = false;
    try {
      final raw = await platform.invokeMethod('consumeUninstallVerificationFlag');
      pending = raw == true;
    } catch (e) {
      debugPrint('consumeUninstallVerificationFlag: $e');
      return;
    }
    if (!pending || !mounted) return;

    final pin = await _promptParentPinDialog(
      title: 'Parent PIN required',
      subtitle:
          'A parent PIN protects removing Kidora. Enter the 4-digit PIN your parent created when they signed up.',
    );
    if (!mounted || pin == null) return;

    final prefs = await SharedPreferences.getInstance();
    final childId = loadChildDbIdFromPrefs(prefs);
    if (childId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not verify device profile. Try again later.')),
        );
      }
      return;
    }

    try {
      final outcome = await ApiService.verifyUninstallPin(childId: childId, pin: pin);
      if (!mounted) return;
      if (outcome.isValid) {
        await platform.invokeMethod('setUninstallBypassMinutes', {'minutes': 5});
        try {
          await platform.invokeMethod('openAppUninstallSettings');
        } catch (e) {
          debugPrint('openAppUninstallSettings: $e');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN accepted. You have a few minutes to uninstall from system settings if needed.'),
          ),
        );
      } else {
        if (!mounted) return;
        final msg = outcome.message?.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (msg != null && msg.isNotEmpty) ? msg : 'Incorrect PIN. Uninstall is still blocked.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not verify PIN. Check your internet connection and try uninstalling again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final bodyColor = isDark ? Colors.white70 : AppTheme.lightTextSecondary;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Disconnect from parent?',
            style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
          ),
          content: Text(
            'You will need your parent\'s 4-digit PIN. Monitoring stops until this device is linked again.',
            style: TextStyle(color: bodyColor, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
              child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final pin = await _promptParentPinDialog(
      title: 'Enter parent PIN',
      subtitle: 'Ask your parent for the PIN they set when creating their account.',
    );
    if (pin == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final childId = loadChildDbIdFromPrefs(prefs);
    if (childId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing device profile. Cannot disconnect.')),
        );
      }
      return;
    }

    try {
      final outcome = await ApiService.verifyUninstallPin(childId: childId, pin: pin);
      if (!mounted) return;
      if (!outcome.isValid) {
        final msg = outcome.message?.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (msg != null && msg.isNotEmpty) ? msg : 'Incorrect PIN. This device stays linked.',
            ),
          ),
        );
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not verify PIN. Check internet and try again.'),
          ),
        );
      }
      return;
    }

    await _performDisconnect();
  }

  Future<void> _performDisconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // Stop the background monitoring service when user disconnects
    await stopBackgroundService();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LandingScreen()),
        (route) => false,
      );
    }
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    const days = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday",
    ];
    return "${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}";
  }

  Widget _buildNotificationsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_notifications.isEmpty) {
      return const SizedBox.shrink();
    }

    return GlassCard(
      padding: const EdgeInsets.all(24),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                "Recent Reminders",
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._notifications.take(3).map((notif) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    notif['priority'] == 'urgent'
                        ? Icons.error_outline
                        : Icons.info_outline,
                    color: notif['priority'] == 'urgent'
                        ? Colors.redAccent
                        : AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (notif['title'] != null)
                          Text(
                            notif['title'].toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(
                          notif['message']?.toString() ?? 'New notification',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===== BUILD =====
  @override
  Widget build(BuildContext context) {
    if (!_hasPermission && !kIsWeb && Platform.isAndroid) {
      return PermissionRequestScreen(
        onPermissionGranted: () {
          setState(() => _hasPermission = true);
          _loadRealUsage();
          fetchScreenTime();
        },
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: ModernBackground(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: CustomScrollView(
              cacheExtent: 500,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        _buildHeader(),
                        const SizedBox(height: 20),
                        if (!_hasPermission && !kIsWeb && Platform.isAndroid)
                          _buildPermissionBanner(),
                        _buildHeroScreenTimeToday(isDark),
                        const SizedBox(height: 32),
                        _buildStatusRow(),
                        const SizedBox(height: 32),
                        _buildMonitoringStatus(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
                ..._buildAppGridSlivers(isDark),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        const SizedBox(height: 32),
                        _buildNotificationsSection(),
                        const SizedBox(height: 40),
                        Align(
                          alignment: Alignment.center,
                          child: Opacity(
                            opacity: 0.4,
                            child: TextButton.icon(
                              onPressed: _disconnect,
                              icon: const Icon(
                                Icons.link_off,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: const Text(
                                "Device Linked (Tap to disconnect)",
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getFormattedDate(),
              style: TextStyle(
                color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Hi, $_childName!",
              style: TextStyle(
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            backgroundImage: (_childPhoto != null && _childPhoto!.isNotEmpty)
                ? NetworkImage("${Config.serverUrl}$_childPhoto")
                    as ImageProvider
                : AssetImage(
                    _childGender == 'Girl'
                        ? 'assets/icons/emma.png'
                        : 'assets/icons/alex.png',
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Usage Access permission is missing. Monitoring disabled.",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          TextButton(
            onPressed: _openUsageSettings,
            child: const Text(
              "FIX",
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }

  /// Prominent daily total (replaces the old "minutes left" ring).
  Widget _buildHeroScreenTimeToday(bool isDark) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      borderRadius: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.chevron_left,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                ),
                onPressed: () => _changeUsageOverviewDay(-1),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _pickUsageOverviewDay,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isUsageOverviewToday
                                ? "Today"
                                : DateFormat('EEE, MMM d')
                                    .format(_usageOverviewDate),
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : AppTheme.lightTextSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isUsageOverviewToday
                            ? "Screen time today"
                            : "Screen time this day",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : AppTheme.lightTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.chevron_right,
                  color: _isUsageOverviewToday
                      ? (isDark ? Colors.white24 : Colors.grey[400])
                      : (isDark ? Colors.white : AppTheme.lightTextPrimary),
                ),
                onPressed: _isUsageOverviewToday
                    ? null
                    : () => _changeUsageOverviewDay(1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            formatTotalScreenTimeHero(_heroTotalSeconds),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryColor,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatusWidget(
            Icons.local_fire_department_rounded,
            "$_streakDays Day Streak",
            Colors.orangeAccent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatusWidget(
            Icons.bedtime_rounded,
            "Bedtime $_bedtime",
            Colors.indigoAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusWidget(IconData icon, String text, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      borderRadius: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accentColor, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitoringStatus() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.all(24),
      borderRadius: 24,
      child: Row(
        children: [
          Icon(
            _hasPermission ? Icons.security_rounded : Icons.warning_rounded,
            color: _hasPermission ? Colors.greenAccent : Colors.orangeAccent,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasPermission
                      ? "Kidora Protection is ON"
                      : "Action Required",
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _hasPermission
                      ? "Active monitoring and app blocking is enabled."
                      : "Usage Access permission is needed to block apps.",
                  style: TextStyle(
                    color:
                        isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Slivers for the app grid: [SliverGrid] builds tiles lazily so scrolling
  /// stays smooth (replaces shrink-wrapped GridView inside SingleChildScrollView).
  List<Widget> _buildAppGridSlivers(bool isDark) {
    final usageByPkg = _usageMsByPackage;
    final apps = _usageService.filteredApps;
    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.72,
    );

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        sliver: SliverToBoxAdapter(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Installed Apps",
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "${apps.length} apps",
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
      if (apps.isEmpty)
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Text(
                "No apps detected yet.\nOpen a few apps to let Kidora scan them.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white54 : AppTheme.lightTextSecondary,
                ),
              ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          sliver: SliverGrid(
            gridDelegate: gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int i) {
                final app = apps[i];
                final pkg = app['package_name'] ?? '';
                final name = app['app_name'] ?? pkg;
                final ms = usageByPkg[pkg] ?? 0;
                return RepaintBoundary(
                  child: GlassCard(
                    borderRadius: 20,
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : AppTheme.primaryColor
                                    .withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: AppIconHelper.getAppIcon(pkg, name, size: 28),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : AppTheme.lightTextPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatUsageFromMs(ms),
                          style: TextStyle(
                            color: isDark
                                ? Colors.white60
                                : AppTheme.lightTextSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: apps.length,
            ),
          ),
        ),
    ];
  }
}

class _ChildReminderFullScreen extends StatelessWidget {
  const _ChildReminderFullScreen({
    required this.title,
    required this.message,
    required this.priority,
  });

  final String title;
  final String message;
  final String priority;

  @override
  Widget build(BuildContext context) {
    final isUrgent = priority.toLowerCase() == 'urgent';
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isUrgent
                ? [const Color(0xFFB71C1C), const Color(0xFF1A1A1A)]
                : [AppTheme.primaryColor, const Color(0xFF1A1A1A)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isUrgent ? Icons.error_outline : Icons.notifications_active,
                  size: 64,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 48),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

