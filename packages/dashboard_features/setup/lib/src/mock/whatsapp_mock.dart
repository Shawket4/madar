/// The mock backend for WhatsApp pairing, platform admins only (`/settings/whatsapp`, SET-WA rows).
///
/// Routes this unit answers: /whatsapp/status, /whatsapp/pair, /whatsapp/logout, /whatsapp/pause. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerWhatsappMocks(MockServer server, MockDb db) {}
