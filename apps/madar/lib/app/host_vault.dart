import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Host-side persistence — NON-SECRET UI prefs only (theme, locale, the
/// landscape flip). Session durability moved INTO the core (`session:blob`
/// in its SQLite, plain by design): OS file-based encryption, token expiry,
/// and server-side revocation carry the at-rest story, and an attacker who
/// can read app-private storage can read process memory anyway. That call
/// removed flutter_secure_storage entirely.
class HostVault {
  HostVault._(this._prefs);

  final SharedPreferences _prefs;

  /// Open the prefs store.
  static Future<HostVault> open() async {
    return HostVault._(await SharedPreferences.getInstance());
  }

  /// UI theme preference: 'light' (default, matching the natives) or 'dark'.
  String get themeMode => _prefs.getString('madar.theme') ?? 'light';
  set themeMode(String value) {
    unawaited(_prefs.setString('madar.theme', value));
  }

  /// Animations setting: 'full' (default), 'reduced' or 'system'.
  String get motion => _prefs.getString('madar.motion') ?? 'full';
  set motion(String value) {
    unawaited(_prefs.setString('madar.motion', value));
  }

  /// Sell screen layout on a tablet: 'standard' (default) or 'legacy'.
  String get sellLayout => _prefs.getString('madar.sell_layout') ?? 'standard';
  set sellLayout(String value) {
    unawaited(_prefs.setString('madar.sell_layout', value));
  }

  /// Last chosen locale ('' = follow the core's default).
  String get locale => _prefs.getString('madar.locale') ?? '';
  set locale(String value) {
    unawaited(_prefs.setString('madar.locale', value));
  }

  /// Tablet landscape-flip choice (true = landscapeRight, the default).
  bool get landscapeRight => _prefs.getBool('madar.landscape_right') ?? true;
  set landscapeRight(bool value) {
    unawaited(_prefs.setBool('madar.landscape_right', value));
  }

  /// Orientation lock: 'device' (default — follow device class), 'portrait'
  /// or 'landscape'. Stored as a plain string (not an index) so the Android
  /// side can read it without knowing this enum's Dart layout — see
  /// `MainActivity.kt`, which reads the SAME `flutter.madar.orientation_mode`
  /// key out of the `FlutterSharedPreferences` file directly, before Flutter
  /// ever starts, to pick the launch orientation with no rotate flash.
  String get orientationMode =>
      _prefs.getString('madar.orientation_mode') ?? 'device';
  set orientationMode(String value) {
    unawaited(_prefs.setString('madar.orientation_mode', value));
  }

  /// Tablet-vs-phone diagonal-inch cutoff for the orientation lock —
  /// user-adjustable in Settings for devices whose reported density
  /// misclassifies them (see [OrientationController]).
  double get tabletThresholdInches =>
      _prefs.getDouble('madar.tablet_threshold_inches') ??
      OrientationController.defaultTabletThresholdInches;
  set tabletThresholdInches(double value) {
    unawaited(_prefs.setDouble('madar.tablet_threshold_inches', value));
  }
}
