/// The mock backend for Loyalty settings and members admin (`/settings/loyalty`, SET-LOY rows).
///
/// Routes this unit answers: GET/PUT/DELETE /loyalty/settings, /loyalty/reward-items, /loyalty/earning-items, /loyalty/members…, /loyalty/adjust, /loyalty/analytics, /loyalty/wallet-status, /loyalty/birthday-preview, the loyalty QR codes, GET /menu-items, GET /customers. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerLoyaltyMocks(MockServer server, MockDb db) {}
