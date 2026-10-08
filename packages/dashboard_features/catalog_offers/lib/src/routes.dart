/// The offers catalogue area's pages (`/menu/combos`, `/menu/deals`,
/// `/discounts`) with the web's capabilities (any-of, from the generated nav
/// and settings nav) and module. A route without a builder shows the shell's
/// placeholder until its page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';

const List<DashRoute> catalogOffersRoutes = [
  DashRoute(
    path: '/menu/combos',
    titleKey: 'nav.combos',
    titleFallback: 'Combos',
    caps: [Cap.menuItemsRead],
    module: OrgModule.pos,
    children: [
      DashRoute(
        path: ':comboId',
        titleKey: 'nav.combos',
        titleFallback: 'Combos',
        caps: [Cap.menuItemsRead],
        module: OrgModule.pos,
      ),
    ],
  ),
  DashRoute(
    path: '/menu/deals',
    titleKey: 'nav.deals',
    titleFallback: 'Deals',
    caps: [Cap.menuItemsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/discounts',
    titleKey: 'nav.discounts',
    titleFallback: 'Discounts',
    caps: [Cap.discountsRead],
    module: OrgModule.pos,
  ),
];
