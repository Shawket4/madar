// Shared set-up for the Requests unit's tests: the real app shell with the
// team area on a seeded mock server, edited per test before pumping.
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/requests/requests_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String requestsPath = '/staff/requests';
const String listT = '/staff/requests';
const String decideT = '/staff/requests/{id}/decision';
const String employeesT = '/staff/employees';
const String attendanceT = '/staff/attendance';

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv requestsServer({
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

/// Opens Requests as [persona] on [s] (a fresh seeded server by default).
Future<DashHarness> pumpRequests(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
  String path = requestsPath,
}) {
  final srv = s ?? requestsServer(persona: persona, edit: edit);
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

/// A request row as the model writes it, for a test's own data.
MockRow requestRow({
  required String id,
  required String employeeKey,
  required String kind,
  required String onDate,
  String status = 'pending',
  String? endDate,
  String? fromTime,
  String? toTime,
  String? reason,
  String? title,
  bool isHalfDay = false,
  String? leaveHalf,
  bool? paidDefault,
  bool? isPaid,
  bool? canDecide,
  List<String>? workedDates,
  DateTime? recordCheckInAt,
  DateTime? recordCheckOutAt,
  String? decidedByName,
  String? decisionNote,
  String? cancelledBy,
  String? cancelledByName,
  String? cancelNote,
  DateTime? createdAt,
}) {
  final e = MockSeed.instance.employees.firstWhere(
    (e) => e.id == emp(employeeKey),
  );
  final at = createdAt ?? DateTime.utc(2026, 10, 7, 9);
  return StaffRequest(
    id: id,
    orgId: e.orgId,
    employeeId: e.id,
    employeeName: e.name,
    kind: kind,
    status: status,
    onDate: onDate,
    endDate: endDate,
    fromTime: fromTime,
    toTime: toTime,
    isHalfDay: isHalfDay,
    leaveHalf: leaveHalf,
    paidDefault: paidDefault,
    isPaid: isPaid,
    canDecide: canDecide,
    workedDates: workedDates,
    recordCheckInAt: recordCheckInAt,
    recordCheckOutAt: recordCheckOutAt,
    reason: reason,
    title: title,
    decidedBy: decidedByName == null ? null : SeedIds.owner,
    decidedByName: decidedByName,
    decisionNote: decisionNote,
    cancelledBy: cancelledBy,
    cancelledByName: cancelledByName,
    cancelNote: cancelNote,
    createdAt: at,
    updatedAt: at,
  ).toJson();
}

/// Only [rows] in the requests table.
void onlyRequests(MockDb db, List<MockRow> rows) {
  db[TeamTables.requests]
    ..removeWhere((_) => true)
    ..insertAll(rows);
}

// ── Calls ──────────────────────────────────────────────────────────────────

int gets(DashHarness h, [String t = listT]) =>
    h.server.callsTo(t, method: 'GET').length;

/// The query of the last list read.
Map<String, List<String>> lastQuery(DashHarness h) =>
    h.server.callsTo(listT, method: 'GET').last.query;

Map<String, Object?> lastBody(DashHarness h, String t, [String m = 'PATCH']) =>
    (h.server.callsTo(t, method: m).last.body! as Map).cast<String, Object?>();

int patches(DashHarness h) => h.server.callsTo(decideT, method: 'PATCH').length;

// ── Finders ────────────────────────────────────────────────────────────────

final Finder page = find.byType(RequestsInboxPage);

Finder inPage(Finder f) => find.descendant(of: page, matching: f);

Finder pageText(String s) => inPage(find.text(s));

/// Text containing [s] (rich text too) on the page.
Finder pageHas(String s) => inPage(find.textContaining(s, findRichText: true));

/// The row whose words show [text].
Finder rowOf(String text) => find
    .ancestor(of: pageHas(text).first, matching: find.byType(RequestRow))
    .first;

Finder inRow(String text, Finder f) =>
    find.descendant(of: rowOf(text), matching: f);

/// The row's request.
StaffRequest requestOf(WidgetTester tester, String text) =>
    tester.widget<RequestRow>(rowOf(text)).request;

Finder approveIn(String text) => inRow(
  text,
  find.byWidgetPredicate((w) => w is DashButton && w.icon == 'check'),
);

Finder rejectIn(String text) => inRow(
  text,
  find.byWidgetPredicate((w) => w is DashIconButton && w.icon == 'x'),
);

Finder cancelIn(String text) => inRow(
  text,
  find.byWidgetPredicate((w) => w is DashIconButton && w.icon == 'ban'),
);

/// The open dialog / sheet (the last `DashSurface`).
Finder surface() => find.byType(DashSurface).last;

Finder inSurface(Finder f) => find.descendant(of: surface(), matching: f);

Finder surfaceText(String s) => inSurface(find.text(s));

Finder confirmCard() => find.byType(DashConfirmDialog);

Finder inConfirm(Finder f) => find.descendant(of: confirmCard(), matching: f);

/// How many rows the list shows.
int rowCount() => inPage(find.byType(RequestRow)).evaluate().length;

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  List<ScrollableState> vertical(Finder f) => f
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .where((s) => s.position.axis == Axis.vertical)
      .toList();
  final scroll = [
    ...vertical(find.descendant(of: page, matching: find.byType(Scrollable))),
    ...vertical(find.ancestor(of: page, matching: find.byType(Scrollable))),
  ];
  if (scroll.isEmpty) {
    await h.shot('requests/$name-1');
    return;
  }
  final position = scroll.first.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('requests/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}
