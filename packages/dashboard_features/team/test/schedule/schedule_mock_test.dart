// The Schedule unit's mock handlers against hand-computed figures and the
// backend's refusals (MadarRust `src/staff/dawam/roster.rs`, `suggest.rs`,
// `holidays.rs`, `src/staff/schedules.rs`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show ensureTimeZones;
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_support.dart';

Matcher refused(int status, [String? code]) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.code, 'code', code),
);

void main() {
  late MockDb db;
  StaffApi api([Persona p = Persona.owner]) {
    final s = MockServer(persona: p, clock: db.clock);
    registerCoreMocks(s, db);
    registerTeamMocks(s, db);
    return DashboardApi(s).staff;
  }

  Future<RosterView> week0([Persona p = Persona.owner]) =>
      api(p).roster(branchId: SeedIds.zamalek, from: week, to: wd(6));

  setUpAll(ensureTimeZones);
  setUp(() => TeamSeed.loadInto(db = MockDb.seeded()));

  test('the roster: Zamalek\'s staff by name, the pattern, the date sets, '
      'this week published', () async {
    final v = await week0();
    final names = [for (final p in v.staff) p.name];
    expect(names, [...names]..sort());
    expect(names, contains('Youssef Samir'));
    expect(v.publishedWeeks, [week]);
    // Youssef's Monday is a split day; Mariam's Friday a day off by date.
    final youssef = [
      for (final s in v.shifts)
        if (s.employeeId == emp('youssef') && s.date == wd(2)) s.shiftName,
    ];
    expect(youssef, unorderedEquals(['Morning', 'Evening']));
    final mariam = v.dateSets!.firstWhere(
      (d) => d.employeeId == emp('mariam') && d.date == wd(6),
    );
    expect(mariam.dayOff, isTrue);
    final laila = v.shifts.firstWhere(
      (s) => s.employeeId == emp('laila') && s.date == wd(4),
    );
    expect(
      (
        laila.startTime,
        laila.endTime,
        laila.crossesMidnight,
        laila.timesEdited,
      ),
      ('16:00:00', '00:00:00', true, true),
    );
    expect(laila.changed, isTrue);
    expect(v.limitsUnconfirmed, isTrue);
    expect(v.openShifts.single.onDate, wd(6));
  });

  test('labour warnings: Youssef\'s 16 h Monday is past 12 h a day and 14 h '
      'of presence, and leaves 8 h of rest before Tuesday\'s 07:00', () async {
    final v = await week0();
    final mine = [
      for (final w in v.warnings)
        if (w.employeeId == emp('youssef'))
          (w.date, w.kind, w.minutes, w.limitMinutes),
    ];
    expect(mine, [
      (wd(2), 'day_hours', 960, 720),
      (wd(2), 'presence', 960, 840),
      (wd(3), 'rest', 480, 660),
    ]);
  });

  test(
    'publish: the week shows published; a later change marks the day',
    () async {
      final staff = api(Persona.manager);
      await staff.publish(
        body: PublishWeek(branchId: SeedIds.zamalek, weekStart: wd(7)),
      );
      final next = await staff.roster(
        branchId: SeedIds.zamalek,
        from: wd(7),
        to: wd(13),
      );
      expect(next.publishedWeeks, [wd(7)]);
      expect(next.shifts.where((s) => s.changed), isEmpty);
      await staff.putDay(
        body: PutDayRequest(
          employeeId: emp('adham'),
          onDate: wd(7),
          shifts: const [],
          branchId: SeedIds.zamalek,
        ),
      );
      final after = await staff.roster(
        branchId: SeedIds.zamalek,
        from: wd(7),
        to: wd(13),
      );
      expect(
        after.dateSets!.any((d) => d.employeeId == emp('adham') && d.dayOff),
        isTrue,
      );
    },
  );

  test('a day that would overlap is refused 409 SHIFTS_OVERLAP', () async {
    final morning = TeamSeedIds.workShift('sabah', 'morning');
    final evening = TeamSeedIds.workShift('sabah', 'evening');
    await expectLater(
      api().putDay(
        body: PutDayRequest(
          employeeId: emp('adham'),
          onDate: wd(0),
          branchId: SeedIds.zamalek,
          shifts: [
            DayBlock(
              workShiftId: morning,
              startTime: '07:00',
              endTime: '16:00',
            ),
            DayBlock(workShiftId: evening),
          ],
        ),
      ),
      refused(409, 'SHIFTS_OVERLAP'),
    );
  });

  test(
    'move onto someone already on that block: 409 ALREADY_ROSTERED',
    () async {
      final morning = TeamSeedIds.workShift('sabah', 'morning');
      await expectLater(
        api().moveShift(
          body: MoveShiftRequest(
            employeeId: emp('adham'),
            toEmployeeId: emp('karim'),
            onDate: wd(0),
            workShiftId: morning,
          ),
        ),
        refused(409, 'ALREADY_ROSTERED'),
      );
    },
  );

  test(
    'a move answers both days; the receiver\'s 16 h and short rest warn',
    () async {
      final morning = TeamSeedIds.workShift('sabah', 'morning');
      final moved = await api().moveShift(
        body: MoveShiftRequest(
          employeeId: emp('adham'),
          toEmployeeId: emp('hassan'),
          onDate: wd(0),
          workShiftId: morning,
        ),
      );
      expect(moved.from.shifts, isEmpty);
      expect(moved.to.shifts, hasLength(2));
      // Hassan worked the Friday evening until 23:00: 8 h of rest.
      expect(
        [for (final w in moved.to.warnings) w.kind],
        ['day_hours', 'presence', 'rest'],
      );
      final back = await api().resetDay(
        employeeId: emp('hassan'),
        onDate: wd(0),
        branchId: SeedIds.zamalek,
      );
      expect(back.followsPattern, isTrue);
      expect(back.shifts.single.name, 'Evening');
    },
  );

  test(
    'suggestions: decided ones leave the list; a stale one is refused',
    () async {
      final staff = api();
      final list = await staff.suggestions(
        branchId: SeedIds.zamalek,
        weekStart: week,
      );
      final pattern = list.firstWhere((g) => g.id.startsWith('pattern|'));
      expect(pattern.reasonKey, 'staff.sg_pattern_off');
      for (final g in list.where((g) => !g.id.startsWith('pattern|'))) {
        expect(g.date.compareTo(today) >= 0, isTrue, reason: 'from today on');
        expect(g.reasonKey, 'staff.sg_gap');
      }
      await staff.decideSuggestion(
        body: DecideSuggestion(
          branchId: SeedIds.zamalek,
          id: pattern.id,
          accept: false,
        ),
      );
      final after = await staff.suggestions(
        branchId: SeedIds.zamalek,
        weekStart: week,
      );
      expect(after.any((g) => g.id == pattern.id), isFalse);
      await expectLater(
        staff.decideSuggestion(
          body: DecideSuggestion(
            branchId: SeedIds.zamalek,
            id: pattern.id,
            accept: true,
          ),
        ),
        refused(409, 'SUGGESTION_STALE'),
      );
    },
  );

  test(
    'suggestions need hr.schedule.edit; the roster hr.schedule.read',
    () async {
      await expectLater(
        api(
          Persona.limited,
        ).suggestions(branchId: SeedIds.maadi, weekStart: week),
        refused(403),
      );
      await expectLater(
        api(
          Persona.limited,
        ).roster(branchId: SeedIds.maadi, from: week, to: wd(6)),
        refused(403),
      );
      await expectLater(
        api(
          Persona.manager,
        ).roster(branchId: SeedIds.maadi, from: week, to: wd(6)),
        refused(403),
      );
    },
  );

  test('a range over 62 days is refused 400 RANGE_TOO_WIDE', () async {
    await expectLater(
      api().roster(branchId: SeedIds.zamalek, from: week, to: '2026-12-31'),
      refused(400, 'RANGE_TOO_WIDE'),
    );
  });

  test('holidays: only the owner decides (403 OWNER_ONLY for a manager); '
      'the roster then carries the decision', () async {
    await expectLater(
      api(Persona.manager).decideHoliday(
        date: '2026-10-06',
        body: const HolidayDecision(decision: 'holiday'),
      ),
      refused(403, 'OWNER_ONLY'),
    );
    await api().decideHoliday(
      date: '2026-10-06',
      body: const HolidayDecision(decision: 'dismissed'),
    );
    final v = await week0();
    expect(v.holidays.single.decision, 'dismissed');
  });

  test('open shifts: one already started is refused; taking back twice is '
      'refused', () async {
    final evening = TeamSeedIds.workShift('sabah', 'evening');
    final morning = TeamSeedIds.workShift('sabah', 'morning');
    await expectLater(
      api().postOpenShift(
        body: PostOpenShift(
          branchId: SeedIds.zamalek,
          onDate: today,
          workShiftId: morning,
        ),
      ),
      refused(409, 'SHIFT_STARTED'),
    );
    final posted = await api().postOpenShift(
      body: PostOpenShift(
        branchId: SeedIds.zamalek,
        onDate: today,
        workShiftId: evening,
      ),
    );
    expect(posted.status, 'open');
    await api().cancelOpenShift(id: posted.id);
    await expectLater(
      api().cancelOpenShift(id: posted.id),
      refused(409, 'OPEN_SHIFT_CLOSED'),
    );
  });

  test('coverage: POS-derived until typed; the whole list replaces it; a '
      'bad band is refused', () async {
    final staff = api();
    final before = await staff.getCoverage(branchId: SeedIds.zamalek);
    expect(before.source, 'pos');
    expect(before.ordersPerStaff, 25);
    await staff.putCoverage(
      body: PutCoverage(
        branchId: SeedIds.zamalek,
        needs: const [
          CoverageNeed(
            dayOfWeek: 6,
            bandStart: '09:00:00',
            bandEnd: '11:00:00',
            staff: 3,
          ),
        ],
      ),
    );
    final after = await staff.getCoverage(branchId: SeedIds.zamalek);
    expect(after.source, 'grid');
    expect(after.needs.single.staff, 3);
    await expectLater(
      staff.putCoverage(
        body: PutCoverage(
          branchId: SeedIds.zamalek,
          needs: const [
            CoverageNeed(
              dayOfWeek: 6,
              bandStart: '11:00:00',
              bandEnd: '09:00:00',
              staff: 3,
            ),
          ],
        ),
      ),
      refused(400),
    );
  });

  test('fairness: the owner\'s; 7 of 14 decisions accepted in four weeks; '
      'Zamalek\'s learning paused', () async {
    final f = await api().fairness(month: '2026-10-01');
    expect((f.accepted4w, f.decided4w, f.learningFrozen), (7, 14, false));
    final z = f.branches.firstWhere((b) => b.branchId == SeedIds.zamalek);
    expect((z.accepted, z.decided, z.learningFrozen), (3, 10, true));
    final audits = await api().fairnessAudits();
    expect(audits, hasLength(4));
    expect(audits.where((a) => a.flagged), hasLength(2));
    await expectLater(
      api(Persona.manager).fairness(month: '2026-10-01'),
      refused(403),
    );
    await expectLater(api().fairness(month: '2026-10-02'), refused(400));
  });

  test('preferences: saved by a manager, logged newest first; a long note is '
      'refused', () async {
    final staff = api();
    await staff.putEmployeePreferences(
      id: emp('adham'),
      body: const Preferences(
        prefTime: 'morning',
        cantWorkDays: [5, 0, 5],
        note: 'Classes on Sundays',
      ),
    );
    final log = await staff.preferenceLog(id: emp('adham'));
    expect(log.first.source, 'manager');
    expect(log.first.cantWorkDays, [0, 5]);
    final v = await week0();
    final adham = v.staff.firstWhere((p) => p.employeeId == emp('adham'));
    expect((adham.prefTime, adham.prefsSetBy), ('morning', 'manager'));
    await expectLater(
      staff.putEmployeePreferences(
        id: emp('adham'),
        body: Preferences(
          prefTime: null,
          cantWorkDays: const [],
          note: 'x' * 301,
        ),
      ),
      refused(400),
    );
    final hassan = await staff.preferenceLog(id: emp('hassan'));
    expect([for (final e in hassan) e.source], ['manager', 'employee']);
  });
}
