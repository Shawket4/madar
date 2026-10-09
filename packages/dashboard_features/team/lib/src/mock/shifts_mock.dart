/// The mock backend of the Work shifts (`/staff/shifts`, TEAM-SHF rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET|POST /staff/work-shifts` (GET replaces the core's)
/// - `PATCH|DELETE /staff/work-shifts/{id}`
/// - `GET|POST /staff/schedules`
/// - `DELETE /staff/schedules/{id}`
///
/// Like the backend (`MadarRust src/staff/schedules.rs`): a block belongs to
/// a branch or to the whole business (which needs the right at every
/// branch); a branch-scoped caller sees the business's blocks and their own
/// branches'; a block's own weekday times live on its row (`day_times`, as
/// the Schedule unit reads them) and its presence-cap warning is worked out
/// on every read from the business's `limit_presence_hours`; a weekday taken
/// away while people are rostered on it is refused (`SHIFT_DAYS_IN_USE`), a
/// block still on the roster is not deleted (`SHIFT_IN_USE`), and a roster
/// row that would make someone's shifts overlap is refused
/// (`SHIFTS_OVERLAP`).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'team_reads_mock.dart' show teamEmployeeRow, teamSeesEmployee;

const List<int> _allDays = [0, 1, 2, 3, 4, 5, 6];

String _sec(Object? v) {
  final s = '$v';
  return s.length == 5 ? '$s:00' : s;
}

int _min(Object? v) {
  final p = '$v'.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

/// Minutes from start to end, past midnight when the end is at or before
/// the start (`span_of_times`).
int _span(Object? start, Object? end) {
  final m = _min(end) - _min(start);
  return m <= 0 ? m + 1440 : m;
}

List<int> _days(MockRow w) =>
    ((w['valid_days'] as List?) ?? _allDays).cast<num>().map((n) => n.toInt()).toList();

List<Map<String, Object?>> _dayTimes(MockRow w) => [
  for (final d in ((w['day_times'] as List?) ?? const []).cast<Map>())
    d.cast<String, Object?>(),
];

/// The business's presence cap in minutes (`Limits::of(settings).presence`).
int _presenceCap(MockDb db, String? orgId) {
  final s = db['attendance_settings'].firstWhere((r) => r['org_id'] == orgId);
  final hours = (s?['limit_presence_hours'] as num?) ?? 10;
  return (hours * 60).round();
}

/// A block as the API answers it (`complete_shifts`).
MockRow shiftAsRead(MockDb db, MockRow w) {
  final cap = _presenceCap(db, w['org_id'] as String?);
  final times = [
    for (final d in _dayTimes(w))
      {
        'day_of_week': d['day_of_week'],
        'start_time': _sec(d['start_time']),
        'end_time': _sec(d['end_time']),
      },
  ]..sort((a, b) => (a['day_of_week']! as num).compareTo(b['day_of_week']! as num));
  return {
    'grace_minutes': 15,
    'break_minutes': 0,
    'paid_break': true,
    'overtime_threshold_minutes': 15,
    'overtime_multiplier': 1.5,
    'checkin_window_minutes': 120,
    'is_active': true,
    ...w,
    'start_time': _sec(w['start_time']),
    'end_time': _sec(w['end_time']),
    'valid_days': _days(w),
    'crosses_midnight': _min(w['end_time']) <= _min(w['start_time']),
    'day_times': times,
    'over_presence_cap':
        _span(w['start_time'], w['end_time']) > cap ||
        times.any((d) => _span(d['start_time'], d['end_time']) > cap),
  };
}

void registerShiftsMocks(MockServer server, MockDb db) {
  final shifts = db['work_shifts'];
  final roster = db[TeamTables.assignments];

  Never coded(MockRequest req, int status, String code, String reason, [Object? vars]) =>
      req.fail(MockResponse.error(status, reason, code: code, vars: vars));

  /// `require_at`: the right at [branch] (in this org).
  void requireAt(MockRequest req, String cap, String branch) {
    final b = db['branches'].find(branch);
    if (b == null) coded(req, 404, 'BRANCH_NOT_FOUND', 'Branch not found');
    if (b['org_id'] != req.orgId) {
      req.fail(MockResponse.forbidden('Branch belongs to a different org'));
    }
    req.requireCap(cap, branchId: branch);
  }

  /// `require_shift_scope`: a branch's block is its manager's; a
  /// business-wide one needs the right at every branch.
  void requireScope(MockRequest req, String cap, String? branch) {
    if (branch != null) return requireAt(req, cap, branch);
    req.requireCap(cap);
    if (req.persona.branchIds != null) {
      final meta = mockCapabilities.where((c) => c.key == cap);
      req.fail(
        MockResponse.forbidden(
          'This needs ${meta.isEmpty ? cap : meta.first.en} for every branch ($cap).',
        ),
      );
    }
  }

  MockRow block(MockRequest req, String id) {
    final w = shifts.find(id);
    if (w == null || w['org_id'] != req.orgId) {
      coded(req, 404, 'SHIFT_NOT_FOUND', 'Work shift not found');
    }
    return w;
  }

  Never settingInvalid(MockRequest req, String field, String reason) =>
      coded(req, 400, 'SHIFT_SETTING_INVALID', reason, {'field': field});

  /// `validate_work_shift`.
  String validate(MockRequest req, MockRow b) {
    final name = '${b['name'] ?? ''}'.trim();
    if (name.isEmpty) {
      coded(req, 400, 'SHIFT_NAME_REQUIRED', 'Shift name is required');
    }
    if (b['start_time'] == b['end_time']) {
      coded(req, 400, 'SHIFT_EMPTY', 'A shift cannot start and end at the same time');
    }
    num? n(String k) => b[k] as num?;
    for (final k in const ['grace_minutes', 'break_minutes', 'overtime_threshold_minutes']) {
      if ((n(k) ?? 0) < 0) settingInvalid(req, k, '$k cannot be negative');
    }
    for (final k in const ['checkin_window_minutes', 'half_day_threshold_minutes', 'overtime_multiplier']) {
      if (n(k) != null && n(k)! <= 0) settingInvalid(req, k, '$k must be positive');
    }
    for (final k in const ['ot_day_multiplier', 'ot_night_multiplier']) {
      if (n(k) != null && (n(k)! <= 0 || n(k)! >= 100)) {
        settingInvalid(req, k, '$k must be above 0 and below 100');
      }
    }
    final days = b['valid_days'] as List?;
    if (days != null && (days.isEmpty || days.any((d) => d is! num || d < 0 || d > 6))) {
      coded(req, 400, 'SHIFT_DAYS_REQUIRED',
          'valid_days needs at least one day, 0 (Sunday) through 6 (Saturday)');
    }
    final times = (b['day_times'] as List?)?.cast<Map>();
    if (times != null) {
      final seen = <Object?>{};
      for (final d in times) {
        final dow = d['day_of_week'];
        if (dow is! num || dow < 0 || dow > 6 || !seen.add(dow)) {
          coded(req, 400, 'SHIFT_DAY_TIMES_INVALID',
              'day_times: one entry per day, 0 (Sunday) through 6 (Saturday)');
        }
        if (d['start_time'] == d['end_time']) {
          coded(req, 400, 'SHIFT_EMPTY', 'A shift cannot start and end at the same time');
        }
      }
    }
    return name;
  }

  /// `refuse_times_off_days`.
  void timesOnDays(MockRequest req, List<int> days, List times) {
    for (final d in times.cast<Map>()) {
      if (!days.contains(d['day_of_week'])) {
        coded(req, 400, 'SHIFT_DAY_TIMES_OFF_DAY',
            "day ${d['day_of_week']} has its own times but isn't one of the block's days",
            {'day_of_week': d['day_of_week']});
      }
    }
  }

  // ── work shifts ─────────────────────────────────────────────────────

  server.on('GET', '/staff/work-shifts', (req) {
    req.requireCap('hr.schedule.read');
    final rows = shifts.where(
      (w) =>
          w['org_id'] == req.orgId &&
          (w['branch_id'] == null ||
              req.persona.seesBranch('${w['branch_id']}')),
    )..sort((a, b) {
        final c = _sec(a['start_time']).compareTo(_sec(b['start_time']));
        return c != 0
            ? c
            : '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());
      });
    return MockResponse.ok([for (final w in rows) shiftAsRead(db, w)]);
  });

  server.on('POST', '/staff/work-shifts', (req) {
    req.requireCap('hr.schedule.create');
    final b = req.json;
    final branch = b['branch_id'] as String?;
    requireScope(req, 'hr.schedule.create', branch);
    final name = validate(req, b);
    final days = ((b['valid_days'] as List?) ?? _allDays).cast<num>().map((n) => n.toInt()).toList();
    final times = (b['day_times'] as List?) ?? const [];
    timesOnDays(req, days, times);
    final row = shifts.insert({
      'org_id': req.orgId,
      'branch_id': branch,
      'name': name,
      'start_time': _sec(b['start_time']),
      'end_time': _sec(b['end_time']),
      'grace_minutes': b['grace_minutes'] ?? 15,
      'break_minutes': b['break_minutes'] ?? 0,
      'paid_break': b['paid_break'] ?? true,
      'half_day_threshold_minutes': b['half_day_threshold_minutes'],
      'overtime_threshold_minutes': b['overtime_threshold_minutes'] ?? 15,
      'overtime_multiplier': b['overtime_multiplier'] ?? 1.5,
      'checkin_window_minutes': b['checkin_window_minutes'] ?? 120,
      'is_active': b['is_active'] ?? true,
      'valid_days': days,
      'ot_day_multiplier': b['ot_day_multiplier'],
      'ot_night_multiplier': b['ot_night_multiplier'],
      'day_times': times,
    });
    return MockResponse.created(shiftAsRead(db, row));
  });

  server.on('PATCH', '/staff/work-shifts/{id}', (req) {
    req.requireCap('hr.schedule.edit');
    final w = block(req, req.param('id'));
    final current = w['branch_id'] as String?;
    requireScope(req, 'hr.schedule.edit', current);
    final b = req.json;
    // Omitted keeps the branch; only an explicit null moves the block to
    // the whole business.
    final branch = b.containsKey('branch_id') ? b['branch_id'] as String? : current;
    if (branch != current) requireScope(req, 'hr.schedule.edit', branch);
    final name = validate(req, b);
    final days = b['valid_days'] == null
        ? _days(w)
        : (b['valid_days']! as List).cast<num>().map((n) => n.toInt()).toList();
    final times = (b['day_times'] as List?) ?? _dayTimes(w);
    timesOnDays(req, days, times);
    // Taking a day away while people are rostered on it would silently
    // unroster them: move them first.
    final dropped = [for (final d in _days(w)) if (!days.contains(d)) d];
    if (dropped.isNotEmpty) {
      final today = db.clock.today;
      final stuck = roster.where(
        (a) =>
            a['work_shift_id'] == w['id'] &&
            dropped.contains(a['day_of_week']) &&
            (a['effective_to'] == null || '${a['effective_to']}'.compareTo(today) >= 0),
      ).length;
      if (stuck > 0) {
        coded(req, 409, 'SHIFT_DAYS_IN_USE',
            '$stuck roster entr${stuck == 1 ? 'y' : 'ies'} still put ${w['name']} on the days you took away — move them first.',
            {'n': stuck, 'name': w['name'], 'days': dropped});
      }
    }
    num? keep(String k) => (b[k] as num?) ?? (w[k] as num?);
    final row = shifts.update('${w['id']}', {
      'branch_id': branch,
      'name': name,
      'start_time': _sec(b['start_time']),
      'end_time': _sec(b['end_time']),
      'grace_minutes': keep('grace_minutes'),
      'break_minutes': keep('break_minutes'),
      'paid_break': b['paid_break'] ?? w['paid_break'],
      'half_day_threshold_minutes': b['half_day_threshold_minutes'],
      'overtime_threshold_minutes': keep('overtime_threshold_minutes'),
      'overtime_multiplier': keep('overtime_multiplier'),
      'checkin_window_minutes': keep('checkin_window_minutes'),
      'is_active': b['is_active'] ?? w['is_active'],
      'valid_days': days,
      if (b.containsKey('ot_day_multiplier')) 'ot_day_multiplier': b['ot_day_multiplier'],
      if (b.containsKey('ot_night_multiplier')) 'ot_night_multiplier': b['ot_night_multiplier'],
      'day_times': times,
    });
    for (final a in roster.where((a) => a['work_shift_id'] == w['id'])) {
      a['work_shift_name'] = row['name'];
    }
    return MockResponse.ok(shiftAsRead(db, row));
  });

  server.on('DELETE', '/staff/work-shifts/{id}', (req) {
    req.requireCap('hr.schedule.delete');
    final w = block(req, req.param('id'));
    requireScope(req, 'hr.schedule.delete', w['branch_id'] as String?);
    final n = roster.where((a) => a['work_shift_id'] == w['id']).length;
    if (n > 0) {
      coded(req, 409, 'SHIFT_IN_USE',
          '$n roster assignment(s) still use ${w['name']} — remove them first, or switch the shift off instead',
          {'n': n, 'name': w['name']});
    }
    shifts.delete('${w['id']}');
    return MockResponse.empty();
  });

  // ── the standing roster ─────────────────────────────────────────────

  server.on('GET', '/staff/schedules', (req) {
    req.requireCap('hr.schedule.read');
    final who = req.q('employee_id');
    final rows = roster.where(
      (a) =>
          (who == null || a['employee_id'] == who) &&
          a['org_id'] == req.orgId &&
          teamSeesEmployee(req, db, a['employee_id'] as String?),
    );
    int dayKey(MockRow a) => (a['day_of_week'] as num?)?.toInt() ?? 7;
    rows.sort((a, b) {
      var c = '${a['employee_id']}'.compareTo('${b['employee_id']}');
      if (c != 0) return c;
      c = '${b['effective_from']}'.compareTo('${a['effective_from']}');
      if (c != 0) return c;
      c = dayKey(a).compareTo(dayKey(b));
      if (c != 0) return c;
      final wa = shifts.find('${a['work_shift_id']}');
      final wb = shifts.find('${b['work_shift_id']}');
      return _sec(wa?['start_time']).compareTo(_sec(wb?['start_time']));
    });
    return MockResponse.ok([
      for (final a in rows)
        {...a, 'work_shift_name': shifts.find('${a['work_shift_id']}')?['name']},
    ]);
  });

  /// `access::subject` + `require_for`: the person, and the right at one of
  /// their branches.
  MockRow subject(MockRequest req, String? employeeId) {
    final e = teamEmployeeRow(db, employeeId);
    if (e == null || e['org_id'] != req.orgId) {
      coded(req, 404, 'EMPLOYEE_NOT_FOUND', 'Employee not found');
    }
    req.requireCap('hr.schedule.edit');
    if (!teamSeesEmployee(req, db, employeeId)) {
      req.fail(MockResponse.denied('hr.schedule.edit'));
    }
    return e;
  }

  server.on('POST', '/staff/schedules', (req) {
    req.requireCap('hr.schedule.edit');
    final b = req.json;
    final e = subject(req, b['employee_id'] as String?);
    final dow = (b['day_of_week'] as num?)?.toInt();
    if (dow != null && (dow < 0 || dow > 6)) {
      coded(req, 400, 'DAY_OF_WEEK_INVALID', 'day_of_week must be 0 (Sunday) through 6 (Saturday)');
    }
    final w = block(req, '${b['work_shift_id']}');
    final own = w['branch_id'] as String?;
    if (own != null) requireAt(req, 'hr.schedule.edit', own);
    if (dow != null && !_days(w).contains(dow)) {
      coded(req, 400, 'SHIFT_NOT_ON_DAY', "${w['name']} isn't a shift on that weekday.");
    }
    final branches = ((e['branch_ids'] as List?) ?? const []).cast<String>();
    if (own != null && !branches.contains(own)) {
      coded(req, 400, 'SHIFT_OTHER_BRANCH', "${w['name']} doesn't work at ${e['name']}'s branch.");
    }
    final at = b['branch_id'] as String?;
    final row = <String, Object?>{
      'id': db.newId(TeamTables.assignments),
      'org_id': req.orgId,
      'employee_id': e['id'],
      'work_shift_id': w['id'],
      'work_shift_name': w['name'],
      'day_of_week': dow,
      'effective_from': b['effective_from'] ?? db.clock.today,
      'effective_to': b['effective_to'],
      'created_at': db.nowIso,
      'branch_id': own == null && at != null && branches.contains(at) ? at : null,
    };
    _refuseOverlap(req, db, '${e['id']}', [row, ...roster.rows]);
    roster.insert(row, timestamps: false);
    return MockResponse.created(row);
  });

  server.on('DELETE', '/staff/schedules/{id}', (req) {
    req.requireCap('hr.schedule.edit');
    final a = roster.find(req.param('id'));
    if (a == null || a['org_id'] != req.orgId) {
      coded(req, 404, 'ASSIGNMENT_NOT_FOUND', 'Assignment not found');
    }
    subject(req, a['employee_id'] as String?);
    roster.delete('${a['id']}');
    return MockResponse.empty();
  });
}

/// `check_overlaps` over the next two weeks of the standing pattern [rows]
/// (newest first per slot; a weekday's own row beats the every-day row): a
/// night that runs into the next day's block is refused, naming both.
void _refuseOverlap(MockRequest req, MockDb db, String employeeId, List<MockRow> rows) {
  final mine = [
    for (final a in rows)
      if (a['employee_id'] == employeeId) a,
  ]..sort((a, b) => '${b['effective_from']}'.compareTo('${a['effective_from']}'));
  ({String name, String date, int from, int to})? on(DateTime day, int index) {
    final dow = day.weekday % 7;
    MockRow? pick(int? d) => mine.where((a) => a['day_of_week'] == d).firstOrNull;
    final a = pick(dow) ?? pick(null);
    if (a == null) return null;
    final w = db['work_shifts'].find('${a['work_shift_id']}');
    if (w == null || w['is_active'] == false || !_days(w).contains(dow)) return null;
    final own = _dayTimes(w).where((d) => d['day_of_week'] == dow).firstOrNull;
    final start = _min(own?['start_time'] ?? w['start_time']);
    final from = index * 1440 + start;
    final iso = day.toIso8601String().substring(0, 10);
    return (
      name: '${w['name']}',
      date: iso,
      from: from,
      to: from + _span(own?['start_time'] ?? w['start_time'], own?['end_time'] ?? w['end_time']),
    );
  }

  final p = db.clock.today.split('-').map(int.parse).toList();
  final first = DateTime.utc(p[0], p[1], p[2]);
  final days = [for (var i = 0; i <= 15; i++) on(first.add(Duration(days: i)), i)];
  for (var i = 0; i + 1 < days.length; i++) {
    final a = days[i];
    final b = days[i + 1];
    if (a != null && b != null && a.to > b.from) {
      req.fail(
        MockResponse.error(
          409,
          '${a.name} on ${a.date} and ${b.name} on ${b.date} overlap.',
          code: 'SHIFTS_OVERLAP',
          vars: {'a': a.name, 'b': b.name, 'date': a.date, 'a_date': a.date, 'b_date': b.date},
        ),
      );
    }
  }
}
