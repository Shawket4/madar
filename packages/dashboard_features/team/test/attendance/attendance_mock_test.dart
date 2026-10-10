// The Attendance unit's mock handlers against hand-computed figures and the
// backend's refusals (MadarRust `src/staff/attendance.rs`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show ensureTimeZones;
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'attendance_support.dart';

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

  final morning = TeamSeedIds.workShift('sabah', 'morning');

  setUpAll(ensureTimeZones);
  setUp(() => TeamSeed.loadInto(db = MockDb.seeded()));

  group('GET /staff/attendance/summary', () {
    test(
      'per person, by name; the counts and minutes are the records\'',
      () async {
        final rows = await api().attendanceSummary(from: day(-6), to: day());
        final window = windowRows(db);
        int count(String s) => window.where((r) => r['status'] == s).length;
        int sum(String k) => window.fold(0, (a, r) => a + (r[k]! as int));
        expect(
          rows.fold<int>(0, (a, r) => a + r.presentDays),
          count('present'),
        );
        expect(rows.fold<int>(0, (a, r) => a + r.lateDays), count('late'));
        expect(rows.fold<int>(0, (a, r) => a + r.absentDays), count('absent'));
        expect(rows.fold<int>(0, (a, r) => a + r.leaveDays), count('on_leave'));
        expect(
          rows.fold<int>(0, (a, r) => a + r.totalOvertimeMinutes),
          sum('overtime_minutes'),
        );
        expect(
          rows.fold<int>(0, (a, r) => a + r.totalWorkedMinutes),
          sum('worked_minutes'),
        );
        final names = [for (final r in rows) r.employeeName.toLowerCase()];
        expect(names, [...names]..sort());
      },
    );

    test(
      'a branch manager reads their branch; another branch is refused',
      () async {
        final rows = await api(
          Persona.manager,
        ).attendanceSummary(from: day(-6), to: day());
        final zamalek = windowRows(
          db,
          branchId: SeedIds.zamalek,
        ).map((r) => r['employee_id']).toSet();
        expect(rows.map((r) => r.employeeId).toSet(), zamalek);
        await expectLater(
          api(Persona.manager).attendanceSummary(
            from: day(-6),
            to: day(),
            branchId: SeedIds.maadi,
          ),
          refused(403),
        );
      },
    );

    test('a window over 400 days or backwards is refused', () async {
      await expectLater(
        api().attendanceSummary(from: '2025-01-01', to: day()),
        refused(400, 'RANGE_TOO_WIDE'),
      );
      await expectLater(
        api().attendanceSummary(from: day(), to: day(-1)),
        refused(400, 'RANGE_BACKWARDS'),
      );
    });
  });

  group('GET /staff/attendance', () {
    test('a window is required unless it lists pending items', () async {
      await expectLater(api().listAttendance(), refused(400, 'RANGE_REQUIRED'));
      final pending = await api().listAttendance(coverStatus: 'pending');
      expect(pending.single.employeeName, 'Youssef Samir');
      await expectLater(
        api().listAttendance(from: day(-1), to: day(), status: 'gone'),
        refused(400),
      );
      await expectLater(
        api().listAttendance(from: day(-1), to: day(), coverStatus: 'maybe'),
        refused(400),
      );
    });

    test('month_closed follows the payroll months live', () async {
      var rows = await api().listAttendance(from: '2026-09-28', to: day());
      expect(
        rows
            .where((r) => r.monthClosed == true)
            .map((r) => r.businessDate)
            .toSet(),
        {
          '2026-09-28',
          '2026-09-29',
          '2026-09-30',
        }.intersection(rows.map((r) => r.businessDate).toSet()),
      );
      db[TeamTables.payrollPeriods].insert({
        'org_id': SeedIds.sabahOrg,
        'name': 'October 2026',
        'start_date': '2026-10-01',
        'end_date': '2026-10-31',
        'status': 'generated',
      });
      rows = await api().listAttendance(from: '2026-09-28', to: day());
      expect(rows.every((r) => r.monthClosed == true), isTrue);
    });

    test(
      'newest day first, then by name; the limited persona is refused',
      () async {
        final rows = await api().listAttendance(from: day(-6), to: day());
        for (var i = 1; i < rows.length; i++) {
          final a = rows[i - 1], b = rows[i];
          final c = b.businessDate.compareTo(a.businessDate);
          expect(c <= 0, isTrue);
          if (c == 0) {
            expect(
              a.employeeName!.toLowerCase().compareTo(
                    b.employeeName!.toLowerCase(),
                  ) <=
                  0,
              isTrue,
            );
          }
        }
        await expectLater(
          api(Persona.limited).listAttendance(from: day(-6), to: day()),
          refused(403),
        );
      },
    );
  });

  group('POST /staff/attendance', () {
    ManualRecordRequest body({
      String employee = 'mariam',
      String? branch,
      String? date,
      String? shift,
      DateTime? checkIn,
      DateTime? checkOut,
      String? status,
      String reason = 'The app missed the day',
    }) => ManualRecordRequest(
      employeeId: emp(employee),
      branchId: branch ?? SeedIds.zamalek,
      businessDate: date ?? day(-2),
      workShiftId: shift,
      checkInAt: checkIn,
      checkOutAt: checkOut,
      status: status,
      reason: reason,
    );

    test(
      'a day derived from its stamps on the shift: 07:25 against 07:00 '
      'with 10 grace minutes is 15 late; it lists as entered by hand',
      () async {
        records(db).removeWhere(
          (r) =>
              r['employee_id'] == emp('mariam') &&
              r['business_date'] == day(-2),
        );
        final r = await api().createManualRecord(
          body: body(
            shift: morning,
            checkIn: DateTime.parse(cairo(day(-2), '07:25')),
            checkOut: DateTime.parse(cairo(day(-2), '15:50')),
          ),
        );
        expect(r.status, 'late');
        expect(r.lateMinutes, 15);
        expect(r.workedMinutes, 505);
        expect(r.overtimeMinutes, 20); // 50 past the end, 30 of threshold
        expect(r.checkInMethod, 'manual');
        expect(r.isManual, isTrue);
        expect(r.workShiftName, 'Morning');
        final listed = await api().listAttendance(
          from: day(-2),
          to: day(-2),
          employeeId: emp('mariam'),
        );
        expect(listed.single.id, r.id);
        await expectLater(
          api().createManualRecord(
            body: body(
              shift: morning,
              checkIn: DateTime.parse(cairo(day(-2), '07:00')),
            ),
          ),
          refused(409, 'RECORD_EXISTS'),
        );
      },
    );

    test('an explicit status sticks: an absence has no stamps', () async {
      final r = await api().createManualRecord(
        body: body(date: day(-5), status: 'absent'),
      );
      expect(r.status, 'absent');
      expect(r.statusOverridden, isTrue);
      expect(r.checkInAt, isNull);
    });

    test('refusals: a closed month, a covered shift, no reason, an out '
        'without an in or before it, a stranger, another branch', () async {
      await expectLater(
        api().createManualRecord(body: body(date: '2026-09-20')),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.code, 'code', 'PERIOD_CLOSED')
              .having((e) => (e.details! as Map)['vars'], 'vars', {
                'date': '2026-09-20',
                'paid': true,
              }),
        ),
      );
      await expectLater(
        api().createManualRecord(
          body: body(
            date: day(-1),
            shift: morning,
            checkIn: DateTime.parse(cairo(day(-1), '07:00')),
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'SHIFT_COVERED')
              .having((e) => (e.details! as Map)['vars'], 'vars', {
                'coverer_name': 'Youssef Samir',
              }),
        ),
      );
      await expectLater(
        api().createManualRecord(body: body(reason: '  ')),
        refused(400),
      );
      await expectLater(
        api().createManualRecord(
          body: body(checkOut: DateTime.parse(cairo(day(-2), '15:00'))),
        ),
        refused(400),
      );
      await expectLater(
        api().createManualRecord(
          body: body(
            checkIn: DateTime.parse(cairo(day(-2), '15:00')),
            checkOut: DateTime.parse(cairo(day(-2), '07:00')),
          ),
        ),
        refused(400),
      );
      final stranger = db['employees'].firstWhere(
        (e) => e['org_id'] == SeedIds.nakhlaOrg,
      )!;
      await expectLater(
        api().createManualRecord(
          body: ManualRecordRequest(
            employeeId: stranger['id']! as String,
            branchId: SeedIds.zamalek,
            businessDate: day(-2),
            reason: 'x',
          ),
        ),
        refused(404),
      );
      await expectLater(
        api(Persona.manager).createManualRecord(
          body: body(employee: 'hana', branch: SeedIds.maadi, date: day(-5)),
        ),
        refused(403),
      );
      await expectLater(
        api(Persona.limited).createManualRecord(body: body()),
        refused(403),
      );
    });
  });

  group('PATCH /staff/attendance/{id}', () {
    test('a moved out is a correction; the day re-derived; the in keeps how '
        'it was made', () async {
      final r = (await api().listAttendance(
        from: day(-2),
        to: day(-2),
        employeeId: emp('karim'),
      )).single;
      final out = r.checkOutAt!.add(const Duration(minutes: 90));
      final fixed = await api().correctRecord(
        id: r.id,
        body: CorrectRecordRequest(checkOutAt: out, reason: 'Stayed late'),
      );
      expect(fixed.checkOutMethod, 'correction');
      expect(fixed.checkInMethod, r.checkInMethod);
      expect(fixed.checkOutAt, out);
      expect(fixed.workedMinutes, out.difference(r.checkInAt!).inMinutes);
      expect(fixed.editReason, 'Stayed late');
    });

    test('a status set by hand sticks through a later correction', () async {
      final r = (await api().listAttendance(
        from: day(-3),
        to: day(-3),
        employeeId: emp('karim'),
      )).single;
      await api().correctRecord(
        id: r.id,
        body: const CorrectRecordRequest(status: 'half_day', reason: 'Agreed'),
      );
      final again = await api().correctRecord(
        id: r.id,
        body: CorrectRecordRequest(
          checkOutAt: r.checkOutAt!.add(const Duration(minutes: 5)),
          reason: 'Clock drift',
        ),
      );
      expect(again.status, 'half_day');
      expect(again.statusOverridden, isTrue);
    });

    test('refusals: a closed month, a covered owner clocked in, no reason, '
        'out before in, unknown, another branch', () async {
      final sept = records(db).firstWhere(
        (r) =>
            r['org_id'] == SeedIds.sabahOrg &&
            r['business_date'] == '2026-09-28',
      )!;
      await expectLater(
        api().correctRecord(
          id: sept['id']! as String,
          body: const CorrectRecordRequest(reason: 'x'),
        ),
        refused(409, 'PERIOD_CLOSED'),
      );
      records(db).insert(
        recordRow(
          id: 'r-mariam',
          employeeKey: 'mariam',
          date: day(-1),
          status: 'absent',
          workShiftId: morning,
        ),
      );
      await expectLater(
        api().correctRecord(
          id: 'r-mariam',
          body: CorrectRecordRequest(
            checkInAt: DateTime.parse(cairo(day(-1), '07:00')),
            reason: 'He came',
          ),
        ),
        refused(409, 'SHIFT_COVERED'),
      );
      await expectLater(
        api().correctRecord(
          id: 'r-mariam',
          body: const CorrectRecordRequest(reason: ''),
        ),
        refused(400),
      );
      final karim = (await api().listAttendance(
        from: day(-2),
        to: day(-2),
        employeeId: emp('karim'),
      )).single;
      await expectLater(
        api().correctRecord(
          id: karim.id,
          body: CorrectRecordRequest(
            checkOutAt: karim.checkInAt!.subtract(const Duration(hours: 1)),
            reason: 'x',
          ),
        ),
        refused(400),
      );
      await expectLater(
        api().correctRecord(
          id: 'nope',
          body: const CorrectRecordRequest(reason: 'x'),
        ),
        refused(404),
      );
      final maadi = records(db).firstWhere(
        (r) => r['branch_id'] == SeedIds.maadi && r['business_date'] == day(-2),
      )!;
      await expectLater(
        api(Persona.manager).correctRecord(
          id: maadi['id']! as String,
          body: const CorrectRecordRequest(reason: 'x'),
        ),
        refused(403),
      );
    });
  });
}
