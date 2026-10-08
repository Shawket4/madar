/// The mock backend for Delivery settings and zones (`/settings/delivery`, `/settings/delivery-zones`, SET-DLV and SET-DZN rows).
///
/// Routes this unit answers: /delivery/settings, /delivery/zones…, GET /discounts. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerDeliveryMocks(MockServer server, MockDb db) {}
