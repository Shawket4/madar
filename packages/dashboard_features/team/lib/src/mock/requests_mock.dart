/// The mock backend of the Requests (`/staff/requests`, TEAM-REQ rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET|POST /staff/requests` (the list replaces the shared read in
///   team_reads_mock.dart with the backend's full answer)
/// - `PATCH /staff/requests/{id}/decision`
///
/// Each follows MadarRust `src/staff/requests.rs` (`list_requests`,
/// `create_request_admin`, `decide_request`): the capability and the
/// employee's branches, the request's shape by kind, a closed payroll month
/// (`PERIOD_CLOSED`), one live request per kind and time
/// (`OVERLAPPING_REQUEST`), "never your own" (`OWN_REQUEST`), a manager's
/// request decided above them (`MANAGER_REQUEST_ABOVE`), a cancel's reason
/// (`CANCEL_REASON_REQUIRED {status}`), one decision only
/// (`REQUEST_ALREADY_DECIDED {status}`), and the fields the server works out
/// for the caller (`is_own`, `can_decide`, `month_closed`, `to_owner`).
///
/// ponytail: a decision does not reprice attendance or rewrite a corrected
/// punch (the backend's `reprice_days` / `apply_correction`); add it when a
/// page reads the effect.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'team_reads_mock.dart';

const List<String> _kinds = [
  'leave',
  'late_arrival',
  'early_departure',
  'excuse',
  'mission',
  'correction',
];

Never _coded(
  MockRequest req,
  int status,
  String code,
  String words, [
  Object? vars,
]) => req.fail(MockResponse.error(status, words, code: code, vars: vars));

/// `clean`: trimmed, and a note of nothing but punctuation is no note.
String? _clean(Object? v) {
  final s = (v as String?)?.trim();
  if (s == null || !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s)) {
    return null;
  }
  return s;
}

String _hhmm(Object? t) => (t! as String).substring(0, 5);

String _nextDay(String day) {
  final d = DateTime.parse(day).add(const Duration(days: 1));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// `period_lock::closed_as` over [from]…[to]: null when every day is open,
/// else whether a closed month there is paid.
bool? requestMonthClosed(MockDb db, Object? org, String from, String to) {
  bool? paid;
  for (final p in db[TeamTables.payrollPeriods].rows) {
    final s = p['status'];
    if (p['org_id'] != org ||
        !const {'generated', 'paid', 'closed'}.contains(s)) {
      continue;
    }
    if ((p['start_date']! as String).compareTo(to) > 0) continue;
    if ((p['end_date']! as String).compareTo(from) < 0) continue;
    paid = (paid ?? false) || s != 'generated';
  }
  return paid;
}

/// `require_open_month`: 409 `PERIOD_CLOSED {date, paid}`.
void _requireOpen(MockRequest req, MockDb db, String from, String to) {
  final paid = requestMonthClosed(db, req.orgId, from, to);
  if (paid == null) return;
  _coded(
    req,
    409,
    'PERIOD_CLOSED',
    paid
        ? "That month is paid — this change dated $from can't change it. "
              'Add it to the next open month instead.'
        : "That month's payroll is approved — this change dated $from can't "
              'change it. Reopen it first, or add it to the next open month.',
    {'date': from, 'paid': paid},
  );
}

/// `is_decider`: the person behind [employee] decides requests themselves.
bool _decider(MockRow? employee) {
  final user = employee?['user_id'] as String?;
  if (user == null) return false;
  final p = Persona.byUserId(user);
  if (p != null) return p.can('hr.leave.edit');
  // ponytail: a seed person who is no persona decides by their role.
  return const {'org_admin', 'branch_manager'}.contains(employee!['role']);
}

/// `require_dominance`. ponytail: only an owner outranks a manager; no rank
/// between two owners.
bool _outranks(MockRequest req, MockRow employee) =>
    req.persona.isOwner && employee['role'] != 'org_admin';

bool _isOwn(MockRequest req, MockRow? employee) =>
    employee?['user_id'] != null && employee!['user_id'] == req.persona.userId;

/// Who did it, by name: their employee's, else their account's.
String? _nameOf(MockDb db, String user) =>
    db['employees'].firstWhere((e) => e['user_id'] == user)?['name']
        as String? ??
    Persona.byUserId(user)?.displayName;

/// `enrich` + `mark_for_caller`: what the server works out for the caller.
/// A test's own `is_own` / `can_decide` / `to_owner` on the row is kept.
MockRow requestForCaller(MockRequest req, MockDb db, MockRow r) {
  final id = r['employee_id'] as String?;
  final e = teamEmployeeRow(db, id);
  final own = r['is_own'] as bool? ?? _isOwn(req, e);
  final decider = _decider(e);
  final pending = r['status'] == 'pending';
  final may =
      !own &&
      req.persona.can('hr.leave.edit') &&
      teamSeesEmployee(req, db, id) &&
      (!decider || _outranks(req, e!));
  final on = r['on_date']! as String;
  return {
    ...r,
    'is_own': own,
    'can_decide': r['can_decide'] ?? (may && pending),
    'month_closed':
        requestMonthClosed(
          db,
          r['org_id'],
          on,
          r['end_date'] as String? ?? on,
        ) !=
        null,
    'to_owner': r['to_owner'] ?? (pending && decider),
  };
}

/// `validate_shape`: what a valid request stores beyond the body.
({String? end, String? half, String? title}) _shape(
  MockRequest req,
  Map<String, Object?> b,
) {
  Never bad(String code, String words) => _coded(req, 400, code, words);
  final kind = b['kind'];
  final on = b['on_date']! as String;
  final end = b['end_date'] as String? ?? on;
  if (b['work_shift_id'] != null &&
      !const {
        'late_arrival',
        'early_departure',
        'excuse',
        'correction',
      }.contains(kind)) {
    bad(
      'SHIFT_NOT_FOR_KIND',
      'Only a late arrival, early departure, excuse or correction names a shift',
    );
  }
  switch (kind) {
    case 'leave':
      if (end.compareTo(on) < 0) {
        bad('END_BEFORE_START', 'End date is before start date');
      }
      final half = b['is_half_day'] == true;
      if (half && end != on) {
        bad(
          'HALF_DAY_ONE_DATE',
          'A half day must start and end on the same date',
        );
      }
      final which = b['leave_half'];
      if (!half && which != null) {
        bad('HALF_ONLY_FOR_HALF_DAY', 'Only a half day says which half');
      }
      if (half && which != null && which != 'first' && which != 'second') {
        bad(
          'HALF_DAY_WHICH_HALF',
          'A half day is the first or the second half',
        );
      }
      return (
        end: end,
        half: half ? (which as String? ?? 'first') : null,
        title: null,
      );
    case 'late_arrival':
      if (b['to_time'] == null) {
        bad(
          'LATE_ARRIVAL_TIME_REQUIRED',
          'A late arrival needs the time you expect to arrive',
        );
      }
    case 'early_departure':
      if (b['from_time'] == null) {
        bad(
          'EARLY_DEPARTURE_TIME_REQUIRED',
          'An early departure needs the time you expect to leave',
        );
      }
    case 'excuse':
      if (b['from_time'] == null || b['to_time'] == null) {
        bad(
          'EXCUSE_TIMES_REQUIRED',
          'A permission needs a start and an end time',
        );
      }
      final from = _hhmm(b['from_time']);
      final to = _hhmm(b['to_time']);
      if (from == to)
        bad('WINDOW_EMPTY', 'The window must end after it starts');
      // Ending at or before it starts on the clock = past midnight.
      if (to.compareTo(from) < 0)
        return (end: _nextDay(on), half: null, title: null);
    case 'mission':
      final title = _clean(b['title']) ?? _clean(b['reason']);
      if (title == null) {
        bad(
          'MISSION_TITLE_REQUIRED',
          "A mission needs a title or a note saying where you'll be",
        );
      }
      if (end.compareTo(on) < 0) {
        bad('END_BEFORE_START', 'End date is before start date');
      }
      return (end: end, half: null, title: title);
    case 'correction':
      if (b['attendance_record_id'] == null && b['work_shift_id'] == null) {
        bad(
          'CORRECTION_TARGET_REQUIRED',
          'A correction needs the attendance record or the shift it fixes',
        );
      }
      if (b['from_time'] == null && b['to_time'] == null) {
        bad('CORRECTION_TIME_REQUIRED', 'A correction needs a proposed time');
      }
  }
  return (end: null, half: null, title: null);
}

/// The stretch of time a request holds (`staff_requests_no_overlap`).
(String, String) _window(Map<String, Object?> r) {
  final on = r['on_date']! as String;
  final from = r['from_time'] == null ? '00:00' : _hhmm(r['from_time']);
  final to = r['to_time'] == null ? '24:00' : _hhmm(r['to_time']);
  return ('$on $from', '${r['end_date'] as String? ?? on} $to');
}

/// `check_transition`: 409 `REQUEST_ALREADY_DECIDED {status}`.
void _checkTransition(MockRequest req, String existing, String decision) {
  Never decided(String why) =>
      _coded(req, 409, 'REQUEST_ALREADY_DECIDED', why, {'status': existing});
  if (existing == decision) decided('This request is already $decision');
  if (existing == 'rejected' || existing == 'cancelled') {
    decided('This request was already $existing and cannot be changed');
  }
  if (existing == 'approved' && decision == 'rejected') {
    decided('An approved request cannot be rejected — cancel it instead');
  }
}

void registerRequestsMocks(MockServer server, MockDb db) {
  MockTable table() => db[TeamTables.requests];

  // ── list_requests ─────────────────────────────────────────────────────
  server.on('GET', '/staff/requests', (req) {
    req.requireCap('hr.leave.read');
    final status = req.q('status');
    final kind = req.q('kind');
    if (status != null &&
        !const {
          'pending',
          'approved',
          'rejected',
          'cancelled',
        }.contains(status)) {
      _coded(
        req,
        400,
        'STATUS_UNKNOWN',
        "Unknown status '$status' — expected pending, approved, rejected, or cancelled",
        {'status': status},
      );
    }
    if (kind != null && !_kinds.contains(kind)) {
      _coded(
        req,
        400,
        'REQUEST_KIND_UNKNOWN',
        "Unknown request kind '$kind' — expected one of ${_kinds.join(', ')}",
        {'kind': kind},
      );
    }
    final from = req.q('from');
    final to = req.q('to');
    final rows =
        table().query(
          filters: {
            'org_id': req.orgId,
            'employee_id': req.q('employee_id'),
            'kind': kind,
            'status': status,
          },
          where: (r) {
            final on = r['on_date']! as String;
            final end = r['end_date'] as String? ?? on;
            if (from != null && end.compareTo(from) < 0) return false;
            if (to != null && on.compareTo(to) > 0) return false;
            return teamSeesEmployee(req, db, r['employee_id'] as String?);
          },
        )..sort((a, b) {
          // Pending first, then the latest day, then the newest.
          final p =
              (b['status'] == 'pending' ? 1 : 0) -
              (a['status'] == 'pending' ? 1 : 0);
          if (p != 0) return p;
          final d = compareJson(b['on_date'], a['on_date']);
          return d != 0 ? d : compareJson(b['created_at'], a['created_at']);
        });
    return MockResponse.ok([
      for (final r in rows) requestForCaller(req, db, r),
    ]);
  });

  // ── create_request_admin ──────────────────────────────────────────────
  server.on('POST', '/staff/requests', (req) {
    req.requireCap('hr.leave.create');
    final b = req.json;
    final employeeId = b['employee_id'] as String?;
    if (employeeId == null) {
      _coded(req, 400, 'EMPLOYEE_REQUIRED', 'employee_id is required');
    }
    final e = teamEmployeeRow(db, employeeId);
    if (e == null || e['org_id'] != req.orgId) {
      _coded(req, 404, 'EMPLOYEE_NOT_FOUND', 'Employee not found');
    }
    if (!teamSeesEmployee(req, db, employeeId)) {
      req.fail(MockResponse.denied('hr.leave.create'));
    }
    final kind = b['kind'] as String? ?? '';
    final on = b['on_date'] as String?;
    if (on == null)
      req.badRequest('Json deserialize error: missing field `on_date`');
    // Approved as it is filed: the filer's own, with the right (RQ-5).
    final selfApproves =
        _isOwn(req, e) && req.persona.can('hr.requests.self_approve');
    if (kind == 'leave' && b['is_paid'] == null && selfApproves) {
      _coded(
        req,
        400,
        'LEAVE_PAY_REQUIRED',
        'Say whether this leave is paid or unpaid: it is approved as it is filed.',
        const <String, Object?>{},
      );
    }
    if (!_kinds.contains(kind)) {
      _coded(
        req,
        400,
        'REQUEST_KIND_UNKNOWN',
        "Unknown request kind '$kind' — expected one of ${_kinds.join(', ')}",
        {'kind': kind},
      );
    }
    final shape = _shape(req, b);
    _requireOpen(req, db, on, shape.end ?? on);
    final row = <String, Object?>{
      'org_id': e['org_id'],
      'employee_id': employeeId,
      'employee_name': e['name'],
      'kind': kind,
      'status': 'pending',
      'on_date': on,
      'end_date': shape.end,
      'from_time': b['from_time'],
      'to_time': b['to_time'],
      'is_half_day': b['is_half_day'] ?? false,
      'leave_half': shape.half,
      'work_shift_id': b['work_shift_id'],
      'title': shape.title,
      'location': _clean(b['location']),
      'attendance_record_id': b['attendance_record_id'],
      'reason': _clean(b['reason']),
    };
    final (start, end) = _window(row);
    final clash = table().firstWhere((r) {
      if (r['employee_id'] != employeeId || r['kind'] != kind) return false;
      if (kind == 'correction') return false;
      if (r['status'] != 'pending' && r['status'] != 'approved') return false;
      final (s, e) = _window(r);
      return s.compareTo(end) < 0 && start.compareTo(e) < 0;
    });
    if (clash != null) {
      _coded(
        req,
        409,
        'OVERLAPPING_REQUEST',
        'You already have a request like this for that time.',
      );
    }
    final stored = table().insert(row);
    if (selfApproves) {
      final user = req.persona.userId;
      table().update(stored['id']! as String, {
        'status': 'approved',
        'decided_by': user,
        'decided_at': db.nowIso,
        'decided_by_name': _nameOf(db, user),
        'is_paid': switch (kind) {
          'leave' => b['is_paid'],
          // ponytail: the rule's default is the business's (paid).
          'excuse' || 'early_departure' => b['is_paid'] ?? true,
          _ => null,
        },
      });
    }
    return MockResponse.created(requestForCaller(req, db, stored));
  });

  // ── decide_request ────────────────────────────────────────────────────
  server.on('PATCH', '/staff/requests/{id}/decision', (req) {
    final body = req.json;
    final decision = body['status'] as String? ?? '';
    // Only cancelling one's own needs no right; anything else is refused
    // before the request is looked up.
    if (decision != 'cancelled') req.requireCap('hr.leave.edit');
    if (decision != 'approved' &&
        decision != 'rejected' &&
        decision != 'cancelled') {
      _coded(
        req,
        400,
        'STATUS_UNKNOWN',
        "Unknown decision '$decision' — expected approved, rejected, or cancelled",
        {'status': decision},
      );
    }
    final row = table().find(req.param('id'));
    if (row == null || row['org_id'] != req.orgId) {
      _coded(req, 404, 'REQUEST_NOT_FOUND', 'Request not found');
    }
    final employeeId = row['employee_id'] as String?;
    final e = teamEmployeeRow(db, employeeId);
    final own = _isOwn(req, e);
    if (!(decision == 'cancelled' && own)) {
      req.requireCap('hr.leave.edit');
      if (!teamSeesEmployee(req, db, employeeId)) {
        req.fail(MockResponse.denied('hr.leave.edit'));
      }
      if (own) {
        _coded(
          req,
          403,
          'OWN_REQUEST',
          'Your own requests are decided by someone above you.',
        );
      }
      if (_decider(e) && !_outranks(req, e!)) {
        _coded(
          req,
          403,
          'MANAGER_REQUEST_ABOVE',
          "A manager's own request is decided by someone above them, usually the owner.",
        );
      }
    }
    final status = row['status']! as String;
    final kind = row['kind']! as String;
    final note = _clean(body['note']);
    if (decision == 'cancelled') {
      if ((!own || status == 'approved') && note == null) {
        _coded(
          req,
          400,
          'CANCEL_REASON_REQUIRED',
          status == 'approved'
              ? 'Say why this approved request is cancelled'
              : "Say why you are cancelling someone else's request",
          {'status': status},
        );
      }
      if (kind == 'correction' && status == 'approved') {
        _coded(
          req,
          409,
          'CORRECTION_APPLIED',
          'An approved correction has already rewritten the punch — correct '
              'the attendance record instead',
        );
      }
    }
    if (decision == 'approved' && kind == 'leave' && body['is_paid'] == null) {
      _coded(
        req,
        400,
        'LEAVE_PAY_REQUIRED',
        'Say whether this leave is paid or unpaid',
      );
    }
    final on = row['on_date']! as String;
    if (decision != 'rejected') {
      _requireOpen(req, db, on, row['end_date'] as String? ?? on);
    }
    _checkTransition(req, status, decision);
    final user = req.persona.userId;
    final paid = switch ((decision, kind)) {
      ('approved', 'leave') => body['is_paid'],
      // ponytail: the rule's default is the business's (paid).
      ('approved', 'excuse' || 'early_departure') =>
        body['is_paid'] ?? row['paid_default'] ?? true,
      _ => null,
    };
    // A cancellation has its own who / when / why; the approval stays.
    final updated = table().update(row['id']! as String, {
      'status': decision,
      if (decision == 'cancelled') ...{
        'cancelled_by': user,
        'cancelled_at': db.nowIso,
        'cancel_note': note,
        'cancelled_by_name': _nameOf(db, user),
      } else ...{
        'decided_by': user,
        'decided_at': db.nowIso,
        'decision_note': note,
        'decided_by_name': _nameOf(db, user),
      },
      'is_paid': ?paid,
    });
    return MockResponse.ok(requestForCaller(req, db, updated));
  });
}
