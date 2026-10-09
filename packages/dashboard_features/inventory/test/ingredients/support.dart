// Shared set-up for the Ingredients tests: the real app shell with the
// inventory area on the seeded mock server, the route templates the page
// calls, and finders scoped to the page, its dialog and its drawer.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/ingredients/ingredient_dialog.dart';
import 'package:dashboard_inventory/src/ingredients/ingredient_drawer.dart';
import 'package:dashboard_inventory/src/ingredients/ingredients_page.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String ingredientsPath = '/inventory/ingredients';

// Route templates.
const String catalogRoute = '/inventory/orgs/{org_id}/catalog';
const String catalogItemRoute = '/inventory/orgs/{org_id}/catalog/{id}';
const String categoriesRoute = '/inventory/orgs/{org_id}/categories';
const String suppliersRoute = '/purchasing/orgs/{org_id}/suppliers';
const String branchesRoute = '/branches';
const String stockRoute = '/inventory/branches/{branch_id}/stock';
const String parRoute =
    '/inventory/branches/{branch_id}/stock/{org_ingredient_id}/par';
const String stocktakesRoute = '/stocktakes/branches/{branch_id}';
const String movementsRoute = '/inventory/branches/{branch_id}/movements';

/// Opens Ingredients as [persona], with [branch] picked (null = All
/// branches).
Future<DashHarness> pumpIngredients(
  WidgetTester tester, {
  String path = ingredientsPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  Map<String, String>? prefs,
  String? branch,
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
  prefs: {
    ...?prefs,
    if (branch != null)
      ScopePrefKeys.branch: jsonEncode({
        'org': SeedIds.sabahOrg,
        'branch': branch,
      }),
  },
);

/// A seeded server with the core's and the inventory area's handlers, for a
/// test that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) ingredientsServer({
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

// ── Finders ────────────────────────────────────────────────────────────────

Finder get page => find.byType(IngredientsPage);
Finder get dialog => find.byType(IngredientDialog);
Finder get drawer => find.byType(IngredientDrawer);
Finder get table => find.byKey(const ValueKey('ingredients-table'));

Finder inPage(Finder f) => find.descendant(of: page, matching: f);
Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
Finder inDrawer(Finder f) => find.descendant(of: drawer, matching: f);
Finder inTable(Finder f) => find.descendant(of: table, matching: f);

Finder byKey(String key) => find.byKey(ValueKey(key));

/// Text widgets (spans included) containing [s].
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// The seeded ingredient row by its seed key.
MockRow ingredientRow(MockDb db, String key) =>
    db[InvTables.ingredients].find(InvIds.ingredient(key))!;

/// The stock record of [branchId] × ingredient [key].
MockRow? stockRow(MockDb db, String branchId, String key) =>
    db[InvTables.branchStock].firstWhere(
      (r) =>
          r['branch_id'] == branchId &&
          r['org_ingredient_id'] == InvIds.ingredient(key),
    );

/// A cell's text in the table (never the search box's own text).
Finder cellText(String s) => inTable(
  find.byWidgetPredicate((w) => w is Text && w.data == s, description: s),
);

/// Types into the table's search box.
Future<void> search(DashHarness h, String text) =>
    h.enterText(inPage(find.byType(DashSearchInput)), text);

/// Opens the drawer of the ingredient named [name] (searching for it so it
/// is on the first page).
Future<void> openDrawer(DashHarness h, String name) async {
  await search(h, name);
  await h.tap(cellText(name));
  expect(drawer, findsOneWidget);
}

/// Opens the New ingredient dialog.
Future<void> openCreate(DashHarness h) async {
  await h.tap(inPage(byKey('ingredients-new')));
  expect(dialog, findsOneWidget);
}

/// Picks [label] in the select keyed [key] inside the dialog.
Future<void> pick(DashHarness h, String key, String label) async {
  await h.tap(inDialog(byKey(key)));
  await h.tap(find.text(label).last);
}

/// The last JSON body sent to [template] by [method].
Map<String, Object?> lastBody(DashHarness h, String template, String method) =>
    h.server.callsTo(template, method: method).last.body!
        as Map<String, Object?>;
