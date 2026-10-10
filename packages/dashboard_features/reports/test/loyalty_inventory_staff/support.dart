// Shared set-up for the Loyalty, Inventory reports and Staff discipline
// tests: the real app shell with this unit's three pages (exactly as the
// area's routes.dart mounts them) and mocks, on the seeded mock server.
import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/loyalty_inventory_staff/inventory_reports_page.dart';
import 'package:dashboard_reports/src/loyalty_inventory_staff/lis_providers.dart';
import 'package:dashboard_reports/src/loyalty_inventory_staff/loyalty_report_page.dart';
import 'package:dashboard_reports/src/loyalty_inventory_staff/staff_discipline_page.dart';
import 'package:dashboard_reports/src/mock/loyalty_inventory_staff_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const loyaltyPath = '/reports/loyalty';
const inventoryPath = '/reports/inventory';
const staffPath = '/reports/staff';

const behaviorTpl = '/loyalty/behavior';
const campaignsTpl = '/loyalty/campaign-effectiveness';
const liabilityTpl = '/loyalty/liability-trend';
const disciplineTpl = '/staff/discipline-report';

String branchTpl(String report) => '/reports/branches/{branch_id}/$report';
String orgTpl(String report) => '/reports/orgs/{org_id}/$report';

/// The default period (30 days up to the seed's now, Cairo days).
const defaultFrom = '2026-09-08T21:00:00.000Z';
const defaultTo = '2026-10-08T20:59:59.999Z';
const defaultFromDate = '2026-09-09';
const defaultToDate = '2026-10-08';

const List<String> _supplements = [
  'packages/dashboard_reports/assets/i18n/en.json',
  'packages/dashboard_reports/assets/i18n/ar.json',
  'packages/dashboard_reports/assets/i18n/loyalty_inventory_staff.en.json',
  'packages/dashboard_reports/assets/i18n/loyalty_inventory_staff.ar.json',
];

/// This unit's pages as routes.dart mounts them, with only this unit's
/// mocks, so another unit's work in progress never stops these tests.
const DashArea unitArea = DashArea(
  key: 'reports',
  routes: [
    DashRoute(
      path: inventoryPath,
      builder: inventoryReportsPageBuilder,
      titleKey: 'inventory.reports.title',
      titleFallback: 'Inventory reports',
      module: OrgModule.pos,
      tabs: inventoryReportTabs,
      prefetch: prefetchInventoryReports,
    ),
    DashRoute(
      path: loyaltyPath,
      builder: loyaltyReportPageBuilder,
      titleKey: 'reports.loyalty.title',
      titleFallback: 'Loyalty',
      module: OrgModule.pos,
      tabs: loyaltyReportTabs,
    ),
    DashRoute(
      path: staffPath,
      builder: staffDisciplinePageBuilder,
      titleKey: 'reports.staff.title',
      titleFallback: 'Staff discipline',
      module: OrgModule.dawam,
    ),
  ],
  registerMocks: registerLoyaltyInventoryStaffMocks,
  i18nSupplements: _supplements,
);

/// Opens [path] as [persona]; [branchId] picks a branch in the scope bar.
Future<DashHarness> pumpUnit(
  WidgetTester tester, {
  required String path,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  String? branchId,
  bool reducedMotion = true,
  Map<String, String>? prefs,
}) => DashHarness.pump(
  tester,
  areas: const [unitArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  reducedMotion: reducedMotion,
  shotArea: 'reports',
  prefs: {
    if (branchId != null)
      ScopePrefKeys.branch:
          '{"org":"${SeedIds.sabahOrg}","branch":"$branchId"}',
    ...?prefs,
  },
);

/// A seeded server with the core's and this unit's handlers, for a test
/// that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) unitServer({Persona persona = Persona.owner}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerLoyaltyInventoryStaffMocks(server, db);
  return (server: server, db: db);
}

/// `/authz/me` for [persona] with [caps] instead of its own (the server
/// keeps checking the persona's).
void authzWith(MockServer server, Persona persona, Set<String> caps) {
  server.on('GET', '/authz/me', (req) {
    final list = caps.toList()..sort();
    return MockResponse.ok(
      MyAuthz(
        userId: persona.userId,
        branchId: req.q('branch_id'),
        capabilities: list,
        everywhere: persona.branchIds == null ? list : const [],
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

/// The persona's capabilities without [drop].
Set<String> capsWithout(Persona p, Set<String> drop) => {
  for (final c in p.capabilities)
    if (!drop.contains(c)) c,
};

/// Calls to the templates under [prefix] (`/loyalty`, `/reports`, `/staff`).
List<MockCall> callsUnder(DashHarness h, String prefix) => [
  for (final c in h.server.calls)
    if ((c.template ?? '').startsWith(prefix)) c,
];

/// A Text reading exactly [s], with or without the LTR isolates figures
/// wear.
Finder figure(String s) => find.byWidgetPredicate((w) {
  final text = switch (w) {
    Text(:final data?) => data,
    Text(:final textSpan?) => textSpan.toPlainText(),
    _ => null,
  };
  return text != null && (text == s || text == dashFigure(s));
});

/// [f] inside the page body (not the sidebar or the header bar).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(DashPageScaffold), matching: f);

/// The page's tab labelled [label].
Finder tabLabel(String label) => find.descendant(
  of: find.byType(DashTabStrip<String>),
  matching: find.text(label),
);

/// Opens the tab labelled [label].
Future<void> openTab(DashHarness h, String label) => h.tap(tabLabel(label));

/// The file name's UTC date stamp (the mock clock's).
String exportStamp(DashHarness h) =>
    isoString(h.container.read(clockProvider)()).substring(0, 10);

DashFormat fmtOf(DashHarness h) => h.container.read(formatProvider);
