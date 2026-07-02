import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rust_bridge/rust_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Host-side persistence: the core's opaque session blob in the platform
/// secure store (Keychain / EncryptedSharedPreferences), plus non-secret
/// UI prefs. Mirrors the natives' HostVault — the host never inspects the
/// blob; token custody stays in the core.
class HostVault {
  HostVault._(this._prefs);

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _blobKey = 'madar.session.blob';

  final SharedPreferences _prefs;

  static Future<HostVault> open() async {
    return HostVault._(await SharedPreferences.getInstance());
  }

  /// The persisted session blob, or null if signed out / first run.
  Future<List<int>?> readBlob() async {
    final b64 = await _secure.read(key: _blobKey);
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } on FormatException {
      // A corrupt blob must not brick the app — treat as signed out.
      await _secure.delete(key: _blobKey);
      return null;
    }
  }

  /// Apply a core vault command IMMEDIATELY — durability of offline
  /// sign-in depends on it (no debounce).
  Future<void> apply(VaultCommand command) => switch (command) {
    VaultCommand_Save(:final blob) => _secure.write(
      key: _blobKey,
      value: base64Encode(blob),
    ),
    VaultCommand_Clear() => _secure.delete(key: _blobKey),
  };

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
}
