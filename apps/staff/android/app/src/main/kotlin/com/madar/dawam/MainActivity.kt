package com.madar.dawam

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // On shift or not (CL-4, CL-17): the app starts and stops the native
        // location service, with its notification in the app's language.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.madar.dawam/tracking")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        DawamTrackingService.start(
                            this,
                            call.argument<String>("title"),
                            call.argument<String>("text"),
                        )
                        result.success(null)
                    }
                    "stop" -> {
                        DawamTrackingService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
