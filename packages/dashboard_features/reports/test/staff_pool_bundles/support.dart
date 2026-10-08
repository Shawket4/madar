// Shared set-up for the Staff drinks and Bundles tests: the real app shell
// with the reports area, on the seeded mock server.
import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/mock/staff_pool_bundles_mock.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/bundles_report_page.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_pool_report_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const bundlesPath = '/reports/bundles';
const staffPoolPath = '/reports/staff-pool';

const bundlesTpl = '/reports/bundles';
const mixTpl = '/reports/bundles/combos/{id}/mix';
const todayTpl = '/staff-pool/today';
const drinksTpl = '/staff-pool/drinks';
const summaryTpl = '/staff-pool/drinks/summary';
const orderTpl = '/orders/{order_id}';

/// The default period (`30d` at the seed's now, Cairo): 9 Sep – 8 Oct.
const defaultFrom = '2026-09-09';
const defaultTo = '2026-10-08';

const List<String> _supplements = [
  'packages/dashboard_reports/assets/i18n/en.json',
  'packages/dashboard_reports/assets/i18n/ar.json',
  'packages/dashboard_reports/assets/i18n/staff_pool_bundles.en.json',
  'packages/dashboard_reports/assets/i18n/staff_pool_bundles.ar.json',
];

/// This unit's two pages exactly as the area's `routes.dart` mounts them
/// (title, page capability, module) with this unit's mock handlers only, so
/// another unit's work in progress never stops these tests compiling.
const DashArea unitArea = DashArea(
  key: 'reports',
  routes: [
    DashRoute(
      path: bundlesPath,
      builder: bundlesReportPageBuilder,
      titleKey: 'reports.bundles.title',
      titleFallback: 'Bundles',
      caps: [Cap.reportsBundles],
      module: OrgModule.pos,
    ),
    DashRoute(
      path: staffPoolPath,
      builder: staffPoolReportPageBuilder,
      titleKey: 'staffPool.reportTitle',
      titleFallback: 'Staff drinks',
      caps: [Cap.ordersStaffDrinkRecord],
      module: OrgModule.pos,
    ),
  ],
  registerMocks: registerStaffPoolBundlesMocks,
  i18nSupplements: _supplements,
);

/// The two pages without the route's capability, so the page's OWN
/// `<Restricted>` (with `reports.noAccess`) is what refuses — the routing
/// the web uses (its routes carry no guard).
const DashArea pageGatedArea = DashArea(
  key: 'reports',
  routes: [
    DashRoute(
      path: bundlesPath,
      builder: bundlesReportPageBuilder,
      titleKey: 'reports.bundles.title',
      module: OrgModule.pos,
    ),
    DashRoute(
      path: staffPoolPath,
      builder: staffPoolReportPageBuilder,
      titleKey: 'staffPool.reportTitle',
      module: OrgModule.pos,
    ),
  ],
  registerMocks: registerStaffPoolBundlesMocks,
  i18nSupplements: _supplements,
);

/// Opens [path] as [persona] in the real shell with the reports area.
Future<DashHarness> pumpReports(
  WidgetTester tester, {
  required String path,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  DashArea area = unitArea,
}) => DashHarness.pump(
  tester,
  areas: [area],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
);

/// A seeded server with the core's and the reports area's handlers, for a
/// test that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) reportsServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerStaffPoolBundlesMocks(server, db);
  return (server: server, db: db);
}

/// `/authz/me` for [persona] without [drop] (a person the registry gives a
/// different set of capabilities).
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

/// Texts containing [s].
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// The query of the last call to [template].
Map<String, List<String>> lastQuery(DashHarness h, String template) =>
    h.server.callsTo(template).last.query;

/// The stat card labelled [label].
DashStatCard statCard(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashStatCard && w.label == label).first,
);
