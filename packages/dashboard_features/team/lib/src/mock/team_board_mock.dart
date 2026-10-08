/// The mock backend of the Team (`/staff/team`, TEAM-TEM rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/team/presence`
/// - `GET /staff/flags`
/// - `PATCH /staff/flags/{id}`
/// - `POST /staff/attendance/punch`
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
library;

import 'package:dashboard_api/mock.dart';

void registerTeamBoardMocks(MockServer server, MockDb db) {}
