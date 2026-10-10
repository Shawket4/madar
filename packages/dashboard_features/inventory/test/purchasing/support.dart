// Shared set-up for the purchasing tests: the real app shell with the
// inventory area, on the seeded mock server (core seed + area seed).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/purchasing/purchase_order_dialog.dart';
import 'package:dashboard_inventory/src/purchasing/purchasing_page.dart';
import 'package:dashboard_inventory/src/purchasing/receive_dialog.dart';
import 'package:dashboard_inventory/src/purchasing/supplier_dialog.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String purchasingPath = '/inventory/purchasing';

/// The page scoped to [branchId] (a deep link, INV-ALL-008).
String purchasingAt(String branchId) => '$purchasingPath?branchId=$branchId';

/// Templates of the routes the page calls.
abstract final class PurT {
  static const suppliers = '/purchasing/orgs/{org_id}/suppliers';
  static const supplier = '/purchasing/suppliers/{id}';
  static const catalog = '/inventory/orgs/{org_id}/catalog';
  static const orders = '/purchasing/branches/{branch_id}/orders';
  static const order = '/purchasing/orders/{id}';
  static const submit = '/purchasing/orders/{id}/submit';
  static const cancel = '/purchasing/orders/{id}/cancel';
  static const receive = '/purchasing/orders/{id}/receive';
  static const receipts = '/purchasing/orders/{id}/receipts';
  static const reorder = '/purchasing/branches/{branch_id}/reorder-suggestions';
}

/// Seed ids the tests name.
abstract final class PurIds {
  static String po(String key) => InvIds.purchaseOrder(key);
  static String supplier(String key) => InvIds.supplier(key);
  static String ingredient(String key) => InvIds.ingredient(key);
  static String line(String po, int n) => InvIds.poLine(po, n);
}

/// Opens [path] (Purchasing, All branches, by default) as [persona].
Future<DashHarness> pumpPurchasing(
  WidgetTester tester, {
  String path = purchasingPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
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
);

/// A seeded server with the core's and the inventory area's handlers, for a
/// test that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) purchasingServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerInventoryMocks(server, db);
  return (server: server, db: db);
}

/// Text widgets whose text contains [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// [finder], only where a tap would land (over a dialog, the page under it
/// does not take taps).
Finder top(Finder finder) => finder.hitTestable();

/// The widget keyed [key].
Finder byKey(String key) => find.byKey(ValueKey(key));

/// Taps [text] in an open menu or popover.
Future<void> pick(DashHarness h, String text) =>
    h.tap(find.text(text).hitTestable());

// ── Scoped finders ─────────────────────────────────────────────────────────

Finder get page => find.byType(PurchasingPage);
Finder get poDialog => find.byType(PurchaseOrderDialog);
Finder get receiveDialog => find.byType(ReceiveDialog);
Finder get supplierDialog => find.byType(SupplierDialog);
Finder get ordersTable => find.byKey(const ValueKey('po-table'));
Finder get suppliersTable => find.byKey(const ValueKey('supplier-table'));
Finder get tabStrip => find.byKey(const ValueKey('purchasing-tabs'));

Finder inPage(Finder f) => find.descendant(of: page, matching: f);
Finder inOrders(Finder f) => find.descendant(of: ordersTable, matching: f);
Finder inSuppliers(Finder f) =>
    find.descendant(of: suppliersTable, matching: f);
Finder inPo(Finder f) => find.descendant(of: poDialog, matching: f);
Finder inReceive(Finder f) => find.descendant(of: receiveDialog, matching: f);
Finder inSupplier(Finder f) => find.descendant(of: supplierDialog, matching: f);

/// A cell (or any plain text) reading exactly [s] inside [scope].
Finder exactText(Finder scope, String s) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? w.textSpan?.toPlainText()) == s,
    description: '"$s"',
  ),
);

/// Opens the tab labelled [label].
Future<void> openTab(DashHarness h, String label) =>
    h.tap(find.descendant(of: tabStrip, matching: find.text(label)));

/// Opens the ⋯ menu of the order [poId] and taps [item].
Future<void> orderMenu(DashHarness h, String poId, String item) async {
  await h.tap(inPage(byKey('po-menu-$poId')));
  await pick(h, item);
}

/// Opens the ⋯ menu of the supplier [supplierId] and taps [item].
Future<void> supplierMenu(DashHarness h, String supplierId, String item) async {
  await h.tap(inPage(byKey('supplier-menu-$supplierId')));
  await pick(h, item);
}

/// The text inside the input keyed [key].
String inputText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: byKey(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// The hint the input keyed [key] shows while empty.
String? inputHint(WidgetTester tester, String key) => tester
    .widget<TextField>(
      find.descendant(of: byKey(key), matching: find.byType(TextField)),
    )
    .decoration
    ?.hintText;

/// The button keyed [key].
DashButton button(WidgetTester tester, String key) =>
    tester.widget<DashButton>(byKey(key));

/// The last JSON body sent to [template] by [method].
Map<String, Object?> lastBody(DashHarness h, String template, String method) =>
    h.server.callsTo(template, method: method).last.body!
        as Map<String, Object?>;

/// The org's suppliers as the server lists them (by name).
List<MockRow> sabahSuppliers(MockDb db) => db[InvTables.suppliers].query(
  filters: {'org_id': SeedIds.sabahOrg},
  sort: 'name',
);

/// Presses [retry] and draws ONE frame (the read is held by the caller):
/// what shows while the retry is out.
Future<void> retryHeld(DashHarness h, Finder retry) async {
  await h.tester.ensureVisible(retry.first);
  await h.tester.pump();
  await h.tester.tap(retry.first);
  await h.tester.pump();
}
