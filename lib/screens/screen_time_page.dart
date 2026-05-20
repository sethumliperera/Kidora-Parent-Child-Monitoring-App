import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'weekly_insights.dart';
import '../services/api.dart';
import '../services/usage_service.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import '../utils/app_icon_helper.dart';

class ScreenTimePage extends StatefulWidget {
  final Map<String, dynamic> child;
  const ScreenTimePage({super.key, required this.child});

  @override
  State<ScreenTimePage> createState() => _ScreenTimePageState();
}

class _ScreenTimePageState extends State<ScreenTimePage> {
  bool isLoading = true;
  int totalScreenTimeSeconds = 0;
  List<dynamic> apps = [];
  int screenTimeLimitMinutes = 120;
  bool isUpdatingLimit = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    screenTimeLimitMinutes = widget.child['screen_time_limit'] ?? 120;
    _fetchUsage();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  void _showLimitPicker() {
    int tempLimit = screenTimeLimitMinutes;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Set Daily Limit", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${tempLimit ~/ 60}h ${tempLimit % 60}m",
                  style: const TextStyle(color: AppTheme.primaryColorLight, fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Slider(
                  value: tempLimit.toDouble(),
                  min: 5,
                  max: 480,
                  divisions: 95,
                  onChanged: (val) {
                    setDialogState(() {
                      tempLimit = val.toInt();
                    });
                  },
                ),
                const Text("Select daily screen time allowed", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateLimit(tempLimit);
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  Future<void> _updateLimit(int newLimit) async {
    setState(() => isUpdatingLimit = true);
    try {
      await ApiService.updateScreenTimeLimit(widget.child['id'], newLimit);
      setState(() {
        screenTimeLimitMinutes = newLimit;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Screen time limit updated!"), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update limit: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => isUpdatingLimit = false);
    }
  }

  Future<void> _fetchUsage() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final childId = widget.child['id'];
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // Fetch usage for the selected date from the new endpoint
      final usageData = await ApiService.getScreenTimeUsage(childId, date: dateStr);
      
      final usageApps = usageData['apps'] as List<dynamic>? ?? [];
      
      // Also get installed apps to show app names/icons for zero-usage apps
      List<dynamic> installedApps = [];
      try {
        installedApps = await ApiService.getInstalledApps(childId);
      } catch (_) {}

      final usageService = UsageService();
      final List<Map<String, dynamic>> mergedApps = [];

      // Usage rows use package_name when available (matches installed_apps); app_name is display label.
      final usageMap = <String, int>{};
      for (var u in usageApps) {
        final pkg = (u['package_name'] ?? '').toString();
        final label = (u['app_name'] ?? '').toString();
        final key = pkg.isNotEmpty ? pkg : label;
        final dur = (u['duration'] is int) ? u['duration'] as int : (int.tryParse(u['duration'].toString()) ?? 0);
        if (key.isEmpty) continue;
        usageMap[key] = (usageMap[key] ?? 0) + dur;
      }

      String labelForKey(String key) {
        for (var u in usageApps) {
          final pkg = (u['package_name'] ?? '').toString();
          final label = (u['app_name'] ?? '').toString();
          final k = pkg.isNotEmpty ? pkg : label;
          if (k == key && label.isNotEmpty) return label;
        }
        return _findDisplayName(key, installedApps);
      }

      for (var entry in usageMap.entries) {
        mergedApps.add({
          'app_name': labelForKey(entry.key),
          'package_name': entry.key.contains('.') ? entry.key : _findPackageName(entry.key, installedApps),
          'duration': entry.value,
        });
      }

      // Add installed apps with zero usage (only if viewing today)
      if (_isToday) {
        for (var app in installedApps) {
          final pkg = app['package_name'] ?? '';
          final name = app['app_name'] ?? '';
          if (!usageService.isMonitoredApp(pkg, name)) continue;
          if (usageMap.containsKey(pkg) || usageMap.containsKey(name)) continue;
          
          mergedApps.add({
            'app_name': name,
            'package_name': pkg,
            'duration': 0,
          });
        }
      }

      // Sort by duration descending, then alphabetically
      mergedApps.sort((a, b) {
        int cmp = (b['duration'] as int).compareTo(a['duration'] as int);
        if (cmp == 0) {
          return (a['app_name'] as String).compareTo(b['app_name'] as String);
        }
        return cmp;
      });

      if (!mounted) return;
      final sumFallback = mergedApps.fold<int>(0, (a, m) => a + ((m['duration'] as int?) ?? 0));
      final rawTotal = usageData['total_screen_time'];
      int resolved = (rawTotal is int)
          ? rawTotal
          : (int.tryParse(rawTotal?.toString() ?? '') ?? 0);
      if (resolved == 0 && sumFallback > 0) resolved = sumFallback;
      setState(() {
        totalScreenTimeSeconds = resolved;
        apps = mergedApps;
      });
    } catch (e) {
      debugPrint("Error fetching usage: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _findPackageName(String appName, List<dynamic> installedApps) {
    for (var app in installedApps) {
      if (app['app_name'] == appName) return app['package_name'] ?? '';
    }
    return appName;
  }

  String _findDisplayName(String packageOrLabel, List<dynamic> installedApps) {
    for (var app in installedApps) {
      if (app['package_name'] == packageOrLabel) return app['app_name']?.toString() ?? packageOrLabel;
    }
    return packageOrLabel;
  }

  void _changeDate(int delta) {
    final newDate = _selectedDate.add(Duration(days: delta));
    if (newDate.isAfter(DateTime.now())) return; // Can't go to future
    setState(() => _selectedDate = newDate);
    _fetchUsage();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryColorLight,
              surface: Color(0xFF1A1A2E),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _fetchUsage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final h = totalScreenTimeSeconds ~/ 3600;
    final m = (totalScreenTimeSeconds % 3600) ~/ 60;
    final timeString = h > 0 ? "${h}h ${m}m" : "${m}m";

    final limitSeconds = screenTimeLimitMinutes * 60;
    double progress = limitSeconds > 0 ? (totalScreenTimeSeconds / limitSeconds) : 0;
    if (progress > 1.0) progress = 1.0;

    final dateLabel = _isToday
        ? "Today"
        : DateFormat('EEE, MMM d').format(_selectedDate);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Screen Time', style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : AppTheme.lightTextPrimary)),
      ),
      body: ModernBackground(
        child: isLoading
            ? Center(child: CircularProgressIndicator(color: isDark ? Colors.white : AppTheme.primaryColor))
            : SafeArea(
                child: RefreshIndicator(
                  onRefresh: _fetchUsage,
                  color: AppTheme.primaryColorLight,
                  backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date Navigation
                        GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left_rounded, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
                                onPressed: () => _changeDate(-1),
                              ),
                              GestureDetector(
                                onTap: _pickDate,
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.primaryColorLight),
                                    const SizedBox(width: 8),
                                    Text(
                                      dateLabel,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.chevron_right_rounded,
                                  color: _isToday
                                      ? (isDark ? Colors.white24 : Colors.grey[300])
                                      : (isDark ? Colors.white : AppTheme.lightTextPrimary),
                                ),
                                onPressed: _isToday ? null : () => _changeDate(1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Circular Progress Card
                        GlassCard(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Text(
                                "Total Screen Time",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
                              ),
                              const SizedBox(height: 32),
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    height: 180,
                                    width: 180,
                                    child: CircularProgressIndicator(
                                      value: progress,
                                      strokeWidth: 16,
                                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        progress >= 1.0 ? Colors.redAccent : AppTheme.primaryColorLight,
                                      ),
                                      strokeCap: StrokeCap.round,
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(dateLabel, style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextSecondary, fontSize: 12)),
                                      Text(
                                        timeString,
                                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
                                      ),
                                      GestureDetector(
                                        onTap: _showLimitPicker,
                                        child: Column(
                                          children: [
                                            Text(
                                              "limit ${screenTimeLimitMinutes ~/ 60}h ${screenTimeLimitMinutes % 60}m",
                                              style: TextStyle(
                                                color: isDark ? Colors.white : AppTheme.lightTextSecondary, 
                                                fontSize: 12,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                            if (isUpdatingLimit)
                                              const SizedBox(
                                                height: 10,
                                                width: 10,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'App Usage',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => WeeklyInsightsScreen(child: widget.child)),
                                );
                              },
                              child: const Text('Weekly Insights', style: TextStyle(color: Colors.white70)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        if (apps.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                _isToday
                                    ? "No app usage tracked today."
                                    : "No app usage tracked on ${DateFormat('MMM d').format(_selectedDate)}.",
                                style: TextStyle(color: isDark ? Colors.white54 : AppTheme.lightTextSecondary),
                              ),
                            ),
                          )
                        else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: apps.length,
                          itemBuilder: (ctx, i) {
                            final app = apps[i];
                            final name = app['app_name'] ?? 'Unknown';
                            final pkg = app['package_name'] ?? '';
                            final durSecs = app['duration'] ?? 0;
                            final minutes = (durSecs / 60).round();

                            return GlassCard(
                              borderRadius: 20,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withValues(alpha: 0.05) : AppTheme.primaryColor.withValues(alpha: 0.05),
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
                                      color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "$minutes min",
                                    style: TextStyle(
                                      color: isDark ? Colors.white60 : AppTheme.lightTextSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 48),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => WeeklyInsightsScreen(child: widget.child)),
                            );
                          },
                          child: const Text("View All Insights"),
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
}
