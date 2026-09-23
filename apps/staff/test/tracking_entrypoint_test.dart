// E2E bug S3 (Youssef, EN, Pixel 7 AVD): on shift for over an hour, the
// server got no location ping at all. The native service
// (DawamTrackingService.kt) starts `dawamTrackingMain` from
// `package:madar_staff/background.dart` by name, but nothing in the app's
// program imported that library, so the build left it out and the service's
// engine had nothing to run (CL-4, and with it CL-6/8/9/12 on Android).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main,
      contains(
        "export 'package:madar_staff/background.dart' show dawamTrackingMain;",
      ),
    );
  });
}
