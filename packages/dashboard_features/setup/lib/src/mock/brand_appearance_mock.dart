/// The mock backend for Brand and appearance (`/settings/brand`, `/settings`, SET-BRD, SET-APP and SET-SHL rows).
///
/// Routes this unit answers: PATCH /orgs/{id}, PUT /orgs/{id}/logo, PUT /orgs/{id}/card-image. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerBrandAppearanceMocks(MockServer server, MockDb db) {}
