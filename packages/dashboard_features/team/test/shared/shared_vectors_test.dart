// madar-shared's vectors as the web pins them (src/lib/*_vectors.json, copied by
// tool/sync_web_vectors.py), against the team unit's calls into each rule: the
// rules run in Rust (madar-frb-dashboard's rules), so this checks the wiring.
import 'package:dashboard_core/testing.dart' show sharedVectors;
import 'package:dashboard_team/src/employees/employees_data.dart';
import 'package:dashboard_team/src/shared/team_format.dart';
import 'package:dashboard_team/src/shared/week.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, Object?>> _rows(Object? v) =>
    (v! as List).cast<Map<String, Object?>>();

void main() {
  test('pay period (dawam_vectors periods): firstPay', () {
    final periods = (sharedVectors('dawam')! as Map)['periods'];
    for (final v in _rows(periods)) {
      final day = v['day']! as String;
      final startDay = v['start_day']! as int;
      final why = '$day, start day $startDay';
      expect(firstPay(0, day, startDay).to, v['end'], reason: why);
      // Hired on the first day: the whole period, so the whole salary.
      final start = v['start']! as String;
      expect(firstPay(1000, start, startDay), (
        from: start,
        to: v['end'],
        piastres: 1000,
      ), reason: why);
    }
  });

  test('roster week (week_vectors): weekStartOf, weekdayOf', () {
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    for (final v in _rows(sharedVectors('week'))) {
      final date = v['date']! as String;
      expect(weekStartOf(date), v['week_start'], reason: date);
      expect(names[weekdayOf(date)], v['weekday'], reason: date);
    }
  });

  test('business date (business_date_vectors): isoDaysFromToday(0)', () {
    for (final v in _rows(sharedVectors('business_date'))) {
      final at = v['at']! as String;
      expect(
        isoDaysFromToday(
          0,
          timezone: v['tz']! as String,
          now: DateTime.parse(at),
        ),
        v['business_date'],
        reason: '${v['tz']} $at',
      );
    }
  });
}
