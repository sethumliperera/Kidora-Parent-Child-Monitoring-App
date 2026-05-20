import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api.dart';
import '../widgets/modern_background.dart';
import 'screen_time_page.dart';
import 'apps_block_page.dart';
import 'send_reminders_page.dart';
import 'schedules_list_page.dart';
import 'settings_page.dart';
import 'signup_screen.dart';
import 'notification.dart';
import 'create_child_page.dart';
import '../utils/config.dart';
import '../utils/child_identity.dart';
import '../providers/theme_provider.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'fm_service.dart';
import '../services/parent_notification_service.dart';

class ParentDashboard extends StatefulWidget {
  final String token;
  const ParentDashboard({super.key, required this.token});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  List<dynamic> children = [];
  bool isLoading = true;
  int? selectedChildIndex;
  String _todayScreenTimeString = "0m today";
  bool isUsageLoading = false;
  String _appBlockSubtitle = "Manage apps";
  bool _installedAppsSubtitleLoading = false;
  Timer? _presenceTimer;
  Timer? _usageTimer;
  int _unreadNotifications = 0;

  void _onUnreadCountChanged() {
    if (!mounted) return;
    setState(() {
      _unreadNotifications = ParentNotificationService.unreadCount;
    });
  }

  int? get activeChildId => (children.isNotEmpty && selectedChildIndex != null && selectedChildIndex! < children.length)
      ? parseChildDatabaseId(children[selectedChildIndex!]['id'])
      : null;

  @override
  void initState() {
    super.initState();
    ParentNotificationService.addListener(_onUnreadCountChanged);
    _initParentNotifications();
    _fetchChildren();
    _startPresencePolling();
    _startUsagePolling();
  }

  Future<void> _initParentNotifications() async {
    await ParentNotificationService.loadFromPrefs();
    if (mounted) {
      setState(() {
        _unreadNotifications = ParentNotificationService.unreadCount;
      });
    }
    await FcmService.registerParentTokenIfLoggedIn();
    unawaited(
      ParentNotificationService.refreshFromApi().then((_) {
        if (!mounted) return;
        setState(() {
          _unreadNotifications = ParentNotificationService.unreadCount;
        });
      }),
    );
  }

  @override
  void dispose() {
    ParentNotificationService.removeListener(_onUnreadCountChanged);
    _presenceTimer?.cancel();
    _usageTimer?.cancel();
    super.dispose();
  }

  void _startPresencePolling() {
    _presenceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchChildrenSilently();
    });
  }

  void _startUsagePolling() {
    _usageTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      if (selectedChildIndex == null || children.isEmpty) return;
      await _fetchTodayUsage();
    });
  }

  Future<void> _fetchChildrenSilently() async {
    try {
      final data = await ApiService.getChildren();
      if (mounted) {
        setState(() {
          children = data;
        });
      }
      _applyLiveTodayUsageFromChildRow();
    } catch (e) {
      debugPrint("Silent fetch failed: $e");
    }
  }

  void _applyLiveTodayUsageFromChildRow() {
    if (!mounted) return;
    if (selectedChildIndex == null || children.isEmpty || selectedChildIndex! >= children.length) return;
    final child = children[selectedChildIndex!];
    final now = DateTime.now();
    final dayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final rtDay = (child is Map) ? (child['rt_day']?.toString()) : null;
    final rtSecsRaw = (child is Map) ? child['rt_today_seconds'] : null;
    final rtSecs = (rtSecsRaw is int) ? rtSecsRaw : (rtSecsRaw is num ? rtSecsRaw.toInt() : int.tryParse('${rtSecsRaw ?? 0}') ?? 0);

    if (rtDay == dayKey && rtSecs > 0) {
      final h = rtSecs ~/ 3600;
      final m = (rtSecs % 3600) ~/ 60;
      setState(() {
        _todayScreenTimeString = h > 0 ? '${h}h ${m}m today (live)' : '${m}m today (live)';
      });
    }
  }

  Future<void> _fetchChildren() async {
    setState(() => isLoading = true);
    try {
      final data = await ApiService.getChildren();
      setState(() {
        children = data;
        if (children.isEmpty) {
          selectedChildIndex = null;
        } else if (selectedChildIndex == null || selectedChildIndex! >= children.length) {
          selectedChildIndex = 0;
        }
      });
      // Fetch stats for active child
      if (children.isNotEmpty) {
        await _syncInstalledAppsCount();
        await _fetchTodayUsage();
      } else {
        if (mounted) {
          setState(() {
            _appBlockSubtitle = "Manage apps";
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching children: $e");
      if (mounted) {
        String errorMsg = e.toString().replaceFirst("Exception: ", "");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to load children: $errorMsg"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// Loads how many apps were reported by the child device (same API as App Block).
  Future<void> _syncInstalledAppsCount() async {
    if (selectedChildIndex == null ||
        children.isEmpty ||
        selectedChildIndex! >= children.length) {
      if (mounted) {
        setState(() => _appBlockSubtitle = "Manage apps");
      }
      return;
    }
    final id = parseChildDatabaseId(children[selectedChildIndex!]['id']);
    if (id == null) {
      if (mounted) {
        setState(() {
          _appBlockSubtitle = "Manage apps";
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _installedAppsSubtitleLoading = true);
    }
    try {
      final apps = await ApiService.getInstalledApps(id);
      if (mounted) {
        setState(() {
          _installedAppsSubtitleLoading = false;
          final n = apps.length;
          _appBlockSubtitle = n == 0
              ? "Waiting for child device to sync…"
              : "$n apps on device — tap to manage";
        });
      }
    } catch (e) {
      debugPrint("Installed apps summary: $e");
      if (mounted) {
        setState(() {
          _installedAppsSubtitleLoading = false;
          _appBlockSubtitle = "Could not load apps (open App Block to retry)";
        });
      }
    }
  }

  Future<void> _fetchTodayUsage() async {
    if (selectedChildIndex == null || children.isEmpty || selectedChildIndex! >= children.length) return;
    setState(() => isUsageLoading = true);
    try {
      final childId = parseChildDatabaseId(children[selectedChildIndex!]['id']);
      if (childId == null) return;
      final usage = await ApiService.getTodayUsageSummary(childId);
      final totalSeconds = usage['total_screen_time'] ?? 0;

      final h = totalSeconds ~/ 3600;
      final m = (totalSeconds % 3600) ~/ 60;

      setState(() {
        if (h > 0) {
          _todayScreenTimeString = "${h}h ${m}m today";
        } else {
          _todayScreenTimeString = "${m}m today";
        }
      });
    } catch (e) {
      debugPrint("Error fetching today usage: $e");
      setState(() => _todayScreenTimeString = "Error");
    } finally {
      setState(() => isUsageLoading = false);
    }
  }

  void _showSuccessNotification(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  void _showDeleteAccountConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Account?"),
        content: const Text(
          "This action is permanent and will delete all your data, including child profiles. Are you sure?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _handleDeleteAccount();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final error = await AuthService().deleteAccount();

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();

      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Account deleted successfully"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SignUpScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteChild(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Child Profile?"),
        content: const Text(
          "Are you sure you want to remove this child profile?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.deleteChild(id);
        _fetchChildren();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Child profile removed")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to delete: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeChild = (children.isNotEmpty && selectedChildIndex != null && selectedChildIndex! < children.length)
        ? children[selectedChildIndex!]
        : null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu_rounded, size: 28, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          'Kidora Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.w900, 
            color: isDark ? Colors.white : AppTheme.lightTextPrimary, 
            fontSize: 22, 
            letterSpacing: -0.5
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Provider.of<ThemeProvider>(context).isDarkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              size: 24,
              color: isDark ? Colors.white : AppTheme.lightTextPrimary,
            ),
            onPressed: () => Provider.of<ThemeProvider>(context, listen: false).toggleTheme(),
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text(
                _unreadNotifications > 99
                    ? '99+'
                    : '$_unreadNotifications',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              child: Icon(
                Icons.notifications_outlined,
                size: 26,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              ),
            ),
            onPressed: () async {
              int? childDbId;
              if (selectedChildIndex != null &&
                  children.isNotEmpty &&
                  selectedChildIndex! < children.length) {
                childDbId =
                    parseChildDatabaseId(children[selectedChildIndex!]['id']);
              }
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationScreen(childId: childDbId),
                ),
              );
              await ParentNotificationService.refreshFromApi();
              if (mounted) {
                setState(() {
                  _unreadNotifications =
                      ParentNotificationService.unreadCount;
                });
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        width: 280,
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.primaryColor.withValues(alpha: 0.4),
                    theme.primaryColor.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Image.asset(
                        'assets/kidora_logo.jpeg',
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Kidora Family',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'MY CHILDREN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (children.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "No children added yet",
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...children.asMap().entries.map((entry) {
                final idx = entry.key;
                final child = entry.value;
                return _buildDrawerItem(
                  context,
                  child['name'],
                  child['photo_url'],
                  child['gender'],
                  selectedChildIndex == idx,
                  onTap: () async {
                    setState(() {
                      selectedChildIndex = idx;
                    });
                    Navigator.pop(context);
                    await _syncInstalledAppsCount();
                    await _fetchTodayUsage();
                  },
                  onDelete: () {
                    Navigator.pop(context);
                    _deleteChild(child['id']);
                  },
                );
              }),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: Icon(
                Icons.add_circle_outline,
                color: theme.primaryColor,
              ),
              title: const Text(
                'Add Child',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateChildPage()),
                );
                if (result != null && result is Map<String, dynamic>) {
                  setState(() {
                    children.add(result);
                    selectedChildIndex = children.length - 1;
                    isLoading = false; // Ensure loading screen is gone
                  });
                  _showSuccessNotification("Child profile '${result['name']}' created successfully!");
                  await _syncInstalledAppsCount();
                  await _fetchTodayUsage();
                }
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Delete Account',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: _showDeleteAccountConfirmation,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      body: ModernBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _fetchChildren,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back!',
                    style: TextStyle(
                      fontSize: 32, 
                      fontWeight: FontWeight.w900, 
                      color: isDark ? Colors.white : AppTheme.lightTextPrimary, 
                      letterSpacing: -1
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Managing your family safely and easily.',
                    style: TextStyle(
                      fontSize: 15, 
                      color: isDark ? Colors.white70 : AppTheme.lightTextSecondary, 
                      fontWeight: FontWeight.w500
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (children.isEmpty)
                    _buildEmptyState(context)
                  else if (activeChild != null)
                    _buildActiveChildCard(context, activeChild! as Map<String, dynamic>)
                  else
                    const Center(child: CircularProgressIndicator()),

                  const SizedBox(height: 36),
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.w900, 
                      color: isDark ? Colors.white : AppTheme.lightTextPrimary
                    ),
                  ),
                  const SizedBox(height: 20),

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: 0.85,
                    children: [
                       _buildGridCard(
                        context,
                        "Screen Time",
                        isUsageLoading ? "Loading..." : _todayScreenTimeString,
                        "assets/icons/screen_time.png",
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                        onTap: activeChild == null ? null : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ScreenTimePage(child: activeChild! as Map<String, dynamic>),
                          ),
                        ),
                      ),
                      _buildGridCard(
                        context,
                        "App Block",
                        _installedAppsSubtitleLoading ? "Loading…" : _appBlockSubtitle,
                        "assets/icons/app_block.png",
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                        onTap: activeChild == null
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AppsBlockPage(
                                      child: activeChild! as Map<String, dynamic>,
                                    ),
                                  ),
                                );
                                if (mounted) {
                                  await _syncInstalledAppsCount();
                                  await _fetchTodayUsage();
                                }
                              },
                      ),
                      _buildGridCard(
                        context,
                        "Reminders",
                        "Send alerts",
                        "assets/icons/reminders.png",
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                        onTap: activeChild == null
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SendRemindersPage(
                                      child: activeChild! as Map<String, dynamic>,
                                    ),
                                  ),
                                ),
                      ),
                      _buildGridCard(
                        context,
                        "Restrictions",
                        "Set schedules",
                        "assets/icons/restrictions.png",
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                        onTap: activeChild == null ? null : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SchedulesListPage(
                              child: activeChild as Map<String, dynamic>,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? theme.cardColor : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.child_care_rounded,
            size: 64,
            color: theme.primaryColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            "No child profiles found",
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: 18,
              color: isDark ? Colors.white : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Add a child to start managing their activity",
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateChildPage()),
              );
              if (result != null && result is Map<String, dynamic>) {
                setState(() {
                  children.add(result);
                  selectedChildIndex = children.length - 1;
                  isLoading = false;
                });
                _showSuccessNotification("Child profile '${result['name']}' created successfully!");
                _fetchTodayUsage();
              }
            },
            child: const Text("Create Profile"),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context,
    String name,
    String? photoUrl,
    String? gender,
    bool isSelected, {
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: isSelected
            ? theme.primaryColor.withValues(alpha: 0.1)
            : Colors.transparent,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
          backgroundImage: photoUrl != null && photoUrl.isNotEmpty
              ? NetworkImage("${Config.serverUrl}$photoUrl") as ImageProvider
              : AssetImage(
                  gender == 'Girl'
                      ? 'assets/icons/emma.png'
                      : 'assets/icons/alex.png',
                ), // Fallback
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected 
                ? theme.primaryColor 
                : (isDark ? Colors.white : AppTheme.lightTextPrimary),
          ),
        ),
        trailing: isSelected
            ? Icon(
                Icons.check_circle_rounded,
                color: theme.primaryColor,
                size: 20,
              )
            : null,
        onTap: onTap,
        onLongPress: onDelete,
      ),
    );
  }

  Widget _buildActiveChildCard(
    BuildContext context,
    Map<String, dynamic> child,
  ) {
    final photoUrl = child['photo_url'];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine Status
    final status = child['app_status'] ?? 'offline';
    final isActive = status == 'online';
    final isBackground = status == 'background';

    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white,
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                    ? NetworkImage("${Config.serverUrl}$photoUrl") as ImageProvider
                    : AssetImage(
                        child['gender'] == 'Girl'
                            ? 'assets/icons/emma.png'
                            : 'assets/icons/alex.png',
                      ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: isActive ? Colors.greenAccent : (isBackground ? Colors.orangeAccent : Colors.grey),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      child['name'],
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.green.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isActive ? "ONLINE" : (isBackground ? "AWAY" : "OFFLINE"),
                        style: TextStyle(
                          color: isActive ? Colors.greenAccent : (isBackground ? Colors.orangeAccent : Colors.white60),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.circle,
                        color: Color(0xFF69F0AE),
                        size: 10,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "ID: ${child['child_id'] ?? 'N/A'}",
                        style: TextStyle(
                          color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white70),
            onPressed: () => _deleteChild(child['id']),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    String title,
    String subtitle,
    String assetPath,
    Color bgColor, {
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.primaryColor.withValues(alpha: 0.15) : AppTheme.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryColorDark.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Image.asset(
                assetPath,
                width: 38,
                height: 38,
                color: isDark ? Colors.white : AppTheme.primaryColorDark, // Matte Deep Purple Icons in Light Mode
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900, // Extra Bold
                color: isDark ? Colors.white : AppTheme.lightTextPrimary, // Proper Theme Context
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
