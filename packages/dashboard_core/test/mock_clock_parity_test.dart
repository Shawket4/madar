// The mock backend's Cairo clock (dashboard_api's MockClock) hand-codes
// Egypt's summer time, because dashboard_api runs without the native bridge.
// This pins it to madar-time's zone rules (through the dashboard bridge) for
// every hour of the mock's year, so the seeds and screenshots never drift
// from what the server and the POS core compute.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cairo = MockClock.timezone;

  test('the mock zone is the app default zone', () {
    expect(cairo, appTimezone);
  });

  test('every instant of 2026 reads on the wall clock as madar-time reads '
      'it: +03 from the last Friday of April to the last Thursday of '
      'October, +02 otherwise', () {
    final start = DateTime.utc(2026);
    for (var h = 0; h < 365 * 24; h++) {
      for (final m in [0, 30]) {
        final at = start.add(Duration(hours: h, minutes: m));
        expect(MockClock.wall(at), inZone(at, cairo), reason: '$at');
      }
    }
    expect(MockClock.offsetAt(DateTime.utc(2026, 7, 15, 12)).inHours, 3);
    expect(MockClock.offsetAt(DateTime.utc(2026, 10, 29, 20, 59)).inHours, 3);
    expect(MockClock.offsetAt(DateTime.utc(2026, 10, 29, 21)).inHours, 2);
    expect(MockClock.offsetAt(DateTime.utc(2026, 4, 23, 21, 59)).inHours, 2);
    expect(MockClock.offsetAt(DateTime.utc(2026, 4, 23, 22)).inHours, 3);
  });

  test('every wall-clock hour of 2026 is the instant madar-time places it '
      'at, but the two the clocks skip or repeat', () {
    for (var d = DateTime.utc(2026); d.year == 2026; d = d.add(_day)) {
      for (var hour = 0; hour < 24; hour++) {
        // 00:00–00:59 on 24 Apr never happens and 23:00–23:59 on 29 Oct
        // happens twice; the mock reads them its own way and seeds nothing
        // there.
        final skipped = d.month == 4 && d.day == 24 && hour == 0;
        final repeated = d.month == 10 && d.day == 29 && hour == 23;
        if (skipped || repeated) continue;
        expect(
          MockClock.fromCairo(d.year, d.month, d.day, hour, 15),
          wallClock(cairo, d.year, d.month - 1, d.day, hour, 15),
          reason: '${d.toIso8601String().substring(0, 10)} $hour:15',
        );
      }
    }
  });
}

const Duration _day = Duration(days: 1);
