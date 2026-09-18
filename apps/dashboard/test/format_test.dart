import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/format.dart';

void main() {
  group('fmtAxisDate reads the branch wall-clock off the bucket', () {
    test('an hourly bucket is its own hour, whatever the device zone', () {
      // 23:30 UTC Sep 12 buckets as 02:00 on Sep 13 in Cairo (UTC+3).
      expect(
        fmtAxisDate('2026-09-13T02:00:00', hourly: true, locale: 'en'),
        '2 AM',
      );
      expect(
        fmtAxisDate('2026-09-13T02:00:00', hourly: false, locale: 'en'),
        '13/9',
      );
    });

    test('an offset on the stamp never shifts the figures', () {
      expect(
        fmtAxisDate('2026-09-13T02:00:00+03:00', hourly: true, locale: 'en'),
        '2 AM',
      );
      expect(
        fmtAxisDate('2026-09-13T02:00:00Z', hourly: false, locale: 'en'),
        '13/9',
      );
    });

    test('an hour is 12-hour, noon and midnight included, Arabic too', () {
      expect(fmtAxisDate('2026-09-13T00:00:00', hourly: true, locale: 'en'), '12 AM');
      expect(fmtAxisDate('2026-09-13T12:00:00', hourly: true, locale: 'en'), '12 PM');
      expect(fmtAxisDate('2026-09-13T14:00:00', hourly: true, locale: 'en'), '2 PM');
      expect(fmtAxisDate('2026-09-13T14:00:00', hourly: true, locale: 'ar'), '2 م');
      expect(fmtAxisDate('2026-09-13T09:00:00', hourly: true, locale: 'ar'), '9 ص');
    });

    test('garbage falls back to the raw string', () {
      expect(fmtAxisDate('abc', hourly: true, locale: 'en'), 'abc');
    });
  });
}
