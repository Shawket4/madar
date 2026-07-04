import 'dart:async';

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
}
