// The phone's own tracking engine, with no UI (CL-4).
//
// Android: `DawamTrackingService` (android/…/DawamTrackingService.kt) is a
// location foreground service that keeps running when the app is closed, and
// starts again after the phone restarts while someone is on shift.
// iOS: `DawamTracker` (ios/Runner/AppDelegate.swift) starts it when a
// location event wakes the app with no UI engine listening (a relaunch by
// the branch's fence or a significant move, or its 14-minute reading while
// the app runs in the background with no screen).
// Either host starts this entry point in an engine of its own and hands it
// each fix. Both engines live in one process and share ONE core over the one
// store (the staff bridge keeps one core per store), so a ping taken here
// goes into the same outbox, queued offline like any other and dated from the
// server's signed time (CL-10, CL-11). The core decides whether the person
// is still on shift; when they are not, the host stops tracking (CL-17).
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:madar_staff/boot.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';
import 'package:staff_core/staff_core.dart';

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

/// Ping with one fix from the host; whether the person is still on shift
/// (false stops the host's tracking). A refusal or no signal is not "off
/// shift": the ping is queued by the core and the host goes on.
///
/// Android sends the fix's own time (`time`, sent as GPS time). iOS sends
/// none (the phone's clock, CL-11), but why the reading was taken (`wake`,
/// only logged: the ping has no field for it) and how long the host kept it
/// (`age_s`): one kept longer than a fresh reading is not where the person
/// is now, and is not sent, as in the app ([DawamStore.wakeFix]).
Future<bool> onShiftAfter(MadarBridge bridge, Map<String, Object?> fix) async {
  final age = Duration(seconds: (fix['age_s'] as num?)?.round() ?? 0);
  final wake = fix['wake'] as String?;
  if (age > DawamStore.wakeFresh) {
    debugPrint('dawam: a $wake reading ${age.inMinutes} min old is not sent');
    return true;
  }
  if (wake != null) debugPrint('dawam: ping ($wake, no UI)');
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
