import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../utils/child_identity.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';

class AppsBlockPage extends StatefulWidget {
  final Map<String, dynamic> child;
  const AppsBlockPage({super.key, required this.child});

  @override
  State<AppsBlockPage> createState() => _AppsBlockPageState();
}

class _AppsBlockPageState extends State<AppsBlockPage> {
  List<dynamic> _apps = [];
  List<dynamic> _filtered = [];
  bool isLoading = true;
  String _search = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchInstalledApps();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchInstalledApps(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  int? _childDbId() => parseChildDatabaseId(widget.child['id']);

  Future<void> _fetchInstalledApps({bool silent = false}) async {
    final id = _childDbId();
    if (id == null) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invalid child profile — pull to refresh the dashboard."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }
    if (!silent) setState(() => isLoading = true);
    try {
      final data = await ApiService.getInstalledApps(id);
      if (mounted) {
        setState(() {
          _apps = data;
          _applySearch(_search);
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching installed apps: $e");
      if (mounted) {
        setState(() => isLoading = false);
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.toString().replaceFirst('Exception: ', ''),
                maxLines: 3,
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  void _applySearch(String query) {
    _search = query;
    // All apps from the backend are already filtered to social/gaming/entertainment.
    // No client-side secondary filter needed — just apply the search query.
    _filtered = _apps.where((a) {
      final name = (a['app_name'] ?? '').toString();
      return query.isEmpty ||
          name.toLowerCase().contains(query.toLowerCase());
    }).toList();

    // Sort: Blocked apps first, then alphabetically
    _filtered.sort((a, b) {
        if ((a['is_blocked'] == 1) && (b['is_blocked'] != 1)) return -1;
        if ((a['is_blocked'] != 1) && (b['is_blocked'] == 1)) return 1;
        return (a['app_name'] ?? '').toString().toLowerCase().compareTo((b['app_name'] ?? '').toString().toLowerCase());
    });
  }

  Future<void> _toggleBlock(Map<String, dynamic> app, bool block) async {
    final childId = _childDbId();
    if (childId == null) return;
    final packageName = app['package_name'];

    setState(() => app['is_blocked'] = block ? 1 : 0);

    try {
      if (block) {
        await ApiService.blockApp(childId, packageName);
      } else {
        await ApiService.unblockApp(childId, packageName);
      }
    } catch (e) {
      setState(() => app['is_blocked'] = block ? 0 : 1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed: ${e.toString().replaceFirst('Exception: ', '')}"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blockedCount = _apps.where((a) => a['is_blocked'] == 1).length;
    final total = _apps.length;
    final summaryColor = isDark ? Colors.white70 : AppTheme.lightTextSecondary;
    final refreshIconColor =
        isDark ? Colors.white : AppTheme.primaryColorDark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App Control', style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : AppTheme.lightTextPrimary)),
            Text(
              total == 0
                  ? 'No apps synced yet'
                  : '$blockedCount of $total apps blocked',
              style: TextStyle(fontSize: 12, color: summaryColor),
            )
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: refreshIconColor),
            onPressed: _fetchInstalledApps,
          ),
        ],
      ),
      body: ModernBackground(
        child: Column(
          children: [
            const SizedBox(height: kToolbarHeight + 20),
            if (!isLoading && _apps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Material(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 22,
                          color: isDark ? AppTheme.darkPrimaryColor : AppTheme.primaryColorDark,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Blocking summary',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: isDark ? Colors.white60 : AppTheme.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$blockedCount of $total apps are blocked',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: blockedCount > 0
                                ? (isDark
                                    ? Colors.redAccent.withValues(alpha: 0.25)
                                    : Colors.red.shade100)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.white),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: blockedCount > 0
                                  ? Colors.redAccent.withValues(alpha: isDark ? 0.6 : 0.45)
                                  : (isDark ? Colors.white24 : AppTheme.lightBorder),
                            ),
                          ),
                          child: Text(
                            '$blockedCount / $total',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextField(
                onChanged: (q) => setState(() => _applySearch(q)),
                style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: "Search apps...",
                  hintStyle: TextStyle(color: isDark ? Colors.white70 : AppTheme.lightTextSecondary),
                  prefixIcon: Icon(Icons.search_rounded, color: isDark ? Colors.white70 : AppTheme.lightTextSecondary),
                  filled: true,
                  fillColor: isDark ? Colors.white.withValues(alpha: 0.1) : AppTheme.primaryColor.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
              ),
            ),

            if (!isLoading && _apps.isEmpty)
              Expanded(child: _buildEmptyState())
            else if (isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)))
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final app = _filtered[index] as Map<String, dynamic>;
                    return _buildAppCard(app);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phonelink_off_rounded, size: 64, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
              const SizedBox(height: 16),
              Text(
                "No apps detected yet",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                "The child device needs to be open\nfor apps to appear here.",
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white70 : AppTheme.lightTextSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchInstalledApps,
                icon: const Icon(Icons.refresh),
                label: const Text("Refresh"),
              ),
            ],
          ),
        ),
      );
  }

  Widget _buildAppCard(Map<String, dynamic> app) {
    final name = app['app_name'] ?? 'Unknown App';
    final isBlocked = app['is_blocked'] == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // GlassCard applies a strong alpha on `color`; avoid passing redAccent or text washes out.
    final titleColor = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final blockedLabelColor =
        isDark ? const Color(0xFFFFCDD2) : const Color(0xFFB71C1C);
    final allowedLabelColor =
        isDark ? const Color(0xFF69F0AE) : const Color(0xFF1B5E20);
    final rowTint = isBlocked
        ? (isDark
            ? const Color(0xFF3E1818).withValues(alpha: 0.55)
            : const Color(0xFFFFEBEE).withValues(alpha: 0.95))
        : null;
    final rowBorder = isBlocked
        ? Border.all(
            color: isDark
                ? Colors.redAccent.withValues(alpha: 0.65)
                : Colors.red.shade400,
            width: 1.5,
          )
        : null;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          decoration: BoxDecoration(
            color: rowTint,
            border: rowBorder,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isBlocked
                    ? (isDark
                        ? Colors.redAccent.withValues(alpha: 0.2)
                        : Colors.red.shade100)
                    : AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _getIconForApp(name),
                color: isBlocked
                    ? (isDark ? const Color(0xFFFF8A80) : Colors.red.shade700)
                    : AppTheme.primaryColorDark,
                size: 26,
              ),
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold, color: titleColor),
            ),
            subtitle: Text(
              isBlocked ? 'Blocked' : 'Allowed',
              style: TextStyle(
                fontSize: 12,
                color: isBlocked ? blockedLabelColor : allowedLabelColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: Switch(
              value: isBlocked,
              activeThumbColor: Colors.redAccent,
              activeTrackColor: Colors.redAccent.withValues(alpha: 0.35),
              onChanged: (val) => _toggleBlock(app, val),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconForApp(String name) {
    final n = name.toLowerCase();
    if (n.contains('youtube') || n.contains('video')) return Icons.play_circle_fill_rounded;
    if (n.contains('chrome') || n.contains('browser')) return Icons.language_rounded;
    if (n.contains('facebook') || n.contains('meta')) return Icons.facebook_rounded;
    if (n.contains('instagram')) return Icons.camera_alt_rounded;
    if (n.contains('snap')) return Icons.camera_rounded;
    if (n.contains('tiktok') || n.contains('tik')) return Icons.music_note_rounded;
    if (n.contains('game') || n.contains('play')) return Icons.videogame_asset_rounded;
    if (n.contains('whatsapp') || n.contains('message')) return Icons.chat_bubble_rounded;
    if (n.contains('gmail') || n.contains('mail')) return Icons.email_rounded;
    if (n.contains('maps') || n.contains('navigation')) return Icons.map_rounded;
    if (n.contains('shop') || n.contains('store')) return Icons.shopping_bag_rounded;
    if (n.contains('music') || n.contains('spotify')) return Icons.headphones_rounded;
    return Icons.apps_rounded;
  }
}
