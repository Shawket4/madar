// The kit's date rules over madar-shared's vectors (copied by
// tool/sync_web_vectors.py into dashboard_core/test/vectors/; the kit cannot
// import dashboard_core, so it reads the file itself): the pay period
// (madar-dawam `pay::period_window`, the web's quickRange "this_period") and
// the Saturday week start (madar-time, quickRange "this_week").
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

Object? _vectors(String name) => json.decode(
  File('../dashboard_core/test/vectors/${name}_vectors.json').readAsStringSync(),
);

void main() {
  test('dashQuickRange thisPeriod: dawam period vectors', () {
    final periods = ((_vectors('dawam')! as Map)['periods']! as List)
        .cast<Map<String, Object?>>();
    expect(periods, isNotEmpty);
    for (final v in periods) {
      final r = dashQuickRange(
        DashQuickRange.thisPeriod,
        today: dashParseYmd(v['day']! as String)!,
        periodStartDay: v['start_day']! as int,
      );
      expect(
        (dashYmd(r.from), dashYmd(r.to)),
        (v['start'], v['end']),
        reason: '${v['day']}, start day ${v['start_day']}',
      );
    }
  });

  test('dashQuickRange thisWeek and dashDaysIntoWeek: week vectors', () {
    final weeks = (_vectors('week')! as List).cast<Map<String, Object?>>();
    expect(weeks, isNotEmpty);
    for (final v in weeks) {
      final day = dashParseYmd(v['date']! as String)!;
      final r = dashQuickRange(DashQuickRange.thisWeek, today: day);
      expect(dashYmd(r.from), v['week_start'], reason: '${v['date']}');
      final into = DateTime.parse(v['date']! as String)
          .difference(DateTime.parse(v['week_start']! as String))
          .inDays;
      expect(dashDaysIntoWeek(day), into, reason: '${v['date']}');
    }
    // Across a spring-forward (Beirut, Sun 2026-03-29): run with TZ=Asia/Beirut.
    final r = dashQuickRange(
      DashQuickRange.thisWeek,
      today: DateTime(2026, 4, 1),
    );
    expect((dashYmd(r.from), dashYmd(r.to)), ('2026-03-28', '2026-04-03'));
  });
}
