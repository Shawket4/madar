/// The sell area's refresh rules: the web's React Query invalidations (the
/// inventory's "Invalidation names"), over the core's prefix epochs.
///
/// A provider that reads `/floor/tables` watches
/// `realtimeEpochProvider('/floor/tables')`; a write calls
/// `sellInvalidate(ref, SellInvalidate.bookings)`, and every provider whose
/// path starts with one of the prefixes refetches — exactly what the web's
/// `queryKey[0].startsWith(prefix)` predicates do, and what a realtime event
/// does (SELL-ALL-006). One unit can so refresh another's data (a booking
/// write refreshes the floor) without importing its providers.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class SellInvalidate {
  /// `invalidateFloor` (`features/floor/util.ts:4`): every `/floor…` read.
  static const List<String> floor = ['/floor'];

  /// `invalidateOccupants` (`floor/util.ts:11`): the open tickets.
  static const List<String> occupants = ['/open-tickets'];

  /// Transfer fulfil/cancel: the floor and its occupants.
  static const List<String> transfers = ['/floor', '/open-tickets'];

  /// `invalidateBookings` (`bookings/util.ts:55`): bookings and the floor
  /// (tables carry their next booking).
  static const List<String> bookings = ['/bookings', '/floor'];

  /// `invalidateTills` (`tills/api.ts:78`): tills and every report.
  static const List<String> tills = ['/tills', '/reports'];

  /// `isPersonQuery` (`customers/util.ts:70`): customers and loyalty.
  static const List<String> people = ['/customers', '/loyalty/'];

  /// The orders void (`void-order-dialog.tsx:44-45`): the order list and
  /// [orderId]'s own read.
  static List<String> orderVoided(String orderId) => [
    '/orders',
    '/orders/$orderId',
  ];
}

/// Marks [prefixes] stale, as the web's `invalidateQueries` (and a realtime
/// event) would.
void sellInvalidate(Ref ref, List<String> prefixes) =>
    ref.read(realtimeBusProvider).invalidate(prefixes);

/// [sellInvalidate] from a widget.
void sellInvalidateFromWidget(WidgetRef ref, List<String> prefixes) =>
    ref.read(realtimeBusProvider).invalidate(prefixes);
