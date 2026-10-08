/// The mock backend for Combos and deals settings (`/settings/combos`, SET-CMB rows).
///
/// Routes this unit answers: /settings/combos, /settings/combos/branches/{branch_id}. Behave like the backend: the
/// capability checks (`req.requireCap`), the 403/404/409/422 envelopes, and
/// state (a write shows in the next read). Shared records live in
/// `../area_seed.dart` (`SetupSeed`); a route another area also answers goes
/// through `onIfAbsent` (`support.dart`).
library;

import 'package:dashboard_api/mock.dart';

void registerComboSettingsMocks(MockServer server, MockDb db) {}
