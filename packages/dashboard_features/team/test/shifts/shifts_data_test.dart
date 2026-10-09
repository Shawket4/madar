// The shift form's rules and the grid's arithmetic, as the web computes them
// in the browser (`work-shift-dialog.tsx` `shiftSchema`/`bodyOf`,
// `inputs/time.ts`, `schedule-grid.tsx`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_team/src/shifts/schedule_grid.dart';
import 'package:dashboard_team/src/shifts/shift_form.dart';
import 'package:flutter_test/flutter_test.dart';

String _t(String k) => k;

WorkShift _evening() => WorkShift(
  id: 'w1',
  orgId: 'o',
  branchId: 'b1',
  name: 'Evening',
  startTime: '16:00:00',
  endTime: '00:00:00',
  crossesMidnight: true,
  graceMinutes: 15,
  breakMinutes: 30,
  paidBreak: true,
  overtimeThresholdMinutes: 15,
  overtimeMultiplier: 1.5,
  otDayMultiplier: 1.75,
  otNightMultiplier: 2,
  checkinWindowMinutes: 120,
  isActive: true,
  validDays: const [6, 0, 1, 2, 3, 4, 5],
  dayTimes: [
    DayTime(dayOfWeek: 4, startTime: '16:00:00', endTime: '01:00:00'),
    DayTime(dayOfWeek: 5, startTime: '16:00:00', endTime: '01:00:00'),
  ],
  overPresenceCap: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('TEAM-SHF-022 a new block\'s defaults', () {
    final v = ShiftValues.of(null);
    expect(v.branchId, wholeBusiness);
    expect((v.start, v.end), ('09:00', '17:00'));
    expect((v.grace, v.breakMinutes, v.paidBreak), (15, 0, true));
    expect(
      (v.otThreshold, v.otMultiplier, v.otDay, v.otNight),
      (15, 1.5, null, null),
    );
    expect((v.halfDay, v.checkin, v.isActive), (null, 120, true));
    expect(v.validDays, allDays);
    expect(v.hasDayTimes || v.hasOptionalRates, isFalse);
  });

  test('TEAM-SHF-024 the body: empty rates as null, day times only on valid '
      'days, a whole-business block has no branch', () {
    final v = ShiftValues.of(null)
      ..name = ' Brunch '
      ..validDays = [6, 0, 1];
    v.dayTimes = {
      ...v.dayTimes,
      6: (start: '10:00', end: '15:00'),
      5: (start: '11:00', end: '16:00'), // Friday is not a valid day
    };
    expect(shiftProblems(v, _t), isEmpty);
    final body = shiftBody(v).toJson();
    expect(body['branch_id'], isNull);
    expect(body.containsKey('branch_id'), isTrue);
    expect(body['name'], 'Brunch');
    expect(body['ot_day_multiplier'], isNull);
    expect(body.containsKey('ot_night_multiplier'), isTrue);
    expect(body['half_day_threshold_minutes'], isNull);
    expect(body['valid_days'], [0, 1, 6]);
    expect(body['day_times'], [
      {'day_of_week': 6, 'start_time': '10:00:00', 'end_time': '15:00:00'},
    ]);
    expect((body['start_time'], body['end_time']), ('09:00:00', '17:00:00'));
  });

  test('TEAM-SHF-013/015/016/017/018/020 refuses no days, a half-set day, an '
      'empty shift, a rate of 0; a night crossing midnight is a shift', () {
    ShiftValues ev() => ShiftValues.of(_evening());
    expect(shiftProblems(ev(), _t), isEmpty);
    expect(shiftProblems(ev()..validDays = [], _t), {
      'days': 'staff.errNoDays',
    });
    final half = ev();
    half.dayTimes = {...half.dayTimes, 1: (start: '10:00', end: '')};
    expect(shiftProblems(half, _t), {'day:1': 'staff.errBothTimes'});
    expect(shiftProblems(ev()..end = '16:00', _t), {
      'end': 'staff.errSameTime',
    });
    expect(shiftProblems(ev()..otDay = 0, _t), {'otDay': 'staff.errPositive'});
    expect(
      shiftProblems(
        ev()
          ..start = '18:00'
          ..end = '02:00',
        _t,
      ),
      isEmpty,
    );
    expect(shiftProblems(ev()..name = '  ', _t), {
      'name': 'staff.errShiftName',
    });
    expect(shiftProblems(ev()..grace = -5, _t), {
      'grace': 'staff.errNonNegative',
    });
    expect(shiftProblems(ev()..checkin = 0, _t), {
      'checkin': 'staff.errPositive',
    });
    expect(shiftProblems(ev()..halfDay = 0, _t), {
      'halfDay': 'staff.errPositive',
    });
    // A day off the block's days is not checked.
    final off = ev()..validDays = [6];
    off.dayTimes = {...off.dayTimes, 1: (start: '10:00', end: '')};
    expect(shiftProblems(off, _t), isEmpty);
  });

  test('TEAM-ALL-025 refuses what a field refused, never a stand-in: NaN '
      'numbers and times that are not times', () {
    ShiftValues ev() => ShiftValues.of(_evening());
    expect(shiftProblems(ev()..grace = double.nan, _t), {
      'grace': 'staff.errNumber',
    });
    expect(shiftProblems(ev()..otMultiplier = double.nan, _t), {
      'otMultiplier': 'staff.errNumber',
    });
    expect(shiftProblems(ev()..otDay = double.nan, _t), {
      'otDay': 'staff.errNumber',
    });
    expect(shiftProblems(ev()..start = '9x', _t), {'start': 'staff.errTime'});
    final day = ev();
    day.dayTimes = {...day.dayTimes, 4: (start: '9x', end: '01:00')};
    expect(shiftProblems(day, _t), {'day:4': 'staff.errTime'});
    final same = ev();
    same.dayTimes = {...same.dayTimes, 4: (start: '01:00', end: '01:00')};
    expect(shiftProblems(same, _t), {'day:4': 'staff.errSameTime'});
  });

  test('TEAM-SHF-011 editing seeds from the shift: its own times and rates '
      'open their sections', () {
    final v = ShiftValues.of(_evening());
    expect(v.branchId, 'b1');
    expect((v.start, v.end), ('16:00', '00:00'));
    expect(v.dayTimes[4], (start: '16:00', end: '01:00'));
    expect(v.dayTimes[1], (start: '', end: ''));
    expect(v.hasDayTimes && v.hasOptionalRates, isTrue);
    // Clearing the night rate sends null: back to the branch's rules.
    v.otNight = null;
    final body = shiftBody(v).toJson();
    expect(body['ot_day_multiplier'], 1.75);
    expect(body['ot_night_multiplier'], isNull);
    expect(body['valid_days'], [0, 1, 2, 3, 4, 5, 6]);
  });

  test('TEAM-ALL-025 time arithmetic: span, next day, the "9 to 5" slip', () {
    expect(spanMinutes('22:00', '06:00'), 480);
    expect(spanMinutes('09:00', '17:30'), 510);
    expect(spanMinutes('09:00', '09:00'), 0);
    expect(spanMinutes('9x', '09:00'), isNull);
    expect(endsNextDay('16:00:00', '00:00:00'), isTrue);
    expect(endsNextDay('09:00', '17:00'), isFalse);
    expect(suggestEnd('09:00', '05:00'), '17:00');
    expect(suggestEnd('22:00', '06:00'), isNull);
    expect(jsFigure(1.5), '1.5');
    expect(jsFigure(2.0), '2');
    expect(presetMayRename('', const ['Morning']), isTrue);
    expect(presetMayRename('Morning', const ['Morning']), isTrue);
    expect(presetMayRename('Brunch', const ['Morning']), isFalse);
  });

  group('the standing grid', () {
    ScheduleAssignment a(String id, String emp, int? dow, String from) =>
        ScheduleAssignment(
          id: id,
          orgId: 'o',
          employeeId: emp,
          workShiftId: 'w',
          workShiftName: id,
          dayOfWeek: dow,
          effectiveFrom: from,
          createdAt: DateTime.utc(2026),
        );

    test('TEAM-SHF-029 per slot the newest row wins (the list arrives '
        'newest first)', () {
      final r = rosterOf([
        a('new-sat', 'e1', 6, '2026-10-01'),
        a('all', 'e1', null, '2026-10-01'),
        a('old-sat', 'e1', 6, '2026-09-01'),
        a('old-all', 'e1', null, '2026-09-01'),
      ]);
      expect(r['e1']!.byWeekday[6]!.id, 'new-sat');
      expect(r['e1']!.everyDay!.id, 'all');
      expect(r['e1']!.byWeekday[0], isNull);
    });

    test('TEAM-SHF-030 a weekday offers only blocks that run that day, at '
        'that day\'s times', () {
      final ev = _evening();
      final brunch = WorkShift.fromJson({
        ...ev.toJson(),
        'id': 'w2',
        'name': 'Brunch',
        'start_time': '10:00:00',
        'end_time': '14:00:00',
        'valid_days': [6, 0, 1, 2, 3, 4],
        'day_times': <Object?>[],
      });
      expect(offeredOn([ev, brunch], 5).map((s) => s.name), ['Evening']);
      expect(offeredOn([ev, brunch], null).length, 2);
      expect(timesOn(ev, 5), '16:00–01:00');
      expect(timesOn(ev, 1), '16:00–00:00');
      expect(timesOn(ev, null), '16:00–00:00');
    });
  });
}
