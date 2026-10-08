/// The mock backend of the Employees incl. the Excel import (`/staff/employees`, TEAM-EMP and TEAM-ALL rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET|POST /staff/employees` (GET replaces the core's)
/// - `GET /staff/employees/linkable`
/// - `GET|PUT|DELETE /staff/employees/{employee_id}`
/// - `DELETE /staff/employees/{employee_id}/device`
/// - `GET|POST /staff/departments` (the list is shared: team_reads_mock.dart)
/// - `PATCH|DELETE /staff/departments/{id}`
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
library;

import 'package:dashboard_api/mock.dart';

void registerEmployeesMocks(MockServer server, MockDb db) {}
