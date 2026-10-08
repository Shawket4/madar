/// The floor unit's mock backend: `/floor`: GET/POST /floor/sections, PATCH/DELETE /floor/sections/{id},
/// GET/POST /floor/tables, PATCH/DELETE /floor/tables/{id}, PUT /floor/layout,
/// GET /floor/transfers, POST /floor/transfers/{id}/fulfill|cancel,
/// GET /floor/tables/{id}/history, GET /open-tickets.
///
/// Handlers behave like the backend (SPEC 3.2): capability refusals as a 403
/// envelope WITHOUT a code (SELL-ALL-017), validation errors, not-found,
/// paging and filters, and state (a write shows in the next read). Shared
/// rows come from the area seed (`../area_seed.dart`, already loaded into
/// [db]); this unit's own extra rows are added here.
library;

import 'package:dashboard_api/mock.dart';

void registerFloorMocks(MockServer server, MockDb db) {}
