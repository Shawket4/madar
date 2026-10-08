// Shared set-up for the `bases` unit's tests: the real app shell with the
// menu area on the seeded mock server, and finders for the pages' rows.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String basesPath = '/menu/bases';
const String packagingPath = '/menu/packaging';

/// A seeded server with the core's and the menu area's handlers, for a test
/// that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) menuServer({Persona persona = Persona.owner}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerCatalogMenuMocks(server, db);
  return (server: server, db: db);
}

/// Opens [path] as [persona].
Future<DashHarness> pumpMenu(
  WidgetTester tester, {
  String path = basesPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? seeded,
}) => DashHarness.pump(
  tester,
  areas: const [catalogMenuArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: seeded?.server,
  db: seeded?.db,
);

/// The row of the base or rule [id].
Finder rowOf(String id) => find.byKey(ValueKey(id));

/// The control a screen reader calls [label] inside [scope].
Finder labelIn(Finder scope, String label) =>
    find.descendant(of: scope, matching: find.bySemanticsLabel(label));

/// Text widgets whose text contains [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// Seed ids used across the tests.
final String espressoBase = MenuSeedIds.base('espresso');
final String icedBase = MenuSeedIds.base('iced_build');
final String mochaOldBase = MenuSeedIds.base('mocha_old');

/// The sizes following [baseId] (live items), as the seed holds them.
int sizesUsing(MockDb db, String baseId) =>
    db[MenuTables.sizes].where((s) => s['base_id'] == baseId).length;

/// The distinct items with a size following [baseId].
int itemsUsing(MockDb db, String baseId) => {
  for (final s in db[MenuTables.sizes].where((s) => s['base_id'] == baseId))
    s['menu_item_id'],
}.length;

/// The last recorded call to `method template`.
MockCall lastCall(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method).last;
