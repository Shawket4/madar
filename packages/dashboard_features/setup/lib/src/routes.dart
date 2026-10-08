/// The setup area's pages (`/settings`, `/settings/brand`, `/settings/links`,
/// `/settings/delivery`, `/settings/delivery-zones`, `/settings/bookings`,
/// `/settings/loyalty`, `/settings/qr`, `/settings/combos`,
/// `/settings/payment-methods`, `/settings/staff-pool`,
/// `/settings/kitchen-stations`, `/settings/kitchen-routing`,
/// `/settings/integrations`, `/settings/whatsapp`), each inside the settings
/// shell (the web's `routes/_app/settings/route.tsx` layout).
///
/// Gates, as the web's route files have them: NONE at the route. The
/// settings rail hides what a person may not use (the generated
/// `settingsNav`, in the shell), but a typed URL always renders the pane
/// (SET-SHL-009): most panes let their reads 403 into their own error
/// state; Combos, Staff drinks, Integrations and WhatsApp refuse in the pane
/// with their own words. A route-level `caps` would show the generic
/// `Restricted` instead, so none is set. Modules: every pane but
/// Appearance and WhatsApp belongs to `pos` (the shell's `ModuleGate` reads
/// it from the path).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'booking_settings/booking_settings_page.dart';
import 'brand_appearance/appearance_page.dart';
import 'brand_appearance/brand_page.dart';
import 'brand_appearance/settings_shell.dart';
import 'combo_settings/combo_settings_page.dart';
import 'delivery/delivery_settings_page.dart';
import 'delivery/delivery_zones_page.dart';
import 'integrations/integrations_page.dart';
import 'kitchen/kitchen_routing_page.dart';
import 'kitchen/kitchen_stations_page.dart';
import 'links/links_page.dart';
import 'loyalty/loyalty_page.dart';
import 'payment_methods/payment_methods_page.dart';
import 'qr/qr_page.dart';
import 'staff_pool/staff_pool_settings_page.dart';
import 'whatsapp/whatsapp_page.dart';

const List<DashRoute> setupRoutes = [
  DashRoute(
    path: '/settings',
    builder: _appearance,
    titleKey: 'settings.appearance',
    titleFallback: 'Appearance',
  ),
  DashRoute(
    path: '/settings/brand',
    builder: _brand,
    titleKey: 'settings.brand',
    titleFallback: 'Brand',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/links',
    builder: _links,
    titleKey: 'settings.linksPage',
    titleFallback: 'Links page',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/delivery',
    builder: _delivery,
    titleKey: 'nav.delivery',
    titleFallback: 'Delivery',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/delivery-zones',
    builder: _deliveryZones,
    titleKey: 'nav.deliveryZones',
    titleFallback: 'Zone rings',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/bookings',
    builder: _bookings,
    titleKey: 'nav.bookings',
    titleFallback: 'Bookings',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/loyalty',
    builder: _loyalty,
    titleKey: 'nav.loyalty',
    titleFallback: 'Loyalty',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/qr',
    builder: _qr,
    titleKey: 'nav.qr',
    titleFallback: 'QR codes',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/combos',
    builder: _combos,
    titleKey: 'nav.combosSettings',
    titleFallback: 'Combos and deals',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/payment-methods',
    builder: _paymentMethods,
    titleKey: 'nav.paymentMethods',
    titleFallback: 'Payment methods',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/staff-pool',
    builder: _staffPool,
    titleKey: 'nav.staffPool',
    titleFallback: 'Staff drinks',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/kitchen-stations',
    builder: _kitchenStations,
    titleKey: 'nav.kitchenStations',
    titleFallback: 'Stations',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/kitchen-routing',
    builder: _kitchenRouting,
    titleKey: 'nav.kitchenRouting',
    titleFallback: 'Order routing',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/integrations',
    builder: _integrations,
    titleKey: 'nav.integrations',
    titleFallback: 'Integrations',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/whatsapp',
    builder: _whatsapp,
    titleKey: 'nav.whatsapp',
    titleFallback: 'WhatsApp',
  ),
];

Widget _shell(GoRouterState s, Widget pane) =>
    SettingsShell(path: s.uri.path, child: pane);

Widget _appearance(BuildContext c, GoRouterState s) =>
    _shell(s, const AppearancePage());

Widget _brand(BuildContext c, GoRouterState s) => _shell(s, const BrandPage());

Widget _links(BuildContext c, GoRouterState s) => _shell(s, const LinksPage());

Widget _delivery(BuildContext c, GoRouterState s) =>
    _shell(s, const DeliverySettingsPage());

Widget _deliveryZones(BuildContext c, GoRouterState s) =>
    _shell(s, const DeliveryZonesPage());

Widget _bookings(BuildContext c, GoRouterState s) =>
    _shell(s, const BookingSettingsPage());

Widget _loyalty(BuildContext c, GoRouterState s) =>
    _shell(s, const LoyaltyPage());

Widget _qr(BuildContext c, GoRouterState s) => _shell(s, const QrPage());

Widget _combos(BuildContext c, GoRouterState s) =>
    _shell(s, const ComboSettingsPage());

Widget _paymentMethods(BuildContext c, GoRouterState s) =>
    _shell(s, PaymentMethodsPage(edit: s.uri.queryParameters['edit']));

Widget _staffPool(BuildContext c, GoRouterState s) =>
    _shell(s, const StaffPoolSettingsPage());

Widget _kitchenStations(BuildContext c, GoRouterState s) =>
    _shell(s, const KitchenStationsPage());

Widget _kitchenRouting(BuildContext c, GoRouterState s) =>
    _shell(s, const KitchenRoutingPage());

Widget _integrations(BuildContext c, GoRouterState s) =>
    _shell(s, IntegrationsPage(edit: s.uri.queryParameters['edit']));

Widget _whatsapp(BuildContext c, GoRouterState s) =>
    _shell(s, const WhatsappPage());
