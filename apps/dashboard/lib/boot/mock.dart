/// Mock mode (`--dart-define=MADAR_MOCK=1`): the whole app on the in-memory
/// mock backend — the seed (Sabah Coffee and Nakhla Bakery), the core's and
/// every area's handlers — signed in as the seed's owner, so it runs with no
/// backend at all. Signing out leads to the sign-in page, where any persona
/// signs in with the seed's password.
library;

import 'dart:io';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart';

import '../areas.dart';
import '../data/core_xlsx.dart';
import '../real/files.dart';
import '../real/outside.dart';
import '../real/preferences.dart';

/// A little latency, so loading states show as they would.
const Duration mockLatency = Duration(milliseconds: 120);

Future<ProviderContainer> bootMock() async {
  ensureTimeZones();
  final dir = await getApplicationSupportDirectory();
  final sep = Platform.pathSeparator;
  final prefs = await FilePreferences.open(
    File('${dir.path}${sep}madar_dashboard_mock_prefs.json'),
  );
  final strings = await loadDashStrings(areas: dashboardAreas);

  final db = MockDb.seeded();
  final server = MockServer(clock: db.clock, latency: mockLatency);
  registerCoreMocks(server, db);
  for (final a in dashboardAreas) {
    a.registerMocks?.call(server, db);
  }
  final session = MockSessionGateway(server, signedInAs: Persona.owner);

  // Excel through the core when its library loads (it needs no backend);
  // otherwise the recording gateway, which writes the spec as JSON.
  ExportGateway exports;
  try {
    await MadarCore.start(
      config: MadarConfig(
        baseUrl: 'http://127.0.0.1:9',
        environment: 'mock',
        dbPath: '${dir.path}${sep}madar_dashboard_mock.db',
        locale: 'en',
      ),
    );
    exports = const CoreExportGateway(logo: exportLogo);
  } on Object {
    exports = RecordingExportGateway();
  }

  final container = ProviderContainer(
    // The web's retry policy (queryRetry): never a refusal, a 429 thrice.
    retry: webRetry,
    overrides: [
      dashAreasProvider.overrideWithValue(dashboardAreas),
      stringsProvider.overrideWithValue(strings),
      preferencesProvider.overrideWithValue(prefs),
      sessionGatewayProvider.overrideWithValue(session),
      transportProvider.overrideWith(
        (ref) => SessionGuardTransport(
          session.transport,
          onUnauthorized: () =>
              ref.read(sessionProvider.notifier).handleUnauthorized(),
          signedIn: () => ref.read(currentSessionProvider) != null,
        ),
      ),
      clockProvider.overrideWithValue(() => db.clock.now),
      realtimeGatewayProvider.overrideWithValue(
        TransportRealtimeGateway(session.transport),
      ),
      exportGatewayProvider.overrideWithValue(exports),
      fileGatewayProvider.overrideWithValue(const PlatformFileGateway()),
      linkOpenerProvider.overrideWithValue(openExternal),
    ],
  );
  await container.read(sessionProvider.future);
  return container;
}
