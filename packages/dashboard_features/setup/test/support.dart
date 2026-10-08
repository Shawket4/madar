// Shared set-up for the setup area's tests: the whole app (router, frame,
// gates) with this area's pages and mocks, through DashHarness.
//
// ALWAYS pump through [pumpSetup] (or pass [setupTestArea] yourself): inside
// this package's own tests its assets are not under `packages/dashboard_setup/`,
// so the real `setupArea`'s supplement keys would not load and every
// supplement word would fail the harness as missing.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/dashboard_setup.dart';
import 'package:flutter_test/flutter_test.dart';

/// [setupArea] as this package's own tests load it: the same pages and
/// mocks, the supplement tables by their unprefixed keys.
final DashArea setupTestArea = DashArea(
  key: setupArea.key,
  routes: setupArea.routes,
  registerMocks: setupArea.registerMocks,
  i18nSupplements: [
    for (final k in setupArea.i18nSupplements)
      k.replaceFirst('packages/dashboard_setup/', ''),
  ],
);

/// The app at [path] with the setup area on the mock server. Screenshots go
/// to `<FDASH_SHOTS>/setup/<page>/…`.
Future<DashHarness> pumpSetup(
  WidgetTester tester, {
  String path = '/settings',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  MockClock? clock,
  Map<String, String>? prefs,
}) => DashHarness.pump(
  tester,
  areas: [setupTestArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  clock: clock,
  prefs: prefs,
  shotArea: 'setup',
);

/// A seeded server with the core's and this area's mocks, for a test that
/// must hold, fail or inspect a route before the page opens:
///
/// ```dart
/// final m = setupMockServer();
/// final gate = m.server.hold('GET', '/delivery/settings');
/// final h = await pumpSetup(tester, path: '/settings/delivery',
///     server: m.server, db: m.db);
/// ```
({MockServer server, MockDb db}) setupMockServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerSetupMocks(server, db);
  return (server: server, db: db);
}
