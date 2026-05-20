import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../utils/app_icon_helper.dart';

class RestrictionsPage extends StatefulWidget {
  final Map<String, dynamic>? child;
  /// When opening from [SchedulesListPage], pre-fills the editor.
  final Map<String, dynamic>? existingSchedule;
  const RestrictionsPage({super.key, this.child, this.existingSchedule});

  @override
  State<RestrictionsPage> createState() => _RestrictionsPageState();
}

class _RestrictionsPageState extends State<RestrictionsPage> {
  bool isScheduleEnabled = true;
  String selectedType = "Study Time";
  final TextEditingController _customNameController = TextEditingController();

  TimeOfDay _startTime = const TimeOfDay(hour: 16, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 19, minute: 0);
  final Set<String> _selectedDays = {"Mon", "Tue", "Wed", "Thu", "Fri"};

  // Installed apps from child's device
  List<Map<String, dynamic>> _installedApps = [];
  bool _appsLoading = false;
  String? _appsError;

  // Packages the parent has chosen to block in this schedule
  Set<String> _blockedPackages = {};

  // For the App Picker Bottom Sheet
  late TextEditingController _searchController;
  Set<String> _tempBlockedPackages = {};
  List<Map<String, dynamic>> _filteredApps = [];

  bool _saving = false;
  bool _loadingExisting = false;
  List<Map<String, dynamic>> _existingRestrictions = [];
  int? _editingRestrictionId;

  int? get _childId {
    final raw = widget.child?['id'];
    if (raw == null) return null;
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _loadInstalledApps();
    _loadExistingRestrictions();
    final preset = widget.existingSchedule;
    if (preset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Same shape as [ApiService.getSchedules] / save payload
        _loadRestrictionIntoEditor(Map<String, dynamic>.from(preset));
      });
    }
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledApps() async {
    final id = _childId;
    if (id == null) return;
    setState(() {
      _appsLoading = true;
      _appsError = null;
    });
    try {
      final apps = await ApiService.getInstalledApps(id);

      if (!mounted) return;
      setState(() {
        _installedApps = apps
            .map<Map<String, dynamic>>(
                (a) => Map<String, dynamic>.from(a as Map))
            .toList();
        // Per-schedule block list only — not the global "always blocked" set
        _blockedPackages = {};
        _appsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _appsError = 'Could not load apps or restrictions: $e';
        _appsLoading = false;
      });
    }
  }

  Future<void> _saveSchedule() async {
    final id = _childId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a child profile first.')),
      );
      return;
    }

    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one day for the schedule.')),
      );
      return;
    }

    if (_blockedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one app to block.')),
      );
      return;
    }

    if (selectedType == "Custom" && _customNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name for custom mode.')),
      );
      return;
    }

    final startMins = _startTime.hour * 60 + _startTime.minute;
    final endMins = _endTime.hour * 60 + _endTime.minute;
    if (startMins == endMins) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start and end time cannot be the same.')),
      );
      return;
    }

    String formatTimeOfDay(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final startText = formatTimeOfDay(_startTime);
    final endText = formatTimeOfDay(_endTime);

    final scheduleName = _scheduleNameForSave();
    if (_isDuplicateSchedule(scheduleName, startText, endText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A schedule with the same name, time window, and days already exists.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'name': scheduleName,
        'start_time': startText,
        'end_time': endText,
        'days': _selectedDays.toList(),
        'blocked_packages': _blockedPackages.toList(),
        'is_enabled': isScheduleEnabled,
      };
      if (_editingRestrictionId != null) {
        payload['id'] = _editingRestrictionId;
      }
      // Persists to app_restriction_schedules — same data the child app enforces
      await ApiService.saveSchedule(id, payload);

      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
        return;
      }

      await _loadExistingRestrictions();
      _resetEditor();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 12),
                Text(_editingRestrictionId == null
                    ? 'Schedule saved successfully!'
                    : 'Schedule updated successfully!'),
              ],
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _scheduleNameForSave() {
    switch (selectedType) {
      case "Sleep Time":
        return "Sleep Time";
      case "Custom":
        final t = _customNameController.text.trim();
        return t.isEmpty ? "Custom schedule" : t;
      case "Study Time":
      default:
        return "Study Time";
    }
  }

  bool _isOvernightWindow() {
    final startMins = _startTime.hour * 60 + _startTime.minute;
    final endMins = _endTime.hour * 60 + _endTime.minute;
    return startMins > endMins;
  }

  Set<String> _normalizedDaySet(Iterable<dynamic> raw) =>
      raw.map((e) => e.toString()).toSet();

  bool _isDuplicateSchedule(
    String scheduleName,
    String startTime,
    String endTime,
  ) {
    final targetDays = _normalizedDaySet(_selectedDays);
    for (final r in _existingRestrictions) {
      final existingId = r['id'] is int ? r['id'] as int? : int.tryParse('${r['id']}');
      if (_editingRestrictionId != null && existingId == _editingRestrictionId) {
        continue;
      }

      final sameName = (r['name'] ?? '').toString() == scheduleName;
      final sameStart = (r['start_time'] ?? '').toString() == startTime;
      final sameEnd = (r['end_time'] ?? '').toString() == endTime;
      final sameDays =
          _normalizedDaySet((r['days'] as List?) ?? const []) == targetDays;

      if (sameName && sameStart && sameEnd && sameDays) return true;
    }
    return false;
  }

  Future<void> _loadExistingRestrictions() async {
    final id = _childId;
    if (id == null) return;
    setState(() => _loadingExisting = true);
    try {
      final list = await ApiService.getSchedules(id);
      if (!mounted) return;
      setState(() {
        _existingRestrictions = list
            .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map),
            )
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load schedules: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  void _resetEditor() {
    setState(() {
      _editingRestrictionId = null;
      selectedType = "Study Time";
      _customNameController.clear();
      _startTime = const TimeOfDay(hour: 16, minute: 0);
      _endTime = const TimeOfDay(hour: 19, minute: 0);
      _selectedDays
        ..clear()
        ..addAll({"Mon", "Tue", "Wed", "Thu", "Fri"});
      _blockedPackages = {};
      isScheduleEnabled = true;
    });
  }

  TimeOfDay _parseTime(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) return const TimeOfDay(hour: 16, minute: 0);
    final h = int.tryParse(parts[0]) ?? 16;
    final m = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  void _loadRestrictionIntoEditor(Map<String, dynamic> r) {
    final name = (r['name'] ?? 'Study Time').toString().trim();
    String uiType = "Study Time";
    String customName = "";
    if (name == "Sleep Time") {
      uiType = "Sleep Time";
    } else if (name == "Study Time") {
      uiType = "Study Time";
    } else {
      uiType = "Custom";
      customName = name;
    }

    final days = (r['days'] is List)
        ? (r['days'] as List).map((e) => e.toString()).toSet()
        : <String>{};
    final raw = r['blocked_packages'] ?? r['blocked_apps'];
    final blocked = (raw is List)
        ? raw.map((e) => e.toString()).toSet()
        : <String>{};

    setState(() {
      _editingRestrictionId = r['id'] is int ? r['id'] as int? : int.tryParse('${r['id']}');
      selectedType = uiType;
      _customNameController.text = customName;
      _startTime = _parseTime((r['start_time'] ?? "16:00").toString());
      _endTime = _parseTime((r['end_time'] ?? "19:00").toString());
      _selectedDays
        ..clear()
        ..addAll(days);
      _blockedPackages = blocked;
      isScheduleEnabled = (r['is_enabled'] == true) ||
          (r['is_enabled'] == 1) ||
          (r['enabled'] == true) ||
          (r['enabled'] == 1);
    });
  }

  Future<void> _toggleRestriction(Map<String, dynamic> r) async {
    final childId = _childId;
    if (childId == null) return;
    final sid = r['id'] is int ? r['id'] as int? : int.tryParse('${r['id']}');
    if (sid == null) return;
    final wasOn = (r['is_enabled'] ?? 1) == 1;
    try {
      final rawBlocked = r['blocked_packages'] ?? r['blocked_apps'] ?? <dynamic>[];
      final days = r['days'] is List
          ? List<dynamic>.from(r['days'] as List)
          : <dynamic>[];
      await ApiService.saveSchedule(childId, {
        'id': sid,
        'name': (r['name'] ?? 'Schedule').toString(),
        'start_time': (r['start_time'] ?? '09:00').toString(),
        'end_time': (r['end_time'] ?? '17:00').toString(),
        'days': days,
        'blocked_packages':
            rawBlocked is List ? List<dynamic>.from(rawBlocked) : <dynamic>[],
        'is_enabled': !wasOn,
      });
      await _loadExistingRestrictions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update schedule: $e')),
      );
    }
  }

  Future<void> _deleteRestriction(Map<String, dynamic> r) async {
    final childId = _childId;
    final sid = r['id'] is int ? r['id'] as int? : int.tryParse('${r['id']}');
    if (childId == null || sid == null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete schedule?'),
            content: const Text('This schedule will be removed from the child device.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await ApiService.deleteSchedule(childId, sid.toString());
      await _loadExistingRestrictions();
      if (_editingRestrictionId == sid) _resetEditor();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete schedule: $e')),
      );
    }
  }

  void _showAppPickerSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Initialize temporary state for the sheet
    _tempBlockedPackages = Set<String>.from(_blockedPackages);
    _searchController.clear();
    _filteredApps = List.from(_installedApps);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          void onSearch(String q) {
            setSheetState(() {
              _filteredApps = _installedApps
                  .where((a) => (a['app_name'] ?? a['package_name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(q.toLowerCase()))
                  .toList();
            });
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollController) => Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Header
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Apps to Block',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: isDark
                                      ? Colors.white
                                      : AppTheme.lightTextPrimary,
                                ),
                              ),
                              Text(
                                '${_filteredApps.length} apps on device',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white60
                                      : AppTheme.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _blockedPackages = Set.from(_tempBlockedPackages));
                            Navigator.pop(ctx);
                          },
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: AppTheme.primaryColorLight,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Search bar
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: onSearch,
                        style: TextStyle(
                          color:
                              isDark ? Colors.white : AppTheme.lightTextPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search apps...',
                          hintStyle: TextStyle(
                            color: isDark
                                ? Colors.white38
                                : AppTheme.lightTextSecondary,
                          ),
                          border: InputBorder.none,
                          icon: Icon(
                            Icons.search_rounded,
                            color: isDark
                                ? Colors.white38
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // App list
                  Expanded(
                    child: _installedApps.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phonelink_off_rounded,
                                    size: 56,
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text(
                                  'No apps found on device',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _filteredApps.length,
                            separatorBuilder: (context, ignored) => Divider(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.grey.withValues(alpha: 0.12),
                              height: 1,
                            ),
                            itemBuilder: (_, i) {
                              final app = _filteredApps[i];
                              final pkg =
                                  (app['package_name'] ?? '').toString();
                              final name = (app['app_name'] ?? pkg).toString();
                              final isChecked = _tempBlockedPackages.contains(pkg);
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                leading: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: AppIconHelper.getAppIcon(pkg, name,
                                      size: 40),
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: isChecked
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isDark
                                        ? Colors.white
                                        : AppTheme.lightTextPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  pkg,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white38
                                        : AppTheme.lightTextSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: isChecked
                                    ? const Icon(Icons.block_rounded,
                                        color: Colors.redAccent, size: 22)
                                    : Icon(
                                        Icons.radio_button_unchecked_rounded,
                                        color: isDark
                                            ? Colors.white30
                                            : Colors.grey[400],
                                        size: 22,
                                      ),
                                onTap: () {
                                  setSheetState(() {
                                    if (isChecked) {
                                      _tempBlockedPackages.remove(pkg);
                                    } else {
                                      _tempBlockedPackages.add(pkg);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  // Bottom actions
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setSheetState(() => _tempBlockedPackages.clear()),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(
                                    color: Colors.redAccent, width: 1.5),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Clear All'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.block_rounded, size: 18),
                              label: Text(
                                  'Block ${_tempBlockedPackages.length} App${_tempBlockedPackages.length == 1 ? '' : 's'}'),
                              onPressed: () {
                                setState(() =>
                                    _blockedPackages = Set.from(_tempBlockedPackages));
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
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
          icon: Icon(Icons.arrow_back_ios_new,
              size: 20,
              color: isDark ? Colors.white : AppTheme.lightTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Schedule Restrictions',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
        ),
      ),
      body: ModernBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSavedModesSection(isDark),
                const SizedBox(height: 24),
                // ── Type tabs ──────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTypeTab("Study Time"),
                      const SizedBox(width: 12),
                      _buildTypeTab("Sleep Time"),
                      const SizedBox(width: 12),
                      _buildTypeTab("Custom"),
                    ],
                  ),
                ),
                if (selectedType == "Custom") ...[
                  const SizedBox(height: 16),
                  _buildCustomNameInput(),
                ],
                const SizedBox(height: 32),

                Text(
                  'Schedule Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Time pickers ───────────────────────────────────────
                GestureDetector(
                  onTap: () => _selectTime(context, true),
                  child: _buildTimeTile(
                      context, "Start time", _startTime.format(context)),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _selectTime(context, false),
                  child: _buildTimeTile(
                      context, "End time", _endTime.format(context)),
                ),
                if (_isOvernightWindow()) ...[
                  const SizedBox(height: 10),
                  Text(
                    "Overnight mode detected: this runs across midnight.",
                    style: TextStyle(
                      color: isDark ? Colors.orangeAccent : Colors.deepOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 32),

                // ── Repeat ─────────────────────────────────────────────
                _buildSectionCard(
                  context,
                  title: "Repeat On",
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                        .map((day) => GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (_selectedDays.contains(day)) {
                                    _selectedDays.remove(day);
                                  } else {
                                    _selectedDays.add(day);
                                  }
                                });
                              },
                              child: _buildDayChip(
                                  day, _selectedDays.contains(day)),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Blocked Apps ───────────────────────────────────────
                _buildBlockedAppsSection(context, isDark),
                const SizedBox(height: 32),

                // ── Enable toggle ──────────────────────────────────────
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Enable Schedule",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark
                                  ? Colors.white
                                  : AppTheme.lightTextPrimary,
                            ),
                          ),
                          Text(
                            "Toggle this restriction on or off",
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : AppTheme.lightTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: isScheduleEnabled,
                        activeThumbColor: AppTheme.primaryColorLight,
                        onChanged: (val) =>
                            setState(() => isScheduleEnabled = val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Save button ────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded, size: 20),
                    label: Text(
                      _saving
                          ? 'Saving…'
                          : (_editingRestrictionId == null
                              ? 'Save Schedule'
                              : 'Update Schedule'),
                    ),
                    onPressed: _saving ? null : _saveSchedule,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                if (_editingRestrictionId != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _resetEditor,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Cancel Editing'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Blocked Apps Section
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildBlockedAppsSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Blocked Apps',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: _appsLoading ? null : _showAppPickerSheet,
              icon: Icon(
                _appsLoading
                    ? Icons.hourglass_empty_rounded
                    : Icons.add_circle_outline,
                size: 18,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              ),
              label: Text(
                _appsLoading ? 'Loading…' : 'Edit Apps',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: _appsLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _appsError != null
                  ? _buildAppsError(isDark)
                  : _blockedPackages.isEmpty
                      ? _buildNoAppsBlocked(isDark)
                      : _buildBlockedAppChips(isDark),
        ),
      ],
    );
  }

  Widget _buildSavedModesSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Saved Modes',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              ),
            ),
            if (_loadingExisting)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: _existingRestrictions.isEmpty
              ? Text(
                  'No saved modes yet. Create your first schedule below.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                  ),
                )
              : Column(
                  children: _existingRestrictions.map((r) {
                    final title = (r['name'] ?? 'Schedule').toString();
                    final start = (r['start_time'] ?? '--:--').toString();
                    final end = (r['end_time'] ?? '--:--').toString();
                    final enabled =
                        (r['is_enabled'] == true) || (r['is_enabled'] == 1);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        title,
                        style: TextStyle(
                          color:
                              isDark ? Colors.white : AppTheme.lightTextPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '$start - $end',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white70
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: enabled ? 'Disable' : 'Enable',
                            icon: Icon(
                              enabled
                                  ? Icons.toggle_on_rounded
                                  : Icons.toggle_off_rounded,
                              color: enabled ? Colors.green : Colors.grey,
                            ),
                            onPressed: () => _toggleRestriction(r),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _loadRestrictionIntoEditor(r),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _deleteRestriction(r),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildAppsError(bool isDark) {
    return Column(
      children: [
        Icon(Icons.cloud_off_rounded,
            color: isDark ? Colors.white38 : Colors.grey[400], size: 36),
        const SizedBox(height: 8),
        Text(
          widget.child == null
              ? 'No child profile selected'
              : 'Could not load apps from device',
          style: TextStyle(
            color: isDark ? Colors.white54 : AppTheme.lightTextSecondary,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (widget.child != null)
          TextButton.icon(
            onPressed: _loadInstalledApps,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
      ],
    );
  }

  Widget _buildNoAppsBlocked(bool isDark) {
    return GestureDetector(
      onTap: _showAppPickerSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(Icons.add_circle_outline_rounded,
                color: AppTheme.primaryColorLight.withValues(alpha: 0.7),
                size: 40),
            const SizedBox(height: 12),
            Text(
              widget.child == null
                  ? 'Open with a child profile to manage apps'
                  : 'Tap "Edit Apps" to block apps\nfrom the child\'s device',
              style: TextStyle(
                color: isDark ? Colors.white54 : AppTheme.lightTextSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedAppChips(bool isDark) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _blockedPackages.map((pkg) {
        // Try to get a friendly name
        final appInfo = _installedApps.firstWhere(
          (a) => a['package_name'] == pkg,
          orElse: () => <String, dynamic>{},
        );
        final name = (appInfo['app_name'] ?? pkg).toString();
        final shortName = name.length > 16 ? '${name.substring(0, 14)}…' : name;

        return Chip(
          avatar: SizedBox(
            width: 24,
            height: 24,
            child: AppIconHelper.getAppIcon(pkg, name, size: 24),
          ),
          label: Text(
            shortName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppTheme.lightTextPrimary,
            ),
          ),
          backgroundColor: isDark
              ? Colors.redAccent.withValues(alpha: 0.15)
              : Colors.redAccent.withValues(alpha: 0.08),
          side: const BorderSide(color: Colors.redAccent, width: 1),
          deleteIcon: const Icon(Icons.close_rounded,
              size: 16, color: Colors.redAccent),
          onDeleted: () => setState(() => _blockedPackages.remove(pkg)),
        );
      }).toList(),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Reusable widgets
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildTypeTab(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isActive = selectedType == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          final previous = selectedType;
          selectedType = title;
          if (previous == title) return;
          if (title == "Study Time") {
            _startTime = const TimeOfDay(hour: 16, minute: 0);
            _endTime = const TimeOfDay(hour: 19, minute: 0);
          } else if (title == "Sleep Time") {
            _startTime = const TimeOfDay(hour: 22, minute: 0);
            _endTime = const TimeOfDay(hour: 7, minute: 0);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF9D4EDD).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppTheme.primaryColorLight : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isActive
                ? Colors.white
                : (isDark ? Colors.white : AppTheme.lightTextPrimary),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeTile(BuildContext context, String label, String time) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.access_time_rounded,
                color: AppTheme.primaryColorLight, size: 22),
          ),
          const SizedBox(width: 16),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(time,
                    style: TextStyle(
                        color:
                            isDark ? Colors.white : AppTheme.lightTextPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: isDark ? Colors.white : AppTheme.lightTextSecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary)),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(padding: const EdgeInsets.all(16), child: child),
      ],
    );
  }

  Widget _buildDayChip(String day, bool checked) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: checked
            ? AppTheme.primaryColor.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: checked ? AppTheme.primaryColorLight : Colors.white),
      ),
      child: Text(
        day,
        style: TextStyle(
          fontSize: 13,
          fontWeight: checked ? FontWeight.bold : FontWeight.normal,
          color: checked
              ? Colors.white
              : (isDark ? Colors.white : AppTheme.lightTextPrimary),
        ),
      ),
    );
  }

  void _selectTime(BuildContext context, bool isStartTime) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    TimeOfDay initialTime = isStartTime ? _startTime : _endTime;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext builderContext) {
        return Container(
          height: 300,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(builderContext),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.grey,
                              fontSize: 16),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(builderContext),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                              color: AppTheme.primaryColorDark,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                        brightness:
                            isDark ? Brightness.dark : Brightness.light),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: false,
                      initialDateTime: DateTime(
                          2000, 1, 1, initialTime.hour, initialTime.minute),
                      onDateTimeChanged: (DateTime dt) {
                        setState(() {
                          if (isStartTime) {
                            _startTime =
                                TimeOfDay(hour: dt.hour, minute: dt.minute);
                          } else {
                            _endTime =
                                TimeOfDay(hour: dt.hour, minute: dt.minute);
                          }
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomNameInput() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _customNameController,
        style:
            TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary),
        decoration: InputDecoration(
          hintText: "Enter custom mode name...",
          hintStyle: TextStyle(
              color: isDark ? Colors.white54 : AppTheme.lightTextSecondary),
          border: InputBorder.none,
          icon: const Icon(Icons.edit_rounded,
              color: AppTheme.primaryColorLight, size: 20),
        ),
      ),
    );
  }
}