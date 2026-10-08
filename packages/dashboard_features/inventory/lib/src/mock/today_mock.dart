/// Today: the mock backend for the INV-TOD rows. Routes this unit owns
/// (the only file that registers them):
///
/// - GET /reports/branches/{branch_id}/inventory-valuation (branchInventoryValuation)
/// - GET /reports/orgs/{org_id}/inventory-valuation (orgInventoryValuation)
/// - GET /reports/branches/{branch_id}/low-stock (branchLowStock)
/// - GET /reports/orgs/{org_id}/low-stock (orgLowStock)
///
/// Answer from `InvViews.valuation` / `InvViews.lowStock` (the reports
/// area reads the same routes; keep the shapes identical).
///
/// As the backend (`MadarRust/src/reports/handlers.rs:1918-2090`):
/// - every route needs `inventory.read` (checked first);
/// - a branch route answers for that branch (403 when the person does not
///   work there, 404 for an unknown branch) or, for the all-branches
///   sentinel, every branch of the org in scope the person works at (403
///   "No organization in scope" without one);
/// - an org route answers 403 "Not your org" for another org, and rolls up
///   EVERY branch of the org (`require_org` only, no branch scoping).
library;

import 'package:dashboard_api/mock.dart';

import 'inventory_views.dart';

const String _allBranches = '00000000-0000-0000-0000-000000000000';

void registerTodayMocks(MockServer server, MockDb db) {
  /// The branches a `/reports/branches/{branch_id}/…` read covers.
  List<String> branchIds(MockRequest req) {
    final id = req.param('branch_id');
    if (id == _allBranches && req.orgId == null) {
      req.fail(MockResponse.forbidden('No organization in scope'));
    }
    return InvScope.branchIds(req, db, id);
  }

  /// Every branch of the org a `/reports/orgs/{org_id}/…` read names.
  List<String> orgBranchIds(MockRequest req) {
    final orgId = req.param('org_id');
    if (!req.persona.isPlatform && req.persona.orgId != orgId) {
      req.fail(MockResponse.forbidden('Not your org'));
    }
    return [
      for (final b in db['branches'].query(filters: {'org_id': orgId}))
        b['id']! as String,
    ];
  }

  server.on('GET', '/reports/branches/{branch_id}/inventory-valuation', (req) {
    req.requireCap('inventory.read');
    return MockResponse.ok(InvViews.valuation(db, branchIds(req)));
  });

  server.on('GET', '/reports/orgs/{org_id}/inventory-valuation', (req) {
    req.requireCap('inventory.read');
    return MockResponse.ok(InvViews.valuation(db, orgBranchIds(req)));
  });

  server.on('GET', '/reports/branches/{branch_id}/low-stock', (req) {
    req.requireCap('inventory.read');
    return MockResponse.ok(InvViews.lowStock(db, branchIds(req)));
  });

  server.on('GET', '/reports/orgs/{org_id}/low-stock', (req) {
    req.requireCap('inventory.read');
    return MockResponse.ok(InvViews.lowStock(db, orgBranchIds(req)));
  });
}
