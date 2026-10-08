/// The mock backend for Staff drinks settings (`/settings/staff-pool`, SET-SPL rows).
///
/// Routes this unit answers: /staff-pool/settings, GET /menu-items. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerStaffPoolMocks(MockServer server, MockDb db) {}
