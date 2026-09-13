import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/format.dart';

void main() {
  group('fmtAxisDate reads the branch wall-clock off the bucket', () {
    test('an hourly bucket is its own hour, whatever the device zone', () {
      // 23:30 UTC Sep 12 buckets as 02:00 on Sep 13 in Cairo (UTC+3).
      expect(
        fmtAxisDate('2026-09-13T02:00:00', hourly: true, locale: 'en'),
        '2',
      );
      expect(
        fmtAxisDate('2026-09-13T02:00:00', hourly: false, locale: 'en'),
        '13/9',
      );
    });

    test('an offset on the stamp never shifts the figures', () {
      expect(
        fmtAxisDate('2026-09-13T02:00:00+03:00', hourly: true, locale: 'en'),
        '2',
      );
      expect(
        fmtAxisDate('2026-09-13T02:00:00Z', hourly: false, locale: 'en'),
        '13/9',
      );
    });

    test('garbage falls back to the raw string', () {
      expect(fmtAxisDate('abc', hourly: true, locale: 'en'), 'abc');
    });
  });
}
