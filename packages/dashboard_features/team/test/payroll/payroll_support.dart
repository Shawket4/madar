// Shared set-up for the Payroll unit's tests: the real app shell with the
// team area on a seeded mock server, edited per test before pumping.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show formatProvider;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/payroll/payroll_page.dart';
import 'package:flutter/material.dart';
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
    db[TeamTables.payrollPeriods].rows.firstWhere(
          (p) =>
              p['org_id'] == SeedIds.sabahOrg &&
              (p['start_date']! as String).startsWith('2026-10'),
        )['id']!
        as String;

/// [f] inside the topmost dialog, sheet or side panel.
Finder inTop(Finder f) => find
    .descendant(of: find.byType(DashSurface).last, matching: f)
    .hitTestable();

/// Text inside the topmost surface.
Finder topText(String text) => inTop(find.text(text));

/// A form field of type [T] labelled [label] in the topmost surface.
Finder field<T>(String label) => find
    .descendant(
      of: find.byType(DashSurface).last,
      matching: find.widgetWithText(T, label),
    )
    .first;

/// Types [text] into the field of type [T] labelled [label].
Future<void> type<T>(DashHarness h, String label, String text) =>
    h.enterText(field<T>(label), text);

/// Taps the topmost surface's button saying [label].
Future<void> press(DashHarness h, String label) =>
    h.tap(inTop(find.widgetWithText(DashButton, label)));

/// The confirm dialog's button saying [label].
Future<void> confirm(DashHarness h, String label) => h.tap(
  find
      .descendant(
        of: find.byType(DashConfirmDialog),
        matching: find.widgetWithText(DashButton, label),
      )
      .hitTestable(),
);

/// Approves this month through the page (TEAM-PAY-006).
Future<void> approveMonth(DashHarness h) async {
  await h.tap(inPage(find.widgetWithText(DashButton, h.t('dawam.approve'))));
  await confirm(h, h.t('dawam.approve'));
  await h.flushTimers();
}

/// The JSON body of the last [method] call to [template].
Map<String, Object?> lastBody(
  DashHarness h,
  String template, [
  String? method,
]) => (h.server.callsTo(template, method: method).last.body! as Map)
    .cast<String, Object?>();

/// Opens [name]'s payslip from the table.
Future<void> openSlip(DashHarness h, String name) =>
    h.tap(inPage(find.text(name)));

/// Leaves the app and comes back (a focus refetch).
Future<void> background(WidgetTester tester, DashHarness h) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await h.settle();
}

/// [iso] as the page writes a date.
String dateOf(DashHarness h, String iso) =>
    h.container.read(formatProvider).fmtDate(iso);

/// Links [employeeKey]'s employee row to the owner's sign-in.
void linkOwner(MockDb db, String employeeKey) => db['employees'].update(
  SeedIds.employee(employeeKey),
  {'user_id': SeedIds.owner},
);

/// September's period id.
String septemberId() => TeamSeedIds.period('sabah', '2026-09');

/// September approved with [unpaid] people still to pay.
void septemberUnpaid(MockDb db, {int unpaid = 3, String status = 'generated'}) {
  final id = septemberId();
  db[TeamTables.payrollPeriods].update(id, {'status': status});
  var n = 0;
  for (final s in db['payslips'].rows.toList()) {
    if (s['payroll_period_id'] != id || n >= unpaid) continue;
    db['payslips'].update(s['id']! as String, {
      'paid_method': null,
      'paid_at': null,
    });
    n++;
  }
}

/// Shoots the page top to bottom (`payroll/<name>-1`, `-2`, …, at most 4).
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(
        of: find.byType(PayrollPage),
        matching: find.byType(Scrollable),
      )
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .where((s) => s.position.axis == Axis.vertical)
      .toList();
  if (scroll.isEmpty) {
    await h.shot('payroll/$name-1');
    return;
  }
  final position = scroll.first.position;
  var y = 0.0;
  for (var i = 1; i <= 4; i++) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('payroll/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
  }
}
