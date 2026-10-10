// The core's copies of madar-shared rules, run over the vectors the web pins
// (src/lib/*_vectors.json, copied by tool/sync_web_vectors.py into test/vectors/):
// day bounds, business date and the wall clock (madar-time; wallclock copied
// from madar-shared, pinned by its .source.json), the average ticket
// (madar-money). The web's lib/madar-time.test.ts and lib/average-ticket.test.ts.
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, Object?>> _cases(Object? v) =>
    (v! as List).cast<Map<String, Object?>>();

({int y, int m, int d}) _parts(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return (y: p[0], m: p[1] - 1, d: p[2]);
}

String _iso(String instant, [int minusMs = 0]) => isoString(
  DateTime.parse(instant).subtract(Duration(milliseconds: minusMs)),
);

void main() {
  test('dayBoundaryISO and cairoDateISO: day_bounds vectors', () {
    final cases = _cases(sharedVectors('day_bounds'));
    expect(cases, isNotEmpty);
    for (final v in cases) {
      final tz = v['tz']! as String;
      final p = _parts(v['date']! as String);
      final why = '${v['tz']} ${v['date']} (${v['hours']} h)';
      final start = _iso(v['start']! as String);
      // Reports filter `at <= to`: the last instant is Rust's exclusive end minus 1 ms.
      final end = _iso(v['end']! as String, 1);
      expect(dayBoundaryISO(tz, p.y, p.m, p.d), start, reason: why);
      expect(
        dayBoundaryISO(tz, p.y, p.m, p.d, endOfDay: true),
        end,
        reason: why,
      );
      final f = DashFormat(lang: 'en', timezone: tz);
      expect(f.cairoDateISO(p.y, p.m, p.d), start, reason: why);
      expect(f.cairoDateISO(p.y, p.m, p.d, endOfDay: true), end, reason: why);
    }
  });

  test('cairoParts: business_date vectors', () {
    final cases = _cases(sharedVectors('business_date'));
    expect(cases, isNotEmpty);
    for (final v in cases) {
      final f = DashFormat(lang: 'en', timezone: v['tz']! as String);
      expect(
        f.cairoParts(v['at']! as String),
        _parts(v['business_date']! as String),
        reason: '${v['tz']} ${v['at']}',
      );
    }
  });

  test('inZone and wallClock: wallclock vectors', () {
    final m = sharedVectors('wallclock')! as Map;
    final parts = _cases(m['parts']);
    expect(parts, isNotEmpty);
    for (final v in parts) {
      final z = inZone(DateTime.parse(v['at']! as String), v['tz']! as String);
      final d = _parts(v['date']! as String);
      expect(
        (y: z.year, m: z.month - 1, d: z.day, h: z.hour, mi: z.minute),
        (y: d.y, m: d.m, d: d.d, h: v['hour'], mi: v['minute']),
        reason: '${v['note']}',
      );
    }
    final instants = _cases(m['instants']);
    expect(instants, isNotEmpty);
    for (final v in instants) {
      final d = _parts(v['date']! as String);
      expect(
        isoString(
          wallClock(
            v['tz']! as String,
            d.y,
            d.m,
            d.d,
            v['hour']! as int,
            v['minute']! as int,
          ),
        ),
        _iso(v['at']! as String),
        reason: '${v['note']}',
      );
    }
  });

  test('averageTicket: pos_metrics vectors and the Rust rounding cases', () {
    final m = sharedVectors('pos_metrics')! as Map<String, Object?>;
    final cases = _cases(m['expected']);
    expect(cases, isNotEmpty);
    for (final w in cases) {
      expect(
        averageTicket(w['net_sales']! as int, w['order_count']! as int),
        w['average_ticket'],
        reason: '${w['from']}',
      );
    }
    for (final (s, o, want) in [
      (0, 0, 0),
      (1000, 0, 0),
      (1000, -1, 0),
      (5, 2, 3),
      (7, 3, 2),
      (8, 3, 3),
      (-5, 2, -2),
    ]) {
      expect(averageTicket(s, o), want, reason: '$s / $o');
    }
  });
}
