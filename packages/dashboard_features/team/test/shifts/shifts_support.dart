// Shared set-up for the Work shifts unit's tests: the real app shell with the
// team area on a seeded mock server, edited per test before pumping.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/shifts/schedule_grid.dart';
import 'package:dashboard_team/src/shifts/shifts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String shiftsPath = '/staff/shifts';
const String shiftsT = '/staff/work-shifts';
const String shiftT = '/staff/work-shifts/{id}';
const String rosterT = '/staff/schedules';
const String rosterRowT = '/staff/schedules/{id}';
const String employeesT = '/staff/employees';

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv shiftsServer({
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

/// Opens Work shifts as [persona] on [s] (a fresh seeded server by default).
Future<DashHarness> pumpShifts(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
  String path = shiftsPath,
}) {
  final srv = s ?? shiftsServer(persona: persona, edit: edit);
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

/// Answers `/authz/me` with only [caps] (held at every branch unless
/// [everywhere] says otherwise).
void answerAuthz(
  MockServer server,
  List<String> caps, {
  List<String>? everywhere,
  bool owner = false,
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
      'owner': owner,
      'platform': false,
      'role_kinds': req.persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    });
  });
}

// ── Seed helpers ───────────────────────────────────────────────────────────

String sabahShift(String key) => TeamSeedIds.workShift('sabah', key);
String emp(String key) => SeedIds.employee(key);

/// The ids of the blocks [addDemoShifts] adds.
final String eveningZ = mockUuid('work-shift:test:evening-zamalek');
final String brunch = mockUuid('work-shift:test:brunch');
final String maadiLate = mockUuid('work-shift:test:maadi-late');
final String oldNight = mockUuid('work-shift:test:old-night');

/// A Zamalek block that runs past midnight with its own Thu/Fri times and
/// its own rates (the web test's `evening`), a business-wide Brunch that
/// does not run on Friday, a Maadi block, and a switched-off night that is
/// over the presence cap (14 h).
void addDemoShifts(MockDb db) {
  final t = db['work_shifts'];
  MockRow base(String id, String name) => {
    'id': id,
    'org_id': SeedIds.sabahOrg,
    'name': name,
    'grace_minutes': 15,
    'break_minutes': 30,
    'paid_break': true,
    'overtime_threshold_minutes': 15,
    'overtime_multiplier': 1.5,
    'checkin_window_minutes': 120,
    'is_active': true,
    'valid_days': [0, 1, 2, 3, 4, 5, 6],
    'day_times': <Object?>[],
    'created_at': '2026-09-01T09:00:00Z',
    'updated_at': '2026-09-01T09:00:00Z',
  };
  t
    ..insert({
      ...base(eveningZ, 'Late evening'),
      'branch_id': SeedIds.zamalek,
      'start_time': '16:00:00',
      'end_time': '00:00:00',
      'ot_day_multiplier': 1.75,
      'ot_night_multiplier': 2,
      'day_times': [
        {'day_of_week': 4, 'start_time': '16:00:00', 'end_time': '01:00:00'},
        {'day_of_week': 5, 'start_time': '16:00:00', 'end_time': '01:00:00'},
      ],
    }, timestamps: false)
    ..insert({
      ...base(brunch, 'Brunch'),
      'start_time': '10:00:00',
      'end_time': '14:00:00',
      'grace_minutes': 5,
      'valid_days': [6, 0, 1, 2, 3, 4],
    }, timestamps: false)
    ..insert({
      ...base(maadiLate, 'Maadi late'),
      'branch_id': SeedIds.maadi,
      'start_time': '18:00:00',
      'end_time': '02:00:00',
    }, timestamps: false)
    ..insert({
      ...base(oldNight, 'Old night'),
      'branch_id': SeedIds.zamalek,
      'start_time': '18:00:00',
      'end_time': '09:00:00',
      'is_active': false,
    }, timestamps: false);
}

/// Every Sabah roster row gone (and the blocks free to delete).
void noRoster(MockDb db) => db[TeamTables.assignments].removeWhere(
  (a) => a['org_id'] == SeedIds.sabahOrg,
);

// ── Finders ────────────────────────────────────────────────────────────────

final Finder page = find.byType(WorkShiftsPage);

Finder inPage(Finder f) => find.descendant(of: page, matching: f);

Finder pageText(String s) => inPage(find.text(s));

Finder grid() => find.byType(ScheduleGrid);

Finder inGrid(Finder f) => find.descendant(of: grid(), matching: f);

/// The shift list row of [id].
Finder shiftRow(String id) => find.byKey(ValueKey('shift-$id'));

Finder inRow(String id, Finder f) =>
    find.descendant(of: shiftRow(id), matching: f);

/// The grid cell of [employeeKey] on [dow] (null = the every-day column).
Finder cell(String employeeKey, int? dow) =>
    find.byKey(ValueKey('roster-${emp(employeeKey)}-${dow ?? 'all'}'));

/// The open dialog / sheet (the last `DashSurface`).
Finder surface() => find.byType(DashSurface).last;

Finder inSurface(Finder f) => find.descendant(of: surface(), matching: f);

Finder surfaceText(String s) => inSurface(find.text(s));

/// The confirm card.
Finder confirmText(String s) => find.descendant(
  of: find.byType(DashConfirmDialog).last,
  matching: find.text(s),
);

/// Text containing [s] (rich text too).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// The [i]th time box in the dialog.
Finder timeBox(int i) => find.descendant(
  of: inSurface(find.byType(DashTimeField)).at(i),
  matching: find.byType(EditableText),
);

/// The time box a screen reader calls [label].
Finder timeNamed(String label) => find.descendant(
  of: inSurface(
    find.byWidgetPredicate(
      (w) => w is DashTimeField && w.semanticLabel == label,
    ),
  ),
  matching: find.byType(EditableText),
);

/// Types [text] into [box] and leaves it (Enter settles the reading).
Future<void> typeIn(DashHarness h, Finder box, String text) async {
  await h.tester.ensureVisible(box);
  await h.enterText(box, text);
  await h.tester.testTextInput.receiveAction(TextInputAction.done);
  await h.settle();
}

String shownIn(WidgetTester tester, Finder box) =>
    tester.widget<EditableText>(box).controller.text;

/// The number box a screen reader calls [label].
Finder numberNamed(String label) => find.descendant(
  of: inSurface(
    find.byWidgetPredicate(
      (w) => w is DashNumberInput && w.semanticLabel == label,
    ),
  ),
  matching: find.byType(EditableText),
);

/// The text box under the label [label].
Finder textNamed(String label) => find.descendant(
  of: inSurface(
    find.byWidgetPredicate((w) => w is DashTextField && w.label == label),
  ),
  matching: find.byType(EditableText),
);

Finder save() => inSurface(find.byKey(const ValueKey('shift-save')));

/// What a person reads for the server's refusal [r]: the app's words for it
/// (`h.refusalWords`), without the kind the server writes before its
/// sentence, as the web's `getErrorMessage` strips it.
String refusal(DashHarness h, MockResponse r) => h
    .refusalWords(r)
    .replaceFirst(
      RegExp(
        '^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
        'Service unavailable|Database error): ',
      ),
      '',
    );

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
    await h.shot('shifts/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}
