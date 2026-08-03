/// Sidebar information architecture — a Dart port of the web dashboard's
/// `src/config/nav.ts` (the single source of truth for nav + command palette).
/// Icons are MadarIcon catalog names (SF-symbol-style → Lucide via design_system).
library;

sealed class NavEntry {
  const NavEntry();
}

/// A single navigable destination.
class NavLeaf extends NavEntry {
  const NavLeaf({
    required this.path,
    required this.labelKey,
    required this.fallback,
    required this.icon,
    this.roles,
    this.superAdminOnly = false,
  });

  final String path;
  final String labelKey;
  final String fallback;

  /// MadarIcon catalog name.
  final String icon;

  /// Restrict visibility to these roles; null = everyone.
  final List<String>? roles;

  /// Shorthand for `roles: ['super_admin']`.
  final bool superAdminOnly;

  bool visibleTo(String role) {
    if (superAdminOnly) return role == 'super_admin';
    if (roles == null) return true;
    return roles!.contains(role);
  }
}

/// A collapsible group of leaves sharing a base path.
class NavParent extends NavEntry {
  const NavParent({
    required this.labelKey,
    required this.fallback,
    required this.icon,
    required this.basePath,
    required this.children,
  });

  final String labelKey;
  final String fallback;
  final String icon;
  final String basePath;
  final List<NavLeaf> children;
}

/// A titled section of the sidebar.
class NavGroup {
  const NavGroup({
    required this.labelKey,
    required this.fallback,
    required this.entries,
  });

  final String labelKey;
  final String fallback;
  final List<NavEntry> entries;
}

/// The full navigation tree (mirrors NAV in nav.ts).
const List<NavGroup> kNav = [
  NavGroup(
    labelKey: 'nav.overview',
    fallback: 'Overview',
    entries: [
      NavLeaf(
        path: '/',
        labelKey: 'nav.dashboard',
        fallback: 'Dashboard',
        icon: 'square.grid.2x2.fill',
      ),
    ],
  ),
  NavGroup(
    labelKey: 'nav.sell',
    fallback: 'Sell',
    entries: [
      NavLeaf(
        path: '/orders',
        labelKey: 'nav.orders',
        fallback: 'Orders',
        icon: 'receipt',
      ),
      NavLeaf(
        path: '/reservations',
        labelKey: 'nav.reservations',
        fallback: 'Reservations',
        icon: 'person',
      ),
      NavLeaf(
        path: '/shifts',
        labelKey: 'nav.shifts',
        fallback: 'Shifts',
        icon: 'clock',
      ),
      NavLeaf(
        path: '/tills',
        labelKey: 'nav.tills',
        fallback: 'Tills',
        icon: 'wallet',
      ),
    ],
  ),
  NavGroup(
    labelKey: 'nav.catalog',
    fallback: 'Catalog',
    entries: [
      NavParent(
        labelKey: 'nav.menu',
        fallback: 'Menu',
        icon: 'fork.knife',
        basePath: '/menu',
        children: [
          NavLeaf(
            path: '/menu/items',
            labelKey: 'nav.items',
            fallback: 'Items',
            icon: 'cup.and.saucer',
          ),
          NavLeaf(
            path: '/menu/pricing',
            labelKey: 'nav.pricingAvailability',
            fallback: 'Pricing & Availability',
            icon: 'slider.horizontal.3',
          ),
        ],
      ),
      NavLeaf(
        path: '/menu/bundles',
        labelKey: 'nav.bundles',
        fallback: 'Bundles',
        icon: 'layers',
      ),
      NavLeaf(
        path: '/discounts',
        labelKey: 'nav.discounts',
        fallback: 'Discounts',
        icon: 'tag',
      ),
    ],
  ),
  NavGroup(
    labelKey: 'nav.insights',
    fallback: 'Insights',
    entries: [
      NavLeaf(
        path: '/insights/ai-chat',
        labelKey: 'nav.aiChat',
        fallback: 'Ask',
        icon: 'text.bubble',
      ),
      NavLeaf(
        path: '/insights/sales',
        labelKey: 'nav.salesInsights',
        fallback: 'Sales',
        icon: 'chart.pie',
      ),
      NavLeaf(
        path: '/insights/profitability',
        labelKey: 'nav.menuProfitability',
        fallback: 'Menu profitability',
        icon: 'arrow.up.right',
      ),
    ],
  ),
  NavGroup(
    labelKey: 'nav.inventory',
    fallback: 'Inventory',
    entries: [
      NavParent(
        labelKey: 'nav.inventory',
        fallback: 'Inventory',
        icon: 'shippingbox',
        basePath: '/inventory',
        children: [
          NavLeaf(
            path: '/inventory/today',
            labelKey: 'nav.invToday',
            fallback: 'Today',
            icon: 'square.grid.2x2',
          ),
          NavLeaf(
            path: '/inventory/ingredients',
            labelKey: 'nav.ingredients',
            fallback: 'Ingredients',
            icon: 'shippingbox',
          ),
          NavLeaf(
            path: '/inventory/purchasing',
            labelKey: 'nav.invPurchasing',
            fallback: 'Purchasing',
            icon: 'cart',
          ),
          NavLeaf(
            path: '/inventory/counts',
            labelKey: 'nav.invCounts',
            fallback: 'Stock counts',
            icon: 'list.bullet',
          ),
          NavLeaf(
            path: '/inventory/waste',
            labelKey: 'nav.invWaste',
            fallback: 'Waste',
            icon: 'trash',
          ),
          NavLeaf(
            path: '/inventory/transfers',
            labelKey: 'nav.invTransfers',
            fallback: 'Transfers',
            icon: 'arrow.up.arrow.down',
          ),
          NavLeaf(
            path: '/inventory/reports',
            labelKey: 'nav.invReports',
            fallback: 'Reports',
            icon: 'chart.pie',
          ),
          NavLeaf(
            path: '/inventory/settings',
            labelKey: 'nav.invSettings',
            fallback: 'Settings',
            icon: 'gearshape',
          ),
        ],
      ),
    ],
  ),
  NavGroup(
    labelKey: 'nav.setup',
    fallback: 'Setup',
    entries: [
      NavParent(
        labelKey: 'nav.delivery',
        fallback: 'Delivery',
        icon: 'bicycle',
        basePath: '/delivery',
        children: [
          NavLeaf(
            path: '/delivery/settings',
            labelKey: 'nav.deliverySettings',
            fallback: 'Settings',
            icon: 'gearshape',
          ),
          NavLeaf(
            path: '/delivery/zones',
            labelKey: 'nav.deliveryZones',
            fallback: 'Zone rings',
            icon: 'layers',
          ),
        ],
      ),
      NavParent(
        labelKey: 'nav.kitchen',
        fallback: 'Kitchen',
        icon: 'fork.knife',
        basePath: '/kitchen',
        children: [
          NavLeaf(
            path: '/kitchen/stations',
            labelKey: 'nav.kitchenStations',
            fallback: 'Stations',
            icon: 'fork.knife',
          ),
          NavLeaf(
            path: '/kitchen/routing',
            labelKey: 'nav.kitchenRouting',
            fallback: 'Order routing',
            icon: 'slider.horizontal.3',
          ),
        ],
      ),
      NavLeaf(
        path: '/qr',
        labelKey: 'nav.qr',
        fallback: 'QR Codes',
        icon: 'qrcode',
      ),
      NavLeaf(
        path: '/settings/payment-methods',
        labelKey: 'nav.paymentMethods',
        fallback: 'Payment methods',
        icon: 'creditcard',
        roles: ['org_admin', 'super_admin'],
      ),
      NavLeaf(
        path: '/settings/whatsapp',
        labelKey: 'nav.whatsapp',
        fallback: 'WhatsApp',
        icon: 'text.bubble',
        superAdminOnly: true,
      ),
      NavLeaf(
        path: '/settings',
        labelKey: 'nav.settings',
        fallback: 'General settings',
        icon: 'gearshape',
      ),
    ],
  ),
  NavGroup(
    labelKey: 'nav.admin',
    fallback: 'Administration',
    entries: [
      NavLeaf(
        path: '/orgs',
        labelKey: 'nav.orgs',
        fallback: 'Organizations',
        icon: 'building.2',
        superAdminOnly: true,
      ),
      NavLeaf(
        path: '/branches',
        labelKey: 'nav.branches',
        fallback: 'Branches',
        icon: 'storefront',
      ),
      NavLeaf(
        path: '/access/users',
        labelKey: 'nav.usersPermissions',
        fallback: 'Users & Permissions',
        icon: 'person',
      ),
    ],
  ),
];
