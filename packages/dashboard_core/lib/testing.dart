// Test support: imported from tests only (flutter_test is a dev dependency).
// ignore_for_file: depend_on_referenced_packages

/// [DashHarness]: drive the whole dashboard app — router, frame, gates and
/// every area's pages — on the mock server, at phone/tablet/desktop sizes, in
/// English and Arabic, light and dark, and write screenshots to FDASH_SHOTS.
library;

export 'package:dashboard_kit/testing.dart'
    show DashSize, captureShot, dashShotsDir, loadDashFonts;

export 'src/testing/harness.dart';
