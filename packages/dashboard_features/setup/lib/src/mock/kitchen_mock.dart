/// The mock backend for Kitchen stations and order routing (`/settings/kitchen-stations`, `/settings/kitchen-routing`, SET-KST and SET-KRT rows).
///
/// Routes this unit answers: /kitchen/stations…, /kitchen/routing-mode, /kitchen/routes…, GET /categories, GET /costing/catalog. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerKitchenMocks(MockServer server, MockDb db) {}
