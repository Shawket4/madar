// The Android location service's own engine (CL-4).
//
// `DawamTrackingService` (android/…/DawamTrackingService.kt) is a location
// foreground service that keeps running when the app is closed, and starts
// again after the phone restarts while someone is on shift. It has no UI, so
// it starts this entry point in an engine of its own and hands it each fix.
// Both engines live in one process and share ONE core over the one store
// (the staff bridge keeps one core per store), so a ping taken here goes
// into the same outbox, queued offline like any other and dated from the
// server's signed time (CL-10, CL-11). The core decides whether the person
// is still on shift; when they are not, the service stops (CL-17).
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:madar_staff/boot.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

const _channel = MethodChannel('com.madar.dawam/tracking.background');

@pragma('vm:entry-point')
Future<void> dawamTrackingMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final core = await startCore();
  final bridge = core.bridge;
  // The app may already be up in this process (same core): never re-restore
  // a live session, which would reset its connectivity.
  if (!bridge.isAuthenticated()) bridge.restoreSessionCached();
  _channel.setMethodCallHandler((call) async {
    if (call.method != 'fix') return null;
    return onShiftAfter(
      bridge,
      (call.arguments as Map).cast<String, Object?>(),
    );
  });
  await _channel.invokeMethod<void>('ready');
}

/// Ping with one fix from the service; whether the person is still on
/// shift (false stops the service). A refusal or no signal is not "off
/// shift": the ping is queued by the core and the service goes on.
Future<bool> onShiftAfter(MadarBridge bridge, Map<String, Object?> fix) async {
  try {
    final snap = await bridge.dawamPing(
      latitude: (fix['latitude']! as num).toDouble(),
      longitude: (fix['longitude']! as num).toDouble(),
      accuracy: (fix['accuracy'] as num?)?.toDouble(),
      mock: fix['mock'] == true,
      gpsTime: fix['time'] as String?,
      battery: (fix['battery'] as num?)?.toInt(),
    );
    final v = jsonDecode(snap) as Map<String, dynamic>;
    return v['active_shift'] != null;
  } on MadarError catch (e) {
    // Signed out (or this phone was): nobody to track.
    return e is! MadarError_Unauthenticated;
  } on Object {
    return true;
  }
}
