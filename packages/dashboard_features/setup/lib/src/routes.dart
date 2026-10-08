/// The setup area's pages (`/settings`, `/settings/brand`, `/settings/links`,
/// `/settings/delivery`, `/settings/delivery-zones`, `/settings/bookings`,
/// `/settings/loyalty`, `/settings/qr`, `/settings/combos`,
/// `/settings/payment-methods`, `/settings/staff-pool`,
/// `/settings/kitchen-stations`, `/settings/kitchen-routing`,
/// `/settings/integrations`, `/settings/whatsapp`) with the web's capabilities
/// (any-of, from the generated nav and settings nav) and module. A route
/// without a builder shows the shell's placeholder until its page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';

const List<DashRoute> setupRoutes = [
  DashRoute(
    path: '/settings',
    titleKey: 'settings.appearance',
    titleFallback: 'Appearance',
  ),
  DashRoute(
    path: '/settings/brand',
    titleKey: 'settings.brand',
    titleFallback: 'Brand',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/links',
    titleKey: 'settings.linksPage',
    titleFallback: 'Links page',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/delivery',
    titleKey: 'nav.delivery',
    titleFallback: 'Delivery',
    caps: [Cap.deliverySettingsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/delivery-zones',
    titleKey: 'nav.deliveryZones',
    titleFallback: 'Zone rings',
    caps: [Cap.deliverySettingsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/bookings',
    titleKey: 'nav.bookings',
    titleFallback: 'Bookings',
    caps: [Cap.bookingsEdit],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/loyalty',
    titleKey: 'nav.loyalty',
    titleFallback: 'Loyalty',
    caps: [Cap.loyaltyUse, Cap.loyaltyMembersList],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/qr',
    titleKey: 'nav.qr',
    titleFallback: 'QR codes',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/combos',
    titleKey: 'nav.combosSettings',
    titleFallback: 'Combos and deals',
    caps: [Cap.orgSettingsRead, Cap.menuCombosEdit],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/payment-methods',
    titleKey: 'nav.paymentMethods',
    titleFallback: 'Payment methods',
    caps: [Cap.paymentMethodsEdit],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/staff-pool',
    titleKey: 'nav.staffPool',
    titleFallback: 'Staff drinks',
    caps: [Cap.orgSettingsRead, Cap.orgSettingsEdit],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/kitchen-stations',
    titleKey: 'nav.kitchenStations',
    titleFallback: 'Stations',
    caps: [Cap.kitchenStationsEdit],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/kitchen-routing',
    titleKey: 'nav.kitchenRouting',
    titleFallback: 'Order routing',
    caps: [Cap.kitchenStationsEdit],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/integrations',
    titleKey: 'nav.integrations',
    titleFallback: 'Integrations',
    caps: [Cap.integrationsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/settings/whatsapp',
    titleKey: 'nav.whatsapp',
    titleFallback: 'WhatsApp',
    platformOnly: true,
  ),
];
