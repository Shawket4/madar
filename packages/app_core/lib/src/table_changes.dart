import 'package:app_core/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every logical table the core names in a `watchTables` batch, and `*`.
///
/// The core decides WHAT changed (a pull landed, a sale was rung, a peer's
/// op was mirrored, a realtime event arrived); this only routes the name to
/// the board tick that re-reads it. No meaning is decided here.
abstract final class CoreTables {
  static const all = '*';
  static const tills = 'tills';
  static const orders = 'orders';
  static const cashMovements = 'cash_movements';
  static const refunds = 'refunds';
  static const openTickets = 'open_tickets';
  static const kitchen = 'kitchen';
  static const delivery = 'delivery';
  static const bookings = 'bookings';
  static const floor = 'floor';
  static const catalog = 'catalog';
  static const paymentMethods = 'payment_methods';
  static const outbox = 'outbox';
  static const sync = 'sync';
}

/// The board ticks a batch of changed tables bumps (each tick at most once).
List<NotifierProvider<TickNotifier, int>> ticksForTables(
  Iterable<String> tables,
) {
  final set = tables.toSet();
  final all = set.contains(CoreTables.all);
  bool has(String t) => all || set.contains(t);
  return [
    if (has(CoreTables.tills) ||
        has(CoreTables.orders) ||
        has(CoreTables.cashMovements) ||
        has(CoreTables.refunds))
      drawerTickProvider,
    if (has(CoreTables.openTickets)) ticketTickProvider,
    if (has(CoreTables.kitchen)) kitchenTickProvider,
    if (has(CoreTables.delivery)) deliveryTickProvider,
    if (has(CoreTables.bookings)) bookingTickProvider,
    if (has(CoreTables.floor) || has(CoreTables.bookings)) floorTickProvider,
    if (has(CoreTables.catalog) || has(CoreTables.paymentMethods))
      catalogTickProvider,
    if (has(CoreTables.outbox) || has(CoreTables.sync)) syncTickProvider,
  ];
}

/// Bump the ticks for one `watchTables` batch.
void applyTableChanges(Ref ref, Iterable<String> tables) {
  for (final tick in ticksForTables(tables)) {
    ref.read(tick.notifier).bump();
  }
}
