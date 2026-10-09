// The area scaffold's shared pieces: the week and figure helpers, typed
// money, the path-prefix invalidation, the area seed's agreement with
// itself, and the shared mock reads.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show DashFormat, ensureTimeZones;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/shared/export_logo.dart';
import 'package:dashboard_team/src/shared/ladder_pricing.dart';
import 'package:dashboard_team/src/shared/rules_banner.dart';
import 'package:dashboard_team/src/shared/setup_data.dart';
import 'package:dashboard_team/src/shared/staff_query.dart';
import 'package:dashboard_team/src/shared/team_format.dart';
import 'package:dashboard_team/src/shared/team_util.dart';
import 'package:dashboard_team/src/shared/week.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('week (Saturday first, Postgres DOW)', () {
    test('summarizeDays runs and lists', () {
      expect(
        summarizeDays([6, 0, 1, 2, 3], 'en', 'Every day', 'No days'),
        'Sat – Wed',
      );
      expect(summarizeDays([4, 5], 'en', 'Every day', 'No days'), 'Thu, Fri');
      expect(
        summarizeDays([6, 1, 4], 'en', 'Every day', 'No days'),
        'Sat, Mon, Thu',
      );
      expect(
        summarizeDays([0, 1, 2, 3, 4, 5, 6], 'en', 'Every day', 'x'),
        'Every day',
      );
      expect(summarizeDays(const [], 'en', 'x', 'No days'), 'No days');
      expect(summarizeDays([4, 5], 'ar', 'x', 'y'), contains('، '));
    });

    test('week arithmetic on calendar dates', () {
      expect(weekdayOf('2026-10-08'), 4); // a Thursday
      expect(weekStartOf('2026-10-08'), '2026-10-03');
      expect(weekStartOf('2026-10-03'), '2026-10-03');
      expect(weekDays('2026-10-03').last, '2026-10-09');
      expect(addDays('2026-10-31', 1), '2026-11-01');
      expect(weeksFromNow('2026-10-10', '2026-10-08'), 1);
      expect(weeksFromNow('2026-09-26', '2026-10-08'), -1);
    });
  });

  group('figures', () {
    test('fmtHours never uses days', () {
      expect(fmtHours('en', 445), '7h 25m');
      expect(fmtHours('en', 480), '8h');
      expect(fmtHours('en', 45), '45m');
      expect(fmtHours('en', 3360), '56h');
      expect(fmtHours('en', -60), '−1h');
      expect(fmtHours('en', null), '—');
      // Right to left: hours first for an Arabic reader (TEAM-ALL-013).
      expect(fmtHours('ar', 445), '\u20677 س 25 د\u2069');
      expect(fmtHours('ar', -60), '\u2067−1 س\u2069');
    });

    test('fmtMinutes keeps the minus inside the Arabic isolate', () {
      expect(
        fmtMinutes(const DashFormat(lang: 'ar'), 445),
        '\u20677 س 25 د\u2069',
      );
      expect(
        fmtMinutes(const DashFormat(lang: 'ar'), -42),
        '\u2067−42 د\u2069',
      );
      expect(fmtMinutes(const DashFormat(), -42), '−42m');
    });

    test('formatSpan', () {
      expect(formatSpan(480, 'en'), '8 h');
      expect(formatSpan(510, 'en'), '8 h 30 min');
      expect(formatSpan(45, 'en'), '45 min');
      expect(formatSpan(510, 'ar'), '8 س 30 د');
    });

    test('isoDaysFromToday is the zone calendar day', () {
      // 23:30 UTC on 7 Oct is already 8 Oct in Cairo.
      final late = DateTime.utc(2026, 10, 7, 23, 30);
      ensureTimeZones();
      expect(
        isoDaysFromToday(0, timezone: 'Africa/Cairo', now: late),
        '2026-10-08',
      );
      expect(
        isoDaysFromToday(-6, timezone: 'Africa/Cairo', now: late),
        '2026-10-02',
      );
    });
  });

  group('money and refusals', () {
    test('readPounds reads Arabic digits and refuses non-positive', () {
      expect(readPounds('٩٬٠٠٠٫٥٠'), 900050);
      expect(readPounds('1,250.5'), 125050);
      expect(readPounds('0'), isNull);
      expect(readPounds(''), isNull);
      expect(readPounds('abc'), isNull);
      expect(readPounds('-5'), isNull);
    });

    test('rdiv rounds half away from zero', () {
      expect(rdiv(5, 2), 3);
      expect(rdiv(-5, 2), -3);
      expect(rdiv(310000 * 16, 31), 160000);
      expect(rdiv(1, 0), 0);
    });

    test('ladder pricing: one copy for Rules and Set-up (tierPiastres)', () {
      const ex = PayExample.initial; // 12,000 EGP, 30 days, 480 min
      // A minute of pay: 1,200,000 × 15 / (30 × 480) = 1,250.
      expect(rungPiastres('minutes', 15, ex), 1250);
      // A quarter day: 1,200,000 × 0.25 / 30 = 10,000.
      expect(rungPiastres('day_fraction', 0.25, ex), 10000);
      expect(rungPiastres('piastres', 5000, ex), 5000);
      expect(rungPiastres('piastres', -5, ex), 0);
      // Half away from zero: 1 × 1 / (2 × 1) = 0.5 → 1.
      expect(
        rungPiastres(
          'minutes',
          1,
          const PayExample(salary: 1, workingDays: 2, shiftMinutes: 1),
        ),
        1,
      );
      expect(rungPiastres('day_fraction', 1, ex.copyWith(workingDays: 0)), 0);
      expect(rungPiastres('minutes', 1, ex.copyWith(shiftMinutes: 0)), 0);
      expect(rungPiastres('piastres', double.nan, ex), isNaN);
      expect(dayPiastres(ex), 40000);
      expect(dayPiastres(ex, 0.5), 20000);
    });

    test('export logo: the own brand only, trimmed, blank is none', () {
      PublicBrand brand({required bool own, String? logo}) => PublicBrand(
        accentColor: '#000000',
        backgroundColor: '#ffffff',
        customBranding: own,
        foregroundColor: '#000000',
        logoIsMark: false,
        logoUrl: logo,
        name: 'Sabah',
        orgId: 'org',
      );
      expect(teamExportLogo(null), isNull);
      expect(
        teamExportLogo(brand(own: true, logo: ' https://x/l.png ')),
        'https://x/l.png',
      );
      expect(teamExportLogo(brand(own: true, logo: '   ')), isNull);
      expect(teamExportLogo(brand(own: true)), isNull);
      expect(
        teamExportLogo(brand(own: false, logo: 'https://x/l.png')),
        isNull,
      );
    });

    test('stale refusals', () {
      expect(
        isStaleRefusal(
          const ApiException(status: 409, code: 'FLAG_HANDLED', message: 'x'),
        ),
        isTrue,
      );
      expect(
        isStaleRefusal(const ApiException(status: 409, message: 'x')),
        isFalse,
      );
    });
  });

  group('invalidation by path prefix', () {
    test('invalidateStaff is a plain prefix, Refresh is segment-bounded', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      int rev(String p) => c.read(staffRevisionsProvider).revisionOf(p);
      final n = c.read(staffRevisionsProvider.notifier);

      n.refetch();
      expect(rev('/staff/employees'), 1);
      expect(rev('/staff-pool/drinks'), 0);

      n.invalidateStaff();
      expect(rev('/staff/employees'), 2);
      expect(rev('/staff-pool/drinks'), 1);

      n.invalidateEmployees();
      expect(rev('/staff/employees'), 3);
      expect(rev('/staff/work-shifts'), 2);

      n.invalidateAttendance();
      expect(rev('/staff/attendance/settings'), 3);
    });
  });

  group('area seed', () {
    final seed = TeamSeed.instance;

    test('this morning: only the morning shift has records', () {
      expect(seed.todayRecords, isNotEmpty);
      for (final r in seed.todayRecords) {
        expect(r.workShiftName, 'Morning');
        expect(r.checkOutAt, isNull);
        expect(r.checkInAt, isNotNull);
      }
    });

    test('approved leave shows as on leave that day', () {
      final hana = SeedIds.employee('hana');
      final day = seed.attendance.firstWhere(
        (a) => a.employeeId == hana && a.businessDate == seed.hanaLeaveDay,
      );
      expect(day.status, 'on_leave');
      final leave = seed.requests.firstWhere(
        (r) => r.employeeId == hana && r.kind == 'leave',
      );
      expect(leave.status, 'approved');
      expect(leave.onDate, seed.hanaLeaveDay);
    });

    test('nobody works their day off', () {
      for (final a in seed.attendance) {
        if (a.coveredEmployeeId != null) continue;
        expect(seed.works(a.employeeId, a.businessDate), isTrue);
      }
    });

    test('departments count their people', () {
      final total = seed.departments.fold<int>(
        0,
        (n, d) => n + d.employeeCount,
      );
      expect(total, seed.staff.length);
    });

    test('late penalties follow the seeded ladder', () {
      for (final adj in seed.adjustments.where(
        (a) => a.source == 'late_penalty',
      )) {
        final rec = seed.attendance.firstWhere(
          (a) => TeamSeedIds.adjustment('late:${a.id}') == adj.id,
        );
        final salary = seed.staff
            .firstWhere((e) => e.id == rec.employeeId)
            .baseSalaryPiastres!;
        expect(
          adj.valuePiastres,
          TeamSeed.lateDeduction(salary, rec.lateMinutes),
        );
      }
    });
  });

  group('shared mock reads', () {
    late MockDb db;
    MockServer serverFor(Persona p) {
      final s = MockServer(persona: p, clock: db.clock);
      registerCoreMocks(s, db);
      registerTeamMocks(s, db);
      return s;
    }

    setUp(() => db = MockDb.seeded());

    test("today's attendance matches the seed", () async {
      final api = DashboardApi(serverFor(Persona.owner));
      final today = TeamSeed.today;
      final rows = await api.staff.listAttendance(from: today, to: today);
      expect(
        rows.length,
        TeamSeed.instance.todayRecords
            .where((r) => r.orgId == SeedIds.sabahOrg)
            .length,
      );
    });

    test('a branch manager sees only their branch', () async {
      final api = DashboardApi(serverFor(Persona.manager));
      final rows = await api.staff.listAttendance(
        from: '2026-09-24',
        to: TeamSeed.today,
      );
      expect(rows, isNotEmpty);
      expect(rows.map((r) => r.branchId).toSet(), {SeedIds.zamalek});
    });

    test('the limited persona is refused the requests list', () async {
      final api = DashboardApi(serverFor(Persona.limited));
      await expectLater(
        api.staff.listRequests(),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
    });

    test('departments count active people live', () async {
      final api = DashboardApi(serverFor(Persona.owner));
      final deps = await api.staff.listDepartments();
      expect(deps.map((d) => d.name), contains('Bar'));
      expect(deps.every((d) => d.employeeCount > 0), isTrue);
    });
  });

  testWidgets('the rules banner stays hidden while the rules are saved', (
    tester,
  ) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [teamArea],
      path: '/staff/team',
    );
    expect(find.byType(RulesFirstBanner), findsOneWidget);
    expect(find.text(h.t('dawam.rulesFirstTitle')), findsNothing);
  });

  testWidgets('the rules banner asks for the rules when never saved', (
    tester,
  ) async {
    final db = MockDb.seeded();
    for (final s in db['attendance_settings'].rows) {
      s.remove('rules_saved_at');
    }
    final h = await DashHarness.pump(
      tester,
      areas: const [teamArea],
      path: '/staff/team',
      db: db,
    );
    expect(find.text(h.t('dawam.rulesFirstTitle')), findsOneWidget);
    // Every other step is done, so it sends the owner to the rules.
    expect(find.text(h.t('dawam.rulesFirstAction')), findsOneWidget);
    await h.shot('rules-banner');
    await h.tapText(h.t('dawam.rulesFirstAction'));
    expect(h.location.path, '/staff/rules');
  });

  testWidgets('the rules banner fits a phone in Arabic', (tester) async {
    final db = MockDb.seeded();
    for (final s in db['attendance_settings'].rows) {
      s.remove('rules_saved_at');
    }
    final h = await DashHarness.pump(
      tester,
      areas: const [teamArea],
      path: '/staff/schedule',
      db: db,
      size: DashSize.phone,
      locale: 'ar',
      dark: true,
    );
    expect(find.text(h.t('dawam.rulesFirstAction')), findsOneWidget);
    await h.shot('rules-banner');
  });

  testWidgets('the set-up reads come back at once on a remount (webCache)', (
    tester,
  ) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [teamArea],
      path: '/staff/team',
    );
    final reads = [
      setupActiveEmployeesProvider,
      setupWorkShiftsProvider,
      setupAttendanceSettingsProvider,
    ];
    await h.go('/staff/employees');
    h.router.go('/staff/team');
    await tester.pump();
    // The banner's reads were kept, not started again: no skeleton frame.
    for (final r in reads) {
      final v = h.container.read(r);
      expect(v.hasValue && !v.isLoading, isTrue, reason: '$r');
    }
  });
}
