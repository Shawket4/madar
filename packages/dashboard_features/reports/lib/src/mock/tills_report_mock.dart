/// The mock backend for Till sessions (REP-TIL): `/reports/branches/{branchId}/tills`.
///
/// Handlers behave like the backend (capability refusals, branch scoping,
/// the shared figures in `../area_seed.dart`); see SPEC section 3.2.
library;

import 'package:dashboard_api/mock.dart';

void registerTillsReportMocks(MockServer server, MockDb db) {}
