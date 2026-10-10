/// The bookings page's reads (SELL-BKG-003, -040, -047, -060; the floor
/// tables and sections are the floor unit's own reads, one cache entry), each keyed
/// like the web's query and refetched by the same invalidations: a write's
/// `invalidateBookings` (`/bookings…` and `/floor…`, through
/// [SellInvalidate.bookings]) and a realtime `booking.*` event both bump the
/// epoch of the path the provider reads.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// `GET /bookings/settings?branch_id=` (`useGetBookingSettings`) — shared by
/// the page (the online-off notice, the timeline window, the duration
/// placeholder) and the settings dialog, as on the web.
final bookingSettingsProvider = FutureProvider.autoDispose
    .family<BookingSettings, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/bookings/settings'));
      return ref
          .watch(apiProvider)
          .bookings
          .getBookingSettings(branchId: branchId);
    });

/// One branch's day.
typedef BookingDayKey = ({String branchId, String date});

/// `GET /bookings?branch_id=&date=` (`useListBookings`): the whole day, every
/// status, in start order.
final bookingDayProvider = FutureProvider.autoDispose
    .family<List<BookingView>, BookingDayKey>((ref, key) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/bookings'));
      return ref
          .watch(apiProvider)
          .bookings
          .listBookings(branchId: key.branchId, date: key.date);
    });

/// What the booking dialog asks availability for.
typedef BookingAvailabilityKey = ({
  String branchId,
  String date,
  int partySize,
  String? sectionId,
  String? excludeBookingId,
});

/// `GET /bookings/availability` (`useBookingAvailability`): the day's slots
/// for a party, each with the server's table pick.
final bookingAvailabilityProvider = FutureProvider.autoDispose
    .family<AvailabilityResponse, BookingAvailabilityKey>((ref, key) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/bookings/availability'));
      return ref
          .watch(apiProvider)
          .bookings
          .bookingAvailability(
            branchId: key.branchId,
            date: key.date,
            partySize: key.partySize,
            sectionId: key.sectionId,
            excludeBookingId: key.excludeBookingId,
          );
    });

/// The branch's active tables, by label (`tables` on the page: the web's
/// `localeCompare`, case-blind like the backend's `lower(label)`).
List<FloorTable> activeTablesByLabel(List<FloorTable>? all) => [
  for (final t in all ?? const <FloorTable>[])
    if (t.isActive) t,
]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

/// A read the web keeps `enabled: false` is not watched at all: nothing,
/// not loading, no request.
AsyncValue<T?> watchIf<T>(
  WidgetRef ref,
  bool enabled,
  ProviderListenable<AsyncValue<T>> Function() provider,
) => enabled ? ref.watch(provider()) : const AsyncData(null);
