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
import 'loyalty_inventory_staff/lis_providers.dart'
    show prefetchInventoryReports;
import 'loyalty_inventory_staff/loyalty_report_page.dart';
import 'loyalty_inventory_staff/staff_discipline_page.dart';
import 'operations/operations_page.dart';
import 'staff_pool_bundles/bundles_report_page.dart';
import 'staff_pool_bundles/staff_pool_report_page.dart';
import 'tills_report/tills_report_page.dart';

const List<DashRoute> reportsRoutes = [
  // REP-OPS-001: `orders.read`, checked by the page's own `<Restricted>`
  // (with the reports' words, REP-ALL-005), as the web's route has no guard.
  DashRoute(
    path: '/reports/operations',
    builder: operationsPageBuilder,
    titleKey: 'reports.operations.title',
    titleFallback: 'Operations',
    module: OrgModule.pos,
    tabs: operationsTabs,
    prefetch: prefetchOperations,
  ),
  // REP-FIN-002: Restricted only when no tab is visible (`orders.read`,
  // `inventory.read` or `purchasing.orders.read`), checked by the page with
  // the reports' words (REP-ALL-005), as the web's route has no guard.
  DashRoute(
    path: '/reports/financial',
    builder: financialPageBuilder,
    titleKey: 'reports.financial.title',
    titleFallback: 'Financial',
    module: OrgModule.pos,
    tabs: financialTabs,
    prefetch: prefetchFinancial,
  ),
  // REP-INV-001: `inventory.read`, checked by the page's own `<Restricted>`
  // (with the reports' words, REP-ALL-005), as the web's route has no guard.
  DashRoute(
    path: '/reports/inventory',
    builder: inventoryReportsPageBuilder,
    titleKey: 'inventory.reports.title',
    titleFallback: 'Inventory reports',
    module: OrgModule.pos,
    tabs: inventoryReportTabs,
    prefetch: prefetchInventoryReports,
  ),
  // REP-LEG-001: `reports.legal`, checked by the page's own `<Restricted>`
  // (with the reports' words, REP-ALL-005), as the web's route has no guard;
  // no route module (every org), REP-ALL-004.
  DashRoute(
    path: '/reports/legal',
    builder: legalPageBuilder,
    titleKey: 'reports.legal.title',
    titleFallback: 'Legal',
    tabs: legalTabs,
  ),
  // REP-LOY-001: `loyalty.members.list`, checked by the page's own
  // `<Restricted>` (REP-ALL-005).
  DashRoute(
    path: '/reports/loyalty',
    builder: loyaltyReportPageBuilder,
    titleKey: 'reports.loyalty.title',
    titleFallback: 'Loyalty',
    module: OrgModule.pos,
    tabs: loyaltyReportTabs,
  ),
  // REP-BUN-001: `reports.bundles`.
  DashRoute(
    path: '/reports/bundles',
    builder: bundlesReportPageBuilder,
    titleKey: 'reports.bundles.title',
    titleFallback: 'Bundles',
    module: OrgModule.pos,
  ),
  // REP-STF-002: `hr.attendance.read`, checked by the page's own
  // `<Restricted>` (REP-ALL-005); a Dawam page.
  DashRoute(
    path: '/reports/staff',
    builder: staffDisciplinePageBuilder,
    titleKey: 'reports.staff.title',
    titleFallback: 'Staff discipline',
    module: OrgModule.dawam,
  ),
  // REP-SPL-001: `orders.staff_drink.record`; pos (the longer prefix wins
  // over `/reports/staff`, REP-ALL-004).
  DashRoute(
    path: '/reports/staff-pool',
    builder: staffPoolReportPageBuilder,
    titleKey: 'staffPool.reportTitle',
    titleFallback: 'Staff drinks',
    module: OrgModule.pos,
  ),
  // REP-TIL-001: `till.read.branch` (plain `till.read` is Restricted),
  // checked by the page's own `<Restricted>` with the reports' words; the
  // web's route has no guard, so the page renders while rights load
  // (REP-ALL-030).
  DashRoute(
    path: '/reports/tills',
    builder: tillsReportPageBuilder,
    titleKey: 'reports.tills.title',
    titleFallback: 'Till sessions',
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
