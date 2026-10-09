// The Reports unit's mock handlers against hand-computed figures, and the
// backend's gates (MadarRust src/staff/dawam/reports.rs).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show ensureTimeZones;
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher refused(int status, [String? message]) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.message, 'message', contains(message ?? '')),
);

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

  group('every report', () {
    test('from and to are required, the end on or after the start, at most '
        '400 days apart (400)', () async {
      final s = api();
      expect(s.advances(from: '2026-10-09', to: '2026-10-01'), refused(400));
      expect(
        s.payrollHistory(from: '2025-01-01', to: '2026-10-01'),
        refused(400),
      );
      expect(
        s.labourVsSales(from: '2025-08-01', to: '2026-10-01'),
        refused(400),
      );
      await s.advances(from: '2026-10-01', to: '2026-10-01');
      // 400 days is the widest.
      await s.advances(from: '2025-09-01', to: '2026-10-06');
    });

    test('a person without hr.payroll.read is refused (403)', () {
      final s = api(Persona.manager);
      expect(s.advances(from: '2026-10-01', to: '2026-10-31'), refused(403));
      expect(
        s.payrollHistory(from: '2026-10-01', to: '2026-10-31'),
        refused(403),
      );
      expect(
        s.labourVsSales(from: '2026-10-01', to: '2026-10-31'),
        refused(403),
      );
    });
  });

  group('GET /staff/reports/labour-vs-sales', () {
    void tiny(MockDb db) {
      final omar = SeedIds.employee('omar');
      db['employees'].rows.firstWhere(
            (e) => e['id'] == omar,
          )['base_salary_piastres'] =
          1248000; // 100 piastres a minute over 26 × 480
      db['attendance_settings'].rows
          .where((r) => r['org_id'] == SeedIds.sabahOrg)
          .forEach((r) {
            r['working_days_per_month'] = 26;
            r['overtime_day_multiplier'] = 1.35;
          });
      db[TeamTables.attendance].removeWhere((_) => true);
      db['orders'].removeWhere((_) => true);
      Map<String, Object?> rec(String id, Map<String, Object?> extra) => {
        'id': id,
        'org_id': SeedIds.sabahOrg,
        'employee_id': omar,
        'branch_id': SeedIds.zamalek,
        'business_date': '2026-10-05',
        'check_in_at': '2026-10-05T04:00:00Z',
        'worked_minutes': 480,
        'overtime_minutes': 60,
        'overtime_status': 'approved',
        ...extra,
      };
      db[TeamTables.attendance]
        ..insert(rec('a1', {}), timestamps: false)
        // Never punched in: no labour.
        ..insert(rec('a2', {'check_in_at': null}), timestamps: false)
        // A cover not confirmed yet: no labour.
        ..insert(
          rec('a3', {
            'covered_employee_id': SeedIds.employee('laila'),
            'cover_status': 'pending',
          }),
          timestamps: false,
        );
      Map<String, Object?> order(String id, String at, int total, String st) =>
          {
            'id': id,
            'branch_id': SeedIds.zamalek,
            'created_at': at,
            'total_amount': total,
            'status': st,
          };
      db['orders']
        ..insert(order('o1', '2026-10-05T10:00:00Z', 200000, 'completed'))
        // 00:30 on the 5th in Cairo (UTC+3 in October).
        ..insert(order('o2', '2026-10-04T21:30:00Z', 100000, 'completed'))
        ..insert(order('o3', '2026-10-05T11:00:00Z', 50000, 'voided'))
        ..insert(order('o4', '2026-10-06T09:00:00Z', 40000, 'completed'))
        ..insert(order('o5', '2026-11-01T09:00:00Z', 99900, 'completed'));
    }

    test('labour = worked minutes at the minute rate + the approved overtime '
        'premium; sales on the Cairo day, voids left out; share in basis '
        'points, by day then branch', () async {
      tiny(db);
      final rows = await api().labourVsSales(
        from: '2026-10-01',
        to: '2026-10-31',
      );
      // 480 × 100 + 60 × 100 × 0.35 = 48,000 + 2,100.
      expect(rows.map((r) => r.toJson()).toList(), [
        {
          'date': '2026-10-05',
          'branch_id': SeedIds.zamalek,
          'labour_piastres': 50100,
          'sales_piastres': 300000,
          'labour_share_bp': 1670,
        },
        {
          'date': '2026-10-06',
          'branch_id': SeedIds.zamalek,
          'labour_piastres': 0,
          'sales_piastres': 40000,
          'labour_share_bp': 0,
        },
      ]);
    });

    test('a branch asked for narrows it; a day with labour and no sales has '
        'no share', () async {
      tiny(db);
      db['orders'].removeWhere((_) => true);
      final rows = await api().labourVsSales(
        from: '2026-10-01',
        to: '2026-10-31',
        branchId: SeedIds.zamalek,
      );
      expect(rows.single.labourShareBp, isNull);
      expect(
        await api().labourVsSales(
          from: '2026-10-01',
          to: '2026-10-31',
          branchId: SeedIds.maadi,
        ),
        isEmpty,
      );
    });

    test('without POS it is refused (403)', () {
      expect(
        api(Persona.dawamOnly).labourVsSales(from: '2026-10-01', to: '2026-10-31'),
        refused(403, 'Labour cost vs sales needs POS switched on.'),
      );
    });
  });

  group('GET /staff/reports/payroll-history', () {
    test('every pay period overlapping the range, newest first, its frozen '
        'payslips summed', () async {
      final rows = await api().payrollHistory(
        from: '2026-08-15',
        to: '2026-09-10',
      );
      final seeded = {
        for (final p in db[TeamTables.payrollPeriods].rows)
          if (p['org_id'] == SeedIds.sabahOrg) p['start_date']: p,
      };
      expect(rows.map((r) => r.name), ['September 2026', 'August 2026']);
      for (final r in rows) {
        final p = seeded[r.startDate]!;
        expect(r.periodId, p['id']);
        expect(r.status, p['status']);
        expect(r.people, p['employee_count']);
        expect(r.netPiastres, p['total_net_piastres']);
        expect(r.basePiastres, p['total_net_piastres']);
        expect(r.overtimePiastres, 0);
      }
    });

    test('another org\'s periods never show; outside the range nothing', () async {
      final rows = await api(
        Persona.dawamOnly,
      ).payrollHistory(from: '2026-09-01', to: '2026-09-30');
      expect(rows.single.periodId, TeamSeedIds.period('nakhla', '2026-09'));
      expect(
        await api().payrollHistory(from: '2026-06-01', to: '2026-07-31'),
        isEmpty,
      );
    });
  });

  group('GET /staff/reports/advances', () {
    test('approved and settled salary advances given in the range, newest '
        'first; the expense log; the three totals', () async {
      final r = await api().advances(from: '2026-07-01', to: '2026-10-31');
      expect(r.salary.map((s) => (s.employeeName, s.status, s.givenOn)), [
        ('Mariam Fathy', 'approved', '2026-08-29'),
        ('Ali Hassan', 'settled', '2026-07-25'),
      ]);
      expect(r.salary.first.amountPiastres, 400000);
      expect(r.salary.first.remainingPiastres, 300000);
      expect(r.salary.first.installments, 4);
      expect(r.expense.map((e) => (e.employeeName, e.via, e.givenOn)), [
        ('Karim Adel', 'till', '2026-10-06'),
        ('Dina Fouad', 'safe', '2026-10-03'),
      ]);
      expect(r.salaryGivenPiastres, 600000);
      expect(r.salaryOutstandingPiastres, 300000);
      expect(r.expenseGivenPiastres, 185000);
    });

    test('this pay period: no salary advance was given; a branch narrows the '
        'expense log to its own', () async {
      final r = await api().advances(
        from: '2026-10-01',
        to: '2026-10-31',
        branchId: SeedIds.zamalek,
      );
      expect(r.salary, isEmpty);
      expect(r.expense.map((e) => e.employeeName), ['Karim Adel']);
      expect(r.expenseGivenPiastres, 120000);
    });
  });
}
