// The Till sessions arithmetic (`tills_lib.dart`), the web's `lib.test.ts`
// case for case (REP-TIL-018, -021, -022, -006).
import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, TillSessionRow;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_reports/src/shared/report_dates.dart';
import 'package:dashboard_reports/src/tills_report/tills_lib.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

var _seq = 0;

TillSessionRow _till({
  String openedAt = '2026-09-18T06:00:00Z',
  String? closedAt = '2026-09-18T14:00:00Z',
  String status = 'closed',
  int orders = 0,
  int sales = 0,
}) => TillSessionRow.fromJson({
  ...webSessions().first,
  'till_id': 'till-${++_seq}',
  'opened_at': openedAt,
  'closed_at': closedAt,
  'status': status,
  'orders_count': orders,
  'net_sales': sales,
});

const _cairo = 'Africa/Cairo';

void main() {
  setUpAll(ensureTimeZones);

  group('meanTimeOfDay', () {
    test('averages ordinary times the obvious way', () {
      expect(meanTimeOfDay([8 * 60, 10 * 60]), 9 * 60);
    });

    test('averages ACROSS midnight instead of landing at noon', () {
      expect(meanTimeOfDay([23 * 60 + 50, 10]), 0);
    });

    test('has no answer for times spread evenly round the clock', () {
      expect(meanTimeOfDay([0, 6 * 60, 12 * 60, 18 * 60]), isNull);
    });

    test('returns null for nothing to average', () {
      expect(meanTimeOfDay([]), isNull);
    });

    test('formats minutes past midnight on the 12-hour clock, in the app '
        'language', () {
      const en = DashFormat();
      expect(fmtMinutesOfDay(en, 0), '12:00 AM');
      expect(fmtMinutesOfDay(en, 7 * 60 + 5), '07:05 AM');
      expect(fmtMinutesOfDay(en, 19 * 60 + 5), '07:05 PM');
      expect(fmtMinutesOfDay(en, null), '—');
      expect(fmtMinutesOfDay(const DashFormat(lang: 'ar'), 19 * 60 + 5),
          contains('07:05 م'));
    });
  });

  group('salesStats', () {
    test('averages the bill over orders, not over tills', () {
      final s = salesStats([
        _till(orders: 3, sales: 300),
        _till(orders: 1, sales: 100),
      ]);
      expect(s.orders, 4);
      expect(s.sales, 400);
      expect(s.avgOrderValue, 100);
      expect(s.avgSalesPerTill, 200);
    });

    test('divides by nothing safely', () {
      final s = salesStats([]);
      expect(s.avgOrderValue, 0);
      expect(s.avgSalesPerTill, 0);
    });

    test('rounds half up, as Math.round', () {
      expect(salesStats([_till(orders: 2, sales: 5)]).avgOrderValue, 3);
      expect(jsRound(-2.5), -2);
    });
  });

  group('timingStats', () {
    test('only measures length for sessions that closed', () {
      final s = timingStats([
        _till(),
        _till(openedAt: '2026-09-18T07:00:00Z', closedAt: null, status: 'open'),
      ], _cairo);
      expect(s.openNow, 1);
      expect(s.avgDurationMs, 8 * 3600 * 1000);
    });

    test('ignores a negative span rather than averaging an impossibility', () {
      final s = timingStats([
        _till(),
        _till(
          openedAt: '2026-09-18T09:00:00Z',
          closedAt: '2026-09-18T08:00:00Z',
        ),
      ], _cairo);
      expect(s.avgDurationMs, 8 * 3600 * 1000);
    });

    test('has no average length when nothing has closed', () {
      final s = timingStats([
        _till(closedAt: null, status: 'open'),
      ], _cairo);
      expect(s.avgDurationMs, isNull);
      expect(s.avgClose, isNull);
      expect(s.longest, isNull);
    });
  });

  group("the branch's clock, not the device's", () {
    test('reads the hour of an open in the active timezone', () {
      final at = DateTime.parse('2026-09-18T22:30:00Z');
      expect(minutesOfDay(at, _cairo), 90);
      expect(minutesOfDay(at, 'America/New_York'), 18 * 60 + 30);
    });

    test('buckets a session past midnight into the hours it opened and '
        'closed', () {
      final b = byHour([
        _till(
          openedAt: '2026-09-18T19:10:00Z',
          closedAt: '2026-09-18T23:40:00Z',
        ),
      ], _cairo);
      expect(b[22].opened, 1);
      expect(b[2].closed, 1);
      expect(b.fold<int>(0, (n, h) => n + h.opened + h.closed), 2);
    });

    test('measures a session across midnight as one span', () {
      final s = timingStats([
        _till(
          openedAt: '2026-09-18T20:50:00Z',
          closedAt: '2026-09-18T23:10:00Z',
        ),
      ], _cairo);
      expect(s.avgDurationMs, 140 * 60000);
      expect(s.longest?.openedAt, DateTime.parse('2026-09-18T20:50:00Z'));
    });

    test('keeps a business date on its own day in every zone', () {
      for (final zone in [
        _cairo,
        'America/Los_Angeles',
        'Pacific/Kiritimati',
      ]) {
        expect(
          fmtBusinessDate(DashFormat(timezone: zone), '2026-09-18'),
          '18 Sept 2026',
          reason: zone,
        );
      }
      expect(fmtBusinessDate(const DashFormat(), 'not a date'), '—');
    });
  });

  test('isRangeRefused is the 400 and nothing else', () {
    ApiException http(int status) => ApiException(status: status, message: 'x');
    expect(isRangeRefused(http(400)), isTrue);
    expect(isRangeRefused(http(403)), isFalse);
    expect(isRangeRefused(http(500)), isFalse);
    expect(isRangeRefused(StateError('offline')), isFalse);
    expect(isRangeRefused(null), isFalse);
  });

  test('ranks by net sales, ties in the API\'s order', () {
    final a = _till(sales: 100);
    final b = _till(sales: 300);
    final c = _till(sales: 100);
    expect(rankBySales([a, b, c]), [b, a, c]);
  });
}
