// What the Schedule computes in the browser (`schedule_data.dart`): the
// clash checks said before saving, the coverage grid both ways, the
// holidays list, the fairness month and the Saturday-first week.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_team/src/schedule/schedule_data.dart';
import 'package:dashboard_team/src/shared/week.dart';
import 'package:flutter_test/flutter_test.dart';

WorkShiftBrief _block({
  List<int> days = const [0, 1, 2, 3, 4, 5, 6],
  List<DayTime> dayTimes = const [],
}) => WorkShiftBrief(
  id: 'w1',
  name: 'Morning',
  startTime: '07:00:00',
  endTime: '15:00:00',
  crossesMidnight: false,
  checkinWindowMinutes: 60,
  graceMinutes: 10,
  validDays: days,
  dayTimes: dayTimes,
);

HolidayView _holiday(String date) =>
    HolidayView(onDate: date, nameEn: date, nameAr: date);

void main() {
  test('TEAM-ALL-011 the week runs Saturday to Friday, DOW on the wire', () {
    expect(weekStartOf('2026-10-08'), '2026-10-03');
    expect(weekStartOf('2026-10-03'), '2026-10-03');
    expect(weekStartOf('2026-10-02'), '2026-09-26');
    expect(weekdayOf('2026-10-03'), 6);
    expect(weekdayOf('2026-10-09'), 5);
    expect(weekDays('2026-10-03').last, '2026-10-09');
    expect(coverageDayOrder, [6, 0, 1, 2, 3, 4, 5]);
    expect(weeksFromNow('2026-10-17', '2026-10-08'), 2);
    expect(weeksFromNow('2026-09-26', '2026-10-08'), -1);
  });

  test('TEAM-SCH-043/046 clashes: overlaps refused, touching ends are not, '
      'a night runs past midnight', () {
    final morning = timedOf('Morning', '07:00:00', '15:00');
    final evening = timedOf('Evening', '15:00', '23:00');
    final night = timedOf('Night', '22:00', '06:00');
    expect(clashesWith([morning], evening), isEmpty);
    expect(clashesWith([evening], night).single.name, 'Evening');
    expect(clashesWith([morning, evening], timedOf('', '14:00', '16:00')), [
      morning,
      evening,
    ]);
    expect(spanOf('22:00', '06:00'), (1320, 1800));
    expect(toMinutes('9:30'), 570);
    expect(toMinutes('nope'), isNull);
  });

  test('TEAM-SCH-046 a block runs on its valid days, at that day\'s times', () {
    final b = _block(
      days: const [5, 6],
      dayTimes: const [
        DayTime(dayOfWeek: 5, startTime: '13:00:00', endTime: '21:00:00'),
      ],
    );
    expect(blocksOn([b], 5), [b]);
    expect(blocksOn([b], 1), isEmpty);
    expect(blockTimesOn(b, 5), (start: '13:00', end: '21:00'));
    expect(blockTimesOn(b, 6), (start: '07:00', end: '15:00'));
  });

  test('TEAM-SCH-057/058 the coverage grid both ways: equal runs merge, '
      'department needs stay off the grid, a day ends 23:59:59', () {
    const needs = [
      CoverageNeed(
        dayOfWeek: 6,
        bandStart: '08:00:00',
        bandEnd: '10:30:00',
        staff: 2,
      ),
      CoverageNeed(
        dayOfWeek: 6,
        bandStart: '22:00:00',
        bandEnd: '23:59:59',
        staff: 1,
      ),
      CoverageNeed(
        dayOfWeek: 0,
        bandStart: '09:00:00',
        bandEnd: '10:00:00',
        staff: 4,
        departmentId: 'kitchen',
      ),
    ];
    final g = toGrid(needs);
    // A partial hour rounds up: 08, 09 and 10.
    expect(g, {'6|8': 2, '6|9': 2, '6|10': 2, '6|22': 1, '6|23': 1});
    final back = fromGrid(g);
    expect(
      [
        for (final n in back)
          '${n.dayOfWeek} ${n.bandStart}-${n.bandEnd} ${n.staff}',
      ],
      ['6 08:00:00-11:00:00 2', '6 22:00:00-23:59:59 1'],
    );
    expect(back.first.toJson()['department_id'], isNull);
    expect(back.first.toJson().containsKey('department_id'), isTrue);
    expect(coverageHours(['6|8']).first, 6);
    expect(coverageHours(['1|4']).first, 4);
    expect(coverageHours(const []).last, 23);
    expect(readCoverageCell('3'), 3);
    expect(readCoverageCell('0'), isNull);
    expect(readCoverageCell(''), isNull);
    expect(readCoverageCell('900'), 200);
    expect(readCoverageCell('x'), isNull);
  });

  test('TEAM-SCH-033 holidays: the next 45 days and the week\'s, one per '
      'date, sorted', () {
    final merged = mergeHolidays(
      [_holiday('2026-10-20'), _holiday('2026-10-06')],
      [_holiday('2026-10-06'), _holiday('2026-12-25')],
    );
    expect(
      [for (final h in merged) h.onDate],
      ['2026-10-06', '2026-10-20', '2026-12-25'],
    );
    expect(mergeHolidays(null, null), isEmpty);
  });

  test('TEAM-SCH-073 the fairness month is the viewed Saturday\'s month', () {
    expect(monthOf('2026-10-31'), '2026-10-01');
    expect(monthOf('2026-09-26'), '2026-09-01');
  });
}
