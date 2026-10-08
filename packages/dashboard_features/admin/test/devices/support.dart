// Shared set-up for the Devices tests: the real app shell on the seeded mock
// server, with the admin area's Devices route.
//
// The area here carries only the Devices route, wired exactly as
// `lib/src/routes.dart` wires it (path, title, POS module), with the area's
// i18n supplements and the area seed + the Devices mocks: the other admin
// units are being built at the same time, and a half-written page of theirs
// must not stop these tests from compiling. `devices_wiring_test.dart` opens
// the page through the real `adminArea`.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/devices/devices_page.dart';
import 'package:dashboard_admin/src/mock/devices_mock.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

export 'package:dashboard_admin/src/mock/devices_mock.dart' show DevicesRoutes;

Widget _devices(BuildContext context, GoRouterState state) =>
    const DevicesPage();

void _mocks(MockServer server, MockDb db) {
  loadAdminSeed(db);
  registerDevicesMocks(server, db);
}

/// The admin area with its Devices route only.
const DashArea devicesArea = DashArea(
  key: 'admin',
  routes: [
    DashRoute(
      path: DevicesPage.path,
      builder: _devices,
      titleKey: 'nav.devices',
      titleFallback: 'Devices',
      module: OrgModule.pos,
    ),
  ],
  registerMocks: _mocks,
  i18nSupplements: [
    'packages/dashboard_admin/assets/i18n/en.json',
    'packages/dashboard_admin/assets/i18n/ar.json',
    'packages/dashboard_admin/assets/i18n/devices.en.json',
    'packages/dashboard_admin/assets/i18n/devices.ar.json',
  ],
);

/// `?branchId=` for [branchId].
String atBranch(String branchId) => '?branchId=$branchId';

/// Opens `/devices` + [query] as [persona].
Future<DashHarness> pumpDevices(
  WidgetTester tester, {
  String query = '',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  DevicesBackend? backend,
}) => DashHarness.pump(
  tester,
  areas: const [devicesArea],
  path: '/devices$query',
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: backend?.server,
  db: backend?.db,
);

/// A seeded server with the core's handlers, the area seed and the Devices
/// handlers, for a test that changes the data or the answers before the
/// page opens.
class DevicesBackend {
  DevicesBackend({Persona persona = Persona.owner}) {
    db = MockDb.seeded();
    server = MockServer(persona: persona, clock: db.clock);
    registerCoreMocks(server, db);
    _mocks(server, db);
  }

  late final MockDb db;
  late final MockServer server;

  MockTable get devices => db[AdminTables.devices];
  MockTable get codes => db[AdminTables.activationCodes];
  MockTable get clients => db[AdminTables.clientVersions];

  /// The typed API straight on the server (no app), for handler tests.
  DashboardApi get api => DashboardApi(server);
}

bool _keyed(Widget w, String prefix) =>
    w.key is ValueKey<String> &&
    (w.key! as ValueKey<String>).value.startsWith(prefix);

/// The device table's rows (one marker per row).
Finder deviceRows() => find.byWidgetPredicate((w) => _keyed(w, 'device-row-'));

/// The activation code cells.
Finder codeCells() =>
    find.byWidgetPredicate((w) => _keyed(w, 'activation-code-'));

/// The client rows.
Finder clientRows() => find.byWidgetPredicate((w) => _keyed(w, 'client-row-'));

/// The KPI card labelled [label].
DashStatCard kpi(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashStatCard && w.label == label).first,
);

/// [text] where a tap would land (the open dialog, sheet or menu; the page
/// under a dialog does not take taps).
Finder top(String text) => find.text(text).hitTestable();

/// Texts containing [s].
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// The prefixes every invalidation on the realtime bus named, in order.
List<List<String>> watchInvalidations(DashHarness h) {
  final seen = <List<String>>[];
  final sub = h.container
      .read(realtimeBusProvider)
      .invalidations
      .listen(seen.add);
  addTearDown(sub.cancel);
  return seen;
}
