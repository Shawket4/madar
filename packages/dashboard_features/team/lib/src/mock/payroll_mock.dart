/// The mock backend of the Payroll incl. the money sheets (`/staff/payroll`, TEAM-PAY and TEAM-MNY rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/payroll/current`
/// - `POST /staff/payroll/periods/{id}/generate`
/// - `GET /staff/payroll/periods/{id}/payslips`
/// - `GET /staff/payroll/periods/{id}/preview`
/// - `GET /staff/payroll/periods/{id}/export.csv`
/// - `PATCH /staff/payroll/periods/{id}/payslips/{employee_id}/paid`
/// - `PATCH /staff/payroll/periods/{id}/status`
/// - `DELETE /staff/payroll/bonuses/{id}`
/// - `DELETE /staff/payroll/deductions/{id}`
/// - `PATCH /staff/payroll/deductions/{id}/override|waive|unwaive`
/// - `GET /staff/payroll/advances` (replaces the shared list: caps hidden
///   from a caller who may not read pay, `hide_caps`)
/// - `POST /staff/advances/record`
/// - `PATCH /staff/advances/{id}/review`
/// - `POST /staff/adjustments` (the list is shared: team_reads_mock.dart)
/// - `PATCH /staff/adjustments/{kind}/{id}/decision`
/// - `POST /staff/adjustments/{kind}/{id}/stop`
/// - `GET|POST /staff/expense-advances`
/// - `PATCH|DELETE /staff/expense-advances/{id}`
///
/// ponytail: `GET|POST /staff/payroll/periods`, `DELETE /staff/payroll/periods/{id}`,
/// `GET /staff/payroll/bonuses|deductions` and `POST /staff/payroll/advances`
/// are not registered: no web screen calls them. Add them when one does.
///
/// As MadarRust `src/staff/dawam/pay.rs` and `src/staff/payroll.rs`: the
/// running month opens itself (`ensure_current_period`), its live preview is
/// worked out from the area seed's rows (`compute_payslips`: salary, approved
/// overtime, approved bonuses and deductions, waived lines kept but not
/// counted, deductions capped at what was earned, advance installments only
/// from what is left), approval freezes the payslips (and collects the
/// installments), a reopen drops them (and gives them back). Every act dated
/// in an approved month is refused (`PERIOD_CLOSED`). Gates: payroll reads
/// and runs need the right at EVERY branch (`require_everywhere`); pay lines
/// and advances need theirs for someone the caller manages. A pay line or a
/// raise over a branch manager's limit (1,000 EGP here; the owner has none)
/// waits for the owner.
library;

import 'package:dashboard_api/mock.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import '../area_seed.dart';
import 'team_reads_mock.dart';

/// Frozen payslips (`payslips`).
const String payslipsTable = 'payslips';

/// A branch manager's limit on a pay line or a raise, in piastres.
const int managerPayLineLimit = 100000;

const String _loaded = '_payroll_seed';

// ── dates ────────────────────────────────────────────────────────────────

DateTime _d(String iso) {
  final p = iso.substring(0, 10).split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const List<String> _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// ── seed ─────────────────────────────────────────────────────────────────

/// Each person's frozen payslip for the seeded closed months: their salary,
/// paid by their own method (the area seed's totals are those salaries).
void _seedPayslips(MockDb db) {
  if (db.hasTable(_loaded)) return;
  db.table(_loaded);
  final staff = db['employees'].rows;
  for (final p in db[TeamTables.payrollPeriods].rows) {
    if (p['status'] == 'draft') continue;
    for (final e in staff) {
      if (e['org_id'] != p['org_id'] || e['on_payroll'] != true) continue;
      if (((e['hire_date'] as String?) ?? '').compareTo(
            p['end_date']! as String,
          ) >
          0) {
        continue;
      }
      final salary = (e['base_salary_piastres'] as num?)?.toInt() ?? 0;
      db[payslipsTable].insert({
        'id': mockUuid('payslip:${p['id']}:${e['id']}'),
        'org_id': p['org_id'],
        'payroll_period_id': p['id'],
        'employee_id': e['id'],
        'base_salary_piastres': salary,
        'worked_days': 26.0,
        'absent_days': 0.0,
        'leave_days': 0.0,
        'late_minutes': 0,
        'overtime_minutes': 0,
        'overtime_piastres': 0,
        'bonuses_piastres': 0,
        'deductions_piastres': 0,
        'advance_installment_piastres': 0,
        'net_piastres': salary,
        'carry_out_piastres': 0,
        'breakdown': {
          'bonuses': const <Object>[],
          'deductions': const <Object>[],
          'advances': const <Object>[],
          'paid_days': _d(p['end_date']! as String).day,
          'window_days': _d(p['end_date']! as String).day,
          'salary_piastres': salary,
          'capped_piastres': 0,
        },
        'generated_at': p['generated_at'],
        'paid_method': e['pay_method'] ?? 'cash',
        'paid_at': p['paid_at'],
        'paid_by': SeedIds.owner,
        '_applied': const <Object>[],
      }, timestamps: false);
    }
  }
}

// ── the engine ───────────────────────────────────────────────────────────

int _int(Object? v) => v is num ? v.round() : 0;

Map<String, Object?> _settingsOf(MockDb db, String org) =>
    db['attendance_settings'].firstWhere((r) => r['org_id'] == org) ?? const {};

/// `ensure_current_period`: the month covering today, opened when missing.
MockRow currentPeriod(MockDb db, String org) {
  final day = MockClock.cairoDate(db.clock.now);
  final hit = db[TeamTables.payrollPeriods].firstWhere(
    (p) =>
        p['org_id'] == org &&
        (p['start_date']! as String).compareTo(day) <= 0 &&
        (p['end_date']! as String).compareTo(day) >= 0,
  );
  if (hit != null) return hit;
  // The server's `period_window`, through the core.
  final window = rules.payPeriod(
    day: day,
    startDay: _int(_settingsOf(db, org)['period_start_day']),
  )!;
  final (start, end) = (window.from, window.to);
  final s = _d(start), e = _d(end);
  String two(int v) => v.toString().padLeft(2, '0');
  return db[TeamTables.payrollPeriods].insert({
    'id': mockUuid('payroll-period:$org:$start'),
    'org_id': org,
    'name':
        '${two(s.day)} ${_mon[s.month - 1]} – ${two(e.day)} ${_mon[e.month - 1]} ${e.year}',
    'start_date': start,
    'end_date': end,
    'status': 'draft',
    'employee_count': 0,
    'total_net_piastres': 0,
  });
}

bool _inWindow(String? date, String from, String to) =>
    date != null && date.compareTo(from) >= 0 && date.compareTo(to) <= 0;

/// A pay line counts in the window: approved, dated in it, or a monthly one
/// started by its end and not stopped before its start.
bool _lineIn(MockRow a, String from, String to) {
  if (a['status'] != 'approved') return false;
  final eff = a['effective_date']! as String;
  if (a['recurring'] == true) {
    final ends = a['ends_on'] as String?;
    return eff.compareTo(to) <= 0 &&
        (ends == null || ends.compareTo(from) >= 0);
  }
  return _inWindow(eff, from, to);
}

/// What a line charges at [salary] (`resolve_adjustment_piastres`).
int lineValue(MockRow a, int salary) {
  final amount = a['amount_piastres'] as num?;
  if (amount != null) return amount.round();
  final p = a['percent_of_base'] as num?;
  return p == null ? 0 : (salary * p / 100).round();
}

/// `compute_payslips` for [org] over [from]–[to]: a `ComputedPayslip` JSON
/// per active person on payroll hired by the end, with the advance
/// installments each would collect under `_applied`.
List<MockRow> computePayslips(MockDb db, String org, String from, String to) {
  final settings = _settingsOf(db, org);
  final days = _int(settings['working_days_per_month']);
  final perMonthMinutes = (days == 0 ? 26 : days) * 480;
  final otRate = (settings['overtime_day_multiplier'] as num?) ?? 1.35;
  final window = _d(to).difference(_d(from)).inDays + 1;
  final staff =
      db['employees'].rows
          .where(
            (e) =>
                e['org_id'] == org &&
                e['on_payroll'] == true &&
                e['employment_status'] == 'active' &&
                ((e['hire_date'] as String?) ?? '').compareTo(to) <= 0,
          )
          .toList()
        ..sort((a, b) => compareJson(a['name'], b['name']));
  final out = <MockRow>[];
  for (final e in staff) {
    final id = e['id']! as String;
    final salaryRaw = e['base_salary_piastres'] as num?;
    final salary = salaryRaw?.round() ?? 0;
    final hired = (e['hire_date'] as String?) ?? from;
    final start = hired.compareTo(from) > 0 ? hired : from;
    final paidDays = _d(to).difference(_d(start)).inDays + 1;
    final base = (salary * paidDays / window).round();

    final records = db[TeamTables.attendance].rows.where(
      (r) =>
          r['employee_id'] == id &&
          _inWindow(r['business_date'] as String?, from, to),
    );
    var worked = 0.0, absent = 0.0, leave = 0.0;
    var late = 0, otMinutes = 0;
    for (final r in records) {
      switch (r['status']) {
        case 'present' || 'late':
          worked += 1;
        case 'half_day':
          worked += 0.5;
        case 'absent':
          absent += 1;
        case 'on_leave':
          leave += 1;
      }
      late += _int(r['late_minutes']);
      if (r['overtime_status'] == 'approved') {
        otMinutes += _int(r['overtime_minutes']);
      }
    }
    final ot = (salary * otMinutes * otRate / perMonthMinutes).round();

    Map<String, Object?> line(MockRow a, int amount) => {
      'id': a['id'],
      'reason': a['reason'],
      'piastres': amount,
      'source': a['source'],
      'effective_date': a['effective_date'],
      'recurring': a['recurring'],
      'reason_code': a['reason_code'],
      'reason_vars': a['reason_vars'],
      if (a['override_reason'] != null) 'override_reason': a['override_reason'],
      if (a['waived_at'] != null) ...{
        'waived': true,
        'waive_reason': a['waive_reason'],
      },
    };
    var bonuses = 0, deductions = 0;
    final bonusLines = <Object>[], deductionLines = <Object>[];
    for (final a in db[TeamTables.adjustments].rows) {
      if (a['employee_id'] != id || !_lineIn(a, from, to)) continue;
      final amount = lineValue(a, salary);
      final bonus = a['kind'] == 'bonus';
      (bonus ? bonusLines : deductionLines).add(line(a, amount));
      if (a['waived_at'] != null) continue;
      if (bonus) {
        bonuses += amount;
      } else {
        deductions += amount;
      }
    }

    final advances =
        db[TeamTables.advances].rows
            .where(
              (a) =>
                  a['employee_id'] == id &&
                  a['status'] == 'approved' &&
                  _int(a['remaining_piastres']) > 0,
            )
            .toList()
          ..sort((a, b) => compareJson(a['created_at'], b['created_at']));
    final wanted = advances.fold<int>(
      0,
      (s, a) =>
          s +
          [
            _int(a['monthly_installment_piastres']),
            _int(a['remaining_piastres']),
          ].reduce((x, y) => x < y ? x : y),
    );

    // `settle_net`: deductions never past what was earned (the rest
    // carries), the advance only out of what is left.
    final earned = base + ot + bonuses;
    final charged = deductions > earned ? earned : deductions;
    final capped = deductions - charged;
    final left = earned - charged;
    final advance = wanted > left ? left : wanted;
    final net = left - advance;

    var take = advance;
    final applied = <Map<String, Object?>>[];
    for (final a in advances) {
      if (take <= 0) break;
      final want = [
        _int(a['monthly_installment_piastres']),
        _int(a['remaining_piastres']),
        take,
      ].reduce((x, y) => x < y ? x : y);
      if (want <= 0) continue;
      take -= want;
      applied.add({'id': a['id'], 'applied_piastres': want});
    }

    out.add({
      'employee_id': id,
      'name': e['name'],
      'base_salary_piastres': salary,
      'worked_days': worked,
      'absent_days': absent,
      'leave_days': leave,
      'late_minutes': late,
      'overtime_minutes': otMinutes,
      'base_piastres': base,
      'overtime_piastres': ot,
      'bonuses_piastres': bonuses,
      'deductions_piastres': charged,
      'advance_installment_piastres': advance,
      'net_piastres': net,
      'carry_out_piastres': capped,
      'salary_missing': salaryRaw == null,
      'breakdown': {
        'bonuses': bonusLines,
        'deductions': deductionLines,
        'advances': applied,
        'paid_days': paidDays,
        'window_days': window,
        'salary_piastres': salary,
        'working_days_per_month': days,
        'capped_piastres': capped,
      },
      '_applied': applied,
    });
  }
  return out;
}

/// A row as the wire carries it (bookkeeping keys dropped).
MockRow _wire(MockRow r) => {
  for (final e in r.entries)
    if (!e.key.startsWith('_')) e.key: e.value,
};

/// `PAYSLIP_SELECT`: a frozen payslip with its person's live name, pay
/// method and account, and its period.
MockRow payslipOut(MockDb db, MockRow s) {
  final e = db['employees'].find(s['employee_id']! as String);
  final p = db[TeamTables.payrollPeriods].find(
    s['payroll_period_id']! as String,
  );
  return {
    ..._wire(s),
    'employee_name': e?['name'],
    'pay_method': e?['pay_method'],
    'pay_account': e?['pay_account'],
    'period_name': p?['name'],
    'period_start': p?['start_date'],
    'period_end': p?['end_date'],
  };
}

List<MockRow> _slipsOf(MockDb db, String periodId) =>
    db[payslipsTable].rows
        .where((s) => s['payroll_period_id'] == periodId)
        .map((s) => payslipOut(db, s))
        .toList()
      ..sort((a, b) => compareJson(a['employee_name'], b['employee_name']));

Map<String, Object?> _totals(List<MockRow> slips, {required bool computed}) {
  int sum(String k) => slips.fold(0, (a, s) => a + _int(s[k]));
  return {
    'base_piastres': computed
        ? sum('base_piastres')
        : sum('net_piastres') -
              sum('overtime_piastres') -
              sum('bonuses_piastres') +
              sum('deductions_piastres') +
              sum('advance_installment_piastres'),
    'overtime_piastres': sum('overtime_piastres'),
    'bonuses_piastres': sum('bonuses_piastres'),
    'deductions_piastres': sum('deductions_piastres'),
    'advances_piastres': sum('advance_installment_piastres'),
    'net_piastres': sum('net_piastres'),
    'carry_out_piastres': sum('carry_out_piastres'),
    'people': slips.length,
    if (computed)
      'missing_salary_count': slips
          .where((s) => s['salary_missing'] == true)
          .length,
  };
}

/// `period_lock::closed_as`: null when [day] is in no approved month, else
/// whether that month is paid.
bool? closedAt(MockDb db, String org, String day) {
  bool? paid;
  for (final p in db[TeamTables.payrollPeriods].rows) {
    if (p['org_id'] != org) continue;
    final s = p['status'];
    if (s != 'generated' && s != 'paid' && s != 'closed') continue;
    if (!_inWindow(day, p['start_date']! as String, p['end_date']! as String)) {
      continue;
    }
    paid = (paid ?? false) || s == 'paid' || s == 'closed';
  }
  return paid;
}

/// 409 `PERIOD_CLOSED` when [day] is in an approved month.
void assertOpen(
  MockRequest req,
  MockDb db,
  String org,
  String day,
  String what,
) {
  final paid = closedAt(db, org, day);
  if (paid == null) return;
  req.fail(
    MockResponse.error(
      409,
      paid
          ? "That month is paid — $what dated $day can't change it. "
                'Add it to the next open month instead.'
          : "That month's payroll is approved — $what dated $day can't "
                'change it. Reopen it first, or add it to the next open month.',
      code: 'PERIOD_CLOSED',
      vars: {'date': day, 'paid': paid},
    ),
  );
}

// ── gates ────────────────────────────────────────────────────────────────

/// The right at every branch (`require_everywhere`).
void requireEverywhere(MockRequest req, String cap) {
  req.requireCap(cap);
  if (req.persona.branchIds != null) req.fail(MockResponse.denied(cap));
}

bool _everywhere(MockRequest req, String cap) =>
    req.persona.can(cap) && req.persona.branchIds == null;

/// `access::subject` + `require_for`: someone of the caller's org they
/// manage, else 404 / 403.
MockRow _subject(MockRequest req, MockDb db, String? employeeId, String cap) {
  final e = teamEmployeeRow(db, employeeId);
  if (e == null || e['org_id'] != req.orgId) {
    req.fail(
      MockResponse.error(404, 'Employee not found', code: 'EMPLOYEE_NOT_FOUND'),
    );
  }
  if (!teamSeesEmployee(req, db, employeeId)) {
    req.fail(MockResponse.denied(cap));
  }
  return e;
}

bool _isSelf(MockRequest req, MockRow employee) =>
    employee['user_id'] != null && employee['user_id'] == req.persona.userId;

String _capOf(String kind) =>
    kind == 'bonus' ? 'hr.adjustments.create' : 'hr.deductions.create';

/// `gate_kind`: the right before the body is judged; a kind that is neither
/// still hears 403 from someone who may add neither.
String _gateKind(MockRequest req, String kind) {
  if (kind != 'bonus' && kind != 'deduction') {
    req.requireAnyCap(const ['hr.adjustments.create', 'hr.deductions.create']);
    req.badRequest(
      'kind is bonus or deduction',
      code: 'ADJUSTMENT_KIND_INVALID',
    );
  }
  final cap = _capOf(kind);
  req.requireCap(cap);
  return cap;
}

Never _alreadyDecided(MockRequest req, Object? status) => req.fail(
  MockResponse.error(
    409,
    'This was already decided ($status).',
    code: 'ALREADY_DECIDED',
    vars: {'status': status},
  ),
);

String? _trimmed(Object? v) {
  final s = v is String ? v.trim() : null;
  return s == null || s.isEmpty ? null : s;
}

// ── advances ─────────────────────────────────────────────────────────────

int _capOfEmployee(MockRow e) => (_int(e['base_salary_piastres']) * 50) ~/ 100;

int _outstanding(MockDb db, String employeeId) => db[TeamTables.advances].rows
    .where(
      (a) =>
          a['employee_id'] == employeeId &&
          (a['status'] == 'pending' || a['status'] == 'approved'),
    )
    .fold(0, (s, a) => s + _int(a['remaining_piastres']));

/// `approve_advance_checks`: over the cap only the owner approves.
void _capCheck(
  MockRequest req,
  MockDb db,
  MockRow e,
  int amount,
  int alreadyCounted,
) {
  final cap = _capOfEmployee(e);
  final outstanding = _outstanding(db, e['id']! as String);
  if (outstanding - alreadyCounted + amount <= cap) return;
  if (_everywhere(req, 'hr.payroll.run')) return;
  if (!req.persona.can('hr.payroll.read')) {
    req.fail(
      MockResponse.error(
        409,
        "That's over the advance cap. Only the owner can approve it.",
        code: 'ADVANCE_OVER_CAP',
        vars: {'over_cap': true},
      ),
    );
  }
  final more = (cap - outstanding + alreadyCounted).clamp(0, 1 << 52);
  req.fail(
    MockResponse.error(
      409,
      "That's over the advance cap — at most ${more ~/ 100} EGP more; "
      'the owner can approve it.',
      code: 'ADVANCE_OVER_CAP',
      vars: {'over_cap': true, 'more_piastres': more, 'more_egp': more ~/ 100},
    ),
  );
}

/// `installment_of`.
int _installment(MockRequest req, int amount, int installments) {
  if (amount <= 0) req.badRequest('Amount must be positive');
  if (installments < 1 || installments > 24) {
    req.badRequest('Installments must be between 1 and 24');
  }
  return (amount + installments - 1) ~/ installments;
}

/// An advance as the caller reads it: the cap only for someone who may read
/// that person's pay (`hide_caps`).
MockRow _advanceOut(MockRequest req, MockDb db, MockRow a) {
  final e = teamEmployeeRow(db, a['employee_id'] as String?);
  final cap = e == null ? 0 : _capOfEmployee(e);
  final outstanding = e == null ? 0 : _outstanding(db, e['id']! as String);
  return {
    ..._wire(a),
    'outstanding_piastres': outstanding,
    'within_cap': outstanding <= cap,
    'cap_piastres': req.persona.can('hr.payroll.read') ? cap : null,
  };
}

// ── handlers ─────────────────────────────────────────────────────────────

void registerPayrollMocks(MockServer server, MockDb db) {
  _seedPayslips(db);
  final periods = db[TeamTables.payrollPeriods];
  final lines = db[TeamTables.adjustments];
  final advances = db[TeamTables.advances];
  final expenses = db[TeamTables.expenseAdvances];

  MockRow periodOf(MockRequest req, String id, {bool coded = false}) {
    final p = periods.find(id);
    if (p == null || p['org_id'] != req.orgId) {
      if (coded) {
        req.fail(
          MockResponse.error(
            404,
            'Payroll period not found',
            code: 'PERIOD_NOT_FOUND',
          ),
        );
      }
      req.notFound('Payroll period not found');
    }
    return p;
  }

  server.on('GET', '/staff/payroll/current', (req) {
    requireEverywhere(req, 'hr.payroll.read');
    final org = req.orgId!;
    final period = currentPeriod(db, org);
    final draft = period['status'] == 'draft';
    final preview = draft
        ? [
            for (final s in computePayslips(
              db,
              org,
              period['start_date']! as String,
              period['end_date']! as String,
            ))
              _wire(s),
          ]
        : const <MockRow>[];
    final slips = draft
        ? const <MockRow>[]
        : _slipsOf(db, period['id']! as String);
    final start = period['start_date']! as String;
    final older =
        periods.rows
            .where(
              (p) =>
                  p['org_id'] == org &&
                  (p['start_date']! as String).compareTo(start) < 0,
            )
            .toList()
          ..sort((a, b) => compareJson(b['start_date'], a['start_date']));
    final unsettled = [
      for (final p in older.reversed)
        if (p['status'] == 'draft' || p['status'] == 'generated')
          () {
            final isDraft = p['status'] == 'draft';
            final rows = isDraft
                ? computePayslips(
                    db,
                    org,
                    p['start_date']! as String,
                    p['end_date']! as String,
                  )
                : _slipsOf(db, p['id']! as String);
            return {
              'period_id': p['id'],
              'starts_on': p['start_date'],
              'ends_on': p['end_date'],
              'status': p['status'],
              'net_total_piastres': rows.fold(
                0,
                (a, s) => a + _int(s['net_piastres']),
              ),
              'paid_count': isDraft
                  ? 0
                  : rows.where((s) => s['paid_at'] != null).length,
              'people': rows.length,
            };
          }(),
    ];
    return MockResponse.ok({
      'period': period,
      'preview': preview,
      'payslips': slips,
      'history': older.take(24).toList(),
      'totals': slips.isEmpty
          ? _totals(preview, computed: true)
          : _totals(slips, computed: false),
      'paid_count': slips.where((s) => s['paid_at'] != null).length,
      'missing_salary_count': preview
          .where((s) => s['salary_missing'] == true)
          .length,
      'unsettled': unsettled,
    });
  });

  server.on('GET', '/staff/payroll/periods/{id}/preview', (req) {
    requireEverywhere(req, 'hr.payroll.read');
    final p = periodOf(req, req.param('id'));
    return MockResponse.ok([
      for (final s in computePayslips(
        db,
        req.orgId!,
        p['start_date']! as String,
        p['end_date']! as String,
      ))
        _wire(s),
    ]);
  });

  server.on('GET', '/staff/payroll/periods/{id}/payslips', (req) {
    req.requireCap('hr.payroll.read');
    final id = req.param('id');
    return MockResponse.ok([
      for (final s in _slipsOf(db, id))
        if (s['org_id'] == req.orgId &&
            teamSeesEmployee(req, db, s['employee_id'] as String?))
          s,
    ]);
  });

  server.on('POST', '/staff/payroll/periods/{id}/generate', (req) {
    requireEverywhere(req, 'hr.payroll.run');
    final p = periodOf(req, req.param('id'));
    if (p['status'] != 'draft') {
      req.fail(
        MockResponse.error(
          409,
          'A ${p['status']} period is frozen — reopen it (before anyone is '
          'paid) to approve it again',
          code: 'PERIOD_FROZEN',
          vars: {'status': p['status']},
        ),
      );
    }
    final computed = computePayslips(
      db,
      req.orgId!,
      p['start_date']! as String,
      p['end_date']! as String,
    );
    final missing = computed.where((s) => s['salary_missing'] == true).toList();
    if (missing.isNotEmpty) {
      final names = [for (final s in missing) s['name']];
      req.fail(
        MockResponse.error(
          409,
          'Set a salary first (or mark them not on payroll): '
          '${names.join(', ')}.',
          code: 'SALARY_MISSING',
          vars: {
            'names': names,
            'employee_ids': [for (final s in missing) s['employee_id']],
          },
        ),
      );
    }
    db[payslipsTable].removeWhere((s) => s['payroll_period_id'] == p['id']);
    final now = db.nowIso;
    var total = 0;
    for (final s in computed) {
      final empty = _int(s['net_piastres']) == 0;
      total += _int(s['net_piastres']);
      // The run collects the installments (the ledger).
      for (final a in (s['_applied']! as List).cast<Map<String, Object?>>()) {
        final adv = advances.find(a['id']! as String)!;
        final left =
            _int(adv['remaining_piastres']) - _int(a['applied_piastres']);
        adv['remaining_piastres'] = left;
        if (left <= 0) adv['status'] = 'settled';
      }
      db[payslipsTable].insert({
        'id': db.newId(payslipsTable),
        'org_id': req.orgId,
        'payroll_period_id': p['id'],
        for (final k in const [
          'employee_id',
          'base_salary_piastres',
          'worked_days',
          'absent_days',
          'leave_days',
          'late_minutes',
          'overtime_minutes',
          'overtime_piastres',
          'bonuses_piastres',
          'deductions_piastres',
          'advance_installment_piastres',
          'net_piastres',
          'carry_out_piastres',
          'breakdown',
          '_applied',
        ])
          k: s[k],
        'generated_at': now,
        // Nothing to pay is settled by the run itself (PAY-7, M28).
        'paid_method': empty ? 'none' : null,
        'paid_at': empty ? now : null,
        'paid_by': empty ? req.persona.userId : null,
      }, timestamps: false);
    }
    p.addAll({
      'status': 'generated',
      'employee_count': computed.length,
      'total_net_piastres': total,
      'generated_at': now,
      'generated_by': req.persona.userId,
      'updated_at': now,
    });
    return MockResponse.ok(_slipsOf(db, p['id']! as String));
  });

  server.on('PATCH', '/staff/payroll/periods/{id}/status', (req) {
    requireEverywhere(req, 'hr.payroll.run');
    final p = periodOf(req, req.param('id'));
    final body = req.json;
    final target = body['status'];
    final reason = _trimmed(body['reason']);
    final current = p['status'];
    final slips = db[payslipsTable].rows.where(
      (s) => s['payroll_period_id'] == p['id'],
    );
    if (current == 'generated' && target == 'draft') {
      if (reason == null) req.badRequest('Reopening needs a reason');
      if (slips.any(
        (s) => s['paid_at'] != null && s['paid_method'] != 'none',
      )) {
        req.conflict(
          "Someone has already been paid — this payroll can't be reopened.",
          code: 'PAYROLL_PAID_NO_REOPEN',
        );
      }
      // The ledger gives the installments back, never taking them twice.
      for (final s in slips) {
        for (final a
            in ((s['_applied'] as List?) ?? const [])
                .cast<Map<String, Object?>>()) {
          final adv = advances.find(a['id']! as String);
          if (adv == null) continue;
          adv['remaining_piastres'] =
              _int(adv['remaining_piastres']) + _int(a['applied_piastres']);
          adv['status'] = 'approved';
        }
      }
      db[payslipsTable].removeWhere((s) => s['payroll_period_id'] == p['id']);
      p.addAll({
        'status': 'draft',
        'employee_count': 0,
        'total_net_piastres': 0,
        'generated_at': null,
        'generated_by': null,
        'updated_at': db.nowIso,
      });
    } else if (current == 'paid' && target == 'closed') {
      p.addAll({'status': 'closed', 'closed_at': db.nowIso});
    } else if (target == 'generated') {
      req.conflict(
        'Approve a month with POST …/generate; it freezes the payslips.',
        code: 'APPROVE_WITH_GENERATE',
      );
    } else if (target == 'paid') {
      req.conflict(
        'A month is Paid when every payslip is marked paid — never by hand '
        '(PAY-7).',
        code: 'PAID_BY_PAYSLIPS',
      );
    } else {
      req.fail(
        MockResponse.error(
          409,
          'A $current period cannot move to $target',
          code: 'PERIOD_STATUS_MOVE',
          vars: {'from': current, 'to': target},
        ),
      );
    }
    return MockResponse.ok(p);
  });

  server.on(
    'PATCH',
    '/staff/payroll/periods/{id}/payslips/{employee_id}/paid',
    (req) {
      requireEverywhere(req, 'hr.payroll.run');
      final method = req.json['method'];
      if (method != 'cash' && method != 'bank' && method != 'wallet') {
        req.badRequest(
          'method is cash, bank or wallet',
          code: 'PAY_METHOD_INVALID',
        );
      }
      final p = periodOf(req, req.param('id'), coded: true);
      if (p['status'] != 'generated' && p['status'] != 'paid') {
        req.conflict(
          'Approve the payroll before paying it.',
          code: 'PAYROLL_NOT_APPROVED',
        );
      }
      final slip = db[payslipsTable].firstWhere(
        (s) =>
            s['payroll_period_id'] == p['id'] &&
            s['employee_id'] == req.param('employee_id') &&
            s['paid_at'] == null,
      );
      if (slip == null) {
        req.conflict(
          "That payslip is already paid or doesn't exist.",
          code: 'PAYSLIP_ALREADY_PAID',
        );
      }
      slip.addAll({
        'paid_method': method,
        'paid_at': db.nowIso,
        'paid_by': req.persona.userId,
      });
      // The month is Paid once everyone is (`settle_period_if_all_paid`).
      if (db[payslipsTable].rows
          .where((s) => s['payroll_period_id'] == p['id'])
          .every((s) => s['paid_at'] != null)) {
        p.addAll({'status': 'paid', 'paid_at': db.nowIso});
      }
      return MockResponse.ok(payslipOut(db, slip));
    },
  );

  server.on('GET', '/staff/payroll/periods/{id}/export.csv', (req) {
    requireEverywhere(req, 'hr.payroll.read');
    final method = _trimmed(req.q('method'));
    if (method != null && !const ['bank', 'wallet', 'cash'].contains(method)) {
      req.badRequest('method is bank, wallet or cash');
    }
    final p = periodOf(req, req.param('id'));
    if (p['status'] == 'draft') {
      req.conflict(
        'Approve the period before exporting it',
        code: 'PERIOD_NOT_GENERATED',
      );
    }
    String esc(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
    String money(Object? v) {
      final n = _int(v);
      return '${n ~/ 100}.${(n % 100).abs().toString().padLeft(2, '0')}';
    }

    final slips = [
      for (final s in _slipsOf(db, p['id']! as String))
        if (method == null || s['pay_method'] == method) s,
    ];
    final csv = StringBuffer();
    switch (method) {
      case 'bank' || 'wallet':
        csv.writeln(
          'employee,${method == 'bank' ? 'account' : 'wallet_number'},amount',
        );
        for (final s in slips.where((s) => _int(s['net_piastres']) > 0)) {
          csv.writeln(
            '${esc(s['employee_name'])},${esc(s['pay_account'])},'
            '${money(s['net_piastres'])}',
          );
        }
      case 'cash':
        csv.writeln('employee,amount');
        for (final s in slips.where((s) => _int(s['net_piastres']) > 0)) {
          csv.writeln('${esc(s['employee_name'])},${money(s['net_piastres'])}');
        }
      default:
        csv.writeln(
          'employee,employee_id,pay_method,account,base,overtime,bonuses,'
          'deductions,advance,net,carry_out,worked_days,absent_days,paid_method',
        );
        for (final s in slips) {
          csv.writeln(
            [
              esc(s['employee_name']),
              esc(s['employee_id']),
              esc(s['pay_method']),
              esc(s['pay_account']),
              money(s['base_salary_piastres']),
              money(s['overtime_piastres']),
              money(s['bonuses_piastres']),
              money(s['deductions_piastres']),
              money(s['advance_installment_piastres']),
              money(s['net_piastres']),
              money(s['carry_out_piastres']),
              s['worked_days'],
              s['absent_days'],
              esc(s['paid_method']),
            ].join(','),
          );
        }
    }
    return MockResponse.text(
      csv.toString(),
      contentType: 'text/csv; charset=utf-8',
    );
  });

  // ── pay lines ──────────────────────────────────────────────────────────

  MockRow lineOf(MockRequest req, String kind, String id) {
    final a = lines.find(id);
    if (a == null ||
        a['kind'] != kind ||
        teamOrgOfEmployee(db, a['employee_id'] as String?) != req.orgId) {
      req.fail(
        MockResponse.error(
          404,
          'Adjustment not found',
          code: 'ADJUSTMENT_NOT_FOUND',
        ),
      );
    }
    return a;
  }

  /// The first open day from [today] (`first_open_day`).
  String firstOpenDay(String org, String today) {
    var day = today;
    for (var i = 0; i < 24 && closedAt(db, org, day) != null; i++) {
      final p = periods.firstWhere(
        (p) =>
            p['org_id'] == org &&
            _inWindow(
              day,
              p['start_date']! as String,
              p['end_date']! as String,
            ),
      )!;
      day = _iso(_d(p['end_date']! as String).add(const Duration(days: 1)));
    }
    return day;
  }

  server.on('POST', '/staff/adjustments', (req) {
    final body = req.json;
    final kind = '${body['kind']}';
    final cap = _gateKind(req, kind);
    final e = _subject(req, db, body['employee_id'] as String?, cap);
    if (_isSelf(req, e)) {
      req.fail(
        MockResponse.error(
          403,
          "You can't add pay lines for yourself.",
          code: 'OWN_PAY_LINE',
        ),
      );
    }
    final reason = _trimmed(body['reason']);
    if (reason == null) {
      req.badRequest('A reason is required', code: 'REASON_REQUIRED');
    }
    final salary = _int(e['base_salary_piastres']);
    final amount = body['amount_piastres'] as num?;
    final percent = body['percent_of_base'] as num?;
    final int value;
    if (amount != null && percent == null && amount > 0) {
      value = amount.round();
    } else if (amount == null &&
        percent != null &&
        kind == 'bonus' &&
        percent > 0 &&
        percent <= 100) {
      value = (salary * percent / 100).round();
    } else if (amount == null && percent != null && kind == 'deduction') {
      req.badRequest(
        'A deduction is an amount, not a percentage',
        code: 'DEDUCTION_IS_AN_AMOUNT',
      );
    } else {
      req.badRequest(
        'Give a positive amount or a percentage (1–100)',
        code: 'AMOUNT_OR_PERCENT_REQUIRED',
      );
    }
    final today = MockClock.cairoDate(req.now);
    final effective =
        (body['effective_date'] as String?) ?? firstOpenDay(req.orgId!, today);
    assertOpen(req, db, req.orgId!, effective, 'a pay line');
    final pending =
        !_everywhere(req, 'hr.payroll.run') && value > managerPayLineLimit;
    final row = lines.insert({
      'kind': kind,
      'source': 'manual',
      'status': pending ? 'pending' : 'approved',
      'employee_id': e['id'],
      'employee_name': e['name'],
      'effective_date': effective,
      'value_piastres': value,
      'amount_piastres': percent == null ? value : null,
      'percent_of_base': percent,
      'reason': reason,
      'recurring': body['recurring'] == true,
      'created_by': req.persona.userId,
    });
    return MockResponse.created(row);
  });

  server.on('PATCH', '/staff/adjustments/{kind}/{id}/decision', (req) {
    final kind = req.param('kind');
    final cap = _gateKind(req, kind);
    final a = lineOf(req, kind, req.param('id'));
    if (a['status'] != 'pending') _alreadyDecided(req, a['status']);
    _subject(req, db, a['employee_id'] as String?, cap);
    assertOpen(
      req,
      db,
      req.orgId!,
      a['effective_date']! as String,
      'this pay line',
    );
    // Only someone whose limit covers it settles a waiting line.
    if (!_everywhere(req, 'hr.payroll.run')) req.fail(MockResponse.denied(cap));
    final body = req.json;
    final approve = body['approve'] == true;
    final note = _trimmed(body['reason']);
    if (!approve && note == null) {
      req.badRequest("Say why you're rejecting it.", code: 'REASON_REQUIRED');
    }
    a.addAll({
      'status': approve ? 'approved' : 'rejected',
      'decided_by': req.persona.userId,
      'decided_at': db.nowIso,
      'decision_note': note,
    });
    return MockResponse.ok(a);
  });

  server.on('POST', '/staff/adjustments/{kind}/{id}/stop', (req) {
    final kind = req.param('kind');
    final cap = _gateKind(req, kind);
    final a = lineOf(req, kind, req.param('id'));
    _subject(req, db, a['employee_id'] as String?, cap);
    final reason = _trimmed(req.json['reason']);
    if (reason == null) {
      req.badRequest(
        'Stopping a monthly line needs a reason',
        code: 'REASON_REQUIRED',
      );
    }
    if (a['recurring'] != true || a['ends_on'] != null) {
      req.conflict(
        "That isn't a running monthly line.",
        code: 'NOT_A_RUNNING_LINE',
      );
    }
    // From next month: the month open now keeps it (D6).
    final period = currentPeriod(db, req.orgId!);
    a.addAll({
      'ends_on': period['end_date'],
      'stopped_at': db.nowIso,
      'stopped_by': req.persona.userId,
      'stop_reason': reason,
    });
    return MockResponse.ok(a);
  });

  // ── deductions on the payslip ──────────────────────────────────────────

  MockRow deductionFor(MockRequest req, String id, String what) {
    req.requireCap('hr.deductions.create');
    final a = lines.find(id);
    if (a == null ||
        a['kind'] != 'deduction' ||
        teamOrgOfEmployee(db, a['employee_id'] as String?) != req.orgId) {
      req.notFound('Deduction not found');
    }
    _subject(req, db, a['employee_id'] as String?, 'hr.deductions.create');
    assertOpen(req, db, req.orgId!, a['effective_date']! as String, what);
    return a;
  }

  MockRow adjustmentOut(MockRow a) => {
    'id': a['id'],
    'org_id': teamOrgOfEmployee(db, a['employee_id'] as String?),
    'employee_id': a['employee_id'],
    'employee_name': a['employee_name'],
    'amount_piastres': a['amount_piastres'],
    'percent_of_base': a['percent_of_base'],
    'reason': a['reason'],
    'effective_date': a['effective_date'],
    'source': a['source'],
    'status': a['status'],
    'recurring': a['recurring'],
    'created_at': a['created_at'],
    'updated_at': db.nowIso,
    'waived_at': a['waived_at'],
    'overridden_at': a['overridden_at'],
    'original_amount_piastres': a['original_amount_piastres'],
  };

  server.on('PATCH', '/staff/payroll/deductions/{id}/override', (req) {
    final a = deductionFor(req, req.param('id'), 'an override');
    final body = req.json;
    final reason = _trimmed(body['reason']);
    if (reason == null) req.badRequest('An override needs a reason');
    final amount = _int(body['amount_piastres']);
    if (amount < 0) req.badRequest('Amount cannot be negative');
    if (a['waived_at'] != null) {
      req.conflict(
        'This deduction was waived — a waiver is final.',
        code: 'WAIVER_FINAL',
      );
    }
    final current = _int(a['amount_piastres']);
    if (amount > current &&
        !_everywhere(req, 'hr.payroll.run') &&
        amount - current > managerPayLineLimit) {
      req.fail(
        MockResponse.error(
          403,
          'Raising this deduction is above your limit — the owner can '
          'override it.',
          code: 'ABOVE_LIMIT',
        ),
      );
    }
    a.addAll({
      'original_amount_piastres': a['original_amount_piastres'] ?? current,
      'amount_piastres': amount,
      'value_piastres': amount,
      'overridden_at': db.nowIso,
      'override_reason': reason,
    });
    return MockResponse.ok(adjustmentOut(a));
  });

  server.on('PATCH', '/staff/payroll/deductions/{id}/waive', (req) {
    final a = deductionFor(req, req.param('id'), 'a waiver');
    final reason = _trimmed(req.json['reason']);
    if (reason == null) req.badRequest('A waiver needs a reason');
    if (a['waived_at'] != null) {
      req.notFound('Deduction not found, or already waived');
    }
    a.addAll({
      'original_amount_piastres':
          a['original_amount_piastres'] ?? a['amount_piastres'],
      'waived_at': db.nowIso,
      'waive_reason': reason,
    });
    return MockResponse.ok(adjustmentOut(a));
  });

  server.on('PATCH', '/staff/payroll/deductions/{id}/unwaive', (req) {
    final a = deductionFor(req, req.param('id'), 'undoing a waiver');
    final reason = _trimmed(req.json['reason']);
    if (reason == null) req.badRequest('Undoing a waiver needs a reason');
    if (a['waived_at'] == null) {
      req.conflict('This deduction is not waived.', code: 'NOT_WAIVED');
    }
    a.addAll({
      'waived_at': null,
      'waive_reason': null,
      'unwaive_reason': reason,
    });
    return MockResponse.ok(adjustmentOut(a));
  });

  MockResponse deleteLine(MockRequest req, String kind) {
    final cap = _capOf(kind);
    req.requireCap(cap);
    final a = lines.find(req.param('id'));
    if (a == null ||
        a['kind'] != kind ||
        teamOrgOfEmployee(db, a['employee_id'] as String?) != req.orgId) {
      req.notFound('Adjustment not found');
    }
    _subject(req, db, a['employee_id'] as String?, cap);
    if (a['source'] != 'manual') {
      req.conflict(
        'A rule-made line is never deleted: waive or override it, with a '
        'reason.',
        code: 'RULE_LINE_NOT_DELETED',
      );
    }
    assertOpen(
      req,
      db,
      req.orgId!,
      a['effective_date']! as String,
      'a pay line',
    );
    lines.delete(a['id']! as String);
    return MockResponse.empty();
  }

  server.on(
    'DELETE',
    '/staff/payroll/bonuses/{id}',
    (req) => deleteLine(req, 'bonus'),
  );
  server.on(
    'DELETE',
    '/staff/payroll/deductions/{id}',
    (req) => deleteLine(req, 'deduction'),
  );

  // ── salary advances ────────────────────────────────────────────────────

  server.on('GET', '/staff/payroll/advances', (req) {
    req.requireAnyCap(const ['hr.payroll.read', 'hr.advances.decide']);
    final rows = advances.query(
      filters: {'org_id': req.orgId, 'employee_id': req.q('employee_id')},
      where: (r) => teamSeesEmployee(req, db, r['employee_id'] as String?),
      sort: '-created_at',
    );
    return MockResponse.ok([for (final a in rows) _advanceOut(req, db, a)]);
  });

  server.on('POST', '/staff/advances/record', (req) {
    req.requireCap('hr.advances.decide');
    final body = req.json;
    final e = _subject(
      req,
      db,
      body['employee_id'] as String?,
      'hr.advances.decide',
    );
    if (_isSelf(req, e)) {
      req.fail(
        MockResponse.error(
          403,
          'Someone else has to record your advance.',
          code: 'OWN_ADVANCE',
        ),
      );
    }
    final amount = _int(body['amount_piastres']);
    final installments = (body['installments'] as num?)?.toInt() ?? 1;
    final monthly = _installment(req, amount, installments);
    _capCheck(req, db, e, amount, 0);
    final row = advances.insert({
      'org_id': req.orgId,
      'employee_id': e['id'],
      'employee_name': e['name'],
      'amount_piastres': amount,
      'installments': installments,
      'monthly_installment_piastres': monthly,
      'remaining_piastres': amount,
      'outstanding_piastres': 0,
      'within_cap': true,
      'status': 'approved',
      'reason': _trimmed(body['reason']),
      'decided_by': req.persona.userId,
      'decided_at': db.nowIso,
    });
    return MockResponse.created(_advanceOut(req, db, row));
  });

  server.on('PATCH', '/staff/advances/{id}/review', (req) {
    req.requireCap('hr.advances.decide');
    final a = advances.find(req.param('id'));
    if (a == null || a['org_id'] != req.orgId) {
      req.fail(
        MockResponse.error(404, 'Advance not found', code: 'ADVANCE_NOT_FOUND'),
      );
    }
    if (a['status'] != 'pending') _alreadyDecided(req, a['status']);
    final e = _subject(
      req,
      db,
      a['employee_id'] as String?,
      'hr.advances.decide',
    );
    if (_isSelf(req, e)) {
      req.fail(
        MockResponse.error(
          403,
          'Someone else has to decide your advance.',
          code: 'OWN_ADVANCE',
        ),
      );
    }
    final body = req.json;
    final asked = _int(a['amount_piastres']);
    final amount = (body['amount_piastres'] as num?)?.toInt() ?? asked;
    final installments =
        (body['installments'] as num?)?.toInt() ?? _int(a['installments']);
    final monthly = _installment(req, amount, installments);
    final approve = body['approve'] == true;
    final note = _trimmed(body['reason']) ?? _trimmed(body['note']);
    if (!approve && note == null) {
      req.badRequest("Say why you're rejecting it.", code: 'REASON_REQUIRED');
    }
    if (approve) _capCheck(req, db, e, amount, asked);
    a.addAll({
      'status': approve ? 'approved' : 'rejected',
      'amount_piastres': amount,
      'remaining_piastres': amount,
      'installments': installments,
      'monthly_installment_piastres': monthly,
      'decided_by': req.persona.userId,
      'decided_at': db.nowIso,
      'decision_note': note,
      'updated_at': db.nowIso,
    });
    return MockResponse.ok(_advanceOut(req, db, a));
  });

  // ── expense advances ───────────────────────────────────────────────────

  server.on('GET', '/staff/expense-advances', (req) {
    req.requireAnyCap(const ['hr.payroll.read', 'hr.expense_advances.log']);
    final branch = req.q('branch_id');
    if (branch != null && !req.persona.seesBranch(branch)) {
      req.fail(MockResponse.denied('hr.payroll.read'));
    }
    final rows =
        expenses.query(
          filters: {'employee_id': req.q('employee_id'), 'branch_id': branch},
          where: (r) => teamSeesEmployee(req, db, r['employee_id'] as String?),
        )..sort((a, b) {
          final c = compareJson(b['given_on'], a['given_on']);
          return c != 0 ? c : compareJson(b['created_at'], a['created_at']);
        });
    return MockResponse.ok(rows.take(300).toList());
  });

  server.on('POST', '/staff/expense-advances', (req) {
    req.requireCap('hr.expense_advances.log');
    final body = req.json;
    final e = _subject(
      req,
      db,
      body['employee_id'] as String?,
      'hr.expense_advances.log',
    );
    final branch =
        (body['branch_id'] as String?) ??
        (e['branch_ids'] as List?)?.cast<String>().first;
    if (body['branch_id'] != null) {
      if (teamOrgOfBranch(db, branch) != req.orgId) {
        req.notFound('Branch not found');
      }
      req.requireCap('hr.expense_advances.log', branchId: branch);
    }
    final via = body['via'];
    if (via != 'safe' && via != 'bank') {
      req.badRequest(
        'via is safe or bank — a till pay-out is tagged on the till itself',
        code: 'EXPENSE_VIA_INVALID',
      );
    }
    final amount = _int(body['amount_piastres']);
    if (amount <= 0) {
      req.badRequest('Amount must be positive', code: 'AMOUNT_NOT_POSITIVE');
    }
    final purpose = _trimmed(body['purpose']);
    if (purpose == null) {
      req.badRequest("Say what it's for", code: 'PURPOSE_REQUIRED');
    }
    final today = MockClock.cairoDate(req.now);
    final givenOn = (body['given_on'] as String?) ?? today;
    if (givenOn.compareTo(today) > 0) {
      req.badRequest("The date can't be in the future", code: 'DATE_IN_FUTURE');
    }
    final row = expenses.insert({
      'employee_id': e['id'],
      'employee_name': e['name'],
      'branch_id': branch,
      'amount_piastres': amount,
      'purpose': purpose,
      'via': via,
      'given_on': givenOn,
      'handed_by': req.persona.userId,
      'handed_by_name': req.persona.displayName,
    });
    return MockResponse.created(row);
  });

  /// `expense_for_correction`: the owner's, with a reason, in an open month.
  MockRow forCorrection(MockRequest req, String id, Object? reason) {
    if (!_everywhere(req, 'hr.payroll.run')) {
      req.fail(
        MockResponse.error(
          403,
          'Only the owner corrects an expense advance.',
          code: 'OWNER_ONLY',
        ),
      );
    }
    final x = expenses.find(id);
    if (x == null ||
        teamOrgOfEmployee(db, x['employee_id'] as String?) != req.orgId) {
      req.notFound('Expense advance not found');
    }
    if (_trimmed(reason) == null) {
      req.badRequest("Say why you're correcting it.", code: 'REASON_REQUIRED');
    }
    assertOpen(
      req,
      db,
      req.orgId!,
      x['given_on']! as String,
      'this expense advance',
    );
    return x;
  }

  server.on('DELETE', '/staff/expense-advances/{id}', (req) {
    final x = forCorrection(req, req.param('id'), req.q('reason'));
    expenses.delete(x['id']! as String);
    return MockResponse.empty();
  });

  server.on('PATCH', '/staff/expense-advances/{id}', (req) {
    final body = req.json;
    final x = forCorrection(req, req.param('id'), body['reason']);
    final to = teamEmployeeRow(db, body['employee_id'] as String?);
    if (to == null || to['org_id'] != req.orgId) {
      req.fail(
        MockResponse.error(
          404,
          'Employee not found',
          code: 'EMPLOYEE_NOT_FOUND',
        ),
      );
    }
    if (to['employment_status'] != 'active') {
      req.fail(
        MockResponse.error(
          403,
          "That person isn't an active employee.",
          code: 'EMPLOYEE_INACTIVE',
          vars: {'status': to['employment_status']},
        ),
      );
    }
    if (to['id'] == x['employee_id']) req.badRequest("It's already theirs.");
    x.addAll({'employee_id': to['id'], 'employee_name': to['name']});
    return MockResponse.ok(x);
  });
}
