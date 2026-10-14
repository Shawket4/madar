/// Real mode: the Rust core over the dashboard bridge. Every API call goes
/// through [CoreTransport] (the core adds the token, the org and branch
/// headers and the refresh, and words a refusal in the active language); the
/// session, realtime and Excel are the core's; preferences are a JSON file in
/// the app's support folder; files go through the platform's dialogs.
library;

import 'dart:async';
import 'dart:io';

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart';

import '../areas.dart';
import '../data/core_transport.dart';
import '../data/core_xlsx.dart';
import '../real/files.dart';
import '../real/outside.dart';
import '../real/preferences.dart';
import '../real/session.dart';

/// Backend base URL — override for dev with
/// `flutter run --dart-define=MADAR_API=http://localhost:8081`.
const String _apiBase = String.fromEnvironment(
  'MADAR_API',
  defaultValue: 'https://api.madar-pos.cloud',
);
const String _environment = String.fromEnvironment(
  'MADAR_ENV',
  defaultValue: 'prod',
);

/// Boots the core and returns the app's provider container, with the kept
/// session already restored.
Future<ProviderContainer> bootReal() async {
  final dir = await getApplicationSupportDirectory();
  final sep = Platform.pathSeparator;
  final prefs = await FilePreferences.open(
    File('${dir.path}${sep}madar_dashboard_prefs.json'),
  );
  final strings = await loadDashStrings(areas: dashboardAreas);
  final lang =
      prefs.getString(languagePrefKey) ??
      (Platform.localeName.toLowerCase().startsWith('ar') ? 'ar' : 'en');
  final core = await MadarCore.start(
    config: MadarConfig(
      baseUrl: _apiBase,
      environment: _environment,
      dbPath: '${dir.path}${sep}madar_dashboard.db',
      locale: lang,
    ),
  );
  // Every GET answer, for a relaunch with no network (wiped on sign-out), in
  // the core's own store.
  final offline = core.bridge.offlineCache(
    freshMs: kQueryStaleTime.inMilliseconds,
  );
  // What the Dart cache kept before the core took it over (salaries among
  // it) is never read again: gone.
  try {
    await Directory('${dir.path}${sep}offline_cache').delete(recursive: true);
  } on FileSystemException {
    // Never there, or gone already.
  }

  late final ProviderContainer container;
  // The web's own sentence for a coded refusal (`errors.codes.<CODE>`),
  // filled with the refusal's vars, when the tables have one.
  String? refusalWords(String code, Map<String, Object?> vars) {
    final t = container.read(tProvider);
    final key = 'errors.codes.$code';
    return t.exists(key) ? t(key, args: vars) : null;
  }

  final transport = CoreTransport.bridge(
    core.bridge,
    refusalWords: refusalWords,
  );
  container = ProviderContainer(
    // The web's retry policy (queryRetry): never a refusal, a 429 thrice.
    retry: webRetry,
    overrides: [
      dashAreasProvider.overrideWithValue(dashboardAreas),
      areaOpenersProvider.overrideWithValue(dashboardOpeners),
      stringsProvider.overrideWithValue(strings),
      preferencesProvider.overrideWithValue(prefs),
      sessionGatewayProvider.overrideWithValue(
        CoreSessionGateway(core.bridge, transport),
      ),
      offlineCacheProvider.overrideWithValue(offline),
      transportProvider.overrideWith((ref) => dashTransport(ref, transport)),
      realtimeGatewayProvider.overrideWithValue(CoreRealtimeGateway(transport)),
      exportGatewayProvider.overrideWithValue(
        const CoreExportGateway(logo: exportLogo),
      ),
      fileGatewayProvider.overrideWithValue(const PlatformFileGateway()),
      localeSinkProvider.overrideWithValue(
        (lang) => core.bridge.setLocale(locale: lang),
      ),
      linkOpenerProvider.overrideWithValue(openExternal),
    ],
  );
  core.bridge.setLocale(locale: container.read(localeProvider));
  await container.read(sessionProvider.future);
  _followPlan(container, core.bridge);
  return container;
}

/// Keeps [planFeaturesProvider] on the organisation's plan: what the core
/// holds at once (sign-in and the cached session carry it), then the server's
/// word (`/auth/me`), so an upgrade shows without signing in again. Signed
/// out, the plan is unknown and nothing is hidden. Best-effort: a failed read
/// keeps the last answer, and an unknown plan is Paid.
void _followPlan(ProviderContainer container, MadarBridge bridge) {
  void apply() {
    final signedIn = bridge.isAuthenticated();
    container
        .read(planFeaturesProvider.notifier)
        .set(signedIn ? bridge.entitlements().features.toSet() : null);
  }

  Future<void> refresh() async {
    apply();
    if (!bridge.isAuthenticated()) return;
    try {
      await bridge.refreshPlan();
    } on Object {
      // Offline: the last answer stands.
    }
    apply();
  }

  container.listen(sessionProvider, (_, _) => unawaited(refresh()));
  unawaited(refresh());
}
