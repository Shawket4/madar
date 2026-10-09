// Shared set-up for the Stock counts tests: the real app shell with the
// inventory area on the seeded mock server, the route templates the page
// calls, the seed's counts, and finders scoped to the page, the editor and
// the dialogs.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/counts/count_editor.dart';
import 'package:dashboard_inventory/src/counts/counts_page.dart';
import 'package:dashboard_inventory/src/counts/start_count_dialog.dart';
import 'package:dashboard_inventory/src/counts/variance_report_dialog.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String countsPath = '/inventory/counts';

// Route templates.
const String listRoute = '/stocktakes/branches/{branch_id}';
const String getRoute = '/stocktakes/{id}';
const String itemsRoute = '/stocktakes/{id}/items';
const String finalizeRoute = '/stocktakes/{id}/finalize';
const String cancelRoute = '/stocktakes/{id}/cancel';
const String reportRoute = '/stocktakes/{id}/variance-report';
const String catalogRoute = '/inventory/orgs/{org_id}/catalog';
const String categoriesRoute = '/inventory/orgs/{org_id}/categories';

/// The seed's counts.
final String openNewCairo = InvIds.stocktake('new-cairo-1008');
final String zamalekFull = InvIds.stocktake('zamalek-0920');
final String zamalekMilk = InvIds.stocktake('zamalek-1004');
final String zamalekCancelled = InvIds.stocktake('zamalek-0927');
final String maadiSpot = InvIds.stocktake('maadi-0902');

/// Opens Stock counts as [persona], with [branch] picked (null = All
/// branches).
Future<DashHarness> pumpCounts(
  WidgetTester tester, {
  String path = countsPath,
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
({MockServer server, MockDb db}) countsServer({
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

Finder get page => find.byType(CountsPage);
Finder get editor => find.byType(CountEditor);
Finder get scopeDialog => find.byType(StartCountDialog);
Finder get report => find.byType(VarianceReportDialog);
Finder get table => find.byKey(const ValueKey('counts-table'));

Finder inPage(Finder f) => find.descendant(of: page, matching: f);
Finder inEditor(Finder f) => find.descendant(of: editor, matching: f);
Finder inScope(Finder f) => find.descendant(of: scopeDialog, matching: f);
Finder inReport(Finder f) => find.descendant(of: report, matching: f);
Finder inTable(Finder f) => find.descendant(of: table, matching: f);

Finder byKey(String key) => find.byKey(ValueKey(key));

/// Text widgets (spans included) containing [s].
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// A Text whose whole text is [s], inside [scope].
Finder textIn(Finder scope, String s) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) =>
        (w is Text && (w.data ?? w.textSpan?.toPlainText()) == s) ||
        (w is RichText && w.text.toPlainText() == s),
    description: '"$s"',
  ),
);

/// The editor row of ingredient [key].
Finder editorRow(String key) =>
    inEditor(byKey('count-row-${InvIds.ingredient(key)}'));

Finder inRow(String key, Finder f) =>
    find.descendant(of: editorRow(key), matching: f);

/// The counted input of ingredient [key].
Finder countInput(String key) =>
    inEditor(byKey('count-input-${InvIds.ingredient(key)}'));

/// Types [qty] as ingredient [key]'s count.
Future<void> typeCount(DashHarness h, String key, String qty) =>
    h.enterText(countInput(key), qty);

/// Picks [label] in the select keyed [key] (inside [scope]).
Future<void> pick(DashHarness h, Finder select, String label) async {
  await h.tap(select);
  await h.tap(find.text(label).last);
}

/// The open count's item row of ingredient [key] in [db].
MockRow itemRow(MockDb db, String stocktakeId, String key) =>
    db[InvTables.stocktakeItems].firstWhere(
      (i) =>
          i['stocktake_id'] == stocktakeId &&
          i['org_ingredient_id'] == InvIds.ingredient(key),
    )!;

/// The stock record of [branchId] × ingredient [key].
MockRow? stockRow(MockDb db, String branchId, String key) =>
    db[InvTables.branchStock].firstWhere(
      (r) =>
          r['branch_id'] == branchId &&
          r['org_ingredient_id'] == InvIds.ingredient(key),
    );

/// The last JSON body sent to [template] by [method].
Object? lastBody(DashHarness h, String template, String method) =>
    h.server.callsTo(template, method: method).last.body;

/// Lets the editor's 1.2 s autosave run out.
Future<void> waitAutosave(DashHarness h) async {
  await h.tester.pump(const Duration(milliseconds: 1300));
  await h.settle();
}

/// The DashTextInput of [f].
DashTextInput inputOf(WidgetTester tester, Finder f) =>
    tester.widget<DashTextInput>(f);
