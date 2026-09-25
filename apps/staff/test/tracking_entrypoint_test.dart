// E2E bug S3 (Youssef, EN, Pixel 7 AVD): on shift for over an hour, the
// server got no location ping at all. The native service
// (DawamTrackingService.kt) starts `dawamTrackingMain` from
// `package:madar_staff/background.dart` by name, but nothing in the app's
// program imported that library, so the build left it out and the service's
// engine had nothing to run (CL-4, and with it CL-6/8/9/12 on Android).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madar_staff/background.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';
// The app's own entry library must carry the entry point: this line does
// not compile if main.dart stops exporting it.
import 'package:madar_staff/main.dart' as app show dawamTrackingMain;

void main() {
  test('the service\'s entry point is part of the app\'s program', () {
    expect(app.dawamTrackingMain, isA<Function>());
    final kt = File(
      'android/app/src/main/kotlin/com/madar/dawam/DawamTrackingService.kt',
    ).readAsStringSync();
    // The names the service asks the engine for are the ones exported.
    expect(kt, contains('"package:madar_staff/background.dart"'));
    expect(kt, contains('"dawamTrackingMain"'));
    // iOS's headless engine asks for the same entry point, on the same
    // channel the entry point listens on.
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('"package:madar_staff/background.dart"'));
    expect(swift, contains('"dawamTrackingMain"'));
    expect(swift, contains('"com.madar.dawam/tracking.background"'));
    expect(
      File('lib/background.dart').readAsStringSync(),
      contains("MethodChannel('com.madar.dawam/tracking.background')"),
    );
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main,
      contains(
        "export 'package:madar_staff/background.dart' show dawamTrackingMain;",
      ),
    );
  });

  // The same entry point runs in iOS's headless engine (AppDelegate.swift's
  // DawamHeadlessFlutter) when a location event wakes the app with no UI:
  // iOS hands its readings without the fix's own time (the phone's clock,
  // CL-11), with why it was taken and how long it waited.
  group('a reading from either phone', () {
    test('Android: the fix time goes as GPS time, as before', () async {
      final bridge = _Bridge();
      final on = await onShiftAfter(bridge, {
        'latitude': 30.06,
        'longitude': 31.21,
        'accuracy': 12.5,
        'mock': false,
        'time': '2026-09-25T09:00:00.000Z',
        'battery': 64,
      });
      expect(on, isTrue);
      final p = bridge.pings.single.namedArguments;
      expect(p[#latitude], 30.06);
      expect(p[#longitude], 31.21);
      expect(p[#accuracy], 12.5);
      expect(p[#mock], false);
      expect(p[#gpsTime], '2026-09-25T09:00:00.000Z');
      expect(p[#battery], 64);
    });

    test(
      'iOS: no GPS time, and the wake reason does not reach the ping',
      () async {
        final bridge = _Bridge();
        await onShiftAfter(bridge, {
          'id': 'q1',
          'latitude': 30.07,
          'longitude': 31.22,
          'accuracy': 65.0,
          'wake': 'region_exit',
          'age_s': 20,
          'battery': 55,
        });
        final p = bridge.pings.single.namedArguments;
        expect(p[#gpsTime], isNull);
        expect(p[#battery], 55);
        expect(p[#mock], false);
      },
    );

    test(
      'iOS: a reading kept too long is not sent as where they are now',
      () async {
        final bridge = _Bridge();
        final on = await onShiftAfter(bridge, {
          'latitude': 30.07,
          'longitude': 31.22,
          'wake': 'significant_change',
          'age_s': 3600,
        });
        expect(bridge.pings, isEmpty);
        expect(on, isTrue, reason: 'not a sign the shift is over');
      },
    );

    test('off shift the host is told to stop', () async {
      final bridge = _Bridge()..answer = '{"active_shift": null}';
      expect(
        await onShiftAfter(bridge, {'latitude': 30.0, 'longitude': 31.0}),
        isFalse,
      );
    });
  });
}

/// The staff bridge, recording its pings.
class _Bridge implements MadarBridge {
  final pings = <Invocation>[];
  String answer = '{"active_shift": "s1"}';

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #dawamPing) {
      pings.add(i);
      return Future<String>.value(answer);
    }
    return super.noSuchMethod(i);
  }
}
