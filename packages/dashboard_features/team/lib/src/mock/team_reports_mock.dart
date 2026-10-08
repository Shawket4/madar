/// The mock backend of the Team reports (`/staff/reports`, TEAM-RPT rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/reports/advances`
/// - `GET /staff/reports/labour-vs-sales`
/// - `GET /staff/reports/payroll-history`
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
library;

import 'package:dashboard_api/mock.dart';

void registerTeamReportsMocks(MockServer server, MockDb db) {}
