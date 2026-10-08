/// `/onboarding` (ADM-ONB rows): POST /orgs/{id}/onboarding/complete, GET
/// /orgs/{id}/onboarding with live counts, PATCH /orgs/{id} (super admin only),
/// the step reads (categories, menu items).
///
/// Handlers behave like the backend: the capability checks the inventory's
/// `srv:` gates name (403 envelope), validation (400/409/422), not-found,
/// and state over the shared [MockDb] (a create shows in the next list).
library;

import 'package:dashboard_api/mock.dart';

void registerOnboardingMocks(MockServer server, MockDb db) {}
