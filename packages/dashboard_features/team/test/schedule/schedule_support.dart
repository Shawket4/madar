// Shared set-up for the Schedule unit's tests: the real app shell with the
// team area on a seeded mock server, edited per test before pumping.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/schedule/schedule_page.dart';
import 'package:dashboard_team/src/shared/week.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String schedulePath = '/staff/schedule';
const String rosterT = '/staff/roster';
const String suggestionsT = '/staff/roster/suggestions';
const String decideT = '/staff/roster/suggestions/decide';
const String coverageT = '/staff/roster/coverage';
const String fairnessT = '/staff/roster/fairness';
const String auditsT = '/staff/roster/fairness/audits';
const String publishT = '/staff/roster/publish';
const String openT = '/staff/open-shifts';
const String cancelOpenT = '/staff/open-shifts/{id}/cancel';
const String holidayT = '/staff/holidays/{date}';
const String daysT = '/staff/schedules/days';
const String timesT = '/staff/schedules/days/times';
const String moveT = '/staff/schedules/days/move';
const String prefsT = '/staff/employees/{id}/preferences';
const String prefsLogT = '/staff/employees/{id}/preferences/log';

/// Today by the mock clock (Thursday 8 October 2026) and this week's
/// Saturday.
const String today = '2026-10-08';
const String week = '2026-10-03';

/// [week] + [n] days.
String wd(int n) {
  final d = DateTime.utc(2026, 10, 3).add(Duration(days: n));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv scheduleServer({
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

/// The stored scope with [branchId] picked ([org]'s), so the page opens on
/// it from its first frame; null = All branches.
Map<String, String> branchPicked(String? branchId, {String? org}) => {
  ScopePrefKeys.branch: jsonEncode({
    'org': org ?? SeedIds.sabahOrg,
    'branch': branchId,
  }),
};

/// Opens the Schedule as [persona], scoped to [branch] (Zamalek by default;
/// [allBranches] scopes none).
Future<DashHarness> pumpSchedule(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
  String? branch,
  bool allBranches = false,
  bool reducedMotion = true,
}) {
  final srv = s ?? scheduleServer(persona: persona, edit: edit);
  final org = persona == Persona.dawamOnly ? SeedIds.nakhlaOrg : null;
  return DashHarness.pump(
    tester,
    areas: const [teamArea],
    path: schedulePath,
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: srv.server,
    db: srv.db,
    shotArea: 'team',
    reducedMotion: reducedMotion,
    prefs: branchPicked(
      allBranches ? null : (branch ?? SeedIds.zamalek),
      org: org,
    ),
  );
}

/// Answers `/authz/me` with only [caps] ([everywhere] defaults to them).
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

String emp(String key) => SeedIds.employee(key);

/// Sabah's Morning (07:00–15:00) and Evening (15:00–23:00) blocks.
final String morningId = TeamSeedIds.workShift('sabah', 'morning');
final String eveningId = TeamSeedIds.workShift('sabah', 'evening');

// ── Finders ────────────────────────────────────────────────────────────────

final Finder page = find.byType(ScheduleView);

Finder inPage(Finder f) => find.descendant(of: page, matching: f);

Finder pageText(String s) => inPage(find.text(s));

/// Text containing [s] (rich text too), on the page.
Finder pageHas(String s) =>
    inPage(find.textContaining(s, findRichText: true));

final Finder grid = find.byKey(const Key('schedule-grid'));

Finder inGrid(Finder f) => find.descendant(of: grid, matching: f);

/// The pressable whose accessible name is [label] (exactly).
Finder pressable(String label) => find.byWidgetPredicate(
  (w) => w is DashPressable && w.semanticLabel == label,
);

/// The pressables whose accessible name starts with [prefix].
Finder pressableStarting(String prefix) => find.byWidgetPredicate(
  (w) => w is DashPressable && (w.semanticLabel?.startsWith(prefix) ?? false),
);

/// [name]'s day cells (in no particular order).
Finder dayCells(String name) => inGrid(pressableStarting('$name, '));

/// The open dialog / sheet (the last `DashSurface`).
Finder surface() => find.byType(DashSurface).last;

Finder inSurface(Finder f) => find.descendant(of: surface(), matching: f);

Finder surfaceText(String s) => inSurface(find.text(s));

Finder surfaceHas(String s) =>
    inSurface(find.textContaining(s, findRichText: true));

/// The confirm card (one at a time).
Finder confirm() => find.byType(DashConfirmDialog);

Finder inConfirm(Finder f) => find.descendant(of: confirm(), matching: f);

/// Strips the LTR isolates the page wraps figures and times in.
String plain(String s) => s.replaceAll(RegExp('[\u2066-\u2069]'), '');

/// Text whose isolate-free form contains [s].
Finder plainHas(String s) => find.byWidgetPredicate(
  (w) =>
      (w is Text &&
          plain(w.data ?? w.textSpan?.toPlainText() ?? '').contains(s)) ||
      (w is RichText && plain(w.text.toPlainText()).contains(s)),
);

/// The calls to [template] with [method].
List<MockCall> calls(DashHarness h, String template, [String method = 'GET']) =>
    h.server.callsTo(template, method: method);

/// The week roster calls for [from] (the 45-day holidays read excluded).
List<MockCall> weekCalls(DashHarness h, String from) => [
  for (final c in calls(h, rosterT))
    if (c.query['from']?.single == from &&
        c.query['to']?.single == addDays(from, 6))
      c,
];

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// [iso] as the English page writes it ("03 Oct 2026").
String enDate(String iso) {
  final p = iso.split('-');
  return '${p[2]} ${_months[int.parse(p[1]) - 1]} ${p[0]}';
}

/// [name]'s cell on day [day] of this week (0 = Saturday; 7 = next
/// Saturday), as its button names it.
Finder dayCell(String name, int day) =>
    inGrid(pressable('$name, ${enDate(wd(day))}'));

/// [dayCell] in the harness's language.
Finder dayCellOf(DashHarness h, String name, int day) => inGrid(
  pressable(
    h.t(
      'dawam.editDay',
      args: {
        'name': name,
        'date': h.container.read(formatProvider).fmtDate(wd(day)),
      },
    ),
  ),
);

/// Scrolls [f] to the middle of its scroll view, then taps it (a phone's
/// sticky header covers whatever `ensureVisible` leaves at the top).
Future<void> tapCentered(DashHarness h, Finder f) async {
  await Scrollable.ensureVisible(f.evaluate().first, alignment: 0.5);
  await h.settle(rounds: 2);
  await h.tester.tap(f.first);
  await h.settle();
}

/// The JSON body a call sent.
Map<String, Object?> bodyOf(MockCall c) =>
    (c.body! as Map).cast<String, Object?>();

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: page, matching: find.byType(Scrollable))
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .where((s) => s.position.axis == Axis.vertical);
  if (scroll.isEmpty) {
    await h.shot('schedule/$name-1');
    return;
  }
  final position = scroll.first.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('schedule/$name-$i');
    if (y >= position.maxScrollExtent || i >= 6) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}
