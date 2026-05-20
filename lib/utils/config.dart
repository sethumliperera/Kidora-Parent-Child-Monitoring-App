class Config {
  /// When false, hitting the daily screen time cap does not send the child home or open the restriction UI.
  /// Parent blocks, schedules, and per-app limits still apply.
  static const bool enforceDailyScreenTimeLimit = false;

  /// 🌍 LIVE BACKEND (Render)
  /// Safety alerts POST here. New rows show in the MySQL database configured as DATABASE_URL on
  /// **that Render service** — not automatically in Railway unless you paste Railway's MySQL URL into Render.
  static const String baseUrl = "https://kidora-api.onrender.com/api";

  /// 🌍 Server URL (for images/files)
  static const String serverUrl = "https://kidora-api.onrender.com";

  /*
  ================= OPTIONAL (for development) =================

  👉 Use these ONLY when testing locally (NOT for APK)

  Android Emulator:
  static const String baseUrl = "http://10.0.2.2:3000/api";
  static const String serverUrl = "http://10.0.2.2:3000";

  Physical Device (same WiFi):
  static const String baseUrl = "http://192.168.X.X:3000/api";
  static const String serverUrl = "http://192.168.X.X:3000";

  =============================================================
  */
}
