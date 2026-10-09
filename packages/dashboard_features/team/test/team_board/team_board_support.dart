// Shared set-up for the Team board's tests: the real app shell with the team
// area on a seeded mock server, edited per test before pumping.
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/team_board/team_board_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String teamPath = '/staff/team';
const String presenceT = '/staff/team/presence';
const String flagsT = '/staff/flags';
const String resolveT = '/staff/flags/{id}';
const String punchT = '/staff/attendance/punch';
const String attendanceT = '/staff/attendance';
const String employeesT = '/staff/employees';

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv teamServer({
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

/// Opens the Team board as [persona] on [s] (a fresh seeded server by
/// default).
Future<DashHarness> pumpTeam(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
  String path = teamPath,
}) {
  final srv = s ?? teamServer(persona: persona, edit: edit);
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

/// Answers `/authz/me` with only [caps], [ask] (may ask a manager) and the
/// `hr.deductions.create` [deductLimit] (piastres).
void answerAuthz(
  MockServer server,
  List<String> caps, {
  List<String> ask = const [],
  int? deductLimit,
}) {
  server.on('GET', '/authz/me', (req) {
    final sorted = [...caps]..sort();
    return MockResponse.ok({
      'user_id': req.persona.userId,
      'branch_id': req.q('branch_id'),
      'capabilities': sorted,
      'everywhere': sorted,
      'ask_manager': ask,
      'limits': <String, Object?>{
        if (deductLimit != null)
          'hr.deductions.create': {'max_amount': deductLimit},
      },
      'owner': false,
      'platform': false,
      'role_kinds': req.persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    });
  });
}

/// The seed's open flags (newest first) and today's date.
String get today => TeamSeed.today;

String flagId(String key) => TeamSeedIds.flag(key);

MockRow flagRow(MockDb db, String key) => db[TeamTables.flags].find(flagId(key))!;

/// Adds a flag of [kind] for [employeeKey] at Zamalek (or [branchId]).
MockRow addFlag(
  MockDb db,
  String key, {
  required String kind,
  String employeeKey = 'omar',
  String? branchId,
  int minutesAway = 0,
  int suggested = 0,
  String? recordId,
}) {
  final e = db['employees'].find(SeedIds.employee(employeeKey))!;
  return db[TeamTables.flags].put({
    'id': flagId(key),
    'employee_id': e['id'],
    'employee_name': e['name'],
    'branch_id': branchId ?? (e['branch_ids']! as List).first,
    'attendance_record_id': recordId,
    'kind': kind,
    'minutes_away': minutesAway,
    'detected_at': '2026-10-08T06:30:00.000Z',
    'resolution': null,
    'resolved_at': null,
    'suggested_deduction_piastres': suggested,
  });
}

// ── Finders ────────────────────────────────────────────────────────────────

final Finder board = find.byType(TeamBoard);

Finder inBoard(Finder f) => find.descendant(of: board, matching: f);

Finder boardText(String s) => inBoard(find.text(s));

/// Text containing [s] (rich text too) on the board.
Finder boardHas(String s) => inBoard(find.textContaining(s, findRichText: true));

/// The list row whose title is [title].
Finder rowOf(String title) => find
    .ancestor(of: boardText(title).first, matching: find.byType(DashListRow))
    .first;

Finder inRow(String title, Finder f) =>
    find.descendant(of: rowOf(title), matching: f);

/// A button labelled [label] on the board.
Finder boardButton(String label) => inBoard(
  find.byWidgetPredicate((w) => w is DashButton && w.label == label),
);

/// The open dialog (the last `DashSurface`).
Finder surface() => find.byType(DashSurface).last;

Finder inSurface(Finder f) => find.descendant(of: surface(), matching: f);

Finder surfaceText(String s) => inSurface(find.text(s));

Finder surfaceButton(String label) => inSurface(
  find.byWidgetPredicate((w) => w is DashButton && w.label == label),
);

/// The stat card labelled [label].
Finder statCard(String label) => inBoard(
  find.byWidgetPredicate((w) => w is DashStatCard && w.label == label),
);

/// A presence row's DashButton enabled state.
bool enabled(WidgetTester tester, Finder button) =>
    tester.widget<DashButton>(button).onPressed != null;

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .ancestor(of: board, matching: find.byType(Scrollable))
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .where((s) => s.position.axis == Axis.vertical)
      .toList();
  if (scroll.isEmpty) {
    await h.shot('team_board/$name-1');
    return;
  }
  final position = scroll.first.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('team_board/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
  position.jumpTo(0);
  await h.settle(rounds: 2);
}

/// The seed's people, by key.
Employee person(String key) => TeamSeed.instance.employee(key);
