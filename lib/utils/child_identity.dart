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
  final s = prefs.getString('child_db_id');
  if (s == null || s.isEmpty) return null;
  return int.tryParse(s.trim());
}

/// Compact labels for per-app screen time (child + parent grids).
String formatUsageFromSeconds(int seconds) {
  if (seconds <= 0) return '0m';
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds / 60.0;
  if (minutes < 60) return '${minutes.toStringAsFixed(1)}m';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return '${h}h ${m}m';
}

String formatUsageFromMs(int ms) {
  return formatUsageFromSeconds((ms / 1000).round());
}

/// Dashboard hero: always hours + minutes (e.g. `2h 15m`, `0h 45m`).
String formatTotalScreenTimeHero(int totalSeconds) {
  if (totalSeconds <= 0) return '0h 0m';
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '0h ${m}m';
}
