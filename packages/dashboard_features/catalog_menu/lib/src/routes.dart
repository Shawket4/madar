/// The menu catalogue area's pages (`/menu/items`, `/menu/groups`,
/// `/menu/pricing`, `/menu/bases`, `/menu/packaging`) with the web's
/// capabilities (any-of, from the generated nav and settings nav) and module. A
/// route without a builder shows the shell's placeholder until its page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';

const List<DashRoute> catalogMenuRoutes = [
  DashRoute(
    path: '/menu/items',
    titleKey: 'nav.items',
    titleFallback: 'Items',
    caps: [Cap.menuItemsRead],
    module: OrgModule.pos,
    children: [
      DashRoute(
        path: ':itemId',
        titleKey: 'nav.items',
        titleFallback: 'Items',
        caps: [Cap.menuItemsRead],
        module: OrgModule.pos,
      ),
    ],
  ),
  DashRoute(
    path: '/menu/groups',
    titleKey: 'nav.choiceGroups',
    titleFallback: 'Choice groups',
    caps: [Cap.menuItemsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/pricing',
    titleKey: 'nav.pricingAvailability',
    titleFallback: 'Pricing & availability',
    caps: [Cap.menuItemsEdit],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/bases',
    titleKey: 'nav.recipeBases',
    titleFallback: 'Recipe bases',
    caps: [Cap.menuItemsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/packaging',
    titleKey: 'nav.packagingRules',
    titleFallback: 'Packaging rules',
    caps: [Cap.menuItemsRead],
    module: OrgModule.pos,
  ),
];
