// Shared set-up for the Waste log tests: the real app shell with the
// inventory area on the seeded mock server, the route templates the page and
// the dialog call, and finders scoped to the page, the table, the by-reason
// panel and the dialog.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/waste/waste_dialog.dart';
import 'package:dashboard_inventory/src/waste/waste_page.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String wastePath = '/inventory/waste';

// Route templates.
const String logRoute = '/inventory/branches/{branch_id}/waste';
const String reportRoute = '/reports/branches/{branch_id}/waste-report';
const String stockRoute = '/inventory/branches/{branch_id}/stock';

/// The all-branches sentinel.
const String allBranches = '00000000-0000-0000-0000-000000000000';

/// Opens [path] (the Waste log by default) as [persona], with [branch]
/// picked (null = All branches) and the period [preset] (wire name).
Future<DashHarness> pumpWaste(
  WidgetTester tester, {
  String path = wastePath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  Map<String, String>? prefs,
  String? branch,
  String? preset,
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
    if (preset != null) ScopePrefKeys.preset: preset,
  },
);

/// A seeded server with the core's and the inventory area's handlers, for a
/// test that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) wasteServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerInventoryMocks(server, db);
  return (server: server, db: db);
}

/// [s]'s `/authz/me` grants exactly [caps] (the server's own checks still
/// follow the persona).
void grantOnly(MockServer s, Persona persona, List<String> caps) => s.on(
  'GET',
  '/authz/me',
  (req) => MockResponse.ok({
    'user_id': persona.userId,
    'capabilities': caps,
    'ask_manager': <String>[],
    'limits': <String, Object>{},
    'owner': false,
    'platform': false,
    'role_kinds': persona.roleKinds,
    'epoch': 1,
    'spec_version': 2,
  }),
);

// ── Finders ────────────────────────────────────────────────────────────────

Finder get page => find.byType(WastePage);
Finder get table => find.byKey(const ValueKey('waste-table'));
Finder get reasons => find.byType(WasteByReason);
Finder get dialog => find.byType(RecordWasteDialog);

Finder inPage(Finder f) => find.descendant(of: page, matching: f);
Finder inTable(Finder f) => find.descendant(of: table, matching: f);
Finder inReasons(Finder f) => find.descendant(of: reasons, matching: f);
Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);

Finder byKey(String key) => find.byKey(ValueKey(key));

/// Text widgets (spans included) containing [s].
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// The option [label] in the open select's list (popover or sheet).
Finder option(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.text(label),
);

/// Picks [label] in the select [select].
Future<void> pick(DashHarness h, Finder select, String label) async {
  await h.tap(select);
  await h.tap(option(label).last);
}

/// Picks [label] in the searchable picker [select], typing it first (a long
/// list builds only what shows).
Future<void> pickSearch(DashHarness h, Finder select, String label) async {
  await h.tap(select);
  await h.enterText(
    find.byWidgetPredicate((w) => w is DashOptionList).last,
    label,
  );
  await h.tap(option(label).last);
}

/// The Record waste (submit) button in the dialog.
DashButton submitButton(WidgetTester tester) =>
    tester.widget(inDialog(byKey('waste-submit')));

/// The stock record of [branchId] × ingredient [key].
MockRow? stockRow(MockDb db, String branchId, String key) =>
    db[InvTables.branchStock].firstWhere(
      (r) =>
          r['branch_id'] == branchId &&
          r['org_ingredient_id'] == InvIds.ingredient(key),
    );
