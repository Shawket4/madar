// The bookings vocabulary (the web's `bookings/util.test.ts`, ported): the
// booking day, local time, the timeline's geometry, tallies and clock flags.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_sell/src/bookings/bookings_util.dart';
import 'package:flutter_test/flutter_test.dart';

const _tz = 'Africa/Cairo';

BookingSettings _settings(List<HoursEntry> hours) => BookingSettings(
  branchId: 'b',
  enabled: true,
  hours: hours,
  slotMinutes: 30,
  defaultDurationMinutes: 90,
  minParty: 1,
  maxParty: 12,
  leadTimeMinutes: 60,
  horizonDays: 30,
  holdMinutes: 15,
  requireOtp: true,
  blackoutDates: const [],
);

BookingView _b({
  String status = 'confirmed',
  int party = 2,
  bool needsTable = false,
}) => BookingView(
  id: '1',
  branchId: 'b',
  status: status,
  partySize: party,
  startsAt: DateTime.parse('2026-09-10T16:30:00Z'),
  endsAt: DateTime.parse('2026-09-10T18:00:00Z'),
  heldFrom: DateTime.parse('2026-09-10T16:15:00Z'),
  guestName: 'A',
  guestPhone: '2',
  phoneVerified: false,
  source: 'host',
  locale: 'en',
  tableIds: const [],
  tableLabels: const [],
  needsTable: needsTable,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  setUpAll(ensureTimeZones);

  group('SELL-BKG-005 booking day', () {
    test('puts 00:30 on its own calendar date and rolls over at midnight', () {
      expect(
        serviceToday(DateTime.parse('2026-09-10T21:30:00Z'), _tz),
        '2026-09-11',
      );
      expect(
        serviceToday(DateTime.parse('2026-09-10T20:59:00Z'), _tz),
        '2026-09-10',
      );
    });
    test('follows DST in the branch zone', () {
      expect(
        serviceToday(DateTime.parse('2026-03-28T23:30:00Z'), 'Europe/London'),
        '2026-03-28',
      );
      expect(
        serviceToday(DateTime.parse('2026-03-29T00:30:00Z'), 'Europe/London'),
        '2026-03-29',
      );
      expect(
        serviceToday(DateTime.parse('2026-07-01T23:30:00Z'), 'Europe/London'),
        '2026-07-02',
      );
    });
    test('adds days and knows weekdays', () {
      expect(addBookingDays('2026-09-30', 1), '2026-10-01');
      expect(addBookingDays('2026-03-01', -1), '2026-02-28');
      expect(bookingWeekday('2026-09-10'), 4);
    });
    test('serviceDateOf is the branch calendar day, not UTC', () {
      expect(
        serviceDateOf(DateTime.parse('2026-09-10T21:30:00Z'), _tz),
        '2026-09-11',
      );
      expect(
        serviceDateOf(DateTime.parse('2026-09-10T20:59:00Z'), _tz),
        '2026-09-10',
      );
    });
  });

  test('SELL-BKG-042 a wall clock round-trips through the branch zone', () {
    final i = localInstant('2026-09-10', '19:30', _tz);
    expect(i.toUtc().toIso8601String(), '2026-09-10T16:30:00.000Z');
    expect(localHHMM(i, _tz), '19:30');
    expect(customTimePattern.hasMatch('7:05'), isTrue);
    expect(customTimePattern.hasMatch('19:30'), isTrue);
    expect(customTimePattern.hasMatch('1930'), isFalse);
    expect(customTimePattern.hasMatch('١٩:٣٠'), isFalse);
  });

  group('SELL-BKG-027/028 timeline', () {
    final win = dayWindow(
      _settings(const [HoursEntry(dow: 4, open: '18:00', close: '23:00')]),
      '2026-09-10',
    );
    test(
      'the day\'s hours, the whole day past midnight, noon–midnight when closed',
      () {
        expect(win, (open: 18 * 60, close: 23 * 60));
        expect(
          dayWindow(
            _settings(const [
              HoursEntry(dow: 4, open: '18:00', close: '02:00'),
            ]),
            '2026-09-10',
          ),
          (open: 0, close: 24 * 60),
        );
        expect(dayWindow(_settings(const []), '2026-09-10'), (
          open: 12 * 60,
          close: 24 * 60,
        ));
        expect(dayWindow(null, '2026-09-10'), (open: 12 * 60, close: 24 * 60));
      },
    );
    test('places a 19:30–21:00 booking inside an 18:00–23:00 window', () {
      final s = timelineSpan(
        DateTime.parse('2026-09-10T16:30:00Z'),
        DateTime.parse('2026-09-10T18:00:00Z'),
        '2026-09-10',
        win,
        _tz,
      );
      expect(s.left, closeTo(90 / 300 * 100, 1e-9));
      expect(s.width, closeTo(90 / 300 * 100, 1e-9));
      final late = timelineSpan(
        DateTime.parse('2026-09-10T21:30:00Z'),
        DateTime.parse('2026-09-10T23:00:00Z'),
        '2026-09-11',
        (open: 0, close: 1440),
        _tz,
      );
      expect(late.left, closeTo(30 / 1440 * 100, 1e-9));
    });
    test('a block is never narrower than 1.5 % and never leaves the row', () {
      final tiny = timelineSpan(
        DateTime.parse('2026-09-10T16:30:00Z'),
        DateTime.parse('2026-09-10T16:31:00Z'),
        '2026-09-10',
        win,
        _tz,
      );
      expect(tiny.width, 1.5);
      final over = timelineSpan(
        DateTime.parse('2026-09-10T19:30:00Z'),
        DateTime.parse('2026-09-10T21:30:00Z'),
        '2026-09-10',
        win,
        _tz,
      );
      expect(over.left + over.width, lessThanOrEqualTo(100));
    });
    test('hour ticks across the window', () {
      final fmt = const DashFormat(lang: 'en', timezone: _tz);
      final ticks = hourTicks(win, fmt.fmtHour);
      expect(ticks.first, (label: '06:00 PM', left: 0.0));
      expect(ticks.last, (label: '11:00 PM', left: 100.0));
    });
  });

  group('SELL-BKG-008/012 tallies and state', () {
    test(
      'covers count seated and completed only; parties with no table are flagged',
      () {
        final t = DayTotals.of([
          _b(status: 'seated', party: 4),
          _b(status: 'completed', party: 3),
          _b(status: 'no_show'),
          _b(needsTable: true),
        ]);
        expect(
          [t.total, t.covers, t.seated, t.noShow, t.needsTable],
          [4, 7, 1, 1, 1],
        );
      },
    );
    test('held and late from the clock', () {
      final x = _b();
      expect(isHeldBooking(x, DateTime.parse('2026-09-10T16:20:00Z')), isTrue);
      expect(isHeldBooking(x, DateTime.parse('2026-09-10T16:00:00Z')), isFalse);
      expect(isLateBooking(x, DateTime.parse('2026-09-10T16:40:00Z')), isTrue);
      expect(
        isHeldBooking(
          _b(status: 'seated'),
          DateTime.parse('2026-09-10T17:00:00Z'),
        ),
        isFalse,
      );
    });
    test('SELL-BKG-010 the filters', () {
      final all = [
        _b(),
        _b(status: 'seated'),
        _b(status: 'completed'),
        _b(status: 'cancelled'),
      ];
      expect(filterBookings(all, 'active').length, 2);
      expect(filterBookings(all, 'all').length, 4);
      expect(filterBookings(all, 'cancelled').single.status, 'cancelled');
      expect(filterBookings(all, 'no_show'), isEmpty);
    });
  });

  test('SELL-BKG-037/046 a stored phone is shown the way a host types it', () {
    final v = guestValuesOf(_b());
    expect(v.notes, '');
    expect(guestPhoneToWire('0100 123-4567'), '201001234567');
    expect(guestPhoneToWire('٠١٠٠١٢٣٤٥٦٧'), '201001234567');
    expect(guestPhoneToWire('+966512345678'), '966512345678');
  });
}
