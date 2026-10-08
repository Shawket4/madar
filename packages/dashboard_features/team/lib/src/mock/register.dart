/// The team area's mock backend: its handlers on the shared
/// [MockServer], over the seeded [MockDb] (registered after the core's, so a
/// handler here can replace a core route).
///
/// Order: the area seed's tables ([TeamSeed.loadInto]), the area's shared
/// reads (`team_reads_mock.dart`), then each unit's own endpoints. Every
/// endpoint has exactly ONE owning unit (listed in each `<unit>_mock.dart`);
/// a route registered twice is answered by the later registration, so a unit
/// never registers another unit's route. The owner of a shared read may
/// register it again with richer behaviour.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'approvals_mock.dart';
import 'attendance_mock.dart';
import 'employees_mock.dart';
import 'payroll_mock.dart';
import 'requests_mock.dart';
import 'rules_mock.dart';
import 'schedule_mock.dart';
import 'shifts_mock.dart';
import 'team_board_mock.dart';
import 'team_reads_mock.dart';
import 'team_reports_mock.dart';
import 'team_setup_mock.dart';

void registerTeamMocks(MockServer server, MockDb db) {
  TeamSeed.loadInto(db);
  registerTeamReadMocks(server, db);
  registerTeamSetupMocks(server, db);
  registerEmployeesMocks(server, db);
  registerAttendanceMocks(server, db);
  registerShiftsMocks(server, db);
  registerTeamBoardMocks(server, db);
  registerApprovalsMocks(server, db);
  registerScheduleMocks(server, db);
  registerRequestsMocks(server, db);
  registerPayrollMocks(server, db);
  registerTeamReportsMocks(server, db);
  registerRulesMocks(server, db);
}
