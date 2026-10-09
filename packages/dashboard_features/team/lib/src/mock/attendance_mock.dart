/// The mock backend of the Attendance (`/staff/attendance`, TEAM-ATT rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET|POST /staff/attendance` (the list is shared: team_reads_mock.dart;
///   registered again here with the backend's validation and its live
///   `month_closed`)
/// - `PATCH /staff/attendance/{id}`
/// - `GET /staff/attendance/summary`
///
/// As MadarRust `src/staff/attendance.rs` (`list_attendance`,
/// `attendance_summary`, `create_manual_record`, `correct_record`): the
/// capability at the record's branch, the 400-day window, the closed-month
/// lock (409 `PERIOD_CLOSED`), the cover guard (409 `SHIFT_COVERED`), one
/// record per person, day and shift (409 `RECORD_EXISTS`), and the day
/// re-derived from its stamps.
library;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show isoString, wallClock;

import '../area_seed.dart';

const List<String> _statuses = [
  'present',
  'late',
  'absent',
  'half_day',
  'on_leave',
];

/// The window an attendance read may span (`MAX_RANGE_DAYS`).
const int attendanceMaxRangeDays = 400;

DateTime _day(String iso) => DateTime.parse('${iso}T00:00:00Z');

/// `validate_range`: 400 `RANGE_BACKWARDS` / `RANGE_TOO_WIDE`.
void _validateRange(MockRequest req, String from, String to) {
  if (to.compareTo(from) < 0) {
    req.badRequest('`to` is before `from`', code: 'RANGE_BACKWARDS');
  }
  if (_day(to).difference(_day(from)).inDays > attendanceMaxRangeDays) {
    req.fail(
      MockResponse.error(
        400,
        'Range too wide — at most $attendanceMaxRangeDays days per request',
        code: 'RANGE_TOO_WIDE',
        vars: {'max_days': attendanceMaxRangeDays},
      ),
    );
  }
}

/// `AttendanceStatus::parse`.
void _parseStatus(MockRequest req, String status) {
  if (!_statuses.contains(status)) {
    req.badRequest(
      "Unknown attendance status '$status' — expected one of "
      'present, late, absent, half_day, on_leave',
    );
  }
}

/// Whether [day] sits in an approved, paid or closed payroll month of [org]
/// (`period_lock`); null when open, else whether it is paid.
bool? _closedPaid(MockDb db, String? org, String day) {
  bool? paid;
  for (final p in db[TeamTables.payrollPeriods].rows) {
    if (p['org_id'] != org) continue;
    final s = p['status'];
    if (s != 'generated' && s != 'paid' && s != 'closed') continue;
    if ((p['start_date']! as String).compareTo(day) > 0) continue;
    if ((p['end_date']! as String).compareTo(day) < 0) continue;
    paid = (paid ?? false) || s == 'paid' || s == 'closed';
  }
  return paid;
}

/// 409 `PERIOD_CLOSED` when [day] is in a closed month (`assert_open`).
void _assertOpen(MockRequest req, MockDb db, String day, String what) {
  final paid = _closedPaid(db, req.orgId, day);
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

/// `refuse_if_covered`: a colleague's pending or confirmed cover of the
/// owner's shift that day refuses a check-in (D1).
void _refuseIfCovered(
  MockRequest req,
  MockDb db,
  String employeeId,
  String day,
  String? shiftId,
) {
  if (shiftId == null) return;
  final cover = db[TeamTables.attendance].firstWhere(
    (r) =>
        r['covered_employee_id'] == employeeId &&
        r['business_date'] == day &&
        r['work_shift_id'] == shiftId &&
        r['employee_id'] != employeeId &&
        (r['cover_status'] == 'pending' || r['cover_status'] == 'confirmed'),
  );
  if (cover == null) return;
  final name = cover['employee_name'] ?? '';
  req.fail(
    MockResponse.error(
      409,
      '$name is covering this shift. A manager ends or rejects the cover first.',
      code: 'SHIFT_COVERED',
      vars: {'coverer_name': name},
    ),
  );
}

/// A record as `RECORD_COLS` reads it: `month_closed` live from the
/// payroll months.
MockRow _read(MockDb db, MockRow r) => {
  ...r,
  'month_closed':
      _closedPaid(db, r['org_id'] as String?, r['business_date']! as String) !=
      null,
};

int _byDateThenName(MockRow a, MockRow b) {
  final c = compareJson(b['business_date'], a['business_date']);
  if (c != 0) return c;
  return '${a['employee_name'] ?? ''}'.toLowerCase().compareTo(
    '${b['employee_name'] ?? ''}'.toLowerCase(),
  );
}

DateTime? _instant(Object? v) => v is String ? DateTime.parse(v) : null;

String? _iso(DateTime? d) => d == null ? null : isoString(d);

/// A shift's start or end on [day] at [hhmm] on [zone]'s clock.
DateTime _at(String zone, String day, String hhmm) {
  final d = _day(day);
  final t = hhmm.split(':').map(int.parse).toList();
  return wallClock(zone, d.year, d.month - 1, d.day, t[0], t[1]);
}

/// The day's figures from its stamps (`derive`, `rules::classify`).
({String status, int late, int early, int overtime, int worked}) _derive(
  DateTime? inAt,
  DateTime? outAt,
  DateTime? start,
  DateTime? end,
  MockRow? shift,
) {
  int n(String k, [int d = 0]) => (shift?[k] as num?)?.toInt() ?? d;
  final late = start != null && inAt != null
      ? (inAt.difference(start).inMinutes - n('grace_minutes')).clamp(
          0,
          1 << 30,
        )
      : 0;
  var worked = 0;
  if (inAt != null && outAt != null) {
    final raw = outAt.difference(inAt).inMinutes.clamp(0, 1 << 30);
    worked = shift?['paid_break'] == false
        ? (raw - n('break_minutes')).clamp(0, 1 << 30)
        : raw;
  }
  var early = 0, overtime = 0;
  if (end != null && outAt != null) {
    early = end.difference(outAt).inMinutes.clamp(0, 1 << 30);
    overtime = (outAt.difference(end).inMinutes - n('overtime_threshold_minutes'))
        .clamp(0, 1 << 30);
  }
  String status;
  if (outAt == null) {
    status = inAt == null ? 'absent' : (late > 0 ? 'late' : 'present');
  } else if (inAt == null) {
    status = 'absent';
  } else {
    final span = start != null && end != null
        ? end.difference(start).inMinutes
        : 0;
    final threshold = shift?['half_day_threshold_minutes'] as int? ?? span ~/ 2;
    status = worked < (threshold < 1 ? 1 : threshold)
        ? 'half_day'
        : late > 0
        ? 'late'
        : 'present';
  }
  return (
    status: status,
    late: late,
    early: early,
    overtime: overtime,
    worked: worked,
  );
}

void registerAttendanceMocks(MockServer server, MockDb db) {
  final records = db[TeamTables.attendance];

  String zoneOf(String? branchId) =>
      (branchId == null ? null : db['branches'].find(branchId))?['timezone']
          as String? ??
      'Africa/Cairo';

  // ── list_attendance ──────────────────────────────────────────────────
  server.on('GET', '/staff/attendance', (req) {
    final branchId = req.q('branch_id');
    req.requireCap('hr.attendance.read', branchId: branchId);
    final status = req.q('status');
    if (status != null) _parseStatus(req, status);
    void check(String field, List<String> allowed) {
      final v = req.q(field);
      if (v != null && !allowed.contains(v)) {
        req.badRequest('$field is one of ${allowed.join(', ')}');
      }
    }

    check('cover_status', const ['pending', 'confirmed', 'rejected']);
    check('overtime_status', const ['pending', 'approved', 'rejected']);
    // Pending items must all reach Approvals, however old; any other
    // listing is a window.
    final pending =
        req.q('cover_status') == 'pending' ||
        req.q('overtime_status') == 'pending';
    final from = req.q('from');
    final to = req.q('to');
    if (from != null && to != null) {
      _validateRange(req, from, to);
    } else if (!(from == null && to == null && pending)) {
      req.badRequest('Pick a date range (from and to).', code: 'RANGE_REQUIRED');
    }
    final scoped = req.persona.branchIds;
    final rows = [
      for (final r in records.query(
        filters: {
          'org_id': req.orgId,
          'branch_id': branchId,
          'employee_id': req.q('employee_id'),
          'status': status,
          'cover_status': req.q('cover_status'),
          'overtime_status': req.q('overtime_status'),
        },
        where: (r) {
          final d = r['business_date']! as String;
          if (from != null && d.compareTo(from) < 0) return false;
          if (to != null && d.compareTo(to) > 0) return false;
          return scoped == null || scoped.contains(r['branch_id']);
        },
      ))
        _read(db, r),
    ]..sort(_byDateThenName);
    return MockResponse.ok(rows);
  });

  // ── attendance_summary ───────────────────────────────────────────────
  server.on('GET', '/staff/attendance/summary', (req) {
    final branchId = req.q('branch_id');
    req.requireCap('hr.attendance.read', branchId: branchId);
    final from = req.q('from');
    final to = req.q('to');
    if (from == null || to == null) {
      req.badRequest(
        'Query deserialize error: missing field `${from == null ? 'from' : 'to'}`',
      );
    }
    _validateRange(req, from, to);
    final scoped = req.persona.branchIds;
    final by = <String, Map<String, Object?>>{};
    for (final r in records.query(
      filters: {
        'org_id': req.orgId,
        'branch_id': branchId,
        'employee_id': req.q('employee_id'),
      },
      where: (r) {
        final d = r['business_date']! as String;
        return d.compareTo(from) >= 0 &&
            d.compareTo(to) <= 0 &&
            (scoped == null || scoped.contains(r['branch_id']));
      },
    )) {
      final id = r['employee_id']! as String;
      final s = by.putIfAbsent(
        id,
        () => {
          'employee_id': id,
          'employee_name':
              db['employees'].find(id)?['name'] ?? r['employee_name'] ?? '',
          'present_days': 0,
          'late_days': 0,
          'absent_days': 0,
          'half_days': 0,
          'leave_days': 0,
          'total_late_minutes': 0,
          'total_overtime_minutes': 0,
          'total_worked_minutes': 0,
        },
      );
      void add(String k, Object? v) =>
          s[k] = (s[k]! as int) + ((v as num?)?.toInt() ?? 0);
      final counter = switch (r['status']) {
        'present' => 'present_days',
        'late' => 'late_days',
        'absent' => 'absent_days',
        'half_day' => 'half_days',
        'on_leave' => 'leave_days',
        _ => null,
      };
      if (counter != null) add(counter, 1);
      add('total_late_minutes', r['late_minutes']);
      add('total_overtime_minutes', r['overtime_minutes']);
      add('total_worked_minutes', r['worked_minutes']);
    }
    final rows = by.values.toList()
      ..sort(
        (a, b) => '${a['employee_name']}'.toLowerCase().compareTo(
          '${b['employee_name']}'.toLowerCase(),
        ),
      );
    return MockResponse.ok(rows);
  });

  // ── create_manual_record ─────────────────────────────────────────────
  server.on('POST', '/staff/attendance', (req) {
    req.requireCap('hr.attendance.create');
    final body = req.json;
    final branchId = body['branch_id'] as String?;
    final employeeId = body['employee_id'] as String?;
    final day = body['business_date'] as String?;
    if (branchId == null || employeeId == null || day == null) {
      req.unprocessable('Json deserialize error: missing field');
    }
    req.requireCap('hr.attendance.create', branchId: branchId);
    final employee = db['employees'].find(employeeId);
    if (employee == null || employee['org_id'] != req.orgId) {
      req.notFound('Employee not found');
    }
    _assertOpen(req, db, day, 'an attendance record');
    final reason = '${body['reason'] ?? ''}'.trim();
    if (reason.isEmpty) {
      req.badRequest('A manual attendance record needs a reason');
    }
    final inAt = _instant(body['check_in_at']);
    final outAt = _instant(body['check_out_at']);
    if (inAt != null && outAt != null && outAt.isBefore(inAt)) {
      req.badRequest('Check-out is before check-in');
    }
    if (outAt != null && inAt == null) {
      req.badRequest('A check-out needs a check-in');
    }
    final branch = db['branches'].find(branchId);
    if (branch == null) req.notFound('Branch not found');
    if (branch['org_id'] != req.orgId) {
      req.fail(
        MockResponse.forbidden(
          'That branch belongs to a different organization',
        ),
      );
    }
    final shiftId = body['work_shift_id'] as String?;
    if (inAt != null) _refuseIfCovered(req, db, employeeId, day, shiftId);
    final status = body['status'] as String?;
    if (status != null) _parseStatus(req, status);
    final taken = records.firstWhere(
      (r) =>
          r['employee_id'] == employeeId &&
          r['business_date'] == day &&
          r['work_shift_id'] == shiftId &&
          r['covered_employee_id'] == null,
    );
    if (taken != null) {
      req.conflict(
        'This employee already has a record for that day and shift — '
        'correct it instead',
        code: 'RECORD_EXISTS',
      );
    }
    final shift = shiftId == null ? null : db['work_shifts'].find(shiftId);
    final zone = zoneOf(branchId);
    final start = shift == null
        ? null
        : _at(zone, day, shift['start_time']! as String);
    var end = shift == null ? null : _at(zone, day, shift['end_time']! as String);
    if (start != null && end != null && !end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    final d = _derive(inAt, outAt, start, end, shift);
    final row = records.insert({
      'org_id': req.orgId,
      'employee_id': employeeId,
      'employee_name': employee['name'],
      'branch_id': branchId,
      'work_shift_id': shiftId,
      'work_shift_name': shift?['name'],
      'business_date': day,
      'status': status ?? d.status,
      'scheduled_start_at': _iso(start),
      'scheduled_end_at': _iso(end),
      'check_in_at': _iso(inAt),
      'check_in_method': inAt == null ? null : 'manual',
      'check_out_at': _iso(outAt),
      'check_out_method': outAt == null ? null : 'manual',
      'late_minutes': d.late,
      'early_leave_minutes': d.early,
      'overtime_minutes': d.overtime,
      'worked_minutes': d.worked,
      'is_manual': true,
      'tracking_off': false,
      'notes': '${body['notes'] ?? ''}'.trim().isEmpty ? null : body['notes'],
      'edit_reason': reason,
      'created_by': req.persona.userId,
      'edited_by': req.persona.userId,
      'status_overridden': status != null,
    });
    return MockResponse.created(_read(db, row));
  });

  // ── correct_record ───────────────────────────────────────────────────
  server.on('PATCH', '/staff/attendance/{id}', (req) {
    req.requireCap('hr.attendance.edit');
    final existing = records.find(req.param('id'));
    if (existing == null || existing['org_id'] != req.orgId) {
      req.notFound('Attendance record not found');
    }
    req.requireCap(
      'hr.attendance.edit',
      branchId: existing['branch_id']! as String,
    );
    final body = req.json;
    final reason = '${body['reason'] ?? ''}'.trim();
    if (reason.isEmpty) req.badRequest('A correction needs a reason');
    final day = existing['business_date']! as String;
    _assertOpen(req, db, day, 'a correction');
    final newIn = _instant(body['check_in_at']);
    final newOut = _instant(body['check_out_at']);
    final oldIn = _instant(existing['check_in_at']);
    final oldOut = _instant(existing['check_out_at']);
    if (newIn != null &&
        oldIn == null &&
        existing['covered_employee_id'] == null) {
      _refuseIfCovered(
        req,
        db,
        existing['employee_id']! as String,
        day,
        existing['work_shift_id'] as String?,
      );
    }
    final inAt = newIn ?? oldIn;
    final outAt = newOut ?? oldOut;
    if (inAt != null && outAt != null && outAt.isBefore(inAt)) {
      req.badRequest('Check-out is before check-in');
    }
    final shiftId = existing['work_shift_id'] as String?;
    final shift = shiftId == null ? null : db['work_shifts'].find(shiftId);
    final d = _derive(
      inAt,
      outAt,
      _instant(existing['scheduled_start_at']),
      _instant(existing['scheduled_end_at']),
      shift,
    );
    final override = body['status'] as String?;
    if (override != null && override != 'derived') _parseStatus(req, override);
    final (status, overridden) = switch (override) {
      'derived' => (d.status, false),
      final String s => (s, true),
      null when existing['status_overridden'] == true => (
        existing['status']! as String,
        true,
      ),
      null => (d.status, false),
    };
    // A punch the manager moves is recorded as a correction (CL-16).
    String? method(DateTime? at, DateTime? was, Object? old) =>
        at != null && at != was
        ? 'correction'
        : old as String? ?? (at == null ? null : 'manual');
    final row = records.update(existing['id']! as String, {
      'check_in_method': method(inAt, oldIn, existing['check_in_method']),
      'check_out_method': method(outAt, oldOut, existing['check_out_method']),
      'check_in_at': _iso(inAt),
      'check_out_at': _iso(outAt),
      'status': status,
      'late_minutes': d.late,
      'early_leave_minutes': d.early,
      'overtime_minutes': d.overtime,
      'worked_minutes': d.worked,
      'status_overridden': overridden,
      'edit_reason': reason,
      'edited_by': req.persona.userId,
    });
    return MockResponse.ok(_read(db, row));
  });
}
