// Shared set-up for the Transfers tests: the real app shell with the
// inventory area on the seeded mock server, the route templates the page and
// the dialogs call, and finders scoped to the page, the table and a dialog.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/transfers/transfer_dialog.dart';
import 'package:dashboard_inventory/src/transfers/transfers_page.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String transfersPath = '/inventory/transfers';

// Route templates.
const String listRoute = '/inventory/branches/{branch_id}/transfers';
const String createRoute = '/inventory/transfers';
const String itemRoute = '/inventory/transfers/{id}';
const String stockRoute = '/inventory/branches/{branch_id}/stock';
const String branchesRoute = '/branches';

/// The all-branches sentinel.
const String allBranches = '00000000-0000-0000-0000-000000000000';

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

// ── Finders ────────────────────────────────────────────────────────────────

Finder get page => find.byType(TransfersPage);
Finder get table => find.byKey(const ValueKey('transfers-table'));
Finder get dialog => find.byType(TransferDialog);
Finder get noteDialog => find.byType(TransferNoteDialog);

Finder inPage(Finder f) => find.descendant(of: page, matching: f);
Finder inTable(Finder f) => find.descendant(of: table, matching: f);
Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
Finder inNote(Finder f) => find.descendant(of: noteDialog, matching: f);

Finder byKey(String key) => find.byKey(ValueKey(key));

/// The ⋯ button of [transferKey]'s row (`InvIds.transfer`).
Finder menuOf(String transferKey) => find.descendant(
  of: byKey('transfer-menu-${InvIds.transfer(transferKey)}'),
  matching: find.byType(DashIconButton),
);

/// The open menu's item [label].
Finder menuItem(String label) => find.descendant(
  of: find.byType(DashMenuItem),
  matching: find.text(label),
);

/// The option [label] in the open select's list (popover or sheet).
Finder option(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.text(label),
);

/// The trigger of the dialog's select [key].
Finder trigger(String key) => inDialog(
  find.descendant(of: byKey(key), matching: find.byType(DashSelectTrigger)),
);

/// Picks [label] in the dialog's select [key].
Future<void> pick(DashHarness h, String key, String label) async {
  await h.tap(trigger(key));
  await h.tap(option(label).last);
}

/// Picks [label] in the ingredient picker, typing it first.
Future<void> pickIngredient(DashHarness h, String label) async {
  await h.tap(trigger('transfer-ingredient'));
  await h.enterText(
    find.byWidgetPredicate((w) => w is DashOptionList).last,
    label,
  );
  await h.tap(option(label).last);
}

/// The New transfer (submit) button in the dialog.
DashButton submitButton(WidgetTester tester) =>
    tester.widget(inDialog(byKey('transfer-submit')));

/// The stock record of [branchId] × ingredient [key].
MockRow? stockRow(MockDb db, String branchId, String key) =>
    db[InvTables.branchStock].firstWhere(
      (r) =>
          r['branch_id'] == branchId &&
          r['org_ingredient_id'] == InvIds.ingredient(key),
    );

/// Sets [branchId]'s on hand of ingredient [key].
void setOnHand(MockDb db, String branchId, String key, double qty) =>
    stockRow(db, branchId, key)!['on_hand'] = qty;
