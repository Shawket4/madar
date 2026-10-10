// The Team board's mock handlers against hand-computed figures and the
// backend's refusals (MadarRust `team_presence`, `list_flags`,
// `resolve_flag`, `punch_for`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show ensureTimeZones;
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/team_board/team_board_data.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher refused(int status, [String? code]) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.code, 'code', code),
);

String emp(String key) => SeedIds.employee(key);

void main() {
  late MockDb db;
  StaffApi api([Persona p = Persona.owner]) {
    final s = MockServer(persona: p, clock: db.clock);
    registerCoreMocks(s, db);
    registerTeamMocks(s, db);
    return DashboardApi(s).staff;
  }

  setUpAll(ensureTimeZones);
  setUp(() => TeamSeed.loadInto(db = MockDb.seeded()));

  group('GET /staff/team/presence', () {
    test('at 10:00 the morning has started: 5 in, 1 late, 2 absent; the '
        'evening is off until it opens at 14:00', () async {
      final p = await api().teamPresence();
      expect(p.businessDate, '2026-10-08');
      expect((p.present, p.late_, p.absent, p.onLeave), (5, 1, 2, 0));
      final byName = {for (final r in p.rows) r.employeeName: r};
      expect(byName['Adham Reda']!.state, 'late');
      expect(byName['Adham Reda']!.lateMinutes, 33);
      expect(byName['Tarek Saber']!.state, 'absent');
      final ali = byName['Ali Hassan']!;
      expect(ali.state, 'off');
      expect(ali.scheduledMinutes, 480);
      // Evening 15:00 Cairo − the 60-minute window = 11:00 UTC.
      expect(ali.punchOpensAt, DateTime.utc(2026, 10, 8, 11));
      // The owner is on nobody's roster.
      expect(byName['Nour El-Sayed']!.scheduledMinutes, 0);
      expect(
        p.rows.map((r) => r.employeeName.toLowerCase()).toList(),
        [...p.rows.map((r) => r.employeeName.toLowerCase())]..sort(),
      );
      expect(
        p.plannedMinutes,
        p.rows.fold(0, (a, r) => a + r.scheduledMinutes),
      );
    });

    test('a branch manager sees their branch only; a branch asked for '
        'narrows the owner too', () async {
      final mine = await api(Persona.manager).teamPresence();
      expect(mine.rows.map((r) => r.branchName).toSet(), {'Zamalek'});
      expect((mine.present, mine.late_, mine.absent), (1, 1, 0));
      final z = await api().teamPresence(branchId: SeedIds.zamalek);
      expect(z.rows.length, mine.rows.length);
      expect(
        () => api(Persona.manager).teamPresence(branchId: SeedIds.maadi),
        refused(403),
      );
    });

    test('an approved leave covering today reads on leave', () async {
      db[TeamTables.requests].put({
        'id': 'leave-ali',
        'employee_id': emp('ali'),
        'kind': 'leave',
        'status': 'approved',
        'on_date': '2026-10-07',
        'end_date': '2026-10-09',
      });
      final p = await api().teamPresence();
      final ali = p.rows.firstWhere((r) => r.employeeName == 'Ali Hassan');
      expect(ali.state, 'on_leave');
      expect(p.onLeave, 1);
    });

    test('refused without attendance rights', () {
      expect(() => api(Persona.limited).teamPresence(), refused(403));
    });
  });

  group('GET /staff/flags', () {
    test('open flags, newest first; all=true adds the handled', () async {
      final open = await api().listAttendanceFlags();
      expect(open.map((f) => f.kind), ['left_mid_shift', 'new_phone']);
      final every = await api().listAttendanceFlags(all: true);
      expect(every, hasLength(3));
      expect(
        (await api(
          Persona.manager,
        ).listAttendanceFlags()).map((f) => f.employeeName),
        ['Karim Adel'],
      );
    });
  });

  group('PATCH /staff/flags/{id}', () {
    final left = TeamSeedIds.flag('left-mid-shift');

    test(
      'an unpaid excuse writes the suggested deduction as a pay line',
      () async {
        final f = await api().resolveFlag(
          id: left,
          body: const ResolveFlag(action: 'excuse_unpaid'),
        );
        expect(f.resolution, 'excused_unpaid');
        expect(f.deductionStatus, 'approved');
        final line = db[TeamTables.adjustments].find(f.deductionId!)!;
        expect(line['value_piastres'], 3606);
        expect(line['kind'], 'deduction');
        expect(line['reason'], 'Unpaid excuse');
      },
    );

    test(
      'a manager\'s deduction above 1,000 EGP waits for the owner',
      () async {
        final id = TeamSeedIds.flag('adham');
        db[TeamTables.flags].put({
          'id': id,
          'employee_id': emp('adham'),
          'employee_name': 'Adham Reda',
          'branch_id': SeedIds.zamalek,
          'kind': 'left_mid_shift',
          'minutes_away': 30,
          'detected_at': '2026-10-08T06:00:00.000Z',
          'suggested_deduction_piastres': 4000,
        });
        final f = await api(Persona.manager).resolveFlag(
          id: id,
          body: const ResolveFlag(action: 'deduct', amountPiastres: 150000),
        );
        expect(f.deductionStatus, 'pending');
        expect(
          db[TeamTables.adjustments].find(f.deductionId!)!['reason'],
          'Left mid-shift',
        );
      },
    );

    test('the backend\'s refusals', () async {
      final hana = TeamSeedIds.flag('tracking-off');
      expect(
        () => api().resolveFlag(
          id: hana,
          body: const ResolveFlag(action: 'ignore'),
        ),
        refused(404, 'FLAG_HANDLED'),
      );
      expect(
        () => api(Persona.manager).resolveFlag(
          id: left,
          body: const ResolveFlag(action: 'ignore'),
        ),
        refused(403, 'OWN_DECISION'),
      );
      expect(
        () => api().resolveFlag(
          id: left,
          body: const ResolveFlag(action: 'deduct'),
        ),
        refused(400, 'AMOUNT_REQUIRED'),
      );
      expect(
        () => api(Persona.limited).resolveFlag(
          id: left,
          body: const ResolveFlag(action: 'ignore'),
        ),
        refused(403),
      );
      db[TeamTables.flags].put({
        'id': 'cover',
        'employee_id': emp('ziad'),
        'employee_name': 'Ziad Amr',
        'branch_id': SeedIds.maadi,
        'kind': 'cover',
        'minutes_away': 0,
        'detected_at': '2026-10-08T06:00:00.000Z',
        'suggested_deduction_piastres': 0,
      });
      expect(
        () => api().resolveFlag(
          id: 'cover',
          body: const ResolveFlag(action: 'ignore'),
        ),
        refused(400, 'FLAG_COVER_CONFIRM_OR_REJECT'),
      );
    });
  });

  group('POST /staff/attendance/punch', () {
    test('punches the absent in (late past the grace), then out', () async {
      final a = await api().punchFor(
        body: PunchFor(employeeId: emp('tarek'), reason: 'Phone died'),
      );
      expect(a.checkInMethod, 'manager');
      expect(a.lateMinutes, 180);
      expect(a.status, 'late');
      final b = await api().punchFor(
        body: PunchFor(employeeId: emp('tarek'), reason: 'Phone died'),
      );
      expect(b.id, a.id);
      expect(b.checkOutAt, isNotNull);
      final p = await api().teamPresence();
      expect(
        p.rows.firstWhere((r) => r.employeeName == 'Tarek Saber').state,
        'done',
      );
    });

    test('the backend\'s refusals', () async {
      expect(
        () => api().punchFor(
          body: PunchFor(employeeId: emp('tarek'), reason: ' '),
        ),
        refused(400, 'REASON_REQUIRED'),
      );
      expect(
        () => api(Persona.manager).punchFor(
          body: PunchFor(employeeId: emp('karim'), reason: 'x'),
        ),
        refused(403, 'OWN_PUNCH'),
      );
      expect(
        () => api().punchFor(
          body: PunchFor(employeeId: emp('ali'), reason: 'x'),
        ),
        refused(400, 'CHECKIN_TOO_EARLY'),
      );
      expect(
        () => api(Persona.manager).punchFor(
          body: PunchFor(employeeId: emp('tarek'), reason: 'x'),
        ),
        refused(403),
      );
      db[TeamTables.attendance].put({
        'id': 'cover-today',
        'org_id': SeedIds.sabahOrg,
        'employee_id': emp('rana'),
        'employee_name': 'Rana Helmy',
        'business_date': '2026-10-08',
        'work_shift_id': TeamSeedIds.workShift('sabah', 'morning'),
        'covered_employee_id': emp('ziad'),
        'cover_status': 'pending',
      });
      expect(
        () => api().punchFor(
          body: PunchFor(employeeId: emp('ziad'), reason: 'x'),
        ),
        refused(409, 'SHIFT_COVERED'),
      );
      for (final r in db['attendance_settings'].rows) {
        r['rules_saved_at'] = null;
      }
      expect(
        () => api().punchFor(
          body: PunchFor(employeeId: emp('tarek'), reason: 'x'),
        ),
        refused(409, 'RULES_NOT_SET'),
      );
    });
  });

  group('the board\'s rules', () {
    PresenceRow row(
      String state, {
      int sch = 480,
      DateTime? opens,
      DateTime? inAt,
    }) => PresenceRow(
      employeeId: 'e',
      employeeName: 'E',
      lateMinutes: 0,
      scheduledMinutes: sch,
      state: state,
      workedMinutes: 0,
      punchOpensAt: opens,
      checkInAt: inAt,
    );
    final now = DateTime.utc(2026, 10, 8, 7);

    test('the window: off, rostered, not in, opened', () {
      expect(punchWindowOpen(row('off', opens: now), now), isTrue);
      expect(
        punchWindowOpen(
          row('off', opens: now.add(const Duration(minutes: 1))),
          now,
        ),
        isFalse,
      );
      expect(punchWindowOpen(row('off'), now), isFalse);
      expect(punchWindowOpen(row('off', sch: 0, opens: now), now), isFalse);
      expect(punchOffered(row('absent'), now), isTrue);
      expect(punchOffered(row('done'), now), isFalse);
    });

    test('nobody rostered: all off, nothing scheduled, nobody in', () {
      expect(anyoneRostered([row('off', sch: 0)]), isFalse);
      expect(anyoneRostered([row('off', sch: 0), row('off')]), isTrue);
      expect(anyoneRostered([row('done', sch: 0)]), isTrue);
    });

    test('a deduction waits: the server says, else the right and limit', () {
      bool waits({
        String? status,
        bool right = true,
        int? limit,
        int amount = 500,
      }) => deductionWaits(
        handled: status == null
            ? null
            : AttendanceFlag(
                id: 'f',
                employeeId: 'e',
                employeeName: 'E',
                kind: 'left_mid_shift',
                minutesAway: 0,
                detectedAt: now,
                suggestedDeductionPiastres: 0,
                deductionStatus: status,
              ),
        action: 'deduct',
        amountPiastres: amount,
        holdsRight: right,
        limit: limit,
      );
      expect(waits(status: 'pending'), isTrue);
      expect(waits(status: 'approved', right: false), isFalse);
      expect(waits(right: false), isTrue);
      expect(waits(limit: 400), isTrue);
      expect(waits(limit: 500), isFalse);
      expect(waits(), isFalse);
    });
  });
}
