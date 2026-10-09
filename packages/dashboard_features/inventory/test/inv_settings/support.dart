// Shared set-up for the Inventory settings tests: the real app shell with the
// inventory area on the seeded mock server, the route templates the page
// calls, the seed's categories, and finders scoped to the page and dialog.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/inv_settings/inventory_settings_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String settingsPath = '/inventory/settings';

// Route templates.
const String settingsRoute = '/inventory/orgs/{org_id}/settings';
const String categoriesRoute = '/inventory/orgs/{org_id}/categories';
const String categoryRoute = '/inventory/orgs/{org_id}/categories/{id}';

String get org => SeedIds.sabahOrg;
String cat(String slug) => InvIds.category(slug);

/// Opens Inventory settings as [persona].
Future<DashHarness> pumpSettings(
  WidgetTester tester, {
  String path = settingsPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  Map<String, String>? prefs,
}) => DashHarness.pump(
  tester,
  areas: const [inventoryArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  prefs: prefs,
);

/// A seeded server with the core's and the inventory area's handlers, for a
/// test that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) settingsServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerInventoryMocks(server, db);
  return (server: server, db: db);
}

/// A platform admin's preferences with Sabah picked.
Map<String, String> sabahPicked() => {
  ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
};

/// Adds an empty category to [db] (nothing uses it).
String addEmptyCategory(MockDb db, {String name = 'Seasonal', int sort = 8}) {
  final slug = name.toLowerCase();
  db[InvTables.categories].insert({
    'id': InvIds.category(slug),
    'org_id': SeedIds.sabahOrg,
    'slug': slug,
    'name': name,
    'sort_order': sort,
    'is_packaging': false,
    'ingredient_count': 0,
  });
  return InvIds.category(slug);
}

/// How many seed ingredients use category [slug].
int usersOf(MockDb db, String slug) => db[InvTables.ingredients]
    .where((i) => i['category_id'] == InvIds.category(slug))
    .length;

// ── Finders ────────────────────────────────────────────────────────────────

Finder get page => find.byType(InventorySettingsPage);
Finder get dialog => find.byType(DeleteCategoryDialog);
Finder get list => byKey('inv-settings-category-list');

Finder inPage(Finder f) => find.descendant(of: page, matching: f);
Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
Finder inList(Finder f) => find.descendant(of: list, matching: f);

Finder byKey(String key) => find.byKey(ValueKey(key));

/// Category [slug]'s row.
Finder row(String slug) => inPage(byKey('inv-category-${cat(slug)}'));
Finder inRow(String slug, Finder f) =>
    find.descendant(of: row(slug), matching: f);

/// Text widgets (spans included) containing [s].
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// The rows of category ids [ids], ordered top to bottom.
List<String> orderOf(WidgetTester tester, Iterable<String> ids) {
  double y(String id) =>
      tester.getTopLeft(inPage(byKey('inv-category-$id'))).dy;
  return [...ids]..sort((a, b) => y(a).compareTo(y(b)));
}
