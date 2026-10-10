/// What the Bookings settings pane reads (`features/settings/
/// bookings-settings-pane.tsx`, `features/bookings/settings-dialog.tsx`).
///
/// Integration seam: the sell area owns the same dialog for its bookings
/// page (`dashboard_sell` `booking_settings_dialog.dart`, provider
/// `bookingSettingsProvider`). This package cannot import sell, so the pane
/// keeps its own copy keyed the same way (branch id, `/bookings/settings`);
/// one shared opener (e.g. in dashboard_core's `AreaOpeners`) would let both
/// pages open one dialog, as the web does.
library;

import 'package:dashboard_api/dashboard_api.dart' show BookingSettings;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;

abstract final class BookingSettingsPaths {
  static const String settings = '/bookings/settings';

  /// `invalidateBookings`: every key starting `/bookings` or `/floor`.
  static const List<String> invalidated = ['/bookings', '/floor'];
}

/// `GET /bookings/settings?branch_id=` (`useGetBookingSettings`), read only
/// while the dialog is open. `booking.*` refreshes it (`/bookings`).
final bookingRulesProvider = FutureProvider.autoDispose
    .family<BookingSettings, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(BookingSettingsPaths.settings));
      return ref
          .watch(apiProvider)
          .bookings
          .getBookingSettings(branchId: branchId);
    });

/// Sunday = 0 … Saturday = 6, the backend's `dow`.
const List<int> bookingDows = [0, 1, 2, 3, 4, 5, 6];

/// The fields a blank saves as null; the others save 0 when emptied.
const Set<String> bookingOptionalFields = {
  'auto_no_show_minutes',
  'reminder_lead_minutes',
  'max_covers_per_slot',
};

/// The weekday's long name in the UI language (`Intl.DateTimeFormat`
/// `en-GB` / `ar-EG`, `weekday: "long"`).
String bookingDayName(int dow, {required bool arabic}) {
  final locale = arabic ? 'ar' : 'en_GB';
  initializeDateFormatting(locale);
  // 2024-01-07 was a Sunday.
  return DateFormat('EEEE', locale).format(DateTime(2024, 1, 7 + dow));
}

/// [draft] (the settings' JSON, as edited) as the PUT body: the whole
/// object, the blank optional fields as explicit nulls.
BookingSettings bookingSettingsBody(Map<String, Object?> draft) {
  final s = BookingSettings.fromJson(draft);
  return BookingSettings(
    branchId: s.branchId,
    enabled: s.enabled,
    hours: s.hours,
    slotMinutes: s.slotMinutes,
    defaultDurationMinutes: s.defaultDurationMinutes,
    minParty: s.minParty,
    maxParty: s.maxParty,
    leadTimeMinutes: s.leadTimeMinutes,
    horizonDays: s.horizonDays,
    holdMinutes: s.holdMinutes,
    autoNoShowMinutes: s.autoNoShowMinutes,
    reminderLeadMinutes: s.reminderLeadMinutes,
    requireOtp: s.requireOtp,
    maxCoversPerSlot: s.maxCoversPerSlot,
    blackoutDates: s.blackoutDates,
    explicitNulls: {
      for (final k in bookingOptionalFields)
        if (draft[k] == null) k,
    },
  );
}
