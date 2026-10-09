// Shared set-up for the Payroll unit's tests: the real app shell with the
// team area on a seeded mock server, edited per test before pumping.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/payroll/payroll_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String payrollPath = '/staff/payroll';
const String currentT = '/staff/payroll/current';
const String employeesT = '/staff/employees';
const String previewT = '/staff/payroll/periods/{id}/preview';
const String payslipsT = '/staff/payroll/periods/{id}/payslips';
const String generateT = '/staff/payroll/periods/{id}/generate';
const String statusT = '/staff/payroll/periods/{id}/status';
const String paidT = '/staff/payroll/periods/{id}/payslips/{employee_id}/paid';
const String csvT = '/staff/payroll/periods/{id}/export.csv';
const String linesT = '/staff/adjustments';
const String advancesT = '/staff/payroll/advances';
const String expensesT = '/staff/expense-advances';

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv payrollServer({
  Persona persona = Persona.owner,
  void Function(MockDb db)? edit,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  teamArea.registerMocks!(server, db);
  edit?.call(db);
  return (server: server, db: db);
}

/// Opens Payroll as [persona] on [s] (a fresh seeded server by default).
Future<DashHarness> pumpPayroll(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
  String path = payrollPath,
}) {
  final srv = s ?? payrollServer(persona: persona, edit: edit);
  return DashHarness.pump(
    tester,
    areas: const [teamArea],
    path: path,
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: srv.server,
    db: srv.db,
    shotArea: 'team',
  );
}

/// Answers `/authz/me` with only [caps] (everywhere unless [everywhere]).
void answerAuthz(
  MockServer server,
  List<String> caps, {
  List<String>? everywhere,
}) {
  server.on('GET', '/authz/me', (req) {
    final sorted = [...caps]..sort();
    return MockResponse.ok({
      'user_id': req.persona.userId,
      'branch_id': req.q('branch_id'),
      'capabilities': sorted,
      'everywhere': everywhere ?? sorted,
      'ask_manager': <String>[],
      'limits': <String, Object?>{},
      'owner': false,
      'platform': false,
      'role_kinds': req.persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    });
  });
}

/// [f] inside the page (not the sidebar or header).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(PayrollPage), matching: f);

/// Text inside the page.
Finder pageText(String text) => inPage(find.text(text));

/// The current month's period id (the mock opens it on first read).
String currentPeriodId(MockDb db, [String org = 'sabah']) =>
    db[TeamTables.payrollPeriods].rows
        .firstWhere(
          (p) =>
              p['org_id'] == SeedIds.sabahOrg &&
              (p['start_date']! as String).startsWith('2026-10'),
        )['id']!
        as String;
