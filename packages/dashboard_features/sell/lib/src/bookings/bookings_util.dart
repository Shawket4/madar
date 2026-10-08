/// The bookings vocabulary (the web's `features/bookings/util.ts`): the
/// booking day (a plain calendar date in the branch zone, as the backend
/// groups them), the timeline's geometry, the clock-derived Late / Due flags,
/// the day's tallies and the guest form's values. Pure: every function here
/// is unit-tested (`test/bookings/bookings_util_test.dart`).
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart'
    show BookingSettings, BookingView;
import 'package:dashboard_core/dashboard_core.dart';

import '../shared/booking_status.dart' show isActiveBooking;
import '../shared/phone.dart';

String _two(int v) => v.toString().padLeft(2, '0');

/// `YYYY-MM-DD` of a calendar day ([month1] 1-based).
String bookingYmd(int year, int month1, int day) =>
    '${year.toString().padLeft(4, '0')}-${_two(month1)}-${_two(day)}';

final RegExp _ymdPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Whether [s] is a `YYYY-MM-DD` the route accepts (the web's `YMD`).
bool isBookingYmd(String? s) => s != null && _ymdPattern.hasMatch(s);

(int, int, int) _parts(String date) {
  final p = date.split('-').map(int.parse).toList();
  return (p[0], p[1], p[2]);
}

/// Today's calendar date in [tz] at [now] (`serviceToday`): rolls over at the
/// zone's midnight and follows its daylight saving.
String serviceToday(DateTime now, String tz) {
  final z = inZone(now, tz);
  return bookingYmd(z.year, z.month, z.day);
}

/// The calendar date an instant falls on in [tz] (`serviceDateOf`) — the day
/// a booking is listed under.
String serviceDateOf(DateTime instant, String tz) => serviceToday(instant, tz);

/// [date] ± [days], calendar arithmetic with no zone (`addDays`).
String addBookingDays(String date, int days) {
  final (y, m, d) = _parts(date);
  final u = DateTime.utc(y, m, d + days);
  return bookingYmd(u.year, u.month, u.day);
}

/// 0 = Sunday … 6 = Saturday (`weekdayOf`).
int bookingWeekday(String date) {
  final (y, m, d) = _parts(date);
  return DateTime.utc(y, m, d).weekday % 7;
}

/// The instant of wall-clock [hhmm] on [date] in [tz] (`localInstant`).
/// Overflowing parts roll over the way JavaScript's `Date` does.
DateTime localInstant(String date, String hhmm, String tz) {
  final (y, m, d) = _parts(date);
  final t = hhmm.split(':').map(int.parse).toList();
  return wallClock(tz, y, m - 1, d, t[0], t[1]);
}

/// `HH:MM` wall clock of [instant] in [tz] (`localHHMM`).
String localHHMM(DateTime instant, String tz) {
  final z = inZone(instant, tz);
  return '${_two(z.hour)}:${_two(z.minute)}';
}

/// Minutes since midnight for `HH:MM` (`minutesOf`).
int minutesOf(String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p.first.trim()) ?? 0;
  final m = p.length > 1 ? int.tryParse(p[1].trim()) ?? 0 : 0;
  return h * 60 + m;
}

/// A day's timeline window, minutes from the date's local midnight.
typedef DayWindow = ({int open, int close});

/// The window for [date] from the branch's hours (`dayWindow`): that
/// weekday's open–close; a close at or before the open (past midnight) is the
/// whole day; a day with no hours is noon–midnight, so the board still draws.
DayWindow dayWindow(BookingSettings? settings, String date) {
  final dow = bookingWeekday(date);
  final entry = settings?.hours.where((h) => h.dow == dow).firstOrNull;
  if (entry == null) return (open: 12 * 60, close: 24 * 60);
  final open = minutesOf(entry.open);
  final close = minutesOf(entry.close);
  if (close <= open) return (open: 0, close: 24 * 60);
  return (open: open, close: close);
}

/// Where a booking sits on [date]'s timeline, as percentages of [window]
/// (`timelineSpan`): clamped to the window, never narrower than 1.5 %.
({double left, double width}) timelineSpan(
  DateTime startsAt,
  DateTime endsAt,
  String date,
  DayWindow window,
  String tz,
) {
  final (y, m, d) = _parts(date);
  final dayStart = wallClock(tz, y, m - 1, d).millisecondsSinceEpoch;
  double toMin(DateTime i) => (i.millisecondsSinceEpoch - dayStart) / 60000;
  final span = (window.close - window.open).toDouble();
  final start = math.max(toMin(startsAt), window.open.toDouble());
  final end = math.min(toMin(endsAt), window.close.toDouble());
  final left = (start - window.open) / span * 100;
  final width = math.max((end - start) / span * 100, 1.5);
  final clampedLeft = math.max(0.0, math.min(left, 100.0));
  return (
    left: clampedLeft,
    width: math.min(width, 100 - math.max(0.0, left)),
  );
}

/// The hour ticks across [window] (`hourTicks`): [label] of each whole hour
/// (12-hour, `fmtHour`) and its left %.
List<({String label, double left})> hourTicks(
  DayWindow window,
  String Function(int hour) label,
) {
  final out = <({String label, double left})>[];
  final span = window.close - window.open;
  for (var m = (window.open / 60).ceil() * 60; m <= window.close; m += 60) {
    out.add((label: label((m ~/ 60) % 24), left: (m - window.open) / span * 100));
  }
  return out;
}

/// The day's tallies for the stat strip (`dayTotals`).
class DayTotals {
  const DayTotals({
    required this.total,
    required this.covers,
    required this.seated,
    required this.noShow,
    required this.needsTable,
  });

  factory DayTotals.of(List<BookingView> list) {
    var covers = 0;
    var seated = 0;
    var noShow = 0;
    var needsTable = 0;
    for (final b in list) {
      if (b.status == 'seated' || b.status == 'completed') {
        covers += b.partySize;
      }
      if (b.status == 'seated') seated += 1;
      if (b.status == 'no_show') noShow += 1;
      if (b.needsTable) needsTable += 1;
    }
    return DayTotals(
      total: list.length,
      covers: covers,
      seated: seated,
      noShow: noShow,
      needsTable: needsTable,
    );
  }

  final int total;

  /// Σ party of seated + completed.
  final int covers;
  final int seated;
  final int noShow;
  final int needsTable;
}

/// The booking's hold has begun (`isHeld`): confirmed and `held_from` ≤ now.
bool isHeldBooking(BookingView b, DateTime now) =>
    b.status == 'confirmed' && !b.heldFrom.isAfter(now);

/// The party is late (`isLate`): confirmed and its start has passed.
bool isLateBooking(BookingView b, DateTime now) =>
    b.status == 'confirmed' && b.startsAt.isBefore(now);

/// The list's status filter: `active`, `all`, or one status.
const List<String> bookingFilters = [
  'active',
  'all',
  'confirmed',
  'seated',
  'completed',
  'no_show',
  'cancelled',
];

/// [all] narrowed by [filter] (the page's `rows`, and the export's `picked`).
List<BookingView> filterBookings(List<BookingView> all, String filter) =>
    switch (filter) {
      'all' => all,
      'active' => [
        for (final b in all)
          if (isActiveBooking(b.status)) b,
      ],
      _ => [
        for (final b in all)
          if (b.status == filter) b,
      ],
    };

/// The guest fields of the booking form (`BookingGuestValues`).
typedef BookingGuestValues = ({String name, String phone, String notes});

/// The form's values for [b] (`guestValuesOf`): the stored canonical phone is
/// shown the way a host types it (`201001234567` → `01001234567`).
BookingGuestValues guestValuesOf(BookingView? b) => (
  name: b?.guestName ?? '',
  phone: formatPhoneInput(b?.guestPhone),
  notes: b?.notes ?? '',
);

/// What goes on the wire (`guestPhoneToWire`): the canonical phone.
String guestPhoneToWire(String typed) =>
    canonicalPhone(typed) ?? typed.trim();

/// The custom-time box's rule (`/^\d{1,2}:\d{2}$/`, ASCII digits only).
final RegExp customTimePattern = RegExp(r'^[0-9]{1,2}:[0-9]{2}$');
