package com.madar.dawam

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * On-shift location pings that survive the app (CL-4).
 *
 * A location foreground service with its notification, from clock-in to
 * clock-out. It keeps running when the app is swiped away, the OS restarts
 * it if it is killed (START_STICKY), and [DawamBootReceiver] starts it again
 * after the phone restarts. It has no UI: each fix (one per 15 minutes) goes
 * to `dawamTrackingMain` in `lib/background.dart`, run in an engine of its
 * own, which pings through the same madar-core as the app — queued offline,
 * dated from the server's signed time. The core answers whether the person is
 * still on shift; when not, the service stops (CL-17). The notification's
 * words come from the app in its language (APP-4) and are kept for a restart.
 */
class DawamTrackingService : Service(), LocationListener {
    companion object {
        private const val PREFS = "dawam_tracking"
        private const val CHANNEL_ID = "dawam_tracking"
        private const val NOTIFICATION_ID = 4711
        private const val BG_CHANNEL = "com.madar.dawam/tracking.background"

        /** One fix goes to the core per this long (the server wants 15 minutes). */
        private const val PING_EVERY_MS = 14 * 60_000L
        private const val ASK_EVERY_MS = 5 * 60_000L

        private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun isOn(ctx: Context): Boolean = prefs(ctx).getBoolean("on", false)

        fun start(ctx: Context, title: String?, text: String?) {
            val edit = prefs(ctx).edit().putBoolean("on", true)
            if (!title.isNullOrBlank()) edit.putString("title", title)
            if (!text.isNullOrBlank()) edit.putString("text", text)
            edit.apply()
            val intent = Intent(ctx, DawamTrackingService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(intent)
                } else {
                    ctx.startService(intent)
                }
            } catch (e: Exception) {
                // Not allowed right now (no background location): the app
                // still pings while it is open, and the shift reads
                // "tracking off" to the manager if the pings stop.
            }
        }

        fun stop(ctx: Context) {
            prefs(ctx).edit().putBoolean("on", false).apply()
            ctx.stopService(Intent(ctx, DawamTrackingService::class.java))
        }
    }

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private var pending: Map<String, Any?>? = null
    private var lastSent = 0L
    private var listening = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isOn(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!inForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }
        listen()
        return START_STICKY
    }

    /** The notification says why the location is used (APP-4, AT-5). */
    private fun inForeground(): Boolean {
        val p = prefs(this)
        val title = p.getString("title", null) ?: "Dawam · دوام"
        val text = p.getString("text", null) ?: "On shift · في الوردية"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, title, NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        val n = builder
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
            true
        } catch (e: Exception) {
            false // no location permission for a background start
        }
    }

    private fun listen() {
        if (listening) return
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED
        ) {
            stopSelf()
            return
        }
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            try {
                if (lm.isProviderEnabled(provider)) {
                    lm.requestLocationUpdates(provider, ASK_EVERY_MS, 0f, this, Looper.getMainLooper())
                    listening = true
                }
            } catch (e: SecurityException) {
                // permission withdrawn meanwhile
            } catch (e: IllegalArgumentException) {
                // no such provider on this phone
            }
        }
        if (!listening) return
        // Right after a restart: ask the core at once whether the shift is
        // still on, from a recent fix if there is one.
        try {
            val last = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            if (last != null && ageMs(last) < 2 * 60_000L) onLocationChanged(last)
        } catch (e: SecurityException) {
            // nothing known
        }
    }

    private fun ageMs(l: Location): Long =
        (SystemClock.elapsedRealtimeNanos() - l.elapsedRealtimeNanos) / 1_000_000L

    override fun onLocationChanged(location: Location) {
        val now = SystemClock.elapsedRealtime()
        if (lastSent != 0L && now - lastSent < PING_EVERY_MS) return
        lastSent = now
        val fix = mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
            "mock" to isMock(location),
            "time" to iso(location.time),
            "battery" to battery(),
        )
        if (ready) send(fix) else {
            pending = fix
            ensureEngine()
        }
    }

    @Suppress("DEPRECATION")
    private fun isMock(l: Location): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) l.isMock else l.isFromMockProvider

    private fun battery(): Int? {
        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager ?: return null
        val v = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (v in 0..100) v else null
    }

    private fun iso(ms: Long): String {
        val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        f.timeZone = TimeZone.getTimeZone("UTC")
        return f.format(Date(ms))
    }

    private fun send(fix: Map<String, Any?>) {
        channel?.invokeMethod(
            "fix",
            fix,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // The core says the shift is over (or nobody is signed in).
                    if (result == false) stop(this@DawamTrackingService)
                }

                override fun error(code: String, message: String?, details: Any?) {}

                override fun notImplemented() {}
            },
        )
    }

    /** The headless engine running `dawamTrackingMain` (lib/background.dart). */
    private fun ensureEngine() {
        if (engine != null) return
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val e = FlutterEngine(applicationContext)
        channel = MethodChannel(e.dartExecutor.binaryMessenger, BG_CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "ready") {
                    ready = true
                    result.success(null)
                    pending?.let { fix ->
                        pending = null
                        send(fix)
                    }
                } else {
                    result.notImplemented()
                }
            }
        }
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:madar_staff/background.dart",
                "dawamTrackingMain",
            ),
        )
        engine = e
    }

    override fun onDestroy() {
        try {
            (getSystemService(Context.LOCATION_SERVICE) as LocationManager).removeUpdates(this)
        } catch (e: Exception) {
            // already gone
        }
        listening = false
        ready = false
        channel = null
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    // Abstract before API 30: implemented so older phones don't crash.
    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    override fun onProviderEnabled(provider: String) {}

    override fun onProviderDisabled(provider: String) {}
}
