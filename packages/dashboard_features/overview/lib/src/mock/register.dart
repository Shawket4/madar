/// The overview area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route).
///
/// The home's reads (inventory E1–E8; E7, the readiness the Setup card
/// reads, and E8, the org's modules, are the core's). Each one gates and scopes like the backend handler it stands in
/// for, and computes its figures from the same orders (`home_figures.dart`),
/// so the cards agree with each other.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import 'home_figures.dart';

/// `resolve_report_branches`: a real branch (the caller must work there and
/// it must exist), or for the nil id every branch of the org in scope that
/// THIS caller works at.
List<String> reportBranches(MockRequest req, MockDb db, String branchId) {
  if (branchId != nilBranchId) {
    req.requireBranch(branchId);
    final b = db['branches'].get(branchId, what: 'Branch not found');
    if (b['deleted_at'] != null) req.notFound('Branch not found');
    return [branchId];
  }
  final org = req.orgId;
  if (org == null) req.fail(MockResponse.forbidden('No organization in scope'));
  return [
    for (final b in db['branches'].rows)
      if (b['org_id'] == org &&
          b['deleted_at'] == null &&
          req.persona.seesBranch(b['id']! as String))
        b['id']! as String,
  ];
}

String _branchLabel(MockDb db, String branchId) => branchId == nilBranchId
    ? 'All branches'
    : db['branches'].get(branchId, what: 'Branch not found')['name']! as String;

void registerOverviewMocks(MockServer server, MockDb db) {
  // E1 — branch sales (`branch_sales`).
  server.on('GET', '/reports/branches/{branchId}/sales', (req) {
    req.requireCap('orders.read');
    final id = req.param('branchId');
    final ids = reportBranches(req, db, id);
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    return MockResponse.ok(
      branchSalesReport(
        branchId: id,
        branchName: _branchLabel(db, id),
        orders: ordersIn(db, ids, from: from, to: to),
        from: from,
        to: to,
        topLimit: req.qInt('limit') ?? 10,
      ),
    );
  });

  // E2 — the trend (`branch_sales_timeseries`).
  server.on('GET', '/reports/branches/{branchId}/sales/timeseries', (req) {
    req.requireCap('orders.read');
    final id = req.param('branchId');
    final ids = reportBranches(req, db, id);
    final g = req.q('granularity') ?? 'daily';
    return MockResponse.ok(
      salesTimeseries(
        ordersIn(db, ids, from: req.qDateTime('from'), to: req.qDateTime('to')),
        g == 'hourly' || g == 'monthly' ? g : 'daily',
        scopeZone(db, id, req.orgId),
      ),
    );
  });

  // E3 — every branch of the org, not narrowed to the caller's
  // (`org_branch_comparison`).
  server.on('GET', '/reports/orgs/{orgId}/comparison', (req) {
    req.requireCap('orders.read');
    final orgId = req.param('orgId');
    if (!req.persona.isPlatform && req.persona.orgId != orgId) {
      req.fail(MockResponse.forbidden('Not your org'));
    }
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    final rows = [
      for (final b in db['branches'].rows)
        if (b['org_id'] == orgId && b['deleted_at'] == null)
          branchComparisonRow(
            b,
            ordersIn(db, [b['id']! as String], from: from, to: to),
          ),
    ]..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    return MockResponse.ok(
      OrgComparisonReport(orgId: orgId, from: from, to: to, branches: rows),
    );
  });

  // E4 — delivery by channel (`branch_delivery_sales`).
  server.on('GET', '/reports/branches/{branchId}/delivery-sales', (req) {
    req.requireCap('orders.read');
    final ids = reportBranches(req, db, req.param('branchId'));
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    return MockResponse.ok(
      deliverySalesReport(
        deliveryOrdersIn(db, ids, from: from, to: to),
        from: from,
        to: to,
      ),
    );
  });

  // E5 — margin watch (`margin_watch`, snapshot costs).
  server.on('GET', '/insights/branches/{branchId}/margin-watch', (req) {
    req.requireCap('orders.read');
    final id = req.param('branchId');
    final ids = reportBranches(req, db, id);
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    final prev = previousWindow(from, to, req.now);
    return MockResponse.ok(
      marginWatch(
        branchId: id,
        orders: ordersIn(db, ids, from: from, to: to),
        prevOrders: prev == null
            ? const []
            : ordersIn(db, ids, from: prev.$1, to: prev.$2),
        from: from,
        to: to,
      ),
    );
  });

  // E6 — the branch's open tills, newest first (`list_open_tills`).
  server.on('GET', '/tills/branches/{branchId}/open', (req) {
    final id = req.param('branchId');
    req.requireCap('till.read', branchId: id);
    return MockResponse.ok(
      db['tills'].query(
        filters: {'branch_id': id, 'status': 'open'},
        sort: '-opened_at',
      ),
    );
  });
}
