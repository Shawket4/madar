/// The frame's per-device choices: the theme (`madar.theme`, the web's
/// `lib/theme.ts`), whether the sidebar is folded to icons (the web's
/// `sidebarCollapsed`), and the door out to the browser (legal links).
library;

import 'package:dashboard_core/src/gateways/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `light` / `dark` / `system`, as the web stores it.
enum ThemePref {
  light,
  dark,
  system;

  static ThemePref? fromWire(String? v) {
    for (final p in values) {
      if (p.name == v) return p;
    }
    return null;
  }

  /// The i18n key of its label (`theme.light`).
  String get labelKey => 'theme.$name';

  String get fallback => switch (this) {
    light => 'Light',
    dark => 'Dark',
    system => 'System',
  };

  /// The web's Lucide glyph (Sun / Moon / Monitor).
  String get icon => switch (this) {
    light => 'sun',
    dark => 'moon',
    system => 'monitor',
  };

  ThemeMode get mode => switch (this) {
    light => ThemeMode.light,
    dark => ThemeMode.dark,
    system => ThemeMode.system,
  };
}

/// The web's `STORAGE_KEY`.
const String themePrefKey = 'madar.theme';

/// Whether the wide sidebar is folded to its icon rail.
const String sidebarPrefKey = 'madar.sidebar.collapsed';

/// The theme choice; the web defaults to following the system.
class ThemePrefNotifier extends Notifier<ThemePref> {
  @override
  ThemePref build() =>
      ThemePref.fromWire(
        ref.watch(preferencesProvider).getString(themePrefKey),
      ) ??
      ThemePref.system;

  Future<void> set(ThemePref pref) async {
    state = pref;
    await ref.read(preferencesProvider).setString(themePrefKey, pref.name);
  }
}

final themePrefProvider = NotifierProvider<ThemePrefNotifier, ThemePref>(
  ThemePrefNotifier.new,
);

class SidebarCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(preferencesProvider).getString(sidebarPrefKey) == 'true';

  Future<void> toggle() => set(!state);

  Future<void> set(bool collapsed) async {
    state = collapsed;
    await ref
        .read(preferencesProvider)
        .setString(sidebarPrefKey, collapsed ? 'true' : null);
  }
}

final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedNotifier, bool>(
      SidebarCollapsedNotifier.new,
    );

/// Opens a web address outside the app (the legal documents). The app
/// overrides it with the platform's browser; tests record.
final linkOpenerProvider = Provider<Future<void> Function(Uri uri)>(
  (ref) => (_) async {},
);

/// The public legal documents (`src/config/legal.ts`).
abstract final class LegalUrls {
  static const String base = 'https://legal.madar-pos.cloud';
  static final Uri privacy = Uri.parse('$base/privacy-policy.html');
  static final Uri terms = Uri.parse('$base/terms-of-service.html');
}
