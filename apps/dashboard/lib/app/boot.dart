import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart';

import '../i18n/strings.dart';

/// Backend base URL — override for dev with
/// `flutter run --dart-define=MADAR_API=http://192.168.1.10:8080`.
const _apiBase = String.fromEnvironment(
  'MADAR_API',
  defaultValue: 'https://api.madar-pos.cloud',
);
const _environment = String.fromEnvironment('MADAR_ENV', defaultValue: 'prod');

/// What a successful boot yields: the live core handle + loaded UI strings.
class BootData {
  const BootData({required this.core, required this.strings});

  final MadarCore core;
  final Strings strings;
}

/// Boot: load UI strings, start the core (its own SQLite store, independent of
/// the POS), and re-hydrate any persisted session before the UI reads it. Run
/// once in `main()` BEFORE runApp so the core can be installed as a ROOT-scope
/// override (nested-scope overrides aren't seen by root-mounted providers like
/// the router). No business logic here — the core owns networking, auth, i18n.
Future<BootData> bootDashboard() async {
  final strings = await Strings.load();
  final dir = await getApplicationSupportDirectory();
  final core = await MadarCore.start(
    config: MadarConfig(
      baseUrl: _apiBase,
      environment: _environment,
      dbPath: '${dir.path}${Platform.pathSeparator}madar_dashboard.db',
      locale: 'en',
    ),
  );
  core.bridge.restoreSessionCached();
  return BootData(core: core, strings: strings);
}
