import 'dart:async';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_core/staff_core.dart';

/// Backend base URL — for when the core's staff API replaces the mock
/// store. Override with `--dart-define=MADAR_API=http://192.168.1.10:8082`.
const _apiBase = String.fromEnvironment(
  'MADAR_API',
  defaultValue: 'https://api.madar-pos.cloud',
);
const _environment = String.fromEnvironment('MADAR_ENV', defaultValue: 'prod');

/// Starts madar-core through the staff bridge — its own SQLite store, apart
/// from the POS and dashboard — and returns the root overrides: the core's
/// words, and the language and theme hooks that write through to the core
/// and the prefs store under the POS's own keys (`madar.locale`,
/// `madar.theme`). The `readyScopeOverrides` pattern of apps/madar.
Future<List<Override>> boot() async {
  final prefs = await SharedPreferences.getInstance();
  final dir = await getApplicationSupportDirectory();
  final saved = prefs.getString('madar.locale') ?? '';
  final core = await MadarCore.start(
    config: MadarConfig(
      baseUrl: _apiBase,
      environment: _environment,
      dbPath: '${dir.path}${Platform.pathSeparator}madar_staff.db',
      locale: saved.isEmpty ? 'ar' : saved, // Arabic first (APP-4)
    ),
  );
  words = (key) => core.bridge.tr(key: key);
  final lang = core.bridge.locale().startsWith('ar') ? 'ar' : 'en';
  return [
    localeProvider.overrideWith(() => LocaleNotifier(initial: lang)),
    localePersisterProvider.overrideWithValue((l) {
      core.bridge.setLocale(locale: l);
      unawaited(prefs.setString('madar.locale', l));
    }),
    themeChoiceProvider.overrideWith(
      () => ThemeChoiceNotifier(
        initial: ThemeChoice.parse(prefs.getString('madar.theme')),
      ),
    ),
    themeChoicePersisterProvider.overrideWithValue(
      (c) => unawaited(prefs.setString('madar.theme', c.name)),
    ),
  ];
}
