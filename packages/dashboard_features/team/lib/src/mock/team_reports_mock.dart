/// The mock backend of the Team reports (`/staff/reports`, TEAM-RPT rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/reports/advances`
/// - `GET /staff/reports/labour-vs-sales`
/// - `GET /staff/reports/payroll-history`
///
/// As MadarRust `src/staff/dawam/reports.rs`: `from`/`to` required and at
/// most 400 days apart (400 otherwise); labour and advances read the branches
/// the caller holds `hr.payroll.read` at (`scope_at`: a branch asked for must
/// be one of them); payroll history needs it at every branch
/// (`require_everywhere`); labour vs sales needs the POS module (403). The
/// attendance tab's `/staff/attendance/summary` is the Attendance unit's.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'payroll_mock.dart' show payslipsTable, requireEverywhere;
import 'team_reads_mock.dart' show teamOrgOfBranch;

/// The widest report (`MAX_DAYS`).
const int reportMaxDays = 400;

int _int(Object? v) => v is num ? v.round() : 0;

/// `ReportQuery` + `check`.
({String from, String to, String? branchId}) _query(MockRequest req) {
  final from = req.q('from');
  final to = req.q('to');
  if (from == null || to == null) {
    req.badRequest(
      'Query deserialize error: missing field `${from == null ? 'from' : 'to'}`',
    );
  }
  DateTime day(String s) =>
      DateTime.tryParse('${s}T00:00:00Z') ??
      req.badRequest(
        'Query deserialize error: input contains invalid characters',
      );
  final days = day(to).difference(day(from)).inDays;
  if (days < 0 || days > reportMaxDays) {
    req.badRequest('The range must be 0–$reportMaxDays days');
  }
  return (from: from, to: to, branchId: req.q('branch_id'));
}

/// `access::scope_at`: the asked branch (when the caller holds [cap] there),
/// else the caller's branches (null = every branch).
List<String>? _scopeAt(MockRequest req, String cap, String? branchId) {
  req.requireCap(cap, branchId: branchId);
  return branchId != null ? [branchId] : req.persona.branchIds;
}

bool _inScope(List<String>? scope, Object? branchId) =>
    scope == null || scope.contains(branchId);

bool _between(Object? day, String from, String to) =>
    day is String && day.compareTo(from) >= 0 && day.compareTo(to) <= 0;

/// `labour_vs_sales`: each worked shift at the person's minute rate plus the
/// approved overtime premium, against completed sales, per day and branch.
/// ponytail: the org's day rate and a 480-minute day for everyone (no night
/// minutes, no per-shift multipliers, no rostered-minutes split); add them
/// if a test needs payroll's exact pricing.
List<Map<String, Object?>> labourVsSales(
  MockDb db,
  String org,
  String from,
  String to,
  List<String>? scope,
) {
  final settings =
      db['attendance_settings'].firstWhere((r) => r['org_id'] == org) ??
      const {};
  final days = _int(settings['working_days_per_month']);
  final perMonthMinutes = (days == 0 ? 26 : days) * 480;
  final otRate = (settings['overtime_day_multiplier'] as num?) ?? 1.35;
  final salaries = {
    for (final e in db['employees'].rows)
      e['id']: _int(e['base_salary_piastres']),
  };
  final out = <(String, String), (int, int)>{};
  for (final r in db[TeamTables.attendance].rows) {
    if (r['org_id'] != org ||
        r['check_in_at'] == null ||
        !_between(r['business_date'], from, to) ||
        !_inScope(scope, r['branch_id'])) {
      continue;
    }
    final cover = r['covered_employee_id'] != null;
    if (cover && r['cover_status'] != 'confirmed') continue;
    final salary = salaries[r['employee_id']] ?? 0;
    final plain = salary * _int(r['worked_minutes']) / perMonthMinutes;
    final premium = !cover && r['overtime_status'] == 'approved'
        ? salary * _int(r['overtime_minutes']) * (otRate - 1) / perMonthMinutes
        : 0;
    final key = (r['business_date']! as String, r['branch_id']! as String);
    final v = out[key] ?? (0, 0);
    out[key] = (v.$1 + (plain + premium).round(), v.$2);
  }
  for (final o in db['orders'].rows) {
    final branch = o['branch_id'];
    if (teamOrgOfBranch(db, branch as String?) != org ||
        !_inScope(scope, branch) ||
        o['status'] == 'voided' ||
        o['status'] == 'refunded') {
      continue;
    }
    final day = MockClock.cairoDate(DateTime.parse(o['created_at']! as String));
    if (!_between(day, from, to)) continue;
    final key = (day, branch!);
    final v = out[key] ?? (0, 0);
    out[key] = (
      v.$1,
      v.$2 + _int(o['total_amount']) - _int(o['refunded_amount']),
    );
  }
  final keys = out.keys.toList()
    ..sort((a, b) {
      final d = a.$1.compareTo(b.$1);
      return d != 0 ? d : a.$2.compareTo(b.$2);
    });
  return [
    for (final k in keys)
      {
        'date': k.$1,
        'branch_id': k.$2,
        'labour_piastres': out[k]!.$1,
        'sales_piastres': out[k]!.$2,
        'labour_share_bp': out[k]!.$2 > 0
            ? out[k]!.$1 * 10000 ~/ out[k]!.$2
            : null,
      },
  ];
}

/// `payroll_history`: every pay period overlapping the range, newest first,
/// with its frozen payslips summed (a running month has none).
List<Map<String, Object?>> payrollHistory(
  MockDb db,
  String org,
  String from,
  String to,
) {
  final periods =
      db[TeamTables.payrollPeriods].rows
          .where(
            (p) =>
                p['org_id'] == org &&
                (p['end_date']! as String).compareTo(from) >= 0 &&
                (p['start_date']! as String).compareTo(to) <= 0,
          )
          .toList()
        ..sort(
          (a, b) => (b['start_date']! as String).compareTo(
            a['start_date']! as String,
          ),
        );
  final slips = db.hasTable(payslipsTable)
      ? db[payslipsTable].rows
      : const <MockRow>[];
  return [
    for (final p in periods)
      () {
        final mine = slips.where((s) => s['payroll_period_id'] == p['id']);
        int sum(String f) => mine.fold(0, (a, s) => a + _int(s[f]));
        return <String, Object?>{
          'period_id': p['id'],
          'name': p['name'],
          'start_date': p['start_date'],
          'end_date': p['end_date'],
          'status': p['status'],
          'people': mine.length,
          'base_piastres': sum('base_salary_piastres'),
          'overtime_minutes': sum('overtime_minutes'),
          'overtime_piastres': sum('overtime_piastres'),
          'bonuses_piastres': sum('bonuses_piastres'),
          'deductions_piastres': sum('deductions_piastres'),
          'advances_piastres': sum('advance_installment_piastres'),
          'net_piastres': sum('net_piastres'),
        };
      }(),
  ];
}

/// `advances`: approved and settled salary advances given in the range (the
/// day decided, on the Cairo calendar: every seeded branch is in Cairo), for
/// people working in [scope]; expense advances handed out in the range at a
/// branch in [scope]; the three totals.
Map<String, Object?> advancesReport(
  MockDb db,
  String org,
  String from,
  String to,
  List<String>? scope,
) {
  final branchesOf = {
    for (final e in db['employees'].rows)
      e['id']: (e['branch_ids'] as List?) ?? const [],
  };
  String givenOn(MockRow a) => MockClock.cairoDate(
    DateTime.parse((a['decided_at'] ?? a['created_at'])! as String),
  );
  final salary =
      db[TeamTables.advances].rows
          .where(
            (a) =>
                a['org_id'] == org &&
                (a['status'] == 'approved' || a['status'] == 'settled') &&
                _between(givenOn(a), from, to) &&
                (scope == null ||
                    branchesOf[a['employee_id']]!.any(scope.contains)),
          )
          .toList()
        ..sort((a, b) => compareJson(b['created_at'], a['created_at']));
  final expense =
      db[TeamTables.expenseAdvances].rows
          .where(
            (e) =>
                teamOrgOfBranch(db, e['branch_id'] as String?) == org &&
                _between(e['given_on'], from, to) &&
                _inScope(scope, e['branch_id']),
          )
          .toList()
        ..sort((a, b) {
          final d = compareJson(b['given_on'], a['given_on']);
          return d != 0 ? d : compareJson(b['created_at'], a['created_at']);
        });
  return {
    'salary': [
      for (final a in salary)
        {
          'id': a['id'],
          'employee_id': a['employee_id'],
          'employee_name': a['employee_name'],
          'amount_piastres': a['amount_piastres'],
          'remaining_piastres': a['remaining_piastres'],
          'installments': a['installments'],
          'status': a['status'],
          'given_on': givenOn(a),
        },
    ],
    'expense': [
      for (final e in expense)
        {
          'id': e['id'],
          'employee_id': e['employee_id'],
          'employee_name': e['employee_name'],
          'amount_piastres': e['amount_piastres'],
          'purpose': e['purpose'],
          'via': e['via'],
          'given_on': e['given_on'],
        },
    ],
    'salary_given_piastres': salary.fold<int>(
      0,
      (a, s) => a + _int(s['amount_piastres']),
    ),
    'salary_outstanding_piastres': salary
        .where((s) => s['status'] == 'approved')
        .fold<int>(0, (a, s) => a + _int(s['remaining_piastres'])),
    'expense_given_piastres': expense.fold<int>(
      0,
      (a, e) => a + _int(e['amount_piastres']),
    ),
  };
}

void registerTeamReportsMocks(MockServer server, MockDb db) {
  server.on('GET', '/staff/reports/labour-vs-sales', (req) {
    final k = _query(req);
    final scope = _scopeAt(req, 'hr.payroll.read', k.branchId);
    final org = req.orgId!;
    final modules = (db['orgs'].find(org)?['modules'] as List?) ?? const [];
    if (!modules.contains('pos')) {
      req.fail(
        MockResponse.forbidden('Labour cost vs sales needs POS switched on.'),
      );
    }
    return MockResponse.ok(labourVsSales(db, org, k.from, k.to, scope));
  });

  server.on('GET', '/staff/reports/payroll-history', (req) {
    final k = _query(req);
    requireEverywhere(req, 'hr.payroll.read');
    return MockResponse.ok(payrollHistory(db, req.orgId!, k.from, k.to));
  });

  server.on('GET', '/staff/reports/advances', (req) {
    final k = _query(req);
    final scope = _scopeAt(req, 'hr.payroll.read', k.branchId);
    return MockResponse.ok(advancesReport(db, req.orgId!, k.from, k.to, scope));
  });
}
