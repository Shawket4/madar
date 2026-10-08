/// The reports area's pages (`/reports/operations`, `/reports/financial`,
/// `/reports/inventory`, `/reports/legal`, `/reports/loyalty`,
/// `/reports/bundles`, `/reports/staff`, `/reports/staff-pool`,
/// `/reports/tills`, `/basira`) with the web's capabilities (any-of, from the
/// generated nav and settings nav) and module. A route without a builder shows
/// the shell's placeholder until its page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';

const List<DashRoute> reportsRoutes = [
  DashRoute(
    path: '/reports/operations',
    titleKey: 'nav.reportsOperations',
    titleFallback: 'Operations',
    caps: [Cap.ordersRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/reports/financial',
    titleKey: 'nav.reportsFinancial',
    titleFallback: 'Financial',
    caps: [Cap.ordersRead, Cap.inventoryRead, Cap.purchasingOrdersRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/reports/inventory',
    titleKey: 'nav.reportsInventory',
    titleFallback: 'Inventory',
    caps: [Cap.inventoryRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/reports/legal',
    titleKey: 'nav.reportsLegal',
    titleFallback: 'Legal',
    caps: [Cap.reportsLegal],
  ),
  DashRoute(
    path: '/reports/loyalty',
    titleKey: 'nav.reportsLoyalty',
    titleFallback: 'Loyalty',
    caps: [Cap.loyaltyMembersList],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/reports/bundles',
    titleKey: 'nav.reportsBundles',
    titleFallback: 'Bundles',
    caps: [Cap.reportsBundles],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/reports/staff',
    titleKey: 'nav.reportsStaff',
    titleFallback: 'Staff',
    caps: [Cap.hrAttendanceRead],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/reports/staff-pool',
    titleKey: 'nav.reportsStaffPool',
    titleFallback: 'Staff drinks',
    caps: [Cap.ordersStaffDrinkRecord],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/reports/tills',
    titleKey: 'nav.reportsTills',
    titleFallback: 'Tills',
    caps: [Cap.tillReadBranch],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/basira',
    titleKey: 'nav.basira',
    titleFallback: 'Basira',
    caps: [Cap.reportsRead],
    module: OrgModule.pos,
  ),
];
