// Shared set-up for the Rules unit's tests: the real app shell with the team
// area on a seeded mock server, edited per test before pumping.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/rules/rules_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String rulesPath = '/staff/rules';
const String settingsT = '/staff/attendance/settings';
const String branchesT = '/staff/attendance/settings/branches';
const String deleteT = '/staff/attendance/settings/branches/{branch_id}';

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv rulesServer({
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

/// Opens the Rules page as [persona] on [s] (a fresh seeded server by
/// default).
Future<DashHarness> pumpRules(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
  String path = rulesPath,
}) {
  final srv = s ?? rulesServer(persona: persona, edit: edit);
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

/// The business never saved its rules and stores no ladder.
void neverSaved(MockDb db) {
  for (final r in db['attendance_settings'].rows) {
    r['rules_saved_at'] = null;
    r['late_deduction_tiers'] = <Object?>[];
  }
}

final Finder page = find.byType(AttendanceRulesPage);
Finder inPage(Finder f) => find.descendant(of: page, matching: f);
Finder pageText(String s) => inPage(find.text(s));

/// The editable text inside the control keyed [key].
Finder box(Key key) => find.descendant(
  of: find.byKey(key),
  matching: find.byType(EditableText),
);

String shown(WidgetTester tester, Key key) =>
    tester.widget<EditableText>(box(key).first).controller.text;

/// Types [text] into the number field keyed [key] and leaves it (Enter
/// settles the reading).
Future<void> typeIn(DashHarness h, Key key, String text) async {
  await h.tester.ensureVisible(box(key).first);
  await h.settle();
  await h.enterText(box(key).first, text);
  await h.tester.testTextInput.receiveAction(TextInputAction.done);
  await h.settle();
}

/// Taps [key] once it is on screen.
Future<void> tapKey(DashHarness h, Key key) async {
  await h.tester.ensureVisible(find.byKey(key));
  await h.settle();
  await h.tap(find.byKey(key));
}

/// Opens the select keyed [select] and picks the option reading [option].
Future<void> pickIn(DashHarness h, Key select, String option) async {
  await h.tester.ensureVisible(find.byKey(select));
  await h.settle();
  await h.tap(find.byKey(select));
  await h.tap(find.text(option).hitTestable().last);
}

/// Every PUT the page sent, as JSON.
List<Map<String, Object?>> puts(DashHarness h) => [
  for (final c in h.server.callsTo(settingsT, method: 'PUT'))
    (c.body! as Map).cast<String, Object?>(),
];

/// The GETs of the settings read (both scopes).
int settingsGets(DashHarness h) =>
    h.server.callsTo(settingsT, method: 'GET').length;

/// Shoots the page top to bottom: `rules/<name>-1`, `-2`, …
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
    await h.shot('rules/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}
