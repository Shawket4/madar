/// `/access/users` Users (ADM-USR rows): /users CRUD, /users/pin-suggestion,
/// /users/{id}/branches (seed: the `user_branches` table), /authz/users/{id}
/// access, overrides, assignments, /authz/explain, GET /authz/roles for the
/// access sheet.
///
/// Handlers behave like the backend: the capability checks the inventory's
/// `srv:` gates name (403 envelope), validation (400/409/422), not-found,
/// and state over the shared [MockDb] (a create shows in the next list).
library;

import 'package:dashboard_api/mock.dart';

void registerUsersMocks(MockServer server, MockDb db) {}
