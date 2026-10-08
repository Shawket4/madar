/// A booking's status, toned (the web's `features/bookings/status-badge.tsx`
/// + `bookings/util.ts` `STATUS_TONES`): shared by the bookings list
/// (SELL-BKG-014) and a customer's Bookings section (SELL-CUS-050).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';

/// Every booking status, in the web's order (`BOOKING_STATUSES`).
const List<String> bookingStatuses = [
  'confirmed',
  'seated',
  'completed',
  'no_show',
  'cancelled',
];

/// The pill tone of a booking status (`STATUS_TONES`); unknown → neutral.
DashTone bookingStatusTone(String status) => switch (status) {
  'confirmed' => DashTone.accent,
  'seated' => DashTone.success,
  'no_show' => DashTone.danger,
  _ => DashTone.neutral,
};

/// Confirmed or seated (`isActive`).
bool isActiveBooking(String status) =>
    status == 'confirmed' || status == 'seated';

/// The status word: `bookings.status.<status>`, else the raw value with its
/// first "_" read as a space (the web's inline default).
String bookingStatusLabel(Translator t, String status) =>
    t('bookings.status.$status', defaultValue: status.replaceFirst('_', ' '));

/// The toned status pill (`BookingStatusBadge`).
class BookingStatusPill extends StatelessWidget {
  const BookingStatusPill({
    required this.status,
    this.small = false,
    super.key,
  });

  final String status;
  final bool small;

  @override
  Widget build(BuildContext context) => DashStatusPill(
    label: bookingStatusLabel(context.translator, status),
    tone: bookingStatusTone(status),
    small: small,
  );
}
