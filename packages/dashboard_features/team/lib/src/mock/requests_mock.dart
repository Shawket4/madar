/// The mock backend of the Requests (`/staff/requests`, TEAM-REQ rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET|POST /staff/requests` (the list is shared: team_reads_mock.dart)
/// - `PATCH /staff/requests/{id}/decision`
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
library;

import 'package:dashboard_api/mock.dart';

void registerRequestsMocks(MockServer server, MockDb db) {}
