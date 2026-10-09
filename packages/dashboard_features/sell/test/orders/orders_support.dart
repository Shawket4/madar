// Test support for the Orders page: a seeded server the test can edit
// before pumping, the page's routes, and the pump helper (Heliopolis, today,
// unless told otherwise).
import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_sell/dashboard_sell.dart';
import 'package:dashboard_sell/src/orders/orders_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';

export 'package:dashboard_sell/src/mock/orders_mock.dart' show OrderSeedIds;

const String listRoute = '/orders';
const String orderRoute = '/orders/{order_id}';
const String voidRoute = '/orders/{order_id}/void';
const String exportRoute = '/orders/export';
const String deliverySalesRoute =
    '/reports/branches/{branch_id}/delivery-sales';
const String deliveryOrderRoute = '/delivery-orders/{id}';
const String catalogRoute = '/inventory/orgs/{org_id}/catalog';
const String menuItemsRoute = '/menu-items';

({MockServer server, MockDb db}) ordersServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerSellMocks(server, db);
  return (server: server, db: db);
}

/// `/orders` (plus [query]) for [persona], with [branchId] picked (null =
/// All branches) and the period [preset] (today by default).
Future<DashHarness> pumpOrders(
  WidgetTester tester, {
  String query = '',
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  String? branchId = '',
  String preset = 'today',
  MockServer? server,
  MockDb? db,
  Map<String, String> prefs = const {},
}) {
  final s = server == null ? ordersServer(persona: persona) : null;
  return pumpSell(
    tester,
    '$listRoute$query',
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    branchId: branchId == '' ? SeedIds.heliopolis : branchId,
    server: server ?? s!.server,
    db: db ?? s!.db,
    prefs: {ScopePrefKeys.preset: preset, ...prefs},
  );
}

/// Finders scoped to the page (the shell builds sidebar rows with the same
/// words).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(OrdersPage), matching: f);

Finder inTable(Finder f) => find.descendant(
  of: find.byKey(const ValueKey('orders-table')),
  matching: f,
);

/// The signed-in person's capabilities as the APP sees them, without [drop]
/// (the server still answers as the persona): for gates no persona lacks.
void dropCaps(MockServer server, Set<String> drop) {
  server.on('GET', '/authz/me', (req) {
    final p = req.persona;
    final caps = [
      for (final c in p.capabilities)
        if (!drop.contains(c)) c,
    ]..sort();
    return MockResponse.ok(
      MyAuthz(
        userId: p.userId,
        branchId: req.q('branch_id'),
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

/// Today's orders of [branchId], newest first (what the list's first pages
/// show).
List<Map<String, Object?>> todaysOrders(MockDb db, String branchId) {
  final today = MockClock.startOfCairoDay(db.clock.now);
  return db['orders'].where(
    (o) =>
        o['branch_id'] == branchId &&
        !DateTime.parse(o['created_at']! as String).isBefore(today),
  )..sort(
    (a, b) =>
        (b['created_at']! as String).compareTo(a['created_at']! as String),
  );
}

/// Units sold on [orderId] (combo headers left out): what Items Sold counts.
int soldUnits(MockDb db, String orderId) {
  final own = db['order_details'].find(orderId)?['items'];
  final lines = own is List
      ? [for (final l in own) l as Map<String, Object?>]
      : [for (final l in MockSeed.instance.orderItems(orderId)) l.toJson()];
  return lines
      .where((l) => l['line_kind'] != 'combo')
      .fold<int>(0, (n, l) => n + (l['quantity']! as num).toInt());
}
