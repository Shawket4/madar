// madar-shared's vectors as the web pins them (src/lib/*_vectors.json, copied by
// tool/sync_web_vectors.py; salary and ladder copied from madar-shared, pinned
// by their .source.json), against the team unit's calls into each rule: the
// rules run in Rust (madar-frb-dashboard's rules), so this checks the wiring.
import 'package:dashboard_core/testing.dart' show sharedVectors;
import 'package:dashboard_team/src/employees/employees_data.dart';
import 'package:dashboard_team/src/rules/rules_form.dart';
import 'package:dashboard_team/src/rules/rules_preview.dart';
import 'package:dashboard_team/src/shared/team_format.dart';
import 'package:dashboard_team/src/shared/week.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

List<Map<String, Object?>> _rows(Object? v) =>
    (v! as List).cast<Map<String, Object?>>();

void main() {
  test('pay period (dawam_vectors periods): firstPay', () {
    final periods = (sharedVectors('dawam')! as Map)['periods'];
    for (final v in _rows(periods)) {
      final day = v['day']! as String;
      final startDay = v['start_day']! as int;
      final why = '$day, start day $startDay';
      expect(firstPay(0, day, startDay)!.to, v['end'], reason: why);
      // Hired on the first day: the whole period, so the whole salary.
      final start = v['start']! as String;
      expect(firstPay(1000, start, startDay), (
        from: start,
        to: v['end'],
        piastres: 1000,
      ), reason: why);
    }
  });

  // A case carrying `client` is one the old Dart copy got wrong (it threw on a
  // zero divisor, kept a negative salary, or came out a piastre short).
  test('salary (salary_vectors rates): ratesFrom', () {
    final cases = _rows((sharedVectors('salary')! as Map)['rates']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      final value = v['value']! as int;
      final basis = (
        workingDays: double.parse(v['working_days']! as String),
        dayMinutes: v['day_minutes']! as int,
      );
      final got = switch (v['typed']) {
        'monthly' => ratesFrom(basis, monthly: value),
        'daily' => ratesFrom(basis, daily: value),
        _ => ratesFrom(basis, hourly: value),
      };
      expect(got, (
        monthly: v['monthly'],
        daily: v['daily'],
        hourly: v['hourly'],
      ), reason: '$v');
    }
  });

  test('salary (salary_vectors first_pay): firstPay', () {
    final cases = _rows((sharedVectors('salary')! as Map)['first_pay']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        firstPay(
          v['monthly']! as int,
          v['hire_date']! as String,
          v['start_day']! as int,
        ),
        (from: v['from'], to: v['to'], piastres: v['piastres']),
        reason: '$v',
      );
    }
  });

  test('salary (salary_vectors prorated): proratedBase', () {
    final cases = _rows((sharedVectors('salary')! as Map)['prorated']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      final window = (v['window']! as List).cast<String>();
      final paid = (v['paid']! as List).cast<String>();
      expect(
        rules.proratedBase(
          history: [
            for (final h in v['history']! as List)
              rules.SalaryFrom(from: h[0] as String, salary: h[1] as int),
          ],
          fallbackSalary: v['fallback']! as int,
          windowStart: window[0],
          windowEnd: window[1],
          paidFrom: paid[0],
          paidTo: paid[1],
        ),
        v['piastres'],
        reason: '${v['note']}',
      );
    }
  });

  test('percent of a salary (percent_vectors): percentOfSalary', () {
    final cases = _rows(sharedVectors('percent'));
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        rules.percentOfSalary(
          salary: v['salary']! as int,
          percent: double.parse(v['percent']! as String),
        ),
        v['value'],
        reason: '$v',
      );
    }
  });

  test(
    'late ladder (ladder_vectors): selectTier, tierPiastres, dayPiastres',
    () {
      final m = sharedVectors('ladder')! as Map;
      final ladder = [
        for (final t in _rows(m['ladder']))
          RuleTier(
            from: (t['from_minutes']! as int).toDouble(),
            to: (t['to_minutes'] as int?)?.toDouble(),
            kind: TierKind.fromWire(t['kind']),
            value: double.parse(t['value']! as String),
          ),
      ];
      final selects = _rows(m['select']);
      expect(selects, isNotEmpty);
      for (final v in selects) {
        final got = selectTier(ladder, v['late_minutes']! as int);
        expect(
          got == null ? null : ladder.indexOf(got),
          v['tier'],
          reason: '$v',
        );
      }
      // An absence case names no day minutes: a day's pay does not read them.
      PayExample ex(Map<String, Object?> v) => PayExample(
        salary: v['salary']! as int,
        workingDays: double.parse(v['working_days']! as String),
        shiftMinutes: v['day_minutes'] as int? ?? 480,
      );
      final deductions = _rows(m['deductions']);
      expect(deductions, isNotEmpty);
      for (final v in deductions) {
        final tier = RuleTier(
          from: 0,
          to: null,
          kind: TierKind.fromWire(v['kind']),
          value: double.parse(v['value']! as String),
        );
        expect(tierPiastres(tier, ex(v)), v['piastres'], reason: '$v');
      }
      final absences = _rows(m['absences']);
      expect(absences, isNotEmpty);
      for (final v in absences) {
        final per = double.parse(v['deduction_days']! as String);
        final days = double.parse(v['days_absent']! as String);
        // The Rules page docks one absence; the rest go to the rule directly.
        final got = days == 1
            ? dayPiastres(ex(v), per)
            : rules.absenceDeductionPiastres(
                salary: v['salary']! as int,
                workingDays: double.parse(v['working_days']! as String),
                daysAbsent: days,
                deductionDays: per,
              );
        expect(got, v['piastres'], reason: '$v');
      }
    },
  );

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
