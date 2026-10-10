/// The mock backend of the Team (`/staff/team`, TEAM-TEM rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/team/presence`
/// - `GET /staff/flags`
/// - `PATCH /staff/flags/{id}`
/// - `POST /staff/attendance/punch`
///
/// Each follows MadarRust `src/staff/attendance.rs` `team_presence` and
/// `src/staff/dawam/presence.rs` (`list_flags`, `resolve_flag`, `punch_for`):
/// the same gates, scoping, refusals and state, over the area seed's tables.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show isoString;

import '../area_seed.dart';
import 'payroll_mock.dart' show assertOpen, managerPayLineLimit;
import 'rules_mock.dart' show businessRulesRow;
import 'team_reads_mock.dart';

// ponytail: every seeded branch is in Cairo, so "today" and shift times use
// the Cairo clock; read the branch's zone once a seed branch lives elsewhere.
String _today(MockRequest req) => MockClock.cairoDate(req.now);

/// Postgres DOW of `yyyy-mm-dd` (0 = Sunday).
int _dow(String date) => DateTime.parse(date).weekday % 7;

/// The instant of [hhmm] (`07:00` or `07:00:00`) on [date], Cairo time.
DateTime _at(String date, Object? hhmm, {bool nextDay = false}) {
  final d = DateTime.parse(date).add(Duration(days: nextDay ? 1 : 0));
  final p = '$hhmm'.split(':');
  return MockClock.fromCairo(
    d.year,
    d.month,
    d.day,
    int.parse(p[0]),
    int.parse(p[1]),
  );
}

/// [employeeId]'s rostered shift on [date] from the standing roster:
/// `(shift row, start, end)`, or null when off.
// ponytail: the standing weekly roster only; day edits made on Schedule do
// not move the board yet (read them here once a test needs it).
(MockRow, DateTime, DateTime)? teamShiftOn(
  MockDb db,
  String employeeId,
  String date,
) {
  final a = db[TeamTables.assignments].firstWhere(
    (r) =>
        r['employee_id'] == employeeId &&
        r['day_of_week'] == _dow(date) &&
        '${r['effective_from']}'.compareTo(date) <= 0 &&
        (r['effective_to'] == null ||
            '${r['effective_to']}'.compareTo(date) >= 0),
  );
  if (a == null) return null;
  final w = db['work_shifts'].find(a['work_shift_id']! as String);
  if (w == null) return null;
  final start = _at(date, w['start_time']);
  final end = _at(date, w['end_time'], nextDay: w['crosses_midnight'] == true);
  return (w, start, end);
}

/// Who is in, late, absent, on leave or off right now (`team_presence`).
Map<String, Object?> teamPresenceOf(
  MockDb db, {
  required String orgId,
  required List<String>? scope,
  required DateTime now,
}) {
  final today = MockClock.cairoDate(now);
  final yesterday = MockClock.cairoDate(now.subtract(const Duration(days: 1)));
  final rows = <Map<String, Object?>>[];
  final people = db['employees'].where(
    (e) => e['org_id'] == orgId && e['employment_status'] == 'active',
  );
  for (final e in people) {
    final id = e['id']! as String;
    final own = ((e['branch_ids'] as List?) ?? const []).cast<String>();
    final home = own.where((b) => scope == null || scope.contains(b));
    final branchName = home.isEmpty
        ? null
        : db['branches'].find(home.first)?['name'] as String?;
    final shift = teamShiftOn(db, id, today);
    final scheduled = shift == null
        ? 0
        : shift.$3.difference(shift.$2).inMinutes;
    final window = (shift?.$1['checkin_window_minutes'] as num?)?.toInt() ?? 0;
    // Their day's record, or a night shift from yesterday still open.
    final recs = db[TeamTables.attendance].where(
      (a) =>
          a['employee_id'] == id &&
          a['org_id'] == orgId &&
          (a['business_date'] == today ||
              (a['business_date'] == yesterday &&
                  a['check_in_at'] != null &&
                  a['check_out_at'] == null)),
    )..sort((a, b) => compareJson(b['check_in_at'], a['check_in_at']));
    final t = recs.isEmpty ? null : recs.first;
    if (scope != null &&
        !scope.contains(t?['branch_id']) &&
        !own.any(scope.contains)) {
      continue;
    }
    final away = db[TeamTables.requests].rows.any(
      (r) =>
          r['employee_id'] == id &&
          r['status'] == 'approved' &&
          (r['kind'] == 'leave' || r['kind'] == 'mission') &&
          '${r['on_date']}'.compareTo(today) <= 0 &&
          '${r['end_date'] ?? r['on_date']}'.compareTo(today) >= 0,
    );
    final inAt = t?['check_in_at'];
    final outAt = t?['check_out_at'];
    final late = (t?['late_minutes'] as num?)?.toInt() ?? 0;
    final state = switch (t?['status']) {
      'on_leave' => 'on_leave',
      _ when inAt != null && outAt == null && late > 0 => 'late',
      _ when inAt != null && outAt == null => 'in',
      _ when outAt != null => 'done',
      _ when away && scheduled > 0 => 'on_leave',
      _ when scheduled > 0 && !shift!.$2.isAfter(now) => 'absent',
      _ => 'off',
    };
    rows.add({
      'employee_id': id,
      'employee_name': e['name'],
      'job_title': e['job_title'],
      'branch_name': branchName,
      'check_in_at': inAt,
      'check_out_at': outAt,
      'late_minutes': late,
      'worked_minutes': (t?['worked_minutes'] as num?)?.toInt() ?? 0,
      'scheduled_minutes': scheduled,
      'punch_opens_at': shift == null
          ? null
          : isoString(shift.$2.subtract(Duration(minutes: window))),
      'state': state,
    });
  }
  rows.sort(
    (a, b) => '${a['employee_name']}'.toLowerCase().compareTo(
      '${b['employee_name']}'.toLowerCase(),
    ),
  );
  int count(String s) => rows.where((r) => r['state'] == s).length;
  return {
    'business_date': today,
    // `done` counts as present: someone who finished their shift was here.
    'present': count('in') + count('done'),
    'late': count('late'),
    'absent': count('absent'),
    'on_leave': count('on_leave'),
    'worked_minutes': rows.fold<int>(
      0,
      (s, r) => s + (r['worked_minutes']! as int),
    ),
    'planned_minutes': rows.fold<int>(
      0,
      (s, r) => s + (r['scheduled_minutes']! as int),
    ),
    'rows': rows,
    'timezone': MockClock.timezone,
  };
}

/// The branches a read covers (`access::scope_at`): the one asked for
/// (checked), else the caller's own, else every branch (null).
List<String>? _scopeAt(MockRequest req, String cap) {
  final branchId = req.q('branch_id');
  req.requireCap(cap, branchId: branchId);
  return branchId == null ? req.persona.branchIds : [branchId];
}

/// The flag's org: its employee's.
bool _ofOrg(MockRequest req, MockDb db, MockRow f) =>
    teamOrgOfEmployee(db, f['employee_id'] as String?) == req.orgId;

Never _coded(
  MockRequest req,
  int status,
  String code,
  String reason, [
  Object? vars,
]) => req.fail(MockResponse.error(status, reason, code: code, vars: vars));

void registerTeamBoardMocks(MockServer server, MockDb db) {
  server.on('GET', '/staff/team/presence', (req) {
    final scope = _scopeAt(req, 'hr.attendance.read');
    return MockResponse.ok(
      teamPresenceOf(db, orgId: req.orgId!, scope: scope, now: req.now),
    );
  });

  server.on('GET', '/staff/flags', (req) {
    final scope = _scopeAt(req, 'hr.attendance.read');
    final all = req.qBool('all') ?? false;
    final rows = db[TeamTables.flags].where(
      (f) =>
          _ofOrg(req, db, f) &&
          (all || f['resolution'] == null) &&
          (scope == null || scope.contains(f['branch_id'])),
    )..sort((a, b) => compareJson(b['detected_at'], a['detected_at']));
    return MockResponse.ok(rows.take(200).toList());
  });

  server.on('PATCH', '/staff/flags/{id}', (req) {
    req.requireCap('hr.attendance.edit');
    final flag = db[TeamTables.flags].find(req.param('id'));
    if (flag == null || !_ofOrg(req, db, flag) || flag['resolution'] != null) {
      _coded(req, 404, 'FLAG_HANDLED', 'That flag is already handled.');
    }
    final body = req.json;
    final action = '${body['action']}';
    final kind = flag['kind']! as String;
    final employeeId = flag['employee_id']! as String;
    final employee = teamEmployeeRow(db, employeeId)!;
    final branchId = flag['branch_id'] as String?;
    void at(String cap) {
      req.requireCap(cap);
      if (branchId != null) {
        req.requireBranch(branchId);
      } else if (!teamSeesEmployee(req, db, employeeId)) {
        req.fail(MockResponse.denied(cap));
      }
    }

    at('hr.attendance.edit');
    // Nobody decides their own flag; signing your own phone out favours
    // nobody, so it stays.
    final self = employee['user_id'] == req.persona.userId;
    if (self && action != 'revoke') {
      _coded(req, 403, 'OWN_DECISION', 'Someone else has to decide this one.');
    }
    if (kind == 'cover') at('hr.shift_cover.confirm');
    if (action == 'revoke') at('hr.staff.edit');
    if (kind == 'cover' && action != 'confirm' && action != 'reject') {
      _coded(
        req,
        400,
        'FLAG_COVER_CONFIRM_OR_REJECT',
        'A cover is confirmed or rejected.',
      );
    }
    final recordId = flag['attendance_record_id'] as String?;
    final record = recordId == null
        ? null
        : db[TeamTables.attendance].find(recordId);
    final suggested = (flag['suggested_deduction_piastres'] as num?)?.toInt();
    final reason = '${body['reason'] ?? ''}'.trim();
    final (resolution, amount, lineReason) = switch (action) {
      'ignore' => ('ignored', 0, ''),
      'confirm' => ('confirmed', 0, ''),
      'reject' when kind == 'cover' => ('rejected', 0, ''),
      'excuse_paid' => ('excused_paid', 0, ''),
      'excuse_unpaid' => ('excused_unpaid', suggested ?? 0, 'Unpaid excuse'),
      'deduct' => (
        'deducted',
        switch (body['amount_piastres']) {
          final num a when a > 0 => a.toInt(),
          _ => _coded(
            req,
            400,
            'AMOUNT_REQUIRED',
            'Type the amount to deduct.',
          ),
        },
        reason.isEmpty ? 'Left mid-shift' : reason,
      ),
      'revoke' when kind == 'new_phone' => ('revoked', 0, ''),
      _ => _coded(req, 400, 'FLAG_ACTION_UNKNOWN', 'Unknown action'),
    };
    // A cover's flag decides the cover itself.
    if (kind == 'cover' && record != null) {
      db[TeamTables.attendance].update(record['id']! as String, {
        'cover_status': action == 'confirm' ? 'confirmed' : 'rejected',
      });
    }
    String? lineId;
    String? lineStatus;
    if (amount > 0) {
      if (self) {
        _coded(
          req,
          403,
          'OWN_PAY_LINE',
          "You can't add pay lines for yourself.",
        );
      }
      final day = (record?['business_date'] as String?) ?? _today(req);
      assertOpen(req, db, req.orgId!, day, 'this deduction');
      // Above the manager's limit it waits for the owner.
      req.requireCap('hr.deductions.create');
      final everywhere =
          req.persona.can('hr.payroll.run') && req.persona.branchIds == null;
      lineStatus = !everywhere && amount > managerPayLineLimit
          ? 'pending'
          : 'approved';
      lineId =
          db[TeamTables.adjustments].insert({
                'kind': 'deduction',
                'source': resolution == 'deducted'
                    ? 'left_mid_shift'
                    : 'excused_unpaid',
                'status': lineStatus,
                'employee_id': employeeId,
                'employee_name': employee['name'],
                'effective_date': day,
                'value_piastres': amount,
                'amount_piastres': amount,
                'percent_of_base': null,
                'reason': lineReason,
                'recurring': false,
                'created_by': req.persona.userId,
              })['id']
              as String;
    }
    final row = db[TeamTables.flags].update(flag['id']! as String, {
      'resolution': resolution,
      'resolved_at': isoString(req.now),
      'deduction_id': lineId,
      'deduction_status': lineStatus,
    });
    return MockResponse.ok(row);
  });

  server.on('POST', '/staff/attendance/punch', (req) {
    req.requireCap('hr.attendance.punch_others');
    final body = req.json;
    final reason = '${body['reason'] ?? ''}'.trim();
    if (reason.isEmpty) {
      _coded(req, 400, 'REASON_REQUIRED', 'A reason is required.');
    }
    final employeeId = body['employee_id'] as String?;
    final e = teamEmployeeRow(db, employeeId);
    if (e == null || e['org_id'] != req.orgId) req.notFound('Employee');
    if (e['employment_status'] != 'active') {
      _coded(
        req,
        403,
        'EMPLOYMENT_NOT_ACTIVE',
        "That person isn't an active employee.",
        {'status': e['employment_status']},
      );
    }
    if (e['user_id'] == req.persona.userId) {
      _coded(req, 403, 'OWN_PUNCH', 'Punch yourself in from your own phone.');
    }
    if (businessRulesRow(db, req.orgId)?['rules_saved_at'] == null) {
      _coded(
        req,
        409,
        'RULES_NOT_SET',
        "Your business hasn't set its attendance rules yet — ask the owner "
            'to finish set-up.',
      );
    }
    final branches = ((e['branch_ids'] as List?) ?? const []).cast<String>();
    if (branches.isEmpty) {
      _coded(req, 400, 'EMPLOYEE_NO_BRANCH', 'That person has no branch.');
    }
    if (!teamSeesEmployee(req, db, employeeId)) {
      req.fail(MockResponse.denied('hr.attendance.punch_others'));
    }
    final now = req.now;
    final records = db[TeamTables.attendance];
    final open = records.where(
      (r) =>
          r['employee_id'] == employeeId &&
          r['check_in_at'] != null &&
          r['check_out_at'] == null,
    )..sort((a, b) => compareJson(b['check_in_at'], a['check_in_at']));
    if (open.isNotEmpty) {
      final r = open.first;
      final inAt = DateTime.parse(r['check_in_at']! as String);
      return MockResponse.ok(
        records.update(r['id']! as String, {
          'check_out_at': isoString(now),
          'check_out_method': 'manager',
          'check_out_reason': reason,
          'worked_minutes': now.difference(inAt).inMinutes,
          'edited_by': req.persona.userId,
        }),
      );
    }
    final today = _today(req);
    final shift = teamShiftOn(db, employeeId!, today);
    if (shift != null) {
      final (w, start, end) = shift;
      final window = (w['checkin_window_minutes'] as num?)?.toInt() ?? 0;
      final opens = start.subtract(Duration(minutes: window));
      if (now.isBefore(opens)) {
        _coded(
          req,
          400,
          'CHECKIN_TOO_EARLY',
          'Too early — check-in for ${w['name']} opens $window minutes '
              'before it starts',
          {'shift': w['name'], 'minutes': window, 'opens_at': isoString(opens)},
        );
      }
      if (!now.isBefore(end)) {
        _coded(req, 400, 'SHIFT_ENDED', '${w['name']} has already ended', {
          'shift': w['name'],
        });
      }
    }
    final shiftId = shift?.$1['id'] as String?;
    // A colleague is covering it: never paid twice (D1).
    final cover = records.firstWhere(
      (r) =>
          r['covered_employee_id'] == employeeId &&
          r['employee_id'] != employeeId &&
          r['business_date'] == today &&
          r['work_shift_id'] == shiftId &&
          (r['cover_status'] == 'pending' || r['cover_status'] == 'confirmed'),
    );
    if (cover != null) {
      final name = cover['employee_name'] ?? '';
      _coded(
        req,
        409,
        'SHIFT_COVERED',
        '$name is covering this shift. A manager ends or rejects the cover '
            'first.',
        {'coverer_name': name},
      );
    }
    final worked = records.firstWhere(
      (r) =>
          r['employee_id'] == employeeId &&
          r['business_date'] == today &&
          r['work_shift_id'] == shiftId &&
          r['covered_employee_id'] == null,
    );
    if (worked != null) {
      _coded(
        req,
        409,
        'SHIFT_ALREADY_WORKED',
        'They already worked that shift today.',
      );
    }
    final grace = (shift?.$1['grace_minutes'] as num?)?.toInt() ?? 0;
    final lateBy = shift == null ? 0 : now.difference(shift.$2).inMinutes;
    final late = lateBy > grace ? lateBy : 0;
    final branch = (shift?.$1['branch_id'] as String?) ?? branches.first;
    final row = AttendanceRecord(
      id: db.newId(TeamTables.attendance),
      orgId: req.orgId!,
      branchId: branch,
      employeeId: employeeId,
      employeeName: e['name'] as String?,
      businessDate: today,
      workShiftId: shiftId,
      workShiftName: shift?.$1['name'] as String?,
      scheduledStartAt: shift?.$2,
      scheduledEndAt: shift?.$3,
      status: late > 0 ? 'late' : 'present',
      lateMinutes: late,
      earlyLeaveMinutes: 0,
      overtimeMinutes: 0,
      workedMinutes: 0,
      isManual: true,
      trackingOff: false,
      monthClosed: false,
      checkInAt: now,
      checkInMethod: 'manager',
      punchReason: reason,
      createdAt: now,
      updatedAt: now,
    ).toJson();
    return MockResponse.ok(records.insert(row, timestamps: false));
  });
}
