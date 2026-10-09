// Shared set-up for the `groups` unit's tests: the real app shell with the
// menu area on the seeded mock server, finders and the seed's group ids.
//
// The seeded shared groups, in `sort` order: Milk (swaps milk, up to 1, six
// options), Extras (adds, any number), Coffee beans (swaps beans, exactly 1;
// Espresso, Americano, Cortado), Sweetness (nothing, exactly 1; Turkish
// coffee), Toppings (adds with per-size amounts, up to 2; Frappé, Iced
// Mocha) and Serving cup (inactive, used nowhere).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String groupsPath = '/menu/groups';
const String listT = '/modifier-groups';
const String groupT = '/modifier-groups/{gid}';
const String usageT = '/modifier-groups/{gid}/usage';
const String optionsT = '/modifier-groups/{gid}/options';
const String optionT = '/modifier-options/{oid}';
const String recipeT = '/modifier-options/{oid}/recipe';
const String itemsT = '/menu-items';
const String itemT = '/menu-items/{id}';
const String studioT = '/menu-items/{id}/studio';
const String attachT = '/menu-items/{id}/modifier-groups';
const String catalogT = '/inventory/orgs/{org_id}/catalog';
const String categoriesT = '/inventory/orgs/{org_id}/categories';

final String milkId = MenuSeedIds.group('milk');
final String extrasId = MenuSeedIds.group('extras');
final String beansId = MenuSeedIds.group('beans');
final String sweetnessId = MenuSeedIds.group('sweetness');
final String toppingsId = MenuSeedIds.group('toppings');
final String servingId = MenuSeedIds.group('serving');

/// The seeded shared groups in their listed order.
List<String> get seededOrder => [
  milkId,
  extrasId,
  beansId,
  sweetnessId,
  toppingsId,
  servingId,
];

/// A seeded server with the core's and the menu area's handlers, for a test
/// that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) groupsServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerCatalogMenuMocks(server, db);
  return (server: server, db: db);
}

/// Opens [path] as [persona].
Future<DashHarness> pumpGroups(
  WidgetTester tester, {
  String path = groupsPath,
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

/// The row of group [id].
Finder rowOf(String id) => find.byKey(ValueKey(id));

/// The control a screen reader calls [label] inside [scope].
Finder labelIn(Finder scope, String label) =>
    find.descendant(of: scope, matching: find.bySemanticsLabel(label));

/// [text] inside [scope].
Finder textIn(Finder scope, String text) =>
    find.descendant(of: scope, matching: find.text(text));

/// The open dialog / full-screen surface titled [title].
Finder surface(String title) => find
    .ancestor(of: find.text(title), matching: find.byType(DashSurface))
    .first;

/// The calls to `method template`.
List<MockCall> callsTo(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method);

/// The group row [id] as the db holds it.
MockRow groupRow(MockDb db, String id) => db[MenuTables.groups].find(id)!;

/// The prefixes `invalidateCatalog()` names (features/menu/util.ts).
const List<String> catalogPrefixes = [
  '/menu-items',
  '/categories',
  '/addon-items',
  '/branch-menu-overrides',
  '/branch-addon-overrides',
  '/catalog',
  '/costing',
];

/// Every prefix invalidated from now on (the web's `invalidateQueries`).
List<String> recordInvalidations(DashHarness h) {
  final log = <String>[];
  h.container.read(realtimeBusProvider).invalidations.listen(log.addAll);
  return log;
}
