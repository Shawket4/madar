// Shared set-up for the purchasing tests: the real app shell with the
// inventory area, on the seeded mock server (core seed + area seed).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:flutter/widgets.dart';
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
