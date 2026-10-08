/// The reports area's pages (`/reports/operations`, `/reports/financial`,
/// `/reports/inventory`, `/reports/legal`, `/reports/loyalty`,
/// `/reports/bundles`, `/reports/staff`, `/reports/staff-pool`,
/// `/reports/tills`, `/basira`) with the web's page gate (any-of; the cap
/// each page's `<Restricted>` checks) and module.
///
/// The title key is the page's own title, the words `Restricted` shows
/// (REP-OPS-001, REP-FIN-002, REP-INV-001, …); the sidebar labels come from
/// the generated nav. Tabs are page state on the web (REP-ALL-022); each
/// unit declares its own and they are listed here for reference. The legacy
/// paths (`/analytics`, `/reports/sales`, `/insights/*`, …, REP-ALL-006) are
/// the shell's redirects.
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'basira/basira_page.dart';
import 'financial/financial_page.dart';
import 'legal/legal_page.dart';
import 'loyalty_inventory_staff/inventory_reports_page.dart';
import 'loyalty_inventory_staff/loyalty_report_page.dart';
import 'loyalty_inventory_staff/staff_discipline_page.dart';
import 'operations/operations_page.dart';
import 'staff_pool_bundles/bundles_report_page.dart';
import 'staff_pool_bundles/staff_pool_report_page.dart';
import 'tills_report/tills_report_page.dart';

const List<DashRoute> reportsRoutes = [
  // REP-OPS-001: `orders.read`.
  DashRoute(
    path: '/reports/operations',
    builder: operationsPageBuilder,
    titleKey: 'reports.operations.title',
    titleFallback: 'Operations',
    caps: [Cap.ordersRead],
    module: OrgModule.pos,
    tabs: operationsTabs,
  ),
  // REP-FIN-002: Restricted only when no tab is visible.
  DashRoute(
    path: '/reports/financial',
    builder: financialPageBuilder,
    titleKey: 'reports.financial.title',
    titleFallback: 'Financial',
    caps: [Cap.ordersRead, Cap.inventoryRead, Cap.purchasingOrdersRead],
    module: OrgModule.pos,
    tabs: financialTabs,
  ),
  // REP-INV-001: `inventory.read`.
  DashRoute(
    path: '/reports/inventory',
    builder: inventoryReportsPageBuilder,
    titleKey: 'inventory.reports.title',
    titleFallback: 'Inventory reports',
    caps: [Cap.inventoryRead],
    module: OrgModule.pos,
    tabs: inventoryReportTabs,
  ),
  // REP-LEG-001: `reports.legal`; no route module (every org), REP-ALL-004.
  DashRoute(
    path: '/reports/legal',
    builder: legalPageBuilder,
    titleKey: 'reports.legal.title',
    titleFallback: 'Legal',
    caps: [Cap.reportsLegal],
    tabs: legalTabs,
  ),
  // REP-LOY-001: `loyalty.members.list`.
  DashRoute(
    path: '/reports/loyalty',
    builder: loyaltyReportPageBuilder,
    titleKey: 'reports.loyalty.title',
    titleFallback: 'Loyalty',
    caps: [Cap.loyaltyMembersList],
    module: OrgModule.pos,
    tabs: loyaltyReportTabs,
  ),
  // REP-BUN-001: `reports.bundles`.
  DashRoute(
    path: '/reports/bundles',
    builder: bundlesReportPageBuilder,
    titleKey: 'reports.bundles.title',
    titleFallback: 'Bundles',
    caps: [Cap.reportsBundles],
    module: OrgModule.pos,
  ),
  // REP-STF-002: `hr.attendance.read`; a Dawam page.
  DashRoute(
    path: '/reports/staff',
    builder: staffDisciplinePageBuilder,
    titleKey: 'reports.staff.title',
    titleFallback: 'Staff discipline',
    caps: [Cap.hrAttendanceRead],
    module: OrgModule.dawam,
  ),
  // REP-SPL-001: `orders.staff_drink.record`; pos (the longer prefix wins
  // over `/reports/staff`, REP-ALL-004).
  DashRoute(
    path: '/reports/staff-pool',
    builder: staffPoolReportPageBuilder,
    titleKey: 'staffPool.reportTitle',
    titleFallback: 'Staff drinks',
    caps: [Cap.ordersStaffDrinkRecord],
    module: OrgModule.pos,
  ),
  // REP-TIL-001: `till.read.branch` (plain `till.read` is Restricted).
  DashRoute(
    path: '/reports/tills',
    builder: tillsReportPageBuilder,
    titleKey: 'reports.tills.title',
    titleFallback: 'Till sessions',
    caps: [Cap.tillReadBranch],
    module: OrgModule.pos,
    tabs: tillsReportTabs,
  ),
  // REP-BAS-001: no page gate. The nav leaf needs `reports.read`, but the
  // web renders the page for whoever opens the URL; refusals come back from
  // the server as a toast or a question's failure box.
  DashRoute(
    path: '/basira',
    builder: basiraPageBuilder,
    titleKey: 'basira.title',
    titleFallback: 'Basira',
    module: OrgModule.pos,
  ),
];
