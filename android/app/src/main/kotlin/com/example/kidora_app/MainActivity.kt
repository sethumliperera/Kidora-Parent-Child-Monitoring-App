package com.example.kidora_app

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.app.AppOpsManager
import android.provider.Settings
import android.os.Build
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class MainActivity : FlutterActivity() {

    private val CHANNEL = "app.channel"
    private val PREFS = "kidora_prefs"
    private val KEY_USAGE_GRANTED_MS = "kidora_usage_access_granted_ms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->

                when (call.method) {

                    "checkUsagePermission" -> {
                        val granted = hasUsagePermission()
                        if (granted) {
                            val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                            if (!prefs.contains(KEY_USAGE_GRANTED_MS)) {
                                prefs.edit()
                                    .putLong(KEY_USAGE_GRANTED_MS, System.currentTimeMillis())
                                    .apply()
                            }
                        }
                        result.success(granted)
                    }

                    "getUsageStats" -> {
                        result.success(getUsageStats())
                    }

                    "getCurrentApp" -> {
                        result.success(getCurrentForegroundApp())
                    }

                    "goHome" -> {
                        goHome()
                        result.success(true)
                    }

                    "openUsageSettings" -> {
                        openUsageSettings()
                        result.success(true)
                    }

                    "setBlockedApps" -> {
                        val apps = call.arguments as List<String>
                        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                        prefs.edit().putStringSet("blocked_apps", apps.toSet()).apply()
                        result.success(true)
                    }

                    "syncKidoraDeviceContext" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any?>
                        val cid = args?.get("child_db_id")?.toString()?.trim().orEmpty()
                        val base = args?.get("server_base_url")?.toString()?.trim().orEmpty()
                        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                            .putString("child_db_id", cid)
                            .putString("server_base_url", base)
                            .apply()
                        result.success(true)
                    }

                    "consumeUninstallVerificationFlag" -> {
                        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                        val pending = prefs.getBoolean("pending_uninstall_verification", false)
                        if (pending) {
                            prefs.edit().putBoolean("pending_uninstall_verification", false).apply()
                        }
                        result.success(pending)
                    }

                    "setUninstallBypassMinutes" -> {
                        val minutes = call.argument<Int>("minutes") ?: 2
                        val until = System.currentTimeMillis() + (minutes * 60 * 1000L)
                        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                        prefs.edit().putLong("uninstall_bypass_until", until).apply()
                        result.success(true)
                    }

                    "getUninstallBypassSeconds" -> {
                        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
                        val until = prefs.getLong("uninstall_bypass_until", 0L)
                        val remainingMs = until - System.currentTimeMillis()
                        result.success(if (remainingMs > 0) (remainingMs / 1000L).toInt() else 0)
                    }

                    "openAppUninstallSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_SETTINGS_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun hasUsagePermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOps.unsafeCheckOpNoThrow(
                "android:get_usage_stats",
                Process.myUid(),
                packageName
            )
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    /** Same calendar day as Digital Wellbeing / Samsung Screen time (device default timezone). */
    private fun localStartOfTodayMillis(): Long {
        val zone = ZoneId.systemDefault()
        return LocalDate.now(zone)
            .atStartOfDay(zone)
            .toInstant()
            .toEpochMilli()
    }

    /**
     * Foreground time for **today only** (local midnight → now).
     *
     * `queryAndAggregateUsageStats` / loose DAILY rows on some Samsung builds can include
     * **multi-day** `totalTimeInForeground` (e.g. ~14h vs ~2h real). We therefore:
     * 1. **INTERVAL_DAILY** — only buckets whose **bucket starts on today’s local date**, and
     *    `lastTimeUsed >=` midnight; **max** duplicate rows; **cap** each app at elapsed ms since midnight.
     * 2. **Usage events** — clipped to [midnight, now]; merged with daily using **min** when both exist
     *    to avoid inflated query rows dominating real activity time.
     * 3. **queryAndAggregateUsageStats** — only on **non-Samsung** if still empty, with the same per-app cap.
     * 4. **INTERVAL_BEST** — **max** per package (never sum — sums double-count overlapping buckets).
     */
    private fun getUsageStats(): List<Map<String, Any>> {
        if (!hasUsagePermission()) {
            return emptyList()
        }

        val startTime = localStartOfTodayMillis()
        val endTime = System.currentTimeMillis()
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val merged = aggregateForegroundForToday(usm, startTime, endTime)

        return merged.entries
            .filter { it.value > 0 }
            .map { (pkg, ms) ->
                mapOf(
                    "packageName" to pkg,
                    "timeInForeground" to ms
                )
            }
            .sortedByDescending { it["timeInForeground"] as Long }
    }

    /** Galaxy / One UI devices (manufacturer or brand). */
    private fun isSamsungDevice(): Boolean {
        val m = Build.MANUFACTURER
        val b = Build.BRAND
        return m.equals("samsung", ignoreCase = true) || b.equals("samsung", ignoreCase = true)
    }

    private fun aggregateForegroundForToday(
        usm: UsageStatsManager,
        start: Long,
        end: Long
    ): Map<String, Long> {
        val wallMs = (end - start).coerceAtLeast(1L)

        val strictDaily = aggregateStrictTodayDaily(usm, start, end, wallMs)
        val fromEvents = aggregateForegroundFromUsageEvents(usm, start, end)

        val merged = LinkedHashMap<String, Long>()
        val allPkgs = strictDaily.keys + fromEvents.keys
        for (pkg in allPkgs) {
            val s = strictDaily[pkg] ?: 0L
            val e = fromEvents[pkg] ?: 0L
            val v = when {
                s > 0L && e > 0L -> minOf(s, e)
                else -> maxOf(s, e)
            }
            if (v > 0L) merged[pkg] = minOf(v, wallMs)
        }

        if (merged.isNotEmpty()) return merged

        if (!isSamsungDevice() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val aggregated = usm.queryAndAggregateUsageStats(start, end)
                if (aggregated != null && aggregated.isNotEmpty()) {
                    val map = mutableMapOf<String, Long>()
                    for ((pkg, usage) in aggregated) {
                        if (pkg.contains("kidora", ignoreCase = true)) continue
                        var t = usage.totalTimeInForeground
                        if (t <= 0L) continue
                        t = minOf(t, wallMs)
                        map[pkg] = t
                    }
                    if (map.isNotEmpty()) return map
                }
            } catch (_: Exception) {
                // Fall through.
            }
        }

        val best = aggregateIntervalBestMaxPerPackage(usm, start, end, wallMs)
        if (best.isNotEmpty()) return best

        return aggregateDailyQueryTotalsLegacy(usm, start, end)
    }

    /**
     * **INTERVAL_DAILY** rows for “today”: must show **activity since local midnight** (`lastTimeUsed`),
     * or bucket **starts** on today’s local date. Each value is **capped** at elapsed ms since midnight
     * so OEM cumulative / multi-day `totalTimeInForeground` cannot exceed real clock time for the day.
     */
    private fun aggregateStrictTodayDaily(
        usm: UsageStatsManager,
        start: Long,
        end: Long,
        wallMs: Long
    ): Map<String, Long> {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            start,
            end
        ) ?: return emptyMap()

        val map = mutableMapOf<String, Long>()
        for (usage in stats) {
            val pkg = usage.packageName ?: continue
            if (pkg.contains("kidora", ignoreCase = true)) continue

            val first = usage.firstTimeStamp
            val last = usage.lastTimeUsed
            if (last > 0L && last < start) continue

            val firstDay =
                if (first > 0L) Instant.ofEpochMilli(first).atZone(zone).toLocalDate() else null
            val include = firstDay == today || last >= start
            if (!include) continue

            var t = usage.totalTimeInForeground
            if (t <= 0L) continue
            t = minOf(t, wallMs)
            map[pkg] = maxOf(map[pkg] ?: 0L, t)
        }
        return map
    }

    /**
     * **Max** per package (summing BEST buckets overlaps the same foreground and inflates totals).
     */
    private fun aggregateIntervalBestMaxPerPackage(
        usm: UsageStatsManager,
        start: Long,
        end: Long,
        wallMs: Long
    ): Map<String, Long> {
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST,
            start,
            end
        ) ?: return emptyMap()

        val map = mutableMapOf<String, Long>()
        for (usage in stats) {
            val pkg = usage.packageName ?: continue
            if (pkg.contains("kidora", ignoreCase = true)) continue
            if (usage.lastTimeStamp > 0L && usage.lastTimeStamp < start) continue
            if (usage.firstTimeStamp > 0L && usage.firstTimeStamp > end) continue
            var t = usage.totalTimeInForeground
            if (t <= 0L) continue
            t = minOf(t, wallMs)
            map[pkg] = maxOf(map[pkg] ?: 0L, t)
        }
        return map
    }

    /** Look back before midnight so a session that started last night can close inside “today”. */
    private fun aggregateForegroundFromUsageEvents(
        usm: UsageStatsManager,
        windowStart: Long,
        windowEnd: Long
    ): Map<String, Long> {
        val lookbackMs = 6L * 60L * 60L * 1000L
        val queryStart = maxOf(0L, windowStart - lookbackMs)
        val out = mutableMapOf<String, Long>()
        val activeStart = mutableMapOf<String, Long>()

        fun addForegroundMs(pkg: String, sessionStart: Long, sessionEnd: Long) {
            var s = sessionStart
            var e = sessionEnd
            if (e <= windowStart || s >= windowEnd) return
            s = maxOf(s, windowStart)
            e = minOf(e, windowEnd)
            val d = e - s
            if (d > 0L) out[pkg] = (out[pkg] ?: 0L) + d
        }

        val events = usm.queryEvents(queryStart, windowEnd)
        val ev = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            val pkg = ev.packageName ?: continue
            if (pkg.contains("kidora", ignoreCase = true)) continue

            // API 29+: ACTIVITY_* is sent (and MOVE_* for compat); use only ACTIVITY_* to avoid double sessions.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                when (ev.eventType) {
                    UsageEvents.Event.ACTIVITY_RESUMED -> {
                        if (!activeStart.containsKey(pkg)) activeStart[pkg] = ev.timeStamp
                    }
                    UsageEvents.Event.ACTIVITY_PAUSED -> {
                        val t0 = activeStart.remove(pkg) ?: continue
                        addForegroundMs(pkg, t0, ev.timeStamp)
                    }
                }
            } else {
                when (ev.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                        if (!activeStart.containsKey(pkg)) activeStart[pkg] = ev.timeStamp
                    }
                    UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                        val t0 = activeStart.remove(pkg) ?: continue
                        addForegroundMs(pkg, t0, ev.timeStamp)
                    }
                }
            }
        }
        for ((pkg, t0) in activeStart.toMap()) {
            addForegroundMs(pkg, t0, windowEnd)
        }
        return out
    }

    /**
     * INTERVAL_DAILY for **today only**; use **max** per package so duplicate OEM rows
     * are not summed into a fake inflated total.
     */
    private fun aggregateDailyQueryTotalsLegacy(
        usm: UsageStatsManager,
        start: Long,
        end: Long
    ): Map<String, Long> {
        val wallMs = (end - start).coerceAtLeast(1L)
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            start,
            end
        ) ?: return emptyMap()

        val map = mutableMapOf<String, Long>()
        for (usage in stats) {
            val pkg = usage.packageName ?: continue
            if (pkg.contains("kidora", ignoreCase = true)) continue
            if (usage.firstTimeStamp > 0L) {
                val bucketDay = Instant.ofEpochMilli(usage.firstTimeStamp)
                    .atZone(zone)
                    .toLocalDate()
                if (bucketDay != today) continue
            } else if (usage.lastTimeUsed < start) {
                continue
            }
            var t = usage.totalTimeInForeground
            if (t <= 0L) continue
            t = minOf(t, wallMs)
            val existing = map[pkg] ?: 0L
            map[pkg] = maxOf(existing, t)
        }
        return map
    }

    private fun getCurrentForegroundApp(): String {
        if (!hasUsagePermission()) {
            return "Unknown"
        }
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val endTime = System.currentTimeMillis()
        val beginTime = endTime - 60_000L

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST,
            beginTime,
            endTime
        ) ?: emptyList()

        var recentApp = "Unknown"
        var lastTime = 0L

        for (usage in stats) {
            if (usage.lastTimeUsed > lastTime) {
                lastTime = usage.lastTimeUsed
                recentApp = usage.packageName
            }
        }

        return recentApp
    }

    private fun goHome() {
        val intent = Intent(Intent.ACTION_MAIN)
        intent.addCategory(Intent.CATEGORY_HOME)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }

    private fun openUsageSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }
}
