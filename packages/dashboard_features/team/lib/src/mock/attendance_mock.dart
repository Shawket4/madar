/// The mock backend of the Attendance (`/staff/attendance`, TEAM-ATT rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET|POST /staff/attendance` (the list is shared: team_reads_mock.dart)
/// - `PATCH /staff/attendance/{id}`
/// - `GET /staff/attendance/summary`
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
library;

import 'package:dashboard_api/mock.dart';

void registerAttendanceMocks(MockServer server, MockDb db) {}
