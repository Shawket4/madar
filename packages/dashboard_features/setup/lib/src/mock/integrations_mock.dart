/// The mock backend for Integrations (`/settings/integrations`, SET-INT rows).
///
/// Routes this unit answers: /integrations/credentials…. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerIntegrationsMocks(MockServer server, MockDb db) {}
