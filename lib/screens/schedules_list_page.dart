import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import 'restrictions_page.dart';
import '../utils/child_identity.dart';

class SchedulesListPage extends StatefulWidget {
  final Map<String, dynamic> child;

  const SchedulesListPage({super.key, required this.child});

  @override
  State<SchedulesListPage> createState() => _SchedulesListPageState();
}

class _SchedulesListPageState extends State<SchedulesListPage> {
  List<dynamic> _schedules = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSchedules();
  }

  int? get _childId => parseChildDatabaseId(widget.child['id']);

  Future<void> _fetchSchedules() async {
    final id = _childId;
    if (id == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final schedules = await ApiService.getSchedules(id);
      if (mounted) {
        setState(() {
          _schedules = schedules;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Could not load schedules. Tap to retry.";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleSchedule(Map<String, dynamic> schedule, bool enabled) async {
    final id = _childId;
    if (id == null) return;

    // Optimistic update
    setState(() {
      schedule['is_enabled'] = enabled ? 1 : 0;
    });

    try {
      await ApiService.saveSchedule(id, schedule);
    } catch (e) {
      // Revert on error
      setState(() {
        schedule['is_enabled'] = enabled ? 0 : 1;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update schedule: $e")),
        );
      }
    }
  }

  Future<void> _deleteSchedule(String scheduleId) async {
    final id = _childId;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Schedule?"),
        content: const Text("This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.deleteSchedule(id, scheduleId);
        _fetchSchedules();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to delete: $e")),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'App Restrictions',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
            onPressed: _fetchSchedules,
          ),
        ],
      ),
      body: ModernBackground(
        child: SafeArea(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColorLight,
                  ),
                )
              : _error != null
                  ? Center(
                      child: GestureDetector(
                        onTap: _fetchSchedules,
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                          child: Text(
                            "Schedules",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          child: Text(
                            "Apps will be blocked during these periods.",
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _schedules.isEmpty
                              ? _buildEmptyState()
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                                  itemCount: _schedules.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                                  itemBuilder: (ctx, index) {
                                    final schedule = _schedules[index] as Map<String, dynamic>;
                                    return _buildScheduleCard(schedule);
                                  },
                                ),
                        ),
                      ],
                    ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text("Add Schedule"),
        backgroundColor: AppTheme.primaryColorLight,
      ),
    );
  }

  Widget _buildEmptyState() {
    final brightness = Theme.of(context).brightness;
    final muted = AppTheme.textOnBackdropSecondary(brightness);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 64,
            color: muted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 16),
          Text(
            'No schedules yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textOnBackdropPrimary(brightness),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to create one.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: muted,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> schedule) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isEnabled = schedule['is_enabled'] == true ||
        schedule['is_enabled'] == 1;
    final String name = schedule['name'] ?? "Restriction";
    final String timeRange = "${schedule['start_time']} - ${schedule['end_time']}";
    final List<dynamic> days = schedule['days'] ?? [];
    final String daysStr = days.join(", ");

    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _openEditor(schedule),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeRange,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryColorLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isEnabled,
                    onChanged: (val) => _toggleSchedule(schedule, val),
                    activeThumbColor: AppTheme.primaryColorLight,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.repeat_rounded, size: 14, color: isDark ? Colors.white38 : Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      daysStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.white38),
                    onPressed: () => _deleteSchedule(schedule['id'].toString()),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditor([Map<String, dynamic>? schedule]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RestrictionsPage(
          child: widget.child,
          existingSchedule: schedule,
        ),
      ),
    );

    if (result == true && mounted) {
      _fetchSchedules();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Schedule saved"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
