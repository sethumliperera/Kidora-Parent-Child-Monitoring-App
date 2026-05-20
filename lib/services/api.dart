import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import '../utils/config.dart';

class ParentPinVerificationResult {
  final bool isValid;
  final String? message;

  const ParentPinVerificationResult({
    required this.isValid,
    this.message,
  });
}

class ApiService {
  static const String baseUrl = Config.baseUrl;

  /// Device-local calendar day (YYYY-MM-DD), aligned with Android usage stats midnight.
  static String localDateString([DateTime? from]) {
    final n = from ?? DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String _toMySqlDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }

  // ===============================
  // GET AUTH TOKEN
  // ===============================
  static Future<String?> _getToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken(forceRefresh);
  }

  // ===============================
  //  GET FIREBASE UID
  // ===============================
  static String? _getFirebaseUid() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  // ===============================
  //  GET USER EMAIL
  // ===============================
  static String? _getEmail() {
    return FirebaseAuth.instance.currentUser?.email;
  }

  // ===============================
  //  UPLOAD PHOTO
  // ===============================
  static Future<String?> uploadPhoto(File photo) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    var request = http.MultipartRequest(
      'POST',
      Uri.parse("$baseUrl/children/upload-photo"),
    );

    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(
      await http.MultipartFile.fromPath(
        'photo',
        photo.path,
        contentType: MediaType('image', 'jpeg'),
      ),
    );

    var response = await request.send();

    if (response.statusCode == 200) {
      var responseData = await response.stream.bytesToString();
      return jsonDecode(responseData)['photo_url'];
    }

    return null;
  }

  // ===============================
  // ADD CHILD (FIXED)
  // ===============================
  static Future<Map<String, dynamic>> addChild({
    required String name,
    required int age,
    String? gender,
    String? interests,
    String? photoUrl,
  }) async {
    final token = await _getToken();
    final firebaseUid = _getFirebaseUid();
    final email = _getEmail();

    if (token == null || firebaseUid == null || email == null) {
      throw Exception("User not logged in");
    }

    final body = {
      "firebase_uid": firebaseUid,
      "name": name,
      "age": age,
      "email": FirebaseAuth.instance.currentUser?.email,
    };

    if (gender != null) body["gender"] = gender;
    if (interests != null) body["interests"] = interests;
    if (photoUrl != null) body["photo_url"] = photoUrl;

    final response = await http.post(
      Uri.parse("$baseUrl/children/add"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to add child: ${response.body}");
    }

    return jsonDecode(response.body);
  }

  // ===============================
  //  GET CHILDREN
  // ==============================
  static Future<List<dynamic>> getChildren() async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.get(
      Uri.parse("$baseUrl/children"),
      headers: {"Authorization": "Bearer $token"},
    );

    debugPrint("GET CHILDREN RESPONSE:");
    debugPrint(response.body); // ADD THIS

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch children");
    }

    return jsonDecode(response.body);
  }

  // ===============================
  // DELETE CHILD
  // ===============================
  static Future<void> deleteChild(int id) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.delete(
      Uri.parse("$baseUrl/children/$id"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to delete child");
    }
  }

  // ===============================
  //  LINK CHILD
  // ===============================
  static Future<Map<String, dynamic>> linkChild(String code) async {
    final response = await http.post(
      Uri.parse("$baseUrl/children/link"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"linking_code": code}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? "Linking failed");
    }

    return jsonDecode(response.body);
  }

  /// Server compares the entered PIN with the parent account's stored hash (signup / Settings).
  static Future<ParentPinVerificationResult> verifyUninstallPin({
    int? childId,
    String? childPublicId,
    required String pin,
  }) async {
    final payload = <String, dynamic>{"pin": pin.trim()};
    if (childId != null) payload["child_id"] = childId;
    if (childPublicId != null && childPublicId.trim().isNotEmpty) {
      payload["child_public_id"] = childPublicId.trim();
    }

    final response = await http.post(
      Uri.parse("$baseUrl/children/verify-uninstall-pin"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    Map<String, dynamic>? body;
    try {
      if (response.body.isNotEmpty) {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}

    if (response.statusCode == 200) {
      final valid = body?["valid"] == true;
      return ParentPinVerificationResult(
        isValid: valid,
        message: body?["message"]?.toString(),
      );
    }
    throw Exception(
      body?["message"]?.toString() ??
          "PIN verification failed (${response.statusCode})",
    );
  }

  static Future<bool> getHasParentUninstallPin() async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.get(
      Uri.parse("$baseUrl/users/me/uninstall-pin-status"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to load uninstall pin status: ${response.body}");
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body["has_pin"] == true;
  }

  static Future<void> setParentUninstallPin(String pin) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.post(
      Uri.parse("$baseUrl/users/me/uninstall-pin"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"pin": pin.trim()}),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to set uninstall pin: ${response.body}");
    }
  }

  // ===============================
  // ⏱ CHECK SCREEN TIME (optional `date` = device-local YYYY-MM-DD for daily totals)
  // ===============================
  static Future<Map<String, dynamic>> checkScreenTime(
    int childId, {
    String? date,
  }) async {
    final token = await _getToken();
    final d = date ?? localDateString();
    final url = "$baseUrl/screen-time/check/$childId?date=$d";
    final response = await http.get(
      Uri.parse(url),
      headers: {if (token != null) "Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to check screen time");
    }

    return jsonDecode(response.body);
  }

  // ===============================
  // 📱 GET APP CONTROLS
  // ===============================
  static Future<Map<String, dynamic>> getAppControls(int id) async {
    final token = await _getToken();

    final response = await http.get(
      Uri.parse("$baseUrl/children/$id/apps"),
      headers: {if (token != null) "Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch app controls");
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      // Compatibility fallback: if backend returns an array, treat it as controls
      return {"controls": decoded, "blocked_packages": []};
    }
    return decoded as Map<String, dynamic>;
  }

  // ===============================
  // 🚫 UPDATE APP CONTROL
  // ===============================
  static Future<void> updateAppControl(
    int id,
    String appName, {
    int? timeLimit,
    bool? isBlocked,
  }) async {
    final token = await _getToken();

    final Map<String, dynamic> body = {"app_name": appName};

    if (timeLimit != null) {
      body["time_limit"] = timeLimit;
    }

    if (isBlocked != null) {
      body["is_blocked"] = isBlocked;
    }

    final response = await http.post(
      Uri.parse("$baseUrl/children/$id/apps"),
      headers: {
        "Content-Type": "application/json",
        if (token != null) "Authorization": "Bearer $token",
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to update app control");
    }
  }

  // ===============================
  // RECORD USAGE
  // ===============================
  static Future<void> recordUsage(
    int id,
    String appName, {
    int minutes = 1,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/children/$id/usage"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"app_name": appName, "additional_minutes": minutes}),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to record usage");
    }
  }

  // ===============================
  //  Child device → Railway (no auth): daily_screen_time, daily_screen_time_totals, app_usage
  // Same contract as background_service POST /screen-time/save-usage
  // ===============================
  static Future<void> saveScreenTimeUsageBatch({
    required int childId,
    required String localDate,
    required int totalScreenTimeSeconds,
    required Map<String, int> packageToDurationSeconds,
  }) async {
    final usage = packageToDurationSeconds.entries
        .map(
          (e) => <String, dynamic>{
            'app_name': e.key,
            'duration': e.value,
          },
        )
        .toList();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/screen-time/save-usage'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'child_id': childId,
          'local_date': localDate,
          'total_screen_time': totalScreenTimeSeconds,
          'usage': usage,
        }),
      );
      if (response.statusCode == 200) {
        debugPrint(
          'saveScreenTimeUsageBatch OK child=$childId date=$localDate '
          'apps=${packageToDurationSeconds.length} total=${totalScreenTimeSeconds}s',
        );
      } else {
        debugPrint(
          'saveScreenTimeUsageBatch failed ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('saveScreenTimeUsageBatch error: $e');
    }
  }

  // ===============================
  // 📊 GET USAGE FOR A SPECIFIC DATE
  // ===============================
  static Future<Map<String, dynamic>> getScreenTimeUsage(int childId, {String? date}) async {
    final token = await _getToken();
    final d = date ?? localDateString();
    final url = "$baseUrl/screen-time/usage/$childId?date=$d";
    final response = await http.get(
      Uri.parse(url),
      headers: {if (token != null) "Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch usage for date");
    }

    return jsonDecode(response.body);
  }

  // ===============================
  // 📅 GET WEEKLY USAGE SUMMARY
  // ===============================
  static Future<List<dynamic>> getWeeklyUsageSummary(int childId) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse("$baseUrl/screen-time/usage/$childId/history?days=7"),
      headers: {if (token != null) "Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch weekly usage summary");
    }

    return jsonDecode(response.body);
  }

  // ===============================
  // 📊 GET WEEKLY PER-APP USAGE (last N days, for pie chart)
  // ===============================
  static Future<Map<String, dynamic>> getWeeklyAppsUsageSummary(
    int childId, {
    int days = 7,
  }) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse("$baseUrl/screen-time/usage/$childId/weekly-apps?days=$days"),
      headers: {if (token != null) "Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch weekly app usage");
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      final apps = decoded['apps'];
      if (apps is! List) decoded['apps'] = <dynamic>[];
      return decoded;
    }
    return <String, dynamic>{
      'total_screen_time': 0,
      'apps': <dynamic>[],
    };
  }

  // ===============================
  // ⏱ GET DAILY LIMIT
  // ===============================
  static Future<Map<String, dynamic>> getDailyLimit(int childId) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse("$baseUrl/children/$childId/limit"),
      headers: {if (token != null) "Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch daily limit");
    }

    return jsonDecode(response.body);
  }

  // ===============================
  // ⏱ SET DAILY LIMIT (in seconds)
  // ===============================
  static Future<void> setDailyLimitSeconds(int childId, int seconds) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.post(
      Uri.parse("$baseUrl/children/$childId/set-limit"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"daily_limit": seconds}),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to set daily limit");
    }
  }

  // ===============================
  // ⏱ UPDATE SCREEN TIME LIMIT (Bridge for UI)
  // ===============================
  static Future<void> updateScreenTimeLimit(int childId, int minutes) async {
    // UI gives minutes, backend/service expects seconds
    return setDailyLimitSeconds(childId, minutes * 60);
  }

  // ===============================
  // 📊 GET TODAY'S USAGE SUMMARY
  // ===============================
  static Future<Map<String, dynamic>> getTodayUsageSummary(int childId) async {
    return getScreenTimeUsage(childId, date: localDateString());
  }

  // ===============================
  // 🛰 TRACK DETAILED USAGE
  // ===============================
  static Future<void> trackDetailedUsage(
    int childId,
    String appName,
    DateTime startTime,
    DateTime endTime,
    int durationSeconds,
  ) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse("$baseUrl/app-usage/track"),
      headers: {
        "Content-Type": "application/json",
        if (token != null) "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "child_id": childId,
        "app_name": appName,
        "start_time": startTime.toIso8601String(),
        "end_time": endTime.toIso8601String(),
        "duration_seconds": durationSeconds,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to track detailed usage");
    }
  }

  // Presence / Heartbeat API
  static Future<void> updatePresence(
    int childId,
    String status, [
    String? appName,
  ]) async {
    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse("$baseUrl/children/presence"),
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "child_id": childId,
          "status": status,
          if (appName != null && appName.isNotEmpty) "current_app": appName,
        }),
      );
      if (response.statusCode != 200) {
        debugPrint("Failed to update presence: ${response.body}");
      }
    } catch (e) {
      debugPrint("Error sending presence heartbeat: $e");
    }
  }

  // ===============================
  // 🌐 GENERIC POST (no Firebase auth required)
  // ===============================
  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, [
    String? token,
  ]) async {
    final headers = <String, String>{"Content-Type": "application/json"};
    if (token != null) headers["Authorization"] = "Bearer $token";

    final response = await http.post(
      Uri.parse("${Config.serverUrl}$path"),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        "Request failed (${response.statusCode}): ${response.body}",
      );
    }
    return jsonDecode(response.body);
  }

  // ===============================
  // 📱 GET INSTALLED APPS FOR A CHILD (parent-side)
  // ===============================
  static Future<List<dynamic>> getInstalledApps(int childId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("Sign in to load installed apps from the child device.");
    }
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw Exception("Could not refresh sign-in. Try again.");
    }
    final response = await http.get(
      Uri.parse("$baseUrl/installed-apps/$childId"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (response.statusCode != 200) {
      throw Exception(
        "Failed to fetch installed apps (${response.statusCode}): ${response.body}",
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception("Unexpected server response for installed apps.");
    }
    return decoded;
  }

  static Future<void> blockApp(int childId, String packageName) async {
    final token = await _getToken();

    final response = await http.post(
      Uri.parse("$baseUrl/block-apps/block"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"child_id": childId, "package_name": packageName}),
    );

    debugPrint("STATUS: ${response.statusCode}");
    debugPrint("BODY: ${response.body}");

    if (response.statusCode != 200) {
      throw Exception("Failed to block app");
    }
  }

  // ===============================
  // ✅ UNBLOCK APP (PARENT)
  // ===============================
  static Future<void> unblockApp(int childId, String packageName) async {
    final token = await _getToken();
    
    final response = await http.delete(
      Uri.parse("$baseUrl/block-apps/unblock"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"child_id": childId, "package_name": packageName}),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to unblock app");
    }
  }

  // ===============================
  // 📱 UPLOAD INSTALLED APPS (child-side)
  // ===============================
  static Future<void> uploadInstalledApps(
    int childId,
    List<Map<String, String>> apps,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/installed-apps"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"child_id": childId, "apps": apps}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to upload installed apps (${response.statusCode}): ${response.body}",
      );
    }
  }

  /// Child devices may have flaky networks; retry a few times so the parent list populates.
  static Future<void> uploadInstalledAppsWithRetry(
    int childId,
    List<Map<String, String>> apps,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await uploadInstalledApps(childId, apps);
        return;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(Duration(milliseconds: 800 * (attempt + 1)));
      }
    }
    throw lastError ?? Exception("Upload failed after retries");
  }

  static Future<void> saveParentFcmToken({required String fcmToken}) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.post(
      Uri.parse("$baseUrl/users/me/fcm-token"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"fcm_token": fcmToken}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to save parent FCM token (${response.statusCode}): ${response.body}",
      );
    }
  }

  static Future<int> getParentUnreadCount() async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.get(
      Uri.parse("$baseUrl/notifications/parent/unread-count"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to fetch unread count (${response.statusCode}): ${response.body}",
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['unread_count'] != null) {
      return (decoded['unread_count'] as num).toInt();
    }
    return 0;
  }

  static Future<int> markParentNotificationsRead({int? childId}) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final body = <String, dynamic>{};
    if (childId != null) body['child_id'] = childId;

    final response = await http.post(
      Uri.parse("$baseUrl/notifications/parent/mark-read"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to mark notifications read (${response.statusCode}): ${response.body}",
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['unread_count'] != null) {
      return (decoded['unread_count'] as num).toInt();
    }
    return 0;
  }

  static Future<void> saveChildFcmToken({
    int? childId,
    String? childPublicId,
    required String fcmToken,
  }) async {
    if (childId == null &&
        (childPublicId == null || childPublicId.trim().isEmpty)) {
      throw Exception("Missing child identifier for FCM token save.");
    }

    final response = await http.post(
      Uri.parse("$baseUrl/children/save-fcm-token"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "child_id": childId,
        "child_public_id": childPublicId?.trim(),
        "fcm_token": fcmToken,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to save FCM token (${response.statusCode}): ${response.body}",
      );
    }
  }

  // ===============================
  // 🚫 GET BLOCKED APPS (Strict Packages)
  // ===============================
  static Future<List<String>> getBlockedApps(int childId) async {
    final data = await getAppControls(childId);
    final blocked = data['blocked_packages'];
    if (blocked is List) {
      return List<String>.from(blocked);
    }
    return [];
  }

  // ===============================
  // 🔔 GET NOTIFICATIONS
  // ===============================
  static Future<List<dynamic>> getNotifications(int childId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/notifications/$childId"),
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to load notifications");
    }
  }

  // ===============================
  // 🔔 GET REMINDERS FOR CHILD DEVICE
  // ===============================
  static Future<List<dynamic>> getReceivedReminders(int childId) async {
    http.Response response = await http.get(
      Uri.parse("$baseUrl/reminders/received/$childId"),
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 404) {
      response = await http.get(
        Uri.parse("$baseUrl/children/$childId/reminders"),
        headers: {
          'Content-Type': 'application/json',
        },
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to fetch received reminders (${response.statusCode}): ${response.body}",
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['data'] is List) {
      return decoded['data'] as List<dynamic>;
    }
    if (decoded is List) {
      return decoded;
    }
    return [];
  }

  // ===============================
  // 🔔 GET PARENT NOTIFICATIONS (new app installs, alerts, etc.)
  // ===============================
  static Future<List<dynamic>> getParentNotifications(int childId) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.get(
      Uri.parse("$baseUrl/notifications/$childId"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to fetch notifications (${response.statusCode}): ${response.body}",
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded;
  }

  // ===============================
  // 🗑 DELETE NOTIFICATION
  // ===============================
  static Future<void> deleteNotification(int id) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.delete(
      Uri.parse("$baseUrl/notifications/$id"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to delete notification");
    }
  }

  // ===============================
  // 🔔 SEND REMINDER (PARENT)
  // ===============================
  static Future<void> sendReminder(
    int childId,
    String message, {
    required String title,
    required String priority,
    required String frequency,
    required String scheduledAt,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");
    final parsedSchedule = DateTime.tryParse(scheduledAt);
    final isFutureSchedule =
        parsedSchedule != null && parsedSchedule.isAfter(DateTime.now());
    final normalizedSchedule =
        parsedSchedule != null ? _toMySqlDateTime(parsedSchedule.toUtc()) : null;

    http.Response response = await http.post(
      Uri.parse("$baseUrl/reminders/send"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "child_id": childId,
        "message": message,
        "title": title,
        "priority": priority.toLowerCase(),
        "frequency": frequency.toLowerCase(),
        "scheduled_at": normalizedSchedule ?? scheduledAt,
      }),
    );

    if (response.statusCode == 404) {
      if (isFutureSchedule) {
        throw Exception(
          "Scheduled reminders are not supported by this backend version. "
          "Please deploy the latest backend.",
        );
      }
      response = await http.post(
        Uri.parse("$baseUrl/children/$childId/reminders"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "message": message,
          "time": normalizedSchedule ?? scheduledAt,
          "type": title,
          "priority": priority.toLowerCase(),
        }),
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        "Failed to send reminder (${response.statusCode}): ${response.body}",
      );
    }
  }

  static Future<void> createRestriction({
    required int childId,
    required String type,
    required String startTime,
    required String endTime,
    required List<String> days,
    required List<String> blockedApps,
    required bool enabled,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.post(
      Uri.parse("$baseUrl/restrictions"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "child_id": childId,
        "type": type,
        "start_time": startTime,
        "end_time": endTime,
        "days": days,
        "blocked_apps": blockedApps,
        "enabled": enabled,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        "Failed to create restriction (${response.statusCode}): ${response.body}",
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getRestrictionsForChild(
    int childId,
  ) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.get(
      Uri.parse("$baseUrl/restrictions/child/$childId"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to fetch restrictions (${response.statusCode}): ${response.body}",
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> updateRestriction({
    required int restrictionId,
    required String type,
    required String startTime,
    required String endTime,
    required List<String> days,
    required List<String> blockedApps,
    required bool enabled,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.put(
      Uri.parse("$baseUrl/restrictions/$restrictionId"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "type": type,
        "start_time": startTime,
        "end_time": endTime,
        "days": days,
        "blocked_apps": blockedApps,
        "enabled": enabled,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to update restriction (${response.statusCode}): ${response.body}",
      );
    }
  }

  static Future<void> toggleRestriction(int restrictionId) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.patch(
      Uri.parse("$baseUrl/restrictions/$restrictionId/toggle"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to toggle restriction (${response.statusCode}): ${response.body}",
      );
    }
  }

  static Future<void> deleteRestriction(int restrictionId) async {
    final token = await _getToken();
    if (token == null) throw Exception("User not logged in");

    final response = await http.delete(
      Uri.parse("$baseUrl/restrictions/$restrictionId"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to delete restriction (${response.statusCode}): ${response.body}",
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getActiveRestrictionsForChild(
    int childId,
  ) async {
    final response = await http.get(
      Uri.parse("$baseUrl/restrictions/active/$childId"),
      headers: {"Content-Type": "application/json"},
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to fetch active restrictions (${response.statusCode}): ${response.body}",
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ===============================
  // 📅 SCHEDULES API
  // ===============================

  static Future<List<dynamic>> getSchedules(int childId) async {
    final token = await _getToken();
    final uri = Uri.parse("$baseUrl/children/$childId/schedules");
    final http.Response response;
    try {
      response = await http.get(
        uri,
        headers: {if (token != null) "Authorization": "Bearer $token"},
      );
    } catch (e) {
      throw Exception("Failed to fetch schedules: $e");
    }

    if (response.statusCode != 200) {
      if (response.statusCode == 404) return [];
      final b = response.body;
      final preview = b.length > 280 ? "${b.substring(0, 280)}..." : b;
      throw Exception(
        "Failed to fetch schedules (HTTP ${response.statusCode}): $preview",
      );
    }

    final decoded = jsonDecode(response.body);
    return decoded is List ? decoded : [];
  }

  static Future<void> saveSchedule(int childId, Map<String, dynamic> schedule) async {
    final token = await _getToken();
    if (token == null) {
      throw Exception("User not logged in");
    }
    final response = await http.post(
      Uri.parse("$baseUrl/children/$childId/schedules"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode(schedule),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        "Failed to save schedule (${response.statusCode}): ${response.body}",
      );
    }
  }

  static Future<void> deleteSchedule(int childId, String scheduleId) async {
    final token = await _getToken();
    if (token == null) {
      throw Exception("User not logged in");
    }
    final response = await http.delete(
      Uri.parse("$baseUrl/children/$childId/schedules/$scheduleId"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to delete schedule");
    }
  }
}