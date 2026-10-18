package com.madar.madar_dashboard

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        highRefresh.start()
    }

    // Run at the display's highest refresh rate (same resolution); see HighRefreshRate.
    private val highRefresh = HighRefreshRate(this)

    override fun onResume() {
        super.onResume()
        highRefresh.apply()
    }

    override fun onDestroy() {
        highRefresh.stop()
        super.onDestroy()
    }
}
