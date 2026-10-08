/// The mock backend of the Work shifts (`/staff/shifts`, TEAM-SHF rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET|POST /staff/work-shifts` (GET replaces the core's)
/// - `PATCH|DELETE /staff/work-shifts/{id}`
/// - `GET|POST /staff/schedules`
/// - `DELETE /staff/schedules/{id}`
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
library;

import 'package:dashboard_api/mock.dart';

void registerShiftsMocks(MockServer server, MockDb db) {}
