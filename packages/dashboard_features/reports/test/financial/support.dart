// Shared set-up for the Financial tests: the real app shell with the
// reports area, on the seeded mock server.
import 'package:dashboard_api/dashboard_api.dart'
    show MarginLedgerReport, MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/dashboard_reports.dart';
import 'package:dashboard_reports/src/financial/fin_data.dart';
import 'package:dashboard_reports/src/financial/financial_page.dart';
import 'package:dashboard_reports/src/mock/financial_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String finPath = '/reports/financial';

// The endpoint templates the page reads.
const String ledgerRoute = '/insights/branches/{branch_id}/menu-margin';
const String repricingRoute = '/insights/branches/{branch_id}/repricing';
const String decisionsRoute = '/insights/decisions';
const String targetsRoute = '/insights/margin-target';
const String usersRoute = '/users';
const String seriesRoute = '/reports/branches/{branch_id}/sales/timeseries';
const String peakHoursRoute = '/reports/branches/{branch_id}/sales/peak-hours';
const String peakDaysRoute = '/reports/branches/{branch_id}/sales/peak-days';
const String channelRoute = '/reports/branches/{branch_id}/channel-breakdown';
const String branchValuationRoute =
    '/reports/branches/{branch_id}/inventory-valuation';
const String orgValuationRoute = '/reports/orgs/{org_id}/inventory-valuation';
const String catalogRoute = '/inventory/orgs/{org_id}/catalog';
const String branchSpendRoute = '/reports/branches/{branch_id}/supplier-spend';
const String orgSpendRoute = '/reports/orgs/{org_id}/supplier-spend';
const String branchTrendRoute =
    '/reports/branches/{branch_id}/material-cost-trend';
const String orgTrendRoute = '/reports/orgs/{org_id}/material-cost-trend';

/// Every read the page may fire, for "nothing was asked" checks.
const List<String> finReads = [
  ledgerRoute,
  repricingRoute,
  decisionsRoute,
  targetsRoute,
  usersRoute,
  seriesRoute,
  peakHoursRoute,
  peakDaysRoute,
  channelRoute,
  branchValuationRoute,
  orgValuationRoute,
  catalogRoute,
  branchSpendRoute,
  orgSpendRoute,
  branchTrendRoute,
  orgTrendRoute,
];

/// Opens Financial (or [path]) as [persona], optionally with [branchId]
/// picked in the scope bar.
Future<DashHarness> pumpFin(
  WidgetTester tester, {
  String path = finPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
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
  },
);

/// A seeded server with the core's and the reports area's handlers.
({MockServer server, MockDb db}) finServer({Persona persona = Persona.owner}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerReportsMocks(server, db);
  return (server: server, db: db);
}

/// The page under test.
Finder get finPage => find.byType(FinancialReportPage);

/// [f] inside the page.
Finder inPage(Finder f) => find.descendant(of: finPage, matching: f);

/// The text [s] inside the page.
Finder pageText(String s) => inPage(find.text(s));

/// Text widgets containing [s] (spans included), inside the page.
Finder pageHas(String s) => inPage(find.textContaining(s, findRichText: true));

/// Opens the page tab labelled [label].
Future<void> openTab(DashHarness h, String label) => h.tap(
  find.descendant(
    of: find.byKey(const ValueKey('fin-tabs')),
    matching: find.text(label),
  ),
);

/// Opens the profitability tab labelled [label] (Ledger, Repricing, …).
Future<void> openInner(DashHarness h, String label) => h.tap(
  find.descendant(
    of: find.byKey(const ValueKey('fin-inner-tabs')),
    matching: find.text(label),
  ),
);

/// Taps the segment labelled [label] of the control keyed [key].
Future<void> pickSegment(DashHarness h, String key, String label) => h.tap(
  find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(label)),
);

/// The calls to [template] (GET unless [method]).
List<MockCall> callsTo(DashHarness h, String template, {String? method}) =>
    h.server.callsTo(template, method: method ?? 'GET');

/// How many reads of the page went out.
int readCount(DashHarness h) =>
    finReads.fold(0, (n, r) => n + callsTo(h, r).length);

/// The KPI card labelled [label].
Finder kpiCard(String label) => find
    .ancestor(of: find.text(label), matching: find.byType(DashStatCard))
    .first;

/// `/authz/me` for [persona] with only [keep] of its capabilities (or
/// without [drop]).
void authzCaps(
  MockServer server,
  Persona persona, {
  Set<String>? keep,
  Set<String> drop = const {},
}) {
  server.on('GET', '/authz/me', (req) {
    final caps = [
      for (final c in persona.capabilities)
        if ((keep == null || keep.contains(c)) && !drop.contains(c)) c,
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

/// A Text (or rich text) reading exactly [s], with or without the LTR
/// isolates figures wear.
Finder figure(String s) => find.byWidgetPredicate((w) {
  final text = switch (w) {
    Text(:final data?) => data,
    Text(:final textSpan?) => textSpan.toPlainText(),
    _ => null,
  };
  return text != null && (text == s || text == dashFigure(s));
});

/// The page's vertical scroll.
Finder get pageScroll => find
    .descendant(
      of: finPage,
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    )
    .first;

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(
        of: finPage,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('financial/$name-$i');
    if (y >= position.maxScrollExtent || i >= 4) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

/// The ledger the page shows (the provider's value, keyed as the page).
MarginLedgerReport served(DashHarness h, {bool current = false}) => h.container
    .read(
      finLedgerProvider(
        h.container.read(currentScopeProvider).finLedger(current: current),
      ),
    )
    .requireValue;

/// Replaces the ledger handler with the real one's answer edited by [edit].
void ledgerAnswer(
  ({MockServer server, MockDb db}) s,
  Map<String, Object?> Function(Map<String, Object?> json) edit,
) {
  s.server.on('GET', ledgerRoute, (req) {
    final r = finLedger(
      s.db,
      orgId: SeedIds.sabahOrg,
      branchId: req.param('branch_id'),
      branchIds: SeedIds.sabahBranches,
      from: req.qDateTime('from'),
      to: req.qDateTime('to'),
      current: req.q('cost_basis') == 'current',
    );
    return MockResponse.ok(edit(r.toJson()));
  });
}

List<Map<String, Object?>> rowsOf(Map<String, Object?> j) =>
    (j['rows']! as List).cast<Map<String, Object?>>();
