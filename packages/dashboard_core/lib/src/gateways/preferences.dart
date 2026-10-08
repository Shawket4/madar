/// Per-device preferences (the web's localStorage): the language, the scope
/// last used, the remembered authz answer.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads are synchronous (the app loads the store once at boot); writes are
/// asynchronous and may fail quietly: a preference is a convenience, never
/// state that must survive.
abstract interface class PreferencesGateway {
  String? getString(String key);

  /// Stores [value]; null removes the key.
  Future<void> setString(String key, String? value);
}

extension PreferencesJson on PreferencesGateway {
  /// The JSON value under [key], or null when absent or unreadable.
  Object? getJson(String key) {
    final raw = getString(key);
    if (raw == null) return null;
    try {
      return json.decode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> setJson(String key, Object? value) =>
      setString(key, value == null ? null : json.encode(value));
}

/// The device's preferences. The app overrides it (shared preferences); tests
/// use `MemoryPreferences` from package:dashboard_core/mock.dart.
final preferencesProvider = Provider<PreferencesGateway>(
  (ref) => throw StateError('preferencesProvider must be overridden at boot'),
);
