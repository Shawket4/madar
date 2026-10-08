/// The mock backend for The links page editor (`/settings/links`, SET-LNK rows).
///
/// Routes this unit answers: /orgs/{id}/links-page, /orgs/{id}/links-qr, GET /public/orgs/links. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerLinksMocks(MockServer server, MockDb db) {}
