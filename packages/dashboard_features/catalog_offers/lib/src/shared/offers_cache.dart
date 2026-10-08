/// What a write in this area makes stale, as the web's React Query
/// invalidations (`invalidateCombos`, `invalidateDiscounts`), through the
/// core's prefix invalidation: a provider that reads `/deals` watches
/// `realtimeEpochProvider(OffersPaths.deals)` and refetches when a write (or
/// a `resync` frame) invalidates that prefix — in this area and in others
/// (the combo settings, the Bundles report, the menu, costing).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The read paths this area's providers key their epochs on.
abstract final class OffersPaths {
  static const String combos = '/combos';
  static const String deals = '/deals';
  static const String discounts = '/discounts';
  static const String menuItems = '/menu-items';
  static const String categories = '/categories';
  static const String branches = '/branches';
}

/// Every prefix `invalidateCombos()` refreshes (`features/combos/util.ts`).
const List<String> combosInvalidationPrefixes = [
  '/combos',
  '/deals',
  '/settings/combos',
  '/reports/bundles',
  '/menu-items',
  '/costing',
];

/// After any combo, deal or deal-branch write: the combos list, a combo,
/// the price check, the deals, the combo settings, the Bundles report, menu
/// items and costing all refetch.
void invalidateCombos(WidgetRef ref) =>
    ref.read(realtimeBusProvider).invalidate(combosInvalidationPrefixes);

/// After any discount write: every `/discounts` read refetches.
void invalidateDiscounts(WidgetRef ref) =>
    ref.read(realtimeBusProvider).invalidate(const [OffersPaths.discounts]);
