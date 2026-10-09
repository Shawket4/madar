// Shared set-up for the Attendance unit's tests: the real app shell with the
// team area on a seeded mock server, edited per test before pumping.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/attendance/attendance_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String attendancePath = '/staff/attendance';
const String listT = '/staff/attendance';
const String summaryT = '/staff/attendance/summary';
const String recordT = '/staff/attendance/{id}';
const String employeesT = '/staff/employees';

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv attendanceServer({
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

/// Opens Attendance as [persona] on [s] (a fresh seeded server by default).
Future<DashHarness> pumpAttendance(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
  Map<String, String>? prefs,
}) {
  final srv = s ?? attendanceServer(persona: persona, edit: edit);
  return DashHarness.pump(
    tester,
    areas: const [teamArea],
    path: attendancePath,
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: srv.server,
    db: srv.db,
    shotArea: 'team',
    prefs: prefs,
  );
}

/// Answers `/authz/me` with only [caps].
void answerAuthz(MockServer server, List<String> caps) {
  server.on('GET', '/authz/me', (req) {
    final sorted = [...caps]..sort();
    return MockResponse.ok({
      'user_id': req.persona.userId,
      'branch_id': req.q('branch_id'),
      'capabilities': sorted,
      'everywhere': sorted,
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

// ── Seed helpers ───────────────────────────────────────────────────────────

String emp(String key) => SeedIds.employee(key);

/// Today in Cairo (`2026-10-08`) and [n] days from it.
String day([int n = 0]) {
  final d = DateTime.utc(2026, 10, 8).add(Duration(days: n));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// [hhmm] on [date] in Cairo as an ISO instant.
String cairo(String date, String hhmm) {
  final p = date.split('-').map(int.parse).toList();
  final t = hhmm.split(':').map(int.parse).toList();
  return MockClock.fromCairo(p[0], p[1], p[2], t[0], t[1]).toIso8601String();
}

MockTable records(MockDb db) => db[TeamTables.attendance];

/// Sabah's seeded records in the default window (the last 7 days).
List<MockRow> windowRows(MockDb db, {String? branchId}) => records(db)
    .where(
      (r) =>
          r['org_id'] == SeedIds.sabahOrg &&
          (r['business_date']! as String).compareTo(day(-6)) >= 0 &&
          (r['business_date']! as String).compareTo(day()) <= 0 &&
          (branchId == null || r['branch_id'] == branchId),
    );

/// A record row as the model writes it, for a test's own data.
MockRow recordRow({
  required String id,
  required String employeeKey,
  required String date,
  String status = 'present',
  String? branchId,
  String? inAt,
  String? outAt,
  String? inMethod,
  String? outMethod,
  String? workShiftId,
  String? workShiftName,
  int late = 0,
  int early = 0,
  int overtime = 0,
  int worked = 0,
  String? scheduledStart,
  String? scheduledEnd,
  double? distance,
  String? punchReason,
  String? outReason,
  String? coveredEmployeeId,
  String? coverStatus,
}) => AttendanceRecord(
  id: id,
  orgId: SeedIds.sabahOrg,
  branchId: branchId ?? SeedIds.zamalek,
  employeeId: emp(employeeKey),
  employeeName: MockSeed.instance.employees
      .firstWhere((e) => e.id == emp(employeeKey))
      .name,
  businessDate: date,
  workShiftId: workShiftId,
  workShiftName: workShiftName,
  status: status,
  checkInAt: inAt == null ? null : DateTime.parse(inAt),
  checkOutAt: outAt == null ? null : DateTime.parse(outAt),
  checkInMethod: inMethod,
  checkOutMethod: outMethod,
  lateMinutes: late,
  earlyLeaveMinutes: early,
  overtimeMinutes: overtime,
  workedMinutes: worked,
  scheduledStartAt: scheduledStart == null
      ? null
      : DateTime.parse(scheduledStart),
  scheduledEndAt: scheduledEnd == null ? null : DateTime.parse(scheduledEnd),
  checkInDistanceMeters: distance,
  punchReason: punchReason,
  checkOutReason: outReason,
  coveredEmployeeId: coveredEmployeeId,
  coverStatus: coverStatus,
  isManual: false,
  trackingOff: false,
  createdAt: DateTime.parse(cairo(date, '07:00')),
  updatedAt: DateTime.parse(cairo(date, '07:00')),
).toJson();

/// Replaces every Sabah record with [rows].
void onlyRecords(MockDb db, List<MockRow> rows) {
  records(db).removeWhere((r) => r['org_id'] == SeedIds.sabahOrg);
  records(db).insertAll(rows);
}

// ── Finders ────────────────────────────────────────────────────────────────

final Finder page = find.byType(AttendancePage);

Finder inPage(Finder f) => find.descendant(of: page, matching: f);

Finder pageText(String s) => inPage(find.text(s));

Finder table() => inPage(find.byType(DashDataTable<AttendanceRecord>));

Finder inTable(Finder f) => find.descendant(of: table(), matching: f);

Finder tableText(String s) => inTable(find.text(s));

/// The open dialog / sheet (the last `DashSurface`).
Finder surface() => find.byType(DashSurface).last;

Finder inSurface(Finder f) => find.descendant(of: surface(), matching: f);

Finder surfaceText(String s) => inSurface(find.text(s));

/// Text containing [s] (rich text too).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// What a person reads for the server's refusal [r], as `getErrorMessage`
/// words it (the kind prefix stripped).
String refusal(DashHarness h, MockResponse r) => h
    .refusalWords(r)
    .replaceFirst(
      RegExp(
        '^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
        'Service unavailable|Database error): ',
      ),
      '',
    );

/// The page's own list calls (the Add dialog's look-ahead excluded).
List<MockCall> pageListCalls(DashHarness h) => h.server
    .callsTo(listT, method: 'GET')
    .where((c) => c.headers['X-Madar-Export'] == null)
    .toList();

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: page, matching: find.byType(Scrollable))
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .firstWhere((s) => s.position.axis == Axis.vertical);
  final position = scroll.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('attendance/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}
