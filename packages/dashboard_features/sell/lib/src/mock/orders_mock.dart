/// The orders unit's mock backend: `/orders` and the order sheet: GET /orders (list + summary), GET /orders/{order_id},
/// POST /orders/{order_id}/void, GET /orders/export,
/// GET /reports/branches/{branch_id}/delivery-sales, GET /delivery-orders/{id},
/// GET /inventory/orgs/{org_id}/catalog, GET /menu-items (exclude-items control).
///
/// Handlers behave like the backend (SPEC 3.2): capability refusals as a 403
/// envelope WITHOUT a code (SELL-ALL-017), validation errors, not-found,
/// paging and filters, and state (a write shows in the next read). Shared
/// rows come from the area seed (`../area_seed.dart`, already loaded into
/// [db]); this unit's own extra rows are added here.
library;

import 'package:dashboard_api/mock.dart';

void registerOrdersMocks(MockServer server, MockDb db) {}
