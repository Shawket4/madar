// Shared set-up for the Operations tests: the real app shell with the
// reports area, on the seeded mock server.
import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/dashboard_reports.dart';
import 'package:dashboard_reports/src/operations/operations_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String opsPath = '/reports/operations';

// The endpoint templates the page reads.
const String metricsRoute = '/metrics/query';
const String floorRoute = '/floor/tables';
const String historyRoute = '/floor/tables/{id}/history';
const String salesRoute = '/reports/branches/{branchId}/sales';
const String itemsRoute = '/reports/branches/{branchId}/items-combined';
const String addonsRoute = '/reports/branches/{branchId}/addons';
const String tellersRoute = '/reports/branches/{branchId}/tellers';
const String waitersRoute = '/reports/branches/{branchId}/waiters';
const String comparisonRoute = '/reports/orgs/{orgId}/comparison';
const String menuRoute = '/menu-items';

/// Every read the page may fire, for "nothing was asked" checks.
const List<String> opsReads = [
  metricsRoute,
  floorRoute,
  historyRoute,
  salesRoute,
  itemsRoute,
  addonsRoute,
  tellersRoute,
  waitersRoute,
  comparisonRoute,
  menuRoute,
];

/// Opens Operations (or [path]) as [persona].
Future<DashHarness> pumpOps(
  WidgetTester tester, {
  String path = opsPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  Map<String, String>? prefs,
  String? branchId,
  bool reducedMotion = true,
}) => DashHarness.pump(
  tester,
  areas: const [reportsArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  reducedMotion: reducedMotion,
  prefs: {
    if (branchId != null)
      ScopePrefKeys.branch:
          '{"org":"${SeedIds.sabahOrg}","branch":"$branchId"}',
    ...?prefs,
  },
);

/// A seeded server with the core's and the reports area's handlers, for a
/// test that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) opsServer({Persona persona = Persona.owner}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerReportsMocks(server, db);
  return (server: server, db: db);
}

/// The page under test.
Finder get opsPage => find.byType(OperationsReportPage);

/// [f] inside the page (the shell shares words with it).
Finder inPage(Finder f) => find.descendant(of: opsPage, matching: f);

/// The text [s] inside the page.
Finder pageText(String s) => inPage(find.text(s));

/// Opens the tab labelled [label].
Future<void> openTab(DashHarness h, String label) async {
  final tab = find.descendant(
    of: find.byType(DashPageTabs<String>),
    matching: find.text(label),
  );
  await h.tap(tab);
}

/// The calls to [template] (GET unless [method]).
List<MockCall> callsTo(DashHarness h, String template, {String? method}) =>
    h.server.callsTo(template, method: method ?? 'GET');

/// The KPI card labelled [label] (a stat card of the ledger strip).
Finder kpiCard(String label) => find
    .ancestor(of: find.text(label), matching: find.byType(DashStatCard))
    .first;

/// The text [value] inside the KPI card labelled [label].
Finder kpiValue(String label, String value) => find.descendant(
  of: kpiCard(label),
  matching: find.textContaining(value, findRichText: true),
);

/// The chart card titled [title].
Finder chartCard(String title) => find.ancestor(
  of: find.text(title),
  matching: find.byType(DashChartCard),
);

/// Text widgets containing [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// `/authz/me` for [persona] without [drop].
void authzWithout(MockServer server, Persona persona, Set<String> drop) {
  server.on('GET', '/authz/me', (req) {
    final caps = [
      for (final c in persona.capabilities)
        if (!drop.contains(c)) c,
    ]..sort();
    return MockResponse.ok(
      MyAuthz(
        userId: persona.userId,
        branchId: req.q('branch_id'),
        capabilities: caps,
        everywhere: persona.branchIds == null ? caps : const [],
        askManager: const [],
        limits: const {},
        owner: false,
        platform: false,
        roleKinds: persona.roleKinds,
        epoch: 1,
        specVersion: 2,
      ),
    );
  });
}

/// Opens the select [select] and picks the option labelled [label].
Future<void> pickOption(DashHarness h, Finder select, String label) async {
  await h.tap(select);
  await h.tap(
    find.descendant(
      of: find.byType(DashOptionList<String>),
      matching: find.text(label),
    ),
  );
}

/// A Text (or rich text) reading exactly [s], with or without the LTR
/// isolates figures wear.
Finder figure(String s) => find.byWidgetPredicate((w) {
  final text = switch (w) {
    Text(:final data?) => data,
    Text(:final textSpan?) => textSpan.toPlainText(),
    RichText(:final text) => text.toPlainText(),
    _ => null,
  };
  return text != null && (text == s || text == dashFigure(s));
});
