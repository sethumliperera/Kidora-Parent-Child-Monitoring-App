package com.example.kidora_app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.concurrent.thread

/**
 * App blocking + browser search monitoring (Chrome, Google app, Edge, Firefox, Brave, DuckDuckGo, Samsung Internet, etc.).
 * Reads search URLs / omnibox, extracts the query for major search engines, and if it matches the safety list POSTs to Kidora for parent email.
 */
class AppBlockService : AccessibilityService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var searchScanRunnable: Runnable? = null
    @Volatile
    private var lastWindowHintPrivate: Boolean = false

    private fun getBlockedApps(): Set<String> {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        return prefs.getStringSet("blocked_apps", setOf()) ?: setOf()
    }

    private fun isUninstallBypassActive(): Boolean {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val until = prefs.getLong("uninstall_bypass_until", 0L)
        return until > System.currentTimeMillis()
    }

    private fun markUninstallPinPending() {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        prefs.edit().putBoolean("pending_uninstall_verification", true).apply()
    }

    private fun isPackageInstaller(packageName: String): Boolean {
        return packageName.contains("packageinstaller", ignoreCase = true) ||
            packageName.contains("permissioncontroller", ignoreCase = true)
    }

    private fun isSystemSettings(packageName: String): Boolean {
        return packageName == "com.android.settings"
    }

    private fun isAttemptingToUninstallKidora(event: AccessibilityEvent): Boolean {
        val text = event.text?.joinToString(" ")?.lowercase() ?: ""
        val contentDescription = event.contentDescription?.toString()?.lowercase() ?: ""
        val combined = "$text $contentDescription"
        return combined.contains("kidora") || combined.contains("com.example.kidora_app")
    }

    private fun isSettingsUninstallSurface(event: AccessibilityEvent): Boolean {
        val text = event.text?.joinToString(" ")?.lowercase() ?: ""
        val contentDescription = event.contentDescription?.toString()?.lowercase() ?: ""
        val combined = "$text $contentDescription"
        val hasUninstallTerms = combined.contains("uninstall") ||
            combined.contains("remove app") ||
            combined.contains("delete app")
        return hasUninstallTerms && isAttemptingToUninstallKidora(event)
    }

    /**
     * When user tries to uninstall Kidora (no parent bypass), send them back to the app for PIN flow.
     */
    private fun maybeHandleUninstallAttempt(event: AccessibilityEvent, packageName: String): Boolean {
        val uninstallAttemptDetected =
            (isPackageInstaller(packageName) && isAttemptingToUninstallKidora(event)) ||
                (isSystemSettings(packageName) && isSettingsUninstallSurface(event))

        if (!uninstallAttemptDetected || isUninstallBypassActive()) {
            return false
        }

        Log.d(TAG_BLOCK, "UNINSTALL ATTEMPT DETECTED for Kidora")
        markUninstallPinPending()

        val appIntent = packageManager.getLaunchIntentForPackage(applicationContext.packageName)
        appIntent?.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        if (appIntent != null) {
            startActivity(appIntent)
        } else {
            performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
        }
        return true
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        synchronized(reportLock) {
            lastReportedSig =
                getSharedPreferences(PREFS, MODE_PRIVATE).getString("last_safety_sig", null)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (maybeHandleUninstallAttempt(event, packageName)) {
                return
            }
            updatePrivateWindowHint(event)
            maybeBlockApp(packageName)
            if (isSearchMonitoredPackage(packageName)) {
                scheduleSearchContentScan(packageName, fast = true)
            }
        }
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED
        ) {
            if (event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED) {
                updatePrivateWindowHint(event)
            }
            if (isSearchMonitoredPackage(packageName)) {
                val fast = event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED ||
                    lastWindowHintPrivate
                scheduleSearchContentScan(packageName, fast = fast)
            }
        }
    }

    private fun updatePrivateWindowHint(event: AccessibilityEvent) {
        val blob = buildString {
            event.text?.forEach { append(it).append(' ') }
            event.contentDescription?.let { append(it) }
            event.className?.let { append(' ').append(it) }
        }.lowercase(Locale.US)
        if (PRIVATE_SESSION_MARKERS.any { blob.contains(it) }) {
            lastWindowHintPrivate = true
        }
    }

    private fun maybeBlockApp(packageName: String) {
        val blockedApps = getBlockedApps()
        Log.d(TAG_BLOCK, "Window: $packageName blocked=$blockedApps")
        if (blockedApps.isEmpty()) return
        if (!blockedApps.contains(packageName)) return
        Log.d(TAG_BLOCK, "BLOCKING: $packageName")
        val intent = Intent(Intent.ACTION_MAIN)
        intent.addCategory(Intent.CATEGORY_HOME)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }

    private val searchBrowserPackages = setOf(
        "com.android.chrome",
        "com.chrome.beta",
        "com.chrome.dev",
        "com.google.android.googlequicksearchbox",
        "com.brave.browser",
        "org.mozilla.firefox",
        "org.mozilla.firefox_beta",
        "org.mozilla.fenix",
        "com.microsoft.emmx",
        "com.microsoft.emmx.canary",
        "com.opera.browser",
        "com.opera.mini.native",
        "com.sec.android.app.sbrowser",
        "com.duckduckgo.mobile.android",
        "com.google.android.youtube",
        "com.google.android.apps.youtube.kids",
        "com.vanced.android.youtube"
    )

    private val youtubePackages = setOf(
        "com.google.android.youtube",
        "com.google.android.apps.youtube.kids",
        "com.vanced.android.youtube"
    )

    private val googleAppPackage = "com.google.android.googlequicksearchbox"

    private fun isSearchMonitoredPackage(pkg: String): Boolean {
        if (searchBrowserPackages.contains(pkg)) return true
        if (pkg.startsWith("com.android.chrome") || pkg.contains("chrome", ignoreCase = true)) return true
        return pkg.contains("youtube", ignoreCase = true)
    }

    private fun scheduleSearchContentScan(triggerPackage: String, fast: Boolean = false) {
        searchScanRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable { scanForFlaggedSearch(triggerPackage) }
        searchScanRunnable = r
        val delay = if (fast || lastWindowHintPrivate) SEARCH_DEBOUNCE_FAST_MS else SEARCH_DEBOUNCE_MS
        mainHandler.postDelayed(r, delay)
    }

    private fun scanForFlaggedSearch(triggerPackage: String) {
        val root = rootInActiveWindow ?: return
        try {
            val isPrivate = isPrivateBrowsingSession(root)
            // 1) Native YouTube / YouTube Kids: search EditText — no URL bar.
            if (youtubePackages.contains(triggerPackage) ||
                triggerPackage.contains("youtube", ignoreCase = true)
            ) {
                val native = findNativeSearchFieldText(root)
                if (!native.isNullOrBlank()) {
                    val cleaned = native.trim()
                    if (cleaned.length >= 2 && isQueryBlocked(cleaned)) {
                        maybeReportFlaggedSearch(cleaned, triggerPackage, isPrivateBrowsing = isPrivate)
                        return
                    }
                }
            }

            // 2) Google app: often shows plain query ("vape") in the search plate — not a full URL.
            if (triggerPackage == googleAppPackage ||
                triggerPackage.contains("googlequicksearch", ignoreCase = true)
            ) {
                val g = findGoogleAppSearchEditText(root)
                if (!g.isNullOrBlank()) {
                    val cleaned = g.trim()
                    if (cleaned.length >= 2 && isQueryBlocked(cleaned)) {
                        maybeReportFlaggedSearch(cleaned, triggerPackage, isPrivateBrowsing = isPrivate)
                        return
                    }
                }
            }

            // 3) Browsers + URLs in tree (incl. youtube.com/results?search_query=…, incognito omnibox)
            val bar = findUrlBarText(root)
            val treeUrl = findSearchEngineUrlInTree(root)
            val broad = findBroadSearchFieldText(root)
            val query = resolveSearchQuery(bar, treeUrl, broad) ?: return
            if (query.length < 2) return
            if (!isQueryBlocked(query)) return

            if (isPrivate) {
                Log.i(TAG_SEARCH, "Private browsing flagged search: ${query.take(40)}")
            }
            maybeReportFlaggedSearch(query, triggerPackage, isPrivateBrowsing = isPrivate)
        } catch (e: Exception) {
            Log.e(TAG_SEARCH, "scan failed", e)
        } finally {
            root.recycle()
        }
    }

    /**
     * Google app's search field: EditText with resource id containing search/query (not Chrome url_bar).
     */
    private fun findGoogleAppSearchEditText(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
        val id = (node.viewIdResourceName ?: "").lowercase(Locale.US)
        val cls = (node.className?.toString() ?: "").lowercase(Locale.US)
        if (cls.contains("edittext") && (id.contains("search") || id.contains("query"))) {
            val t = node.text?.toString()?.trim()
            if (!t.isNullOrEmpty()) return t
        }
        for (i in 0 until node.childCount) {
            val ch = node.getChild(i) ?: continue
            try {
                findGoogleAppSearchEditText(ch)?.let { return it }
            } finally {
                ch.recycle()
            }
        }
        return null
    }

    /** Omnibox often shows only the keywords; [extractSearchQuery] needs a URL with params. */
    private fun plainQueryFromSearchBar(raw: String): String? {
        val t = raw.trim()
        if (t.length < 2 || t.length > 500) return null
        if (t.contains("://")) return null
        if (lineLooksLikeSearchUrl(t)) return null
        if (!t.contains(" ") && t.contains(".") && DOMAIN_LIKE.matches(t)) return null
        return t
    }

    private fun resolveSearchQuery(bar: String?, treeUrl: String?, broad: String? = null): String? {
        if (!bar.isNullOrBlank()) {
            extractSearchQuery(bar)?.let { return it }
            plainQueryFromSearchBar(bar)?.let { return it }
        }
        if (!broad.isNullOrBlank()) {
            extractSearchQuery(broad)?.let { return it }
            plainQueryFromSearchBar(broad)?.let { return it }
        }
        if (!treeUrl.isNullOrBlank()) {
            extractSearchQuery(treeUrl)?.let { return it }
            plainQueryFromSearchBar(treeUrl)?.let { return it }
        }
        return null
    }

    /** Incognito / InPrivate / Secret mode — Chrome still uses com.android.chrome. */
    private fun isPrivateBrowsingSession(root: AccessibilityNodeInfo): Boolean {
        if (lastWindowHintPrivate) return true
        return treeIndicatesPrivateSession(root)
    }

    private fun treeIndicatesPrivateSession(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false
        val id = (node.viewIdResourceName ?: "").lowercase(Locale.US)
        if (id.contains("incognito") || id.contains("private") || id.contains("secret")) return true
        val t = node.text?.toString()?.lowercase(Locale.US).orEmpty()
        val d = node.contentDescription?.toString()?.lowercase(Locale.US).orEmpty()
        val blob = "$t $d"
        if (PRIVATE_SESSION_MARKERS.any { blob.contains(it) }) return true
        for (i in 0 until node.childCount) {
            val ch = node.getChild(i) ?: continue
            try {
                if (treeIndicatesPrivateSession(ch)) return true
            } finally {
                ch.recycle()
            }
        }
        return false
    }

    /**
     * Incognito often hides the URL until submit; scan any search-like EditText / omnibox variant.
     */
    private fun findBroadSearchFieldText(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
        val id = (node.viewIdResourceName ?: "").lowercase(Locale.US)
        val cls = (node.className?.toString() ?: "").lowercase(Locale.US)
        val hint = node.hintText?.toString()?.lowercase(Locale.US).orEmpty()
        val isSearchLikeId = id.contains("search") || id.contains("query") || id.contains("omnibox") ||
            id.contains("url_bar") || id.contains("location_bar") || id.contains("address_bar") ||
            id.contains("search_box") || id.contains("search_toolbar") || id.contains("fake_search")
        val isSearchHint = hint.contains("search") || hint.contains("query") || hint.contains("address")
        if (cls.contains("edittext") && (isSearchLikeId || isSearchHint)) {
            val t = node.text?.toString()?.trim()
            if (!t.isNullOrEmpty() && t.length >= 2) return t
        }
        for (i in 0 until node.childCount) {
            val ch = node.getChild(i) ?: continue
            try {
                findBroadSearchFieldText(ch)?.let { return it }
            } finally {
                ch.recycle()
            }
        }
        return null
    }

    /** YouTube / YouTube Kids native search: look for EditText nodes whose id contains "search". */
    private fun findNativeSearchFieldText(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
        val id = node.viewIdResourceName ?: ""
        val cls = node.className?.toString() ?: ""
        if (cls.contains("EditText", ignoreCase = true) &&
            (id.contains("search_edit", ignoreCase = true) ||
             id.contains("search_input", ignoreCase = true) ||
             id.contains("search_text", ignoreCase = true) ||
             id.contains("search_src_text", ignoreCase = true) ||
             id.endsWith("search_edit_text_field", ignoreCase = true))
        ) {
            val t = node.text?.toString()
            if (!t.isNullOrBlank()) return t
        }
        for (i in 0 until node.childCount) {
            val ch = node.getChild(i) ?: continue
            try {
                findNativeSearchFieldText(ch)?.let { return it }
            } finally {
                ch.recycle()
            }
        }
        return null
    }

    private fun findUrlBarText(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
        val id = node.viewIdResourceName ?: ""
        if (id.endsWith("url_bar") ||
            id.contains("omnibox") ||
            id.contains("location_bar") ||
            id.contains("search_box") ||
            id.contains("search_toolbar")
        ) {
            val t = node.text?.toString()
            if (!t.isNullOrBlank()) return t
        }
        for (i in 0 until node.childCount) {
            val ch = node.getChild(i) ?: continue
            try {
                findUrlBarText(ch)?.let { return it }
            } finally {
                ch.recycle()
            }
        }
        return null
    }

    private fun lineLooksLikeSearchUrl(s: String): Boolean {
        val l = s.lowercase(Locale.US)
        if (l.isBlank()) return false
        return (
            (l.contains("google.") && (l.contains("/search") || l.contains("?q=") || l.contains("&q="))) ||
                (l.contains("bing.com") && (l.contains("/search") || l.contains("?q=") || l.contains("&q="))) ||
                (l.contains("duckduckgo.") && l.contains("q=")) ||
                l.contains("search.yahoo.com") ||
                l.contains("yahoo.com/search") ||
                (l.contains("yandex.") && (l.contains("text=") || l.contains("query="))) ||
                l.contains("brave.com/search") ||
                (l.contains("ecosia.org") && l.contains("q=")) ||
                (l.contains("startpage.com") && (l.contains("query=") || l.contains("q="))) ||
                (l.contains("youtube.com") && (l.contains("search_query=") || l.contains("/results"))) ||
                (l.contains("m.youtube.com") && (l.contains("search_query=") || l.contains("/results")))
            )
    }

    private fun findSearchEngineUrlInTree(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
        val t = node.text?.toString()
        if (!t.isNullOrBlank() && lineLooksLikeSearchUrl(t)) return t
        val d = node.contentDescription?.toString()
        if (!d.isNullOrBlank() && lineLooksLikeSearchUrl(d)) return d
        for (i in 0 until node.childCount) {
            val ch = node.getChild(i) ?: continue
            try {
                findSearchEngineUrlInTree(ch)?.let { return it }
            } finally {
                ch.recycle()
            }
        }
        return null
    }

    private fun extractSearchQuery(raw: String): String? {
        val line = try {
            URLDecoder.decode(raw.trim(), "UTF-8")
        } catch (_: Exception) {
            raw.trim()
        }
        val lower = line.lowercase(Locale.US)
        val looksEngine =
            (lower.contains("google.") && (lower.contains("/search") || lower.contains("?q=") || lower.contains("&q="))) ||
                lower.contains("bing.com") ||
                lower.contains("duckduckgo.") ||
                lower.contains("search.yahoo") ||
                lower.contains("yahoo.com/search") ||
                lower.contains("yandex.") ||
                lower.contains("brave.com/search") ||
                lower.contains("ecosia.org") ||
                lower.contains("startpage.com") ||
                lower.contains("youtube.com/results") ||
                lower.contains("youtube.com") && lower.contains("search_query=")
        if (!looksEngine) return null

        val paramPatterns = listOf(
            Regex("[?&]search_query=([^&]+)"),
            Regex("[?&]q=([^&]+)"),
            Regex("[?&]p=([^&]+)"),
            Regex("[?&]query=([^&]+)"),
            Regex("[?&]oq=([^&]+)"),
            Regex("[?&]text=([^&]+)")
        )
        for (re in paramPatterns) {
            val m = re.find(lower) ?: continue
            val enc = m.groupValues.getOrNull(1) ?: continue
            val decoded = try {
                URLDecoder.decode(enc, "UTF-8").replace("+", " ").trim()
            } catch (_: Exception) {
                enc.replace("+", " ").trim()
            }
            if (decoded.isNotEmpty()) return decoded
        }
        return null
    }

    private fun isQueryBlocked(query: String): Boolean {
        val n = query.lowercase(Locale.US).replace(Regex("\\s+"), " ").trim()
        if (n.length < 2) return false
        for (p in BLOCKED_PHRASES) {
            if (p.length >= 2 && n.contains(p)) return true
        }
        return false
    }

    private fun maybeReportFlaggedSearch(
        query: String,
        sourcePackage: String,
        isPrivateBrowsing: Boolean
    ) {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val childId = prefs.getString("child_db_id", null)?.trim()?.toIntOrNull() ?: run {
            Log.w(TAG_SEARCH, "No child_db_id in kidora_prefs — open child app after linking")
            return
        }
        val base = prefs.getString("server_base_url", null)?.trim().orEmpty()
        if (base.isEmpty()) {
            Log.w(TAG_SEARCH, "No server_base_url in kidora_prefs")
            return
        }

        val bucketMs = if (isPrivateBrowsing) PRIVATE_DEDUP_MS else NORMAL_DEDUP_MS
        val timeBucket = System.currentTimeMillis() / bucketMs
        val sig = "${query.lowercase(Locale.US)}|private=$isPrivateBrowsing|$timeBucket"
        synchronized(reportLock) {
            if (sig == lastReportedSig) return
        }

        thread {
            try {
                val url = URL("${base.trimEnd('/')}/safety/report-flagged-search")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    doOutput = true
                    connectTimeout = 15000
                    readTimeout = 15000
                }
                val zone = ZoneId.systemDefault()
                val z = ZonedDateTime.now(zone)
                val dateFmt = DateTimeFormatter.ofPattern("EEEE, MMMM d, yyyy", Locale.US)
                val timeFmt = DateTimeFormatter.ofPattern("HH:mm:ss", Locale.US)

                val body = JSONObject()
                body.put("child_id", childId)
                body.put("query", query.take(500))
                body.put("source_package", sourcePackage.take(200))
                body.put("device_local_date", z.format(dateFmt))
                body.put("device_local_time", z.format(timeFmt))
                body.put("device_timezone", zone.id)
                body.put("occurred_at", z.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME))
                body.put("is_private_browsing", isPrivateBrowsing)

                OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(body.toString()) }
                val code = conn.responseCode
                val errBody = if (code !in 200..299) {
                    try {
                        val stream = conn.errorStream ?: conn.inputStream
                        BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { it.readText() }
                            .take(600)
                    } catch (_: Exception) {
                        ""
                    }
                } else ""
                conn.disconnect()

                if (code in 200..299) {
                    synchronized(reportLock) {
                        lastReportedSig = sig
                    }
                    getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                        .putString("last_safety_sig", sig)
                        .apply()
                    Log.i(
                        TAG_SEARCH,
                        "Reported ${if (isPrivateBrowsing) "private" else "flagged"} search (HTTP $code)"
                    )
                } else {
                    Log.w(TAG_SEARCH, "Report failed HTTP $code — $errBody")
                }
            } catch (e: Exception) {
                Log.e(TAG_SEARCH, "HTTP report error", e)
            }
        }
    }

    override fun onInterrupt() {}

    companion object {
        private const val PREFS = "kidora_prefs"
        private const val TAG_BLOCK = "BLOCK_DEBUG"
        private const val TAG_SEARCH = "SEARCH_SAFETY"
        private const val SEARCH_DEBOUNCE_MS = 450L
        private const val SEARCH_DEBOUNCE_FAST_MS = 150L
        private const val NORMAL_DEDUP_MS = 3_600_000L
        private const val PRIVATE_DEDUP_MS = 120_000L

        private val PRIVATE_SESSION_MARKERS = listOf(
            "incognito",
            "inprivate",
            "private tab",
            "private browsing",
            "secret mode",
            "secret tab",
            "you've gone incognito",
            "won't save your activity"
        )

        private val reportLock = Any()
        @Volatile
        private var lastReportedSig: String? = null

        /** Single token like google.com — not treated as a typed search query. */
        private val DOMAIN_LIKE = Regex("^[a-z0-9.-]+\\.[a-z]{2,24}$", RegexOption.IGNORE_CASE)

        /** Keep in sync with kidora_backend/routes/safetyAlerts.js DEFAULT_BLOCKED_PHRASES */
        private val BLOCKED_PHRASES = listOf(
            "porn",
            "xxx",
            "nude",
            "nsfw",
            "sex video",
            "erotic",
            "escort",
            "onlyfans",
            "hentai",
            "cocaine",
            "heroin",
            "meth",
            "buy drugs",
            "suicide",
            "kill myself",
            "how to bomb",
            "make a bomb",
            "terrorist",
            "child abuse",
            "vape",
            "weed",
            "weed vape",
            "weed vape pen",
            "weed vape pen battery",
            "weed vape pen cartridge",
            "weed vape pen cartridge battery",
            "ciggarates",
            "cigarettes"
        ).map { it.lowercase(Locale.US) }
    }
}
