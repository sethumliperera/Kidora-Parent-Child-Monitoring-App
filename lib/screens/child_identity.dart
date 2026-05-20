import 'package:shared_preferences/shared_preferences.dart';

/// Parses `children.id` from API JSON (may be int, double, or string).
int? parseChildDatabaseId(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return int.tryParse(raw.toString().trim());
}

/// Reads the numeric DB id stored after linking (prefers int, falls back to string backup).
int? loadChildDbIdFromPrefs(SharedPreferences prefs) {
  final direct = prefs.getInt('id');
  if (direct != null) return direct;

  final selected = prefs.getInt('selected_child_id');
  if (selected != null) return selected;

  final s = prefs.getString('child_db_id');
  if (s != null && s.isNotEmpty) {
    final parsed = int.tryParse(s.trim());
    if (parsed != null) return parsed;
  }

  // Legacy fallback: some installs stored DB id in child_id as a numeric string.
  final legacy = prefs.getString('child_id');
  if (legacy != null && legacy.trim().isNotEmpty) {
    final parsedLegacy = int.tryParse(legacy.trim());
    if (parsedLegacy != null) return parsedLegacy;
  }

  return null;
}