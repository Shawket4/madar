package com.madar.madar

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val btPrinter = BtPrinter()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Native Classic/SPP printer bridge — robust RFCOMM connect + CoD-filtered
        // paired-device listing (see BtPrinter for why the plugin wasn't enough).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BtPrinter.CHANNEL)
            .setMethodCallHandler { call, result -> btPrinter.handle(call, result) }
    }
}
