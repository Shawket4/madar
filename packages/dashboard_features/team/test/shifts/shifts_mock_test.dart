// The Work shifts unit's mock handlers against hand-computed figures and the
// backend's refusals (MadarRust `src/staff/schedules.rs`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shifts_support.dart';

Matcher refused(int status, [String? code]) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.code, 'code', code),
);

UpsertWorkShiftRequest block(
  String name,
  String start,
  String end, {
  String? branchId,
  int? grace,
  List<int>? days,
  List<DayTime>? dayTimes,
}) => UpsertWorkShiftRequest(
  branchId: branchId,
  name: name,
  startTime: start,
  endTime: end,
  graceMinutes: grace,
  validDays: days,
  dayTimes: dayTimes,
);

void main() {
  late MockDb db;
  StaffApi api([Persona p = Persona.owner]) {
    final s = MockServer(persona: p, clock: db.clock);
    registerCoreMocks(s, db);
    registerTeamMocks(s, db);
    return DashboardApi(s).staff;
  }

  setUp(() {
    db = MockDb.seeded();
    TeamSeed.loadInto(db);
    addDemoShifts(db);
  });

  group('GET /staff/work-shifts', () {
    test('by start time then name; the cap and midnight worked out per '
        'read (cap 14 h)', () async {
      final rows = await api().listWorkShifts();
      expect([for (final w in rows) w.name], [
        'Morning', // 07:00
        'Brunch', // 10:00
        'Evening', // 15:00
        'Late evening', // 16:00
        'Maadi late', // 18:00
        'Old night', // 18:00
      ]);
      WorkShift named(String n) => rows.firstWhere((w) => w.name == n);
      // 18:00 → 09:00 is 15 h, past the 14 h cap; Thursday's own 9 h is not.
      expect(named('Old night').overPresenceCap, isTrue);
      expect(named('Late evening').overPresenceCap, isFalse);
      expect(named('Late evening').crossesMidnight, isTrue);
      expect(named('Morning').crossesMidnight, isFalse);
      expect([for (final d in named('Late evening').dayTimes!) d.dayOfWeek], [
        4,
        5,
      ]);
    });

    test('a branch manager sees the business\'s blocks and their own '
        'branch\'s, not another branch\'s', () async {
      final names = [
        for (final w in await api(Persona.manager).listWorkShifts()) w.name,
      ];
      expect(names, containsAll(['Morning', 'Brunch', 'Late evening']));
      expect(names, isNot(contains('Maadi late')));
    });
  });

  group('POST/PATCH /staff/work-shifts', () {
    test('a create shows in the next list, its defaults filled', () async {
      final made = await api().createWorkShift(
        body: block('Dawn', '05:00:00', '13:00:00', branchId: SeedIds.maadi),
      );
      expect(made.graceMinutes, 15);
      expect(made.checkinWindowMinutes, 120);
      expect(made.validDays, [0, 1, 2, 3, 4, 5, 6]);
      final list = await api().listWorkShifts();
      expect(list.first.id, made.id);
    });

    test('the backend\'s refusals', () async {
      expect(
        api().createWorkShift(body: block('X', '09:00:00', '09:00:00')),
        refused(400, 'SHIFT_EMPTY'),
      );
      expect(
        api().createWorkShift(
          body: block('X', '09:00:00', '17:00:00', grace: -1),
        ),
        refused(400, 'SHIFT_SETTING_INVALID'),
      );
      expect(
        api().createWorkShift(
          body: block('X', '09:00:00', '17:00:00', days: const []),
        ),
        refused(400, 'SHIFT_DAYS_REQUIRED'),
      );
      expect(
        api().createWorkShift(
          body: block(
            'X',
            '09:00:00',
            '17:00:00',
            days: const [1],
            dayTimes: [
              DayTime(dayOfWeek: 2, startTime: '10:00:00', endTime: '18:00:00'),
            ],
          ),
        ),
        refused(400, 'SHIFT_DAY_TIMES_OFF_DAY'),
      );
    });

    test('a business-wide block needs the right at every branch', () async {
      expect(
        api(Persona.manager).createWorkShift(
          body: block('X', '09:00:00', '17:00:00'),
        ),
        refused(403),
      );
    });

    test('taking away a weekday someone is rostered on is refused, naming '
        'the block', () async {
      final morning = sabahShift('morning');
      final onSaturday = db[TeamTables.assignments].where(
        (a) => a['work_shift_id'] == morning && a['day_of_week'] == 6,
      );
      expect(onSaturday, isNotEmpty);
      await expectLater(
        api().updateWorkShift(
          id: morning,
          body: block(
            'Morning',
            '07:00:00',
            '15:00:00',
            days: const [0, 1, 2, 3, 4, 5],
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'SHIFT_DAYS_IN_USE')
              .having((e) => e.status, 'status', 409),
        ),
      );
    });
  });

  group('DELETE /staff/work-shifts/{id}', () {
    test('a block on the roster is kept; free, it goes', () async {
      final morning = sabahShift('morning');
      expect(
        api().deleteWorkShift(id: morning),
        refused(409, 'SHIFT_IN_USE'),
      );
      noRoster(db);
      await api().deleteWorkShift(id: morning);
      final ids = [for (final w in await api().listWorkShifts()) w.id];
      expect(ids, isNot(contains(morning)));
    });
  });

  group('/staff/schedules', () {
    setUp(() => noRoster(db));

    CreateAssignmentRequest row(String shift, int? dow) =>
        CreateAssignmentRequest(
          employeeId: emp('karim'),
          workShiftId: shift,
          dayOfWeek: dow,
          explicitNulls: const {'day_of_week'},
        );

    test('a create shows in the whole org\'s list; a delete removes it', () async {
      final made = await api().createAssignment(body: row(eveningZ, null));
      expect(made.dayOfWeek, isNull);
      expect(made.workShiftName, 'Late evening');
      final all = await api().listAssignments();
      expect([for (final a in all) a.id], [made.id]);
      await api().deleteAssignment(id: made.id);
      expect(await api().listAssignments(), isEmpty);
    });

    test('a block on a day it does not run, or another branch\'s, is '
        'refused', () async {
      expect(
        api().createAssignment(body: row(brunch, 5)),
        refused(400, 'SHIFT_NOT_ON_DAY'),
      );
      expect(
        api().createAssignment(body: row(maadiLate, 1)),
        refused(400, 'SHIFT_OTHER_BRANCH'),
      );
    });

    test('a night running into the next day\'s block is refused, naming '
        'both', () async {
      // Thursday's own Late evening ends 01:00 Friday; a Zamalek block at
      // 00:30 on Friday starts before it ends.
      final dawn = await api().createWorkShift(
        body: block(
          'Dawn',
          '00:30:00',
          '08:00:00',
          branchId: SeedIds.zamalek,
        ),
      );
      await api().createAssignment(body: row(eveningZ, 4));
      await expectLater(
        api().createAssignment(body: row(dawn.id, 5)),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'SHIFTS_OVERLAP')
              .having(
                (e) => (e.details! as Map)['vars'],
                'vars',
                containsPair('a', 'Late evening'),
              ),
        ),
      );
    });
  });
}
