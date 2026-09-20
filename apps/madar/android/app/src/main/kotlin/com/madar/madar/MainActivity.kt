package com.madar.madar

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val btPrinter = BtPrinter()

    // Orientation-on-launch, no flash: `OrientationController` (Dart,
    // app_core/src/orientation.dart) only gets to call
    // SystemChrome.setPreferredOrientations() once the engine has started and
    // Dart has run — by then the Activity's first frame has *already* been
    // measured and laid out at whatever orientation Android picked at
    // process start, so a wrong initial guess shows as a visible rotation a
    // few hundred ms into boot. The fix has to happen before that first
    // layout pass: `setRequestedOrientation` as literally the first line of
    // `onCreate`, before `super.onCreate()` ever creates the Flutter view.
    //
    // This reads the SAME persisted preference the Dart side writes
    // (`HostVault.orientationMode` / `.landscapeRight`,
    // apps/madar/lib/app/host_vault.dart) directly out of the
    // `shared_preferences` plugin's own SharedPreferences file — no Flutter
    // channel, no engine, nothing async. `shared_preferences` (Android)
    // stores every key under the `FlutterSharedPreferences` file with a
    // `flutter.` prefix, which is why the keys below are prefixed that way.
    override fun onCreate(savedInstanceState: Bundle?) {
        requestedOrientation = resolveLaunchOrientation()
        super.onCreate(savedInstanceState)
    }

    private fun resolveLaunchOrientation(): Int {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val mode = prefs.getString("flutter.madar.orientation_mode", "device")
        val landscapeRight = prefs.getBoolean("flutter.madar.landscape_right", true)

        return when (mode) {
            "portrait" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            "landscape" ->
                // Accept either landscape side once launched (matches the
                // Dart-side lock, which lists both) — the persisted flip only
                // decides which one Android tries first.
                if (landscapeRight) {
                    ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
                } else {
                    ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                }
            else -> {
                if (isTablet(readThresholdInches(prefs))) {
                    ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
                } else {
                    ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
            }
        }
    }

    // `shared_preferences` (the legacy, file-backed API `HostVault` uses)
    // stores a Dart `double` as a STRING on Android, prefixed with a fixed
    // base64 marker (`DOUBLE_PREFIX` in the plugin) rather than as a raw
    // float preference entry — reading it with `getFloat` would throw
    // (ClassCastException: the underlying value is a String). Strip the
    // marker and parse; any surprise (a future plugin version, a missing
    // key) falls back to the same default the Dart side uses.
    private fun readThresholdInches(prefs: android.content.SharedPreferences): Double {
        val raw = prefs.getString("flutter.madar.tablet_threshold_inches", null)
            ?: return DEFAULT_TABLET_THRESHOLD_INCHES.toDouble()
        return raw.removePrefix(DOUBLE_PREFIX).toDoubleOrNull()
            ?: DEFAULT_TABLET_THRESHOLD_INCHES.toDouble()
    }

    // Mirrors `OrientationController.diagonalInches` (Dart): a full-diagonal
    // check on the mdpi (160dp/in) baseline, not a shortest-side dp cutoff —
    // the Material `sw600dp` convention misreads small, low-aspect-ratio
    // tablets whose reported density inflates devicePixelRatio. `resources`
    // is available pre-`super.onCreate()`, so this needs no Flutter view.
    //
    // Belt-and-braces: some real tablets under-report their diagonal this
    // way too (a device tested during this feature's build came in at ~6.5"
    // by this formula despite `ro.build.characteristics=tablet`), so a
    // `screenLayout` size bucket of LARGE/XLARGE — Android's own, OEM-set
    // form-factor classification, not a raw pixel computation — also counts
    // as a tablet even under the diagonal cutoff.
    private fun isTablet(thresholdInches: Double): Boolean {
        val metrics = resources.displayMetrics
        val widthDp = metrics.widthPixels / (metrics.densityDpi / 160.0)
        val heightDp = metrics.heightPixels / (metrics.densityDpi / 160.0)
        val diagonalInches = sqrt(widthDp * widthDp + heightDp * heightDp) / 160.0
        if (diagonalInches >= thresholdInches) return true

        val sizeBucket = resources.configuration.screenLayout and
            Configuration.SCREENLAYOUT_SIZE_MASK
        return sizeBucket == Configuration.SCREENLAYOUT_SIZE_LARGE ||
            sizeBucket == Configuration.SCREENLAYOUT_SIZE_XLARGE
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Native Classic/SPP printer bridge — robust RFCOMM connect + CoD-filtered
        // paired-device listing (see BtPrinter for why the plugin wasn't enough).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BtPrinter.CHANNEL)
            .setMethodCallHandler { call, result -> btPrinter.handle(call, result) }
    }

    private companion object {
        const val DEFAULT_TABLET_THRESHOLD_INCHES = 7f
        // The `shared_preferences_android` plugin's own marker for a
        // Dart double stored via the legacy (file-backed) API — see
        // `readThresholdInches`. Copied verbatim from the plugin's
        // `SharedPreferencesPlugin.DOUBLE_PREFIX` (base64 of
        // "This is the prefix for Double."); it's a plugin implementation
        // detail with no public constant to import here.
        const val DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"
    }
}
