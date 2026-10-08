/// The mock backend for Payment methods (`/settings/payment-methods`, SET-PAY rows).
///
/// Routes this unit answers: /payment-methods…, /payment-methods/availability…, GET /users, GET /devices. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerPaymentMethodsMocks(MockServer server, MockDb db) {}
