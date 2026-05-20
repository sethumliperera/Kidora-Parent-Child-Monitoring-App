import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api.dart';
import '../utils/child_identity.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import '../services/parent_notification_service.dart';

class NotificationScreen extends StatefulWidget {
  /// Optional: pass a specific child's DB id. If null, the screen will
  /// attempt to load the selected child from SharedPreferences (parent side).
  final int? childId;
  const NotificationScreen({super.key, this.childId});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Resolve child id: parameter → SharedPreferences
      int? cid = widget.childId;
      if (cid == null) {
        final prefs = await SharedPreferences.getInstance();
        // Try numeric child_db_id first (set after linking or selecting a child)
        cid = loadChildDbIdFromPrefs(prefs);
        // Fallback: "selected_child_id" saved by parent dashboard
        cid ??= prefs.getInt('selected_child_id');
      }

      if (cid == null) {
        setState(() {
          _error = "No child selected. Open the dashboard and select a child first.";
          _isLoading = false;
        });
        return;
      }

      final data = await ApiService.getParentNotifications(cid)
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      setState(() {
        _notifications = data;
        _isLoading = false;
      });

      unawaited(
        ParentNotificationService.markAllRead(childId: cid).catchError(
          (Object e, StackTrace _) {
            debugPrint('markAllRead deferred: $e');
            return null;
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst("Exception: ", "");
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteNotification(int id) async {
    try {
      await ApiService.deleteNotification(id);
    } catch (_) {}
    setState(() {
      _notifications.removeWhere((n) => n['id'] == id);
    });
    await ParentNotificationService.refreshFromApi();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 22,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary),
            onPressed: _load,
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ModernBackground(
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
              : _error != null
                  ? _buildError()
                  : _notifications.isEmpty
                      ? _buildEmpty(isDark)
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            itemCount: _notifications.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) =>
                                _buildCard(_notifications[i], isDark),
                          ),
                        ),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> n, bool isDark) {
    final type = (n['type'] ?? 'general').toString();
    final isNewApp = type == 'new_app_installed';
    final message = n['message'] ?? '';
    final createdAt = n['created_at'] ?? '';
    final id = n['id'];

    final icon = isNewApp
        ? Icons.install_mobile_rounded
        : Icons.notifications_active_rounded;
    final accentColor = isNewApp ? Colors.purpleAccent : AppTheme.primaryColor;
    final badgeLabel = isNewApp ? "New App" : _labelForType(type);

    String timeAgo = '';
    try {
      final dt = DateTime.parse(createdAt);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) {
        timeAgo = 'Just now';
      } else if (diff.inHours < 1) {
        timeAgo = '${diff.inMinutes}m ago';
      } else if (diff.inDays < 1) {
        timeAgo = '${diff.inHours}h ago';
      } else {
        timeAgo = '${diff.inDays}d ago';
      }
    } catch (_) {
      timeAgo = createdAt;
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      color: isNewApp
          ? Colors.purpleAccent.withValues(alpha: 0.07)
          : null,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: accentColor, size: 26),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            timeAgo,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : AppTheme.lightTextSecondary,
            ),
          ),
        ),
        trailing: id != null
            ? IconButton(
                icon: Icon(Icons.close_rounded,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.black26),
                onPressed: () => _deleteNotification(id),
              )
            : null,
      ),
    );
  }

  String _labelForType(String type) {
    switch (type) {
      case 'new_app_installed':
        return 'New App';
      case 'safety_search':
      case 'safety_search_private':
        return 'Safety Alert';
      case 'screen_time':
        return 'Screen Time';
      case 'reminder':
        return 'Reminder';
      default:
        return 'Alert';
    }
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 72,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              "No notifications yet",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "You'll be notified when your child installs new apps or exceeds screen time.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 60, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              _error ?? "Unknown error",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }
}
