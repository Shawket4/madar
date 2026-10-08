/// The sell area's pages (`/orders`, `/floor`, `/bookings`, `/tills`,
/// `/customers`) with the web's capabilities (any-of, from the generated nav
/// and settings nav) and module. A route without a builder shows the shell's
/// placeholder until its page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';

const List<DashRoute> sellRoutes = [
  DashRoute(
    path: '/orders',
    titleKey: 'nav.orders',
    titleFallback: 'Orders',
    caps: [Cap.ordersRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/floor',
    titleKey: 'nav.floor',
    titleFallback: 'Floor',
    caps: [Cap.floorLayoutRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/bookings',
    titleKey: 'nav.bookings',
    titleFallback: 'Bookings',
    caps: [Cap.bookingsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/tills',
    titleKey: 'nav.tills',
    titleFallback: 'Tills',
    caps: [Cap.tillRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/customers',
    titleKey: 'nav.customers',
    titleFallback: 'Customers',
    caps: [Cap.customersView],
    module: OrgModule.pos,
  ),
];
