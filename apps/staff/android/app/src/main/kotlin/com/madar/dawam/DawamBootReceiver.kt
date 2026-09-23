package com.madar.dawam

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * The phone restarted (or the app was updated) while someone was on shift:
 * the location service starts again without anyone opening the app (CL-4).
 * The core decides from its own records whether they are still on shift;
 * when they are not, the service stops itself after the first fix.
 */
class DawamBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                if (DawamTrackingService.isOn(context)) {
                    DawamTrackingService.start(context, null, null)
                }
            }
        }
    }
}
