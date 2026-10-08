/// The sell area's pages (`/orders`, `/floor`, `/bookings`, `/tills`,
/// `/customers`), all in the POS module.
///
/// Capabilities, exactly as the web: the sidebar and the command palette gate
/// these pages from the generated nav (`orders.read`, `floor.layout.read`,
/// `bookings.read`, `till.read`, `customers.view`; SELL-ALL-001), but NONE of
/// the pages has a route-level guard (SELL-ALL-004): Orders, Floor, Bookings
/// and Tills render for whoever types the URL and their reads refuse, and
/// Customers runs its own `<Restricted>` with its own words (SELL-CUS-002).
/// So no route here carries `caps` — the shell's generic gate would answer
/// first with the wrong page. The legacy `/shifts` → `/tills` redirect is the
/// shell's (generated legacy redirects, SELL-ALL-007).
///
/// Each unit reads its own search params in its page's `route` builder.
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'bookings/bookings_page.dart';
import 'customers/customers_page.dart';
import 'floor/floor_page.dart';
import 'orders/orders_page.dart';
import 'tills/tills_page.dart';

const List<DashRoute> sellRoutes = [
  DashRoute(
    path: '/orders',
    builder: OrdersPage.route,
    titleKey: 'nav.orders',
    titleFallback: 'Orders',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/floor',
    builder: FloorPage.route,
    titleKey: 'floor.title',
    titleFallback: 'Floor',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/bookings',
    builder: BookingsPage.route,
    titleKey: 'bookings.title',
    titleFallback: 'Bookings',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/tills',
    builder: TillsPage.route,
    titleKey: 'nav.tills',
    titleFallback: 'Tills',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/customers',
    builder: CustomersPage.route,
    titleKey: 'customers.title',
    titleFallback: 'Customers',
    module: OrgModule.pos,
  ),
];
