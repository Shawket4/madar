// Shared set-up for the Team reports unit's tests: the real app shell with
// the team area on a seeded mock server, edited per test before pumping.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/team_reports/team_reports_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String reportsPath = '/staff/reports';
const String summaryT = '/staff/attendance/summary';
const String labourT = '/staff/reports/labour-vs-sales';
const String historyT = '/staff/reports/payroll-history';
const String advancesT = '/staff/reports/advances';
const String settingsT = '/staff/attendance/settings';

/// Every report read.
const List<String> reportReads = [summaryT, labourT, historyT, advancesT];

/// The mock clock's pay period (period start day 1): October 2026.
const ({String from, String to}) thisPeriod = (
  from: '2026-10-01',
  to: '2026-10-31',
);

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv reportsServer({
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

/// Opens Reports as [persona] on [s] (a fresh seeded server by default).
Future<DashHarness> pumpReports(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
}) {
  final srv = s ?? reportsServer(persona: persona, edit: edit);
  return DashHarness.pump(
    tester,
    areas: const [teamArea],
    path: reportsPath,
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

/// [f] inside the page (not the sidebar or header).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(StaffReportsPage), matching: f);

/// Text inside the page.
Finder pageText(String text) => inPage(find.text(text));

/// Every report table, whatever its row type.
final Finder tables = find.byWidgetPredicate((w) => w is DashDataTable);

/// [f] inside the report tables.
Finder inTable(Finder f) => find.descendant(of: tables, matching: f);

/// Text inside the report tables.
Finder tableText(String text) => inTable(find.text(text));

/// The stat card labelled [label] (the first, when two tabs share a label).
Finder card(String label) => find
    .ancestor(of: pageText(label), matching: find.byType(DashStatCard))
    .first;

/// [f] inside the stat card labelled [label].
Finder inCard(String label, Finder f) =>
    find.descendant(of: card(label), matching: f);

/// Opens the tab labelled [label].
Future<void> openTab(DashHarness h, String label) => h.tap(
  find.descendant(
    of: find.byType(DashPageTabs<String>),
    matching: find.text(label),
  ),
);

/// GETs to [template] so far.
List<MockCall> gets(DashHarness h, String template) =>
    h.server.callsTo(template, method: 'GET');

/// Report reads so far, every endpoint.
int reportCalls(DashHarness h) =>
    reportReads.fold(0, (n, r) => n + gets(h, r).length);

/// The text of the last file saved (UTF-8), without its BOM.
String lastSaved(DashHarness h) =>
    utf8.decode(h.files.saved.last.bytes).replaceFirst('\uFEFF', '');

/// Shoots the page top to bottom: `reports/<name>-1`, `-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final position = find
      .descendant(
        of: find.byType(StaffReportsPage),
        matching: find.byType(Scrollable),
      )
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .firstWhere((s) => s.position.axis == Axis.vertical)
      .position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('reports/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}
