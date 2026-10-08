/// The reads several inventory pages share, answered once here so every unit
/// can be built and tested in parallel (a route registered twice keeps the
/// LAST handler, so no unit file registers these again — a unit that needs a
/// different answer adds a query parameter here or asks the area owner).
///
/// | Route | Read by |
/// |---|---|
/// | GET /inventory/orgs/{org_id}/catalog | Today, Counts, Ingredients, Purchasing |
/// | GET /inventory/orgs/{org_id}/categories | Counts, Ingredients, Settings |
/// | GET /purchasing/orgs/{org_id}/suppliers | Today, Ingredients, Purchasing |
/// | GET /inventory/branches/{branch_id}/stock | Today, Ingredients, Waste, Transfers |
/// | GET /stocktakes/branches/{branch_id} | Today, Counts, Ingredients |
/// | GET /purchasing/branches/{branch_id}/orders | Purchasing |
/// | GET /purchasing/orgs/{org_id}/orders | Today |
/// | GET /purchasing/orders/{id} | Today, Purchasing (receive dialog) |
/// | GET /inventory/branches/{branch_id}/waste | Today, Waste |
///
/// Capabilities as the backend checks them (inventory §11).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'inventory_views.dart';

void registerInventorySharedReads(MockServer server, MockDb db) {
  String org(MockRequest req) {
    final id = req.param('org_id');
    req.requireSameOrg(id);
    return id;
  }

  server.on('GET', '/inventory/orgs/{org_id}/catalog', (req) {
    req.requireCap('inventory.read');
    return MockResponse.ok(InvViews.catalog(db, org(req)));
  });

  server.on('GET', '/inventory/orgs/{org_id}/categories', (req) {
    req.requireCap('inventory.read');
    return MockResponse.ok(InvViews.categories(db, org(req)));
  });

  server.on('GET', '/purchasing/orgs/{org_id}/suppliers', (req) {
    req.requireCap('purchasing.suppliers.read');
    return MockResponse.ok(InvViews.suppliers(db, org(req)));
  });

  server.on('GET', '/inventory/branches/{branch_id}/stock', (req) {
    req.requireCap('inventory.read');
    final ids = InvScope.branchIds(req, db, req.param('branch_id'));
    if (ids.length != 1) req.badRequest('Pick a branch');
    return MockResponse.ok(InvViews.branchStock(db, ids.single));
  });

  server.on('GET', '/stocktakes/branches/{branch_id}', (req) {
    req.requireCap('inventory.counts.read');
    final ids = InvScope.branchIds(req, db, req.param('branch_id'));
    return MockResponse.ok(InvViews.stocktakes(db, ids));
  });

  server.on('GET', '/purchasing/branches/{branch_id}/orders', (req) {
    req.requireCap('purchasing.orders.read');
    final ids = InvScope.branchIds(req, db, req.param('branch_id')).toSet();
    return MockResponse.ok(
      InvViews.purchaseOrders(
        db,
        where: (po) => ids.contains(po['branch_id']),
        status: req.q('status'),
        expectedBefore: req.qDateTime('expected_before'),
      ),
    );
  });

  server.on('GET', '/purchasing/orgs/{org_id}/orders', (req) {
    req.requireCap('purchasing.orders.read');
    final orgId = org(req);
    final seen = {for (final b in InvScope.branches(req, db, orgId)) b['id']};
    return MockResponse.ok(
      InvViews.purchaseOrders(
        db,
        where: (po) => po['org_id'] == orgId && seen.contains(po['branch_id']),
        status: req.q('status'),
        expectedBefore: req.qDateTime('expected_before'),
        byExpected: true,
      ),
    );
  });

  server.on('GET', '/purchasing/orders/{id}', (req) {
    req.requireCap('purchasing.orders.read');
    final po = db[InvTables.purchaseOrders].get(
      req.param('id'),
      what: 'Purchase order not found',
    );
    req.requireSameOrg(po['org_id'] as String?);
    req.requireBranch(po['branch_id']! as String);
    return MockResponse.ok(InvViews.purchaseOrderFull(db, po));
  });

  server.on('GET', '/inventory/branches/{branch_id}/waste', (req) {
    req.requireCap('inventory.waste.read');
    final ids = InvScope.branchIds(req, db, req.param('branch_id'));
    return MockResponse.ok(
      sliceOf(InvViews.waste(db, ids), req, defaultLimit: 200, maxLimit: 1000),
    );
  });
}
