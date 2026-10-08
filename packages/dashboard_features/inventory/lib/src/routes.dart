/// The inventory area's pages (`/inventory/today`, `/inventory/counts`,
/// `/inventory/ingredients`, `/inventory/purchasing`, `/inventory/waste`,
/// `/inventory/transfers`, `/inventory/settings`) with the web's capabilities
/// (any-of, from the generated nav and settings nav) and module. A route
/// without a builder shows the shell's placeholder until its page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';

const List<DashRoute> inventoryRoutes = [
  DashRoute(
    path: '/inventory/today',
    titleKey: 'nav.invToday',
    titleFallback: 'Today',
    caps: [Cap.inventoryRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/counts',
    titleKey: 'nav.invCounts',
    titleFallback: 'Counts',
    caps: [Cap.inventoryCountsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/ingredients',
    titleKey: 'nav.ingredients',
    titleFallback: 'Ingredients',
    caps: [Cap.inventoryRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/purchasing',
    titleKey: 'nav.invPurchasing',
    titleFallback: 'Purchasing',
    caps: [Cap.purchasingOrdersRead, Cap.purchasingSuppliersRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/waste',
    titleKey: 'nav.invWaste',
    titleFallback: 'Waste',
    caps: [Cap.inventoryWasteRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/transfers',
    titleKey: 'nav.invTransfers',
    titleFallback: 'Transfers',
    caps: [Cap.inventoryTransfersRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/settings',
    titleKey: 'nav.invSettings',
    titleFallback: 'Settings',
    caps: [Cap.inventoryAdjust],
    module: OrgModule.pos,
  ),
];
