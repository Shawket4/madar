/// The mock backend of the Approvals (`/staff/approvals`, TEAM-APR rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/swaps`
/// - `PATCH /staff/swaps/{id}/decision`
/// - `PATCH /staff/open-shifts/{id}/decision`
/// - `PATCH /staff/attendance/{id}/cover`
/// - `PATCH /staff/attendance/{id}/overtime`
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
library;

import 'package:dashboard_api/mock.dart';

void registerApprovalsMocks(MockServer server, MockDb db) {}
