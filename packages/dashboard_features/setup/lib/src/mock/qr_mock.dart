/// The mock backend for QR codes and print cards (`/settings/qr`, SET-QR rows).
///
/// Routes this unit answers: the org/branch/table QR codes, GET /branches/{id}/tables. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerQrMocks(MockServer server, MockDb db) {}
