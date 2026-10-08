/// `/access/roles` Roles & Permissions (ADM-ROL rows): GET/POST /authz/roles,
/// PATCH/DELETE /authz/roles/{id}, PUT /authz/roles/{id}/grants, GET/PUT
/// /authz/policy (seed: the core `roles` table and `AdminSeed.policy`).
///
/// Handlers behave like the backend: the capability checks the inventory's
/// `srv:` gates name (403 envelope), validation (400/409/422), not-found,
/// and state over the shared [MockDb] (a create shows in the next list).
library;

import 'package:dashboard_api/mock.dart';

void registerRolesMocks(MockServer server, MockDb db) {}
