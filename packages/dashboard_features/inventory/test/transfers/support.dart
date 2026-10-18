// Shared set-up for the Transfers tests: the real app shell with the
// inventory area on the seeded mock server, the route templates the page,
// the drawer and the dialogs call, a warehouse for the warehouse rows, and
// finders scoped to the page, the tables, the drawer and each dialog.
//
// The seed (transfers_mock.dart): TR-1…TR-5 are the area seed's received
// one-line transfers, TR-6 is Zamalek's request to Maadi, TR-7 Maadi's
// draft to Heliopolis, TR-8 New Cairo's cancelled draft to Zamalek.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/mock/transfers_mock.dart';
import 'package:dashboard_inventory/src/transfers/replenish_dialog.dart';
import 'package:dashboard_inventory/src/transfers/transfer_dialog.dart';
import 'package:dashboard_inventory/src/transfers/transfer_drawer.dart';
import 'package:dashboard_inventory/src/transfers/transfers_page.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String transfersPath = '/inventory/transfers';

// Route templates.
const String listRoute = '/inventory/branches/{branch_id}/transfers';

/// A list read's query: [filters] plus the "Load more" window from the
/// newest (always sent, so the server's silent 100-row default never applies).
Map<String, List<String>> win([
  Map<String, List<String>> filters = const {},
  int limit = 100,
]) => {
  ...filters,
  'limit': ['$limit'],
  'offset': ['0'],
};
const String locationsRoute = '/inventory/orgs/{org_id}/transfer-locations';
const String diffsRoute = '/inventory/orgs/{org_id}/transfer-differences';
const String replenishRoute =
    '/inventory/warehouses/{warehouse_id}/replenishment';
const String createRoute = '/inventory/transfers';
const String itemRoute = '/inventory/transfers/{id}';
const String stockRoute = '/inventory/branches/{branch_id}/stock';
const String catalogRoute = '/inventory/orgs/{org_id}/catalog';
const String branchesRoute = '/branches';
const String authzRoute = '/authz/me';

/// `POST /inventory/transfers/{id}/<step>`.
String stepRoute(String step) => '/inventory/transfers/{id}/$step';

/// The all-branches sentinel.
const String allBranches = '00000000-0000-0000-0000-000000000000';

/// The warehouse [withWarehouse] adds.
final String centralStore = mockUuid('branch:central-store');

/// Opens [path] (Transfers by default) as [persona], with [branch] picked
/// (null = All branches).
Future<DashHarness> pumpTransfers(
  WidgetTester tester, {
  String path = transfersPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
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
    if (branch != null)
      ScopePrefKeys.branch: jsonEncode({
        'org': SeedIds.sabahOrg,
        'branch': branch,
      }),
  },
);

/// A seeded server with the core's and the inventory area's handlers, for a
/// test that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) transfersServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerInventoryMocks(server, db);
  return (server: server, db: db);
}

/// Adds "Central Store", a warehouse of Sabah holding oat milk (12 L),
/// house blend (8 kg) and paper cups (900), and sets Zamalek's oat milk
/// level to 3–10 L with 2 L on hand, so Zamalek is low on it.
void withWarehouse(MockDb db) {
  db['branches'].insert({
    ...db['branches'].get(SeedIds.maadi),
    'id': centralStore,
    'name': 'Central Store',
    'code': 'CS',
    'kind': 'warehouse',
  });
  for (final (key, qty) in [
    ('oat', 12000.0),
    ('house-blend', 8000.0),
    ('paper-cup-12', 900.0),
  ]) {
    db[InvTables.branchStock].insert({
      'id': db.newId(InvTables.branchStock),
      'branch_id': centralStore,
      'org_ingredient_id': InvIds.ingredient(key),
      'on_hand': qty,
      'par_min': null,
      'par_max': null,
      'cost_per_unit': null,
      'last_counted_at': null,
      'last_movement_at': null,
    }, timestamps: false);
  }
  stockRow(db, SeedIds.zamalek, 'oat')!
    ..['on_hand'] = 2000.0
    ..['par_min'] = 3000.0
    ..['par_max'] = 10000.0;
}

/// The seed transfer [key] (`t1`…`t8`).
MockRow doc(MockDb db, String key) =>
    db[InvTables.transfers].find(InvIds.transfer(key))!;

/// The transfer whose reference is [ref].
MockRow docRef(MockDb db, String ref) =>
    db[InvTables.transfers].firstWhere((t) => t['reference'] == ref)!;

/// Sends TR-7 (Maadi → Heliopolis) as the owner: it is then in transit.
MockRow dispatchDraft(MockDb db) {
  final t = doc(db, 't7');
  transferDispatch(db, t, Persona.owner);
  return t;
}

/// Sends and receives TR-7 with 8 croissants of 10 (short by 2).
MockRow receiveShort(MockDb db) {
  final t = dispatchDraft(db);
  final lines = (t['lines']! as List).cast<MockRow>();
  final croissant = lines.firstWhere(
    (l) => l['ingredient_name'] == 'Croissant Dough',
  );
  transferReceive(
    db,
    t,
    Persona.owner,
    got: {croissant['id']! as String: (8, 'Two crushed in the van')},
  );
  return t;
}

// ── Finders ────────────────────────────────────────────────────────────────

Finder get page => find.byType(TransfersPage);
Finder get table => find.byKey(const ValueKey('transfers-table'));
Finder get diffTable => find.byKey(const ValueKey('transfers-differences'));
Finder get drawer => find.byType(TransferDrawer);
Finder get dialog => find.byType(TransferDialog);
Finder get receiveDialog => find.byType(ReceiveTransferDialog);
Finder get closeDialog => find.byType(CloseTransferDialog);
Finder get replenishDialog => find.byType(ReplenishDialog);

Finder inPage(Finder f) => find.descendant(of: page, matching: f);
Finder inTable(Finder f) => find.descendant(of: table, matching: f);
Finder inDiffs(Finder f) => find.descendant(of: diffTable, matching: f);
Finder inDrawer(Finder f) => find.descendant(of: drawer, matching: f);
Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
Finder inReceive(Finder f) => find.descendant(of: receiveDialog, matching: f);
Finder inClose(Finder f) => find.descendant(of: closeDialog, matching: f);
Finder inReplenish(Finder f) =>
    find.descendant(of: replenishDialog, matching: f);

Finder byKey(String key) => find.byKey(ValueKey(key));

/// The option [label] in the open select's list (popover or sheet).
Finder option(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.text(label),
);

/// The trigger of the select [key] inside [scope].
Finder triggerIn(Finder scope, String key) => find.descendant(
  of: find.descendant(of: scope, matching: byKey(key)),
  matching: find.byType(DashSelectTrigger),
);

/// Picks [label] in the select [key] inside [scope] (the dialog by default).
Future<void> pick(
  DashHarness h,
  String key,
  String label, {
  Finder? scope,
}) async {
  await h.tap(triggerIn(scope ?? dialog, key));
  await h.tap(option(label).last);
}

/// Picks [label] in line [index]'s ingredient picker, typing it first.
Future<void> pickIngredient(DashHarness h, int index, String label) async {
  await h.tap(triggerIn(dialog, 'transfer-ingredient-$index'));
  await h.enterText(
    find.byWidgetPredicate((w) => w is DashOptionList).last,
    label,
  );
  await h.tap(option(label).last);
}

/// The button [key] inside [scope] (the dialog by default).
DashButton button(WidgetTester tester, String key, {Finder? scope}) =>
    tester.widget(find.descendant(of: scope ?? dialog, matching: byKey(key)));

/// Opens the drawer on the row [ref] (`TR-n`).
Future<void> openRow(DashHarness h, String ref) =>
    h.tap(inTable(find.text(ref)));

/// The stock record of [branchId] × ingredient [key].
MockRow? stockRow(MockDb db, String branchId, String key) =>
    db[InvTables.branchStock].firstWhere(
      (r) =>
          r['branch_id'] == branchId &&
          r['org_ingredient_id'] == InvIds.ingredient(key),
    );

/// [branchId]'s on hand of ingredient [key].
double onHand(MockDb db, String branchId, String key) =>
    (stockRow(db, branchId, key)?['on_hand'] as num?)?.toDouble() ?? 0;

/// Answers `/authz/me?branch_id=<branchId>` (null: the org-wide
/// `/authz/me`) without [missing]; every other answer keeps the persona's
/// capabilities.
void holdAt(MockServer server, String? branchId, Set<String> missing) {
  server.on('GET', authzRoute, (req) {
    final p = req.persona;
    final at = req.q('branch_id');
    final caps = [
      for (final c in p.capabilities)
        if (at != branchId || !missing.contains(c)) c,
    ]..sort();
    return MockResponse.ok(
      MyAuthz(
        userId: p.userId,
        branchId: at,
        capabilities: caps,
        everywhere: p.branchIds == null ? caps : const [],
        askManager: const [],
        limits: const {},
        owner: p.isOwner,
        platform: p.isPlatform,
        roleKinds: p.roleKinds,
        epoch: 1,
        specVersion: 2,
      ),
    );
  });
}
