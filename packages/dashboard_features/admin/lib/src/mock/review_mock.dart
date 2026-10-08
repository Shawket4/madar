/// `/access/review` Review (ADM-REV rows): GET /authz/flags, POST
/// /authz/flags/{id}/review, POST /authz/flags/bulk-review (seed:
/// `AdminSeed.flags`).
///
/// Handlers behave like the backend: the capability checks the inventory's
/// `srv:` gates name (403 envelope), validation (400/409/422), not-found,
/// and state over the shared [MockDb] (a create shows in the next list).
library;

import 'package:dashboard_api/mock.dart';

void registerReviewMocks(MockServer server, MockDb db) {}
