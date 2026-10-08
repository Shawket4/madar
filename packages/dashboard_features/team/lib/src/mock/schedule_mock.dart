/// The mock backend of the Schedule (`/staff/schedule`, TEAM-SCH rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/roster`
/// - `GET|PUT /staff/roster/coverage`
/// - `GET /staff/roster/fairness`
/// - `GET /staff/roster/fairness/audits`
/// - `POST /staff/roster/publish`
/// - `GET /staff/roster/suggestions`
/// - `POST /staff/roster/suggestions/decide`
/// - `PUT /staff/holidays/{date}`
/// - `PUT|DELETE /staff/schedules/days`
/// - `POST /staff/schedules/days/move`
/// - `PUT /staff/schedules/days/times`
/// - `GET|POST /staff/open-shifts` (the list is shared: team_reads_mock.dart)
/// - `POST /staff/open-shifts/{id}/cancel`
/// - `PUT /staff/employees/{id}/preferences`
/// - `GET /staff/employees/{id}/preferences/log`
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
library;

import 'package:dashboard_api/mock.dart';

void registerScheduleMocks(MockServer server, MockDb db) {}
