/// The mock backend of the Schedule (`/staff/schedule`, TEAM-SCH rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/roster`
/// - `GET|PUT /staff/roster/coverage`
/// - `GET /staff/roster/fairness`
/// - `GET /staff/roster/fairness/audits`
/// - `POST /staff/roster/publish`
/// - `GET /staff/roster/suggestions`
/// - `POST /staff/roster/suggestions/decide`
/// - `PUT /staff/holidays/{date}`
/// - `PUT|DELETE /staff/schedules/days`
/// - `POST /staff/schedules/days/move`
/// - `PUT /staff/schedules/days/times`
/// - `POST /staff/open-shifts` (the list is shared: team_reads_mock.dart)
/// - `POST /staff/open-shifts/{id}/cancel`
/// - `PUT /staff/employees/{id}/preferences`
/// - `GET /staff/employees/{id}/preferences/log`
///
/// Like the backend (`MadarRust src/staff/dawam/roster.rs`, `suggest.rs`,
/// `holidays.rs`, `src/staff/schedules.rs`): a person's day is the date's own
/// set when it has one, else the standing pattern (the area seed's
/// assignments); the roster partitions it into this branch's shifts and
/// the ones worked elsewhere; labour limits warn and never block; overlaps
/// are refused (409 `SHIFTS_OVERLAP`); a change to a published week marks
/// the day changed.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/week.dart';
import 'team_reads_mock.dart' show teamOrgOfBranch, teamSeesEmployee;

/// This unit's own tables.
abstract final class ScheduleTables {
  /// `{id: emp|date, employee_id, on_date, blocks: [{work_shift_id,
  /// start_time, end_time, branch_id}]}`: a date holding its own set.
  static const String daySets = 'roster_day_sets';

  /// `{id: emp|date}`: days changed after their week was published.
  static const String changed = 'roster_changed';

  /// `{id: branch|week, branch_id, week_start}`.
  static const String publications = 'week_publications';

  /// `{id, org_id, branch_id, day_of_week, band_start, band_end, staff,
  /// department_id}`.
  static const String coverage = 'coverage_needs';

  /// `{id: org|date, org_id, on_date, name_en, name_ar, decision,
  /// decided_by, decided_at}`.
  static const String holidays = 'public_holidays';

  /// `{id, employee_id, source, pref_time, cant_work_days, changed_by_name,
  /// note, created_at}`.
  static const String prefLog = 'preference_log';

  /// Suggestions the engine keeps beside the gaps it finds (pattern ones):
  /// `{id, branch_id, week_start, ...Suggestion}`.
  static const String suggestions = 'roster_suggestions';

  /// `{id: branch|suggestion, branch_id, suggestion_id, accept, by_default,
  /// decided_at}`.
  static const String decisions = 'suggestion_decisions';

  /// `{id, org_id, branch_id, month, flagged, computed_at, report}`.
  static const String audits = 'fairness_audits';

  static const String loaded = '_schedule_seed';
}

void registerScheduleMocks(MockServer server, MockDb db) {
  _seed(db);
  final r = _Roster(db);

  server.on('GET', '/staff/roster', (req) {
    final branchId = _branch(req, db, 'hr.schedule.read', req.q('branch_id'));
    final (from, to) = _range(req);
    return MockResponse.ok(r.view(req, branchId, from, to));
  });

  server.on('POST', '/staff/roster/publish', (req) {
    final body = req.body as Map? ?? const {};
    final branchId = _branch(
      req,
      db,
      'hr.schedule.publish',
      body['branch_id'] as String?,
    );
    final week = weekStartOf(_date(req, body['week_start']));
    db[ScheduleTables.publications].put({
      'id': '$branchId|$week',
      'branch_id': branchId,
      'week_start': week,
    });
    return MockResponse.empty();
  });

  // ── open shifts ──────────────────────────────────────────────────────
  server.on('POST', '/staff/open-shifts', (req) {
    final body = req.body as Map? ?? const {};
    final branchId = _branch(
      req,
      db,
      'hr.schedule.edit',
      body['branch_id'] as String?,
    );
    final date = _date(req, body['on_date']);
    final block = r.block(req, body['work_shift_id'] as String?);
    r.checkBlock(req, block, date, branchId);
    final at = r.timesOn(block, weekdayOf(date));
    if (_instant(date, at.$1).isBefore(req.now)) {
      req.conflict('That shift has already started.', code: 'SHIFT_STARTED');
    }
    final row = db[TeamTables.openShifts].insert({
      'branch_id': branchId,
      'work_shift_id': block['id'],
      'shift_name': block['name'],
      'on_date': date,
      'start_at': _instant(date, at.$1).toIso8601String(),
      'end_at': _instant(date, at.$2, nextDay: _crosses(at)).toIso8601String(),
      'status': 'open',
    }, timestamps: false);
    return MockResponse.created(row);
  });

  server.on('POST', '/staff/open-shifts/{id}/cancel', (req) {
    req.requireCap('hr.schedule.edit');
    final row = db[TeamTables.openShifts].find(req.param('id'));
    if (row == null ||
        teamOrgOfBranch(db, row['branch_id'] as String?) != req.orgId) {
      req.fail(
        MockResponse.error(
          404,
          'No open shift here.',
          code: 'OPEN_SHIFT_NOT_FOUND',
        ),
      );
    }
    req.requireBranch(row['branch_id']! as String);
    final status = row['status'] as String?;
    if (status != 'open' && status != 'claimed') {
      req.fail(
        MockResponse.error(
          409,
          'That shift was already filled or cancelled.',
          code: 'OPEN_SHIFT_CLOSED',
          vars: {'status': status},
        ),
      );
    }
    row['status'] = 'cancelled';
    return MockResponse.empty();
  });

  // ── suggestions ──────────────────────────────────────────────────────
  server.on('GET', '/staff/roster/suggestions', (req) {
    final branchId = _branch(req, db, 'hr.schedule.edit', req.q('branch_id'));
    final week = weekStartOf(_date(req, req.q('week_start')));
    return MockResponse.ok(r.suggestions(req, branchId, week));
  });

  server.on('POST', '/staff/roster/suggestions/decide', (req) {
    final body = req.body as Map? ?? const {};
    final branchId = _branch(
      req,
      db,
      'hr.schedule.edit',
      body['branch_id'] as String?,
    );
    final id = body['id'] as String? ?? '';
    final parts = id.split('|');
    final date = parts.length > 1 ? parts[1] : '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      req.badRequest('Unknown suggestion');
    }
    final s = r
        .suggestions(req, branchId, weekStartOf(date))
        .where((g) => g['id'] == id)
        .firstOrNull;
    if (s == null) {
      req.conflict(
        'That suggestion no longer applies — refresh the suggestions.',
        code: 'SUGGESTION_STALE',
      );
    }
    final accept = body['accept'] == true;
    if (accept) r.apply(s, branchId);
    db[ScheduleTables.decisions].put({
      'id': '$branchId|$id',
      'branch_id': branchId,
      'suggestion_id': id,
      'accept': accept,
      'by_default': s['by_default'],
      'decided_at': req.now.toIso8601String(),
    });
    return MockResponse.empty();
  });

  // ── coverage ─────────────────────────────────────────────────────────
  server.on('GET', '/staff/roster/coverage', (req) {
    final branchId = _branch(req, db, 'hr.schedule.read', req.q('branch_id'));
    final needs = [
      for (final n in db[ScheduleTables.coverage].where(
        (n) => n['branch_id'] == branchId,
      ))
        _need(n),
    ];
    final settings = r.settings(req.orgId);
    final perStaff = (settings?['orders_per_staff'] as num?)?.toInt() ?? 25;
    final pos = ((db['orgs'].find(req.orgId ?? '')?['modules'] as List?) ?? [])
        .contains('pos');
    final derived = pos ? _posNeeds() : const <MockRow>[];
    return MockResponse.ok({
      'source': needs.isNotEmpty
          ? 'grid'
          : derived.isNotEmpty
          ? 'pos'
          : 'pattern',
      'needs': needs,
      'derived': derived,
      'orders_per_staff': perStaff,
    });
  });

  server.on('PUT', '/staff/roster/coverage', (req) {
    final body = req.body as Map? ?? const {};
    final branchId = _branch(
      req,
      db,
      'hr.schedule.edit',
      body['branch_id'] as String?,
    );
    final needs = (body['needs'] as List?) ?? const [];
    for (final n in needs.cast<Map>()) {
      final staff = (n['staff'] as num?)?.toInt() ?? -1;
      final dow = (n['day_of_week'] as num?)?.toInt() ?? -1;
      final a = '${n['band_start']}';
      final b = '${n['band_end']}';
      if (staff < 0 || dow < 0 || dow > 6 || a.compareTo(b) >= 0) {
        req.badRequest('Each need is a weekday, a band and a head count.');
      }
    }
    db[ScheduleTables.coverage].removeWhere((n) => n['branch_id'] == branchId);
    for (final n in needs.cast<Map>()) {
      db[ScheduleTables.coverage].insert({
        'org_id': req.orgId,
        'branch_id': branchId,
        'day_of_week': n['day_of_week'],
        'band_start': n['band_start'],
        'band_end': n['band_end'],
        'staff': n['staff'],
        'department_id': n['department_id'],
      }, timestamps: false);
    }
    return MockResponse.empty();
  });

  // ── fairness (owner: the right at every branch) ──────────────────────
  server.on('GET', '/staff/roster/fairness', (req) {
    _requireEverywhere(req, 'hr.roster.settings');
    final month = req.q('month');
    if (month == null || !RegExp(r'^\d{4}-\d{2}-01$').hasMatch(month)) {
      req.badRequest('Query deserialize error: month is the first of a month');
    }
    return MockResponse.ok(r.fairness(req, month));
  });

  server.on('GET', '/staff/roster/fairness/audits', (req) {
    _requireEverywhere(req, 'hr.roster.settings');
    return MockResponse.ok(
      db[ScheduleTables.audits].query(
        filters: {'org_id': req.orgId},
        sort: '-month',
      ),
    );
  });

  // ── public holidays (owner decision D3) ──────────────────────────────
  server.on('PUT', '/staff/holidays/{date}', (req) {
    if (!(req.persona.can('hr.rules.edit') && req.persona.branchIds == null)) {
      req.fail(
        MockResponse.error(
          403,
          'Only the owner decides public holidays.',
          code: 'OWNER_ONLY',
        ),
      );
    }
    final decision = (req.body as Map?)?['decision'];
    if (decision != 'holiday' && decision != 'dismissed') {
      req.badRequest('decision is holiday or dismissed');
    }
    final row = db[ScheduleTables.holidays].find(
      '${req.orgId}|${req.param('date')}',
    );
    if (row == null) req.notFound('No public holiday on that date.');
    row
      ..['decision'] = decision
      ..['decided_by'] = req.persona.userId
      ..['decided_at'] = req.now.toIso8601String();
    return MockResponse.ok(_holiday(row));
  });

  // ── one person's date ────────────────────────────────────────────────
  server.on('PUT', '/staff/schedules/days', (req) {
    req.requireCap('hr.schedule.edit');
    final body = req.body as Map? ?? const {};
    final emp = r.subject(req, body['employee_id'] as String?);
    final date = _date(req, body['on_date']);
    final at = body['branch_id'] as String?;
    if (at != null) r.board(req, emp, at);
    final blocks = <MockRow>[];
    for (final b in ((body['shifts'] as List?) ?? const []).cast<Map>()) {
      final block = r.block(req, b['work_shift_id'] as String?);
      r.checkBlock(req, block, date, at);
      final (start, end) = _times(req, b['start_time'], b['end_time']);
      blocks.add({
        'work_shift_id': block['id'],
        'start_time': start,
        'end_time': end,
        'branch_id': at ?? block['branch_id'] ?? r.homeBranch(emp),
      });
    }
    // A board sends only its own branch's blocks: the others stay.
    final day = [
      ...blocks,
      if (at != null)
        for (final b in r.dayOf(emp['id']! as String, date))
          if (b['branch_id'] != at &&
              !blocks.any((x) => x['work_shift_id'] == b['work_shift_id']))
            b,
    ];
    r.setDay(req, emp, date, day);
    return MockResponse.ok(r.dayView(emp['id']! as String, date));
  });

  server.on('DELETE', '/staff/schedules/days', (req) {
    req.requireCap('hr.schedule.edit');
    final emp = r.subject(req, req.q('employee_id'));
    final id = emp['id']! as String;
    final date = _date(req, req.q('on_date'));
    final at = req.q('branch_id');
    if (at != null) r.board(req, emp, at);
    final current = r.dayOf(id, date);
    final pattern = r.patternOf(id, date);
    final day = at == null
        ? pattern
        : [
            for (final b in current)
              if (b['branch_id'] != at) b,
            for (final b in pattern)
              if (b['branch_id'] == at) b,
          ];
    if (!r.sameBlocks(day, current)) r.setDay(req, emp, date, day);
    return MockResponse.ok(r.dayView(id, date));
  });

  server.on('PUT', '/staff/schedules/days/times', (req) {
    req.requireCap('hr.schedule.edit');
    final body = req.body as Map? ?? const {};
    final emp = r.subject(req, body['employee_id'] as String?);
    final id = emp['id']! as String;
    final date = _date(req, body['on_date']);
    final block = r.block(req, body['work_shift_id'] as String?);
    final (start, end) = _times(req, body['start_time'], body['end_time']);
    final current = r.dayOf(id, date);
    if (!current.any((b) => b['work_shift_id'] == block['id'])) {
      req.conflict(
        "${emp['name']} isn't on ${block['name']} that day.",
        code: 'NOT_ROSTERED',
      );
    }
    final day = [
      for (final b in current)
        b['work_shift_id'] == block['id']
            ? {...b, 'start_time': start, 'end_time': end}
            : b,
    ];
    r.setDay(req, emp, date, day);
    return MockResponse.ok(r.dayView(id, date));
  });

  server.on('POST', '/staff/schedules/days/move', (req) {
    req.requireCap('hr.schedule.edit');
    final body = req.body as Map? ?? const {};
    if (body['employee_id'] == body['to_employee_id']) {
      req.badRequest('Pick someone else.', code: 'PICK_SOMEONE_ELSE');
    }
    final from = r.subject(req, body['employee_id'] as String?);
    final to = r.subject(req, body['to_employee_id'] as String?);
    if (to['employment_status'] != 'active') {
      req.fail(
        MockResponse.error(
          404,
          'Employee not found',
          code: 'EMPLOYEE_NOT_FOUND',
        ),
      );
    }
    final date = _date(req, body['on_date']);
    final block = r.block(req, body['work_shift_id'] as String?);
    final fromId = from['id']! as String;
    final toId = to['id']! as String;
    final fromDay = r.dayOf(fromId, date);
    final moving = fromDay
        .where((b) => b['work_shift_id'] == block['id'])
        .firstOrNull;
    if (moving == null) {
      req.conflict(
        "${from['name']} isn't on that shift that day.",
        code: 'NOT_ROSTERED',
      );
    }
    final toDay = r.dayOf(toId, date);
    if (toDay.any((b) => b['work_shift_id'] == block['id'])) {
      req.fail(
        MockResponse.error(
          409,
          "${to['name']} is already on ${block['name']} that day.",
          code: 'ALREADY_ROSTERED',
          vars: {'name': to['name'], 'shift': block['name'], 'date': date},
        ),
      );
    }
    final next = [...toDay, moving];
    r.checkOverlaps(req, toId, date, next);
    r.setDay(req, from, date, [
      for (final b in fromDay)
        if (b['work_shift_id'] != block['id']) b,
    ]);
    r.setDay(req, to, date, next);
    return MockResponse.ok({
      'from': r.dayView(fromId, date),
      'to': r.dayView(toId, date),
    });
  });

  // ── preferences ──────────────────────────────────────────────────────
  server.on('PUT', '/staff/employees/{id}/preferences', (req) {
    req.requireCap('hr.staff.edit');
    final emp = r.subject(req, req.param('id'));
    final body = req.body as Map? ?? const {};
    final pref = body['pref_time'];
    if (pref != null && pref != 'morning' && pref != 'evening') {
      req.badRequest('pref_time is morning, evening or null');
    }
    final days = [
      for (final d in (body['cant_work_days'] as List?) ?? const [])
        (d as num).toInt(),
    ];
    if (days.any((d) => d < 0 || d > 6)) {
      req.badRequest('cant_work_days are weekdays 0–6');
    }
    final note = (body['note'] as String?)?.trim();
    if (note != null && note.length > 300) {
      req.badRequest('The note is at most 300 characters.');
    }
    emp
      ..['pref_time'] = pref
      ..['cant_work_days'] = (days.toSet().toList()..sort())
      ..['prefs_set_by'] = 'manager'
      ..['updated_at'] = req.now.toIso8601String();
    db[ScheduleTables.prefLog].insert({
      'employee_id': emp['id'],
      'source': 'manager',
      'pref_time': pref,
      'cant_work_days': emp['cant_work_days'],
      'changed_by_name': req.persona.displayName,
      'note': note == null || note.isEmpty ? null : note,
      'created_at': req.now.toIso8601String(),
    }, timestamps: false);
    return MockResponse.empty();
  });

  server.on('GET', '/staff/employees/{id}/preferences/log', (req) {
    req.requireCap('hr.schedule.read');
    final emp = r.subject(req, req.param('id'));
    return MockResponse.ok(
      db[ScheduleTables.prefLog].query(
        filters: {'employee_id': emp['id']},
        sort: '-created_at',
      ),
    );
  });
}

// ── request helpers ──────────────────────────────────────────────────────

/// The branch a roster call names, in the caller's org, where the caller
/// holds [cap] (`access::require_at`).
String _branch(MockRequest req, MockDb db, String cap, String? branchId) {
  if (branchId == null || branchId.isEmpty) {
    req.badRequest('Query deserialize error: missing field `branch_id`');
  }
  req.requireCap(cap, branchId: branchId);
  if (teamOrgOfBranch(db, branchId) != req.orgId) {
    req.notFound('Branch not found');
  }
  return branchId;
}

void _requireEverywhere(MockRequest req, String cap) {
  req.requireCap(cap);
  if (req.persona.branchIds != null) req.fail(MockResponse.denied(cap));
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _date(MockRequest req, Object? v) {
  if (v is! String || !_isoDate.hasMatch(v)) {
    req.badRequest('Query deserialize error: a date is yyyy-mm-dd');
  }
  return v;
}

(String, String) _range(MockRequest req) {
  final from = _date(req, req.q('from'));
  final to = _date(req, req.q('to'));
  if (to.compareTo(from) < 0) {
    req.badRequest('`to` is before `from`', code: 'RANGE_BACKWARDS');
  }
  if (DateTime.parse(to).difference(DateTime.parse(from)).inDays > 62) {
    req.fail(
      MockResponse.error(
        400,
        'Range too wide — at most 62 days per request',
        code: 'RANGE_TOO_WIDE',
        vars: {'max_days': 62},
      ),
    );
  }
  return (from, to);
}

final RegExp _wireTime = RegExp(r'^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$');

/// Both times or neither (`times_of`), as `HH:MM:SS`.
(String?, String?) _times(MockRequest req, Object? a, Object? b) {
  if (a == null && b == null) return (null, null);
  if (a is! String || b is! String) {
    req.badRequest('Give both times, or neither.');
  }
  if (!_wireTime.hasMatch(a) || !_wireTime.hasMatch(b)) {
    req.badRequest('A time is HH:MM.');
  }
  if (_sec(a) == _sec(b)) {
    req.badRequest('A shift cannot start and end at the same time.');
  }
  return (_sec(a), _sec(b));
}

String _sec(String t) => t.length == 5 ? '$t:00' : t;

int _min(String t) =>
    int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));

bool _crosses((String, String) at) => _min(at.$2) <= _min(at.$1);

/// [date] at the branch's wall clock [time] (Cairo), as an instant.
DateTime _instant(String date, String time, {bool nextDay = false}) {
  final d = DateTime.parse(date).add(Duration(days: nextDay ? 1 : 0));
  return MockClock.fromCairo(
    d.year,
    d.month,
    d.day,
    int.parse(time.substring(0, 2)),
    int.parse(time.substring(3, 5)),
  );
}

MockRow _need(MockRow n) => {
  'day_of_week': n['day_of_week'],
  'band_start': n['band_start'],
  'band_end': n['band_end'],
  'staff': n['staff'],
  'department_id': n['department_id'],
};

MockRow _holiday(MockRow h) => {
  'on_date': h['on_date'],
  'name_en': h['name_en'],
  'name_ar': h['name_ar'],
  'decision': h['decision'],
  'decided_by': h['decided_by'],
  'decided_at': h['decided_at'],
};

/// What POS sales suggest per hour (`pos_need` over the hourly order
/// average): a café's morning and evening peaks, busier on Thu–Sat nights.
List<MockRow> _posNeeds() {
  const day = {
    8: 1, 9: 2, 10: 2, 11: 1, 12: 1, 13: 2, 14: 2, 15: 1, //
    16: 1, 17: 2, 18: 2, 19: 3, 20: 3, 21: 2, 22: 1,
  };
  return [
    for (var dow = 0; dow < 7; dow++)
      for (final MapEntry(key: h, value: n) in day.entries)
        {
          'day_of_week': dow,
          'band_start': '${h.toString().padLeft(2, '0')}:00:00',
          'band_end': '${(h + 1).toString().padLeft(2, '0')}:00:00',
          'staff': n + ((dow >= 4 || dow == 6) && h >= 19 ? 1 : 0),
          'department_id': null,
        },
  ];
}

// ── the roster ───────────────────────────────────────────────────────────

class _Roster {
  _Roster(this.db);

  final MockDb db;

  MockRow? settings(String? orgId) =>
      db['attendance_settings'].firstWhere((s) => s['org_id'] == orgId);

  /// The employee row a write names: in the caller's org and scope.
  MockRow subject(MockRequest req, String? id) {
    final e = id == null ? null : db['employees'].find(id);
    if (e == null || e['org_id'] != req.orgId) {
      req.fail(
        MockResponse.error(
          404,
          'Employee not found',
          code: 'EMPLOYEE_NOT_FOUND',
        ),
      );
    }
    if (!teamSeesEmployee(req, db, id)) {
      req.fail(MockResponse.forbidden('Not assigned to this branch'));
    }
    return e;
  }

  /// The board a day is set from: one of the person's branches, where the
  /// caller edits the roster (`board_branch`).
  void board(MockRequest req, MockRow emp, String at) {
    if (!_branchesOf(emp).contains(at)) {
      req.badRequest(
        "${emp['name']} doesn't work at that branch.",
        code: 'EMPLOYEE_NOT_AT_BRANCH',
      );
    }
    req.requireBranch(at);
  }

  List<String> _branchesOf(MockRow e) =>
      ((e['branch_ids'] as List?) ?? const []).cast<String>();

  String? homeBranch(MockRow e) {
    final b = _branchesOf(e);
    return b.isEmpty ? null : b.first;
  }

  MockRow block(MockRequest req, String? id) {
    final w = id == null ? null : db['work_shifts'].find(id);
    if (w == null || w['org_id'] != req.orgId) {
      req.fail(
        MockResponse.error(
          404,
          'Work shift not found',
          code: 'SHIFT_NOT_FOUND',
        ),
      );
    }
    return w;
  }

  /// A block may be set on [date] at [branchId] (`check_blocks`).
  void checkBlock(MockRequest req, MockRow w, String date, String? branchId) {
    if (w['is_active'] == false) {
      req.badRequest('${w['name']} is switched off.', code: 'SHIFT_INACTIVE');
    }
    final own = w['branch_id'] as String?;
    if (own != null && branchId != null && own != branchId) {
      req.badRequest(
        "${w['name']} is another branch's shift.",
        code: 'SHIFT_OTHER_BRANCH',
      );
    }
    if (!_validOn(w, weekdayOf(date))) {
      req.badRequest(
        "${w['name']} isn't a shift on that day.",
        code: 'SHIFT_NOT_ON_DAY',
      );
    }
  }

  bool _validOn(MockRow w, int dow) {
    final days = w['valid_days'] as List?;
    return days == null || days.contains(dow);
  }

  /// A block's `HH:MM:SS` times on [dow]: that day's own, else its default.
  (String, String) timesOn(MockRow w, int dow) {
    for (final d in ((w['day_times'] as List?) ?? const []).cast<Map>()) {
      if (d['day_of_week'] == dow) {
        return (_sec('${d['start_time']}'), _sec('${d['end_time']}'));
      }
    }
    return (_sec('${w['start_time']}'), _sec('${w['end_time']}'));
  }

  /// The standing pattern's blocks for [employeeId] on [date].
  List<MockRow> patternOf(String employeeId, String date) {
    final dow = weekdayOf(date);
    final seen = <String>{};
    final out = <MockRow>[];
    final rows =
        db[TeamTables.assignments].where(
          (a) =>
              a['employee_id'] == employeeId &&
              a['day_of_week'] == dow &&
              '${a['effective_from']}'.compareTo(date) <= 0 &&
              (a['effective_to'] == null ||
                  '${a['effective_to']}'.compareTo(date) >= 0),
        )..sort(
          (a, b) =>
              '${b['effective_from']}'.compareTo('${a['effective_from']}'),
        );
    for (final a in rows) {
      final w = db['work_shifts'].find('${a['work_shift_id']}');
      if (w == null || w['is_active'] == false || !_validOn(w, dow)) continue;
      if (!seen.add('${a['work_shift_id']}')) continue;
      out.add({
        'work_shift_id': a['work_shift_id'],
        'start_time': null,
        'end_time': null,
        'branch_id': a['branch_id'],
      });
    }
    return out;
  }

  MockRow? _set(String employeeId, String date) =>
      db[ScheduleTables.daySets].find('$employeeId|$date');

  /// The date's blocks: its own set, else the pattern.
  List<MockRow> dayOf(String employeeId, String date) {
    final s = _set(employeeId, date);
    if (s == null) return patternOf(employeeId, date);
    return [
      for (final b in (s['blocks']! as List).cast<Map>())
        MockRow.of(b.cast<String, Object?>()),
    ];
  }

  bool sameBlocks(List<MockRow> a, List<MockRow> b) {
    String key(MockRow x) =>
        '${x['work_shift_id']}|${x['start_time']}|${x['end_time']}|${x['branch_id']}';
    final ka = a.map(key).toList()..sort();
    final kb = b.map(key).toList()..sort();
    return ka.join(',') == kb.join(',');
  }

  /// Stores [day] for the person, refusing an overlap; in a published week
  /// the day is marked changed (SC-4).
  void setDay(MockRequest req, MockRow emp, String date, List<MockRow> day) {
    final id = emp['id']! as String;
    checkOverlaps(req, id, date, day);
    final sets = db[ScheduleTables.daySets];
    if (sameBlocks(day, patternOf(id, date))) {
      sets.delete('$id|$date');
    } else {
      sets.put({
        'id': '$id|$date',
        'employee_id': id,
        'on_date': date,
        'blocks': day,
      });
    }
    final week = weekStartOf(date);
    final published = _branchesOf(
      emp,
    ).any((b) => db[ScheduleTables.publications].find('$b|$week') != null);
    if (published) db[ScheduleTables.changed].put({'id': '$id|$date'});
  }

  /// 409 `SHIFTS_OVERLAP` when two of the date's blocks (or one and the
  /// night before's) overlap.
  void checkOverlaps(
    MockRequest req,
    String employeeId,
    String date,
    List<MockRow> day,
  ) {
    final spans = <(String, int, int)>[];
    for (final (d, blocks, offset) in [
      (addDays(date, -1), dayOf(employeeId, addDays(date, -1)), -1440),
      (date, day, 0),
      (addDays(date, 1), dayOf(employeeId, addDays(date, 1)), 1440),
    ]) {
      for (final b in blocks) {
        final w = db['work_shifts'].find('${b['work_shift_id']}');
        if (w == null) continue;
        final at = _blockTimes(b, w, d);
        final s = _min(at.$1) + offset;
        final e = _min(at.$2) + (_crosses(at) ? 1440 : 0) + offset;
        spans.add(('${w['name']}', s, e));
      }
    }
    for (var i = 0; i < spans.length; i++) {
      for (var j = i + 1; j < spans.length; j++) {
        final a = spans[i];
        final b = spans[j];
        final touchesToday =
            (a.$2 < 1440 && a.$3 > 0) || (b.$2 < 1440 && b.$3 > 0);
        if (touchesToday && a.$2 < b.$3 && b.$2 < a.$3) {
          req.fail(
            MockResponse.error(
              409,
              '${a.$1} on $date and ${b.$1} on $date overlap.',
              code: 'SHIFTS_OVERLAP',
              vars: {'a': a.$1, 'b': b.$1, 'date': date},
            ),
          );
        }
      }
    }
  }

  (String, String) _blockTimes(MockRow b, MockRow w, String date) =>
      b['start_time'] != null && b['end_time'] != null
      ? (_sec('${b['start_time']}'), _sec('${b['end_time']}'))
      : timesOn(w, weekdayOf(date));

  bool _onLeave(String employeeId, String date) =>
      db[TeamTables.requests].firstWhere(
        (q) =>
            q['employee_id'] == employeeId &&
            q['status'] == 'approved' &&
            (q['kind'] == 'leave' || q['kind'] == 'mission') &&
            '${q['on_date']}'.compareTo(date) <= 0 &&
            '${q['end_date'] ?? q['on_date']}'.compareTo(date) >= 0,
      ) !=
      null;

  /// The date's shifts as the roster sends them (`RosterShift`).
  List<MockRow> shiftsOn(MockRow emp, String date) {
    final id = emp['id']! as String;
    final own = _set(id, date) != null;
    final changed = db[ScheduleTables.changed].find('$id|$date') != null;
    final leave = _onLeave(id, date);
    return [
      for (final b in dayOf(id, date))
        if (db['work_shifts'].find('${b['work_shift_id']}') case final w?)
          () {
            final at = _blockTimes(b, w, date);
            final edited = b['start_time'] != null;
            return <String, Object?>{
              'employee_id': id,
              'employee_name': emp['name'],
              'date': date,
              'branch_id': b['branch_id'] ?? homeBranch(emp),
              'work_shift_id': w['id'],
              'shift_name': w['name'],
              'start_time': at.$1,
              'end_time': at.$2,
              'start_at': _instant(date, at.$1).toIso8601String(),
              'end_at': _instant(
                date,
                at.$2,
                nextDay: _crosses(at),
              ).toIso8601String(),
              'crosses_midnight': _crosses(at),
              'times_edited': edited,
              'from_override': own,
              'changed': changed,
              'on_leave': leave,
            };
          }(),
    ];
  }

  /// `DayView`: the person's date after a change, with its warnings.
  MockRow dayView(String employeeId, String date) {
    final emp = db['employees'].find(employeeId)!;
    final shifts = shiftsOn(emp, date);
    return {
      'employee_id': employeeId,
      'on_date': date,
      'follows_pattern': _set(employeeId, date) == null,
      'shifts': [
        for (final s in shifts)
          () {
            final w = db['work_shifts'].find('${s['work_shift_id']}')!;
            return {
              'employee_id': employeeId,
              'on_date': date,
              'branch_id': s['branch_id'],
              'work_shift_id': s['work_shift_id'],
              'name': s['shift_name'],
              'start_time': s['start_time'],
              'end_time': s['end_time'],
              'scheduled_start_at': s['start_at'],
              'scheduled_end_at': s['end_at'],
              'crosses_midnight': s['crosses_midnight'],
              'times_edited': s['times_edited'],
              'from_override': s['from_override'],
              'break_minutes': w['break_minutes'] ?? 0,
              'paid_break': w['paid_break'] ?? true,
              'grace_minutes': w['grace_minutes'] ?? 0,
              'checkin_window_minutes': w['checkin_window_minutes'] ?? 60,
              'overtime_threshold_minutes':
                  w['overtime_threshold_minutes'] ?? 0,
              'overtime_multiplier': w['overtime_multiplier'] ?? 1.5,
            };
          }(),
      ],
      'warnings': [
        for (final w in _warnings(emp['org_id'] as String?, [emp], date, date))
          if (w['date'] == date) w,
      ],
    };
  }

  /// Active people at [branchId], by name (`staff_at`).
  List<MockRow> staffAt(String branchId) =>
      db['employees'].where(
        (e) =>
            e['employment_status'] == 'active' &&
            _branchesOf(e).contains(branchId),
      )..sort((a, b) {
        final c = '${a['name']}'.toLowerCase().compareTo(
          '${b['name']}'.toLowerCase(),
        );
        return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
      });

  List<String> _dates(String from, String to) {
    final out = <String>[];
    for (var d = from; d.compareTo(to) <= 0; d = addDays(d, 1)) {
      out.add(d);
    }
    return out;
  }

  MockRow view(MockRequest req, String branchId, String from, String to) {
    final staff = staffAt(branchId);
    final shifts = <MockRow>[];
    final elsewhere = <MockRow>[];
    final dateSets = <MockRow>[];
    final branchNames = {
      for (final b in db['branches'].rows) b['id']: b['name'],
    };
    for (final e in staff) {
      final id = e['id']! as String;
      for (final d in _dates(from, to)) {
        for (final s in shiftsOn(e, d)) {
          if (s['branch_id'] == branchId) {
            shifts.add(s);
          } else {
            elsewhere.add({
              'employee_id': id,
              'date': d,
              'branch_id': s['branch_id'],
              'branch_name': branchNames[s['branch_id']] ?? '',
              'work_shift_id': s['work_shift_id'],
              'shift_name': s['shift_name'],
              'start_time': s['start_time'],
              'end_time': s['end_time'],
              'crosses_midnight': s['crosses_midnight'],
            });
          }
        }
        if (_set(id, d) != null) {
          final here = [
            for (final b in dayOf(id, d))
              if (b['branch_id'] == branchId) b,
          ];
          final pattern = [
            for (final b in patternOf(id, d))
              if (b['branch_id'] == branchId) b,
          ];
          if (!sameBlocks(here, pattern)) {
            dateSets.add({
              'employee_id': id,
              'date': d,
              'day_off': here.isEmpty,
            });
          }
        }
      }
    }
    final orgId = req.orgId;
    return {
      'branch_id': branchId,
      'from': from,
      'to': to,
      'published_weeks': [
        for (final p in db[ScheduleTables.publications].where(
          (p) =>
              p['branch_id'] == branchId &&
              '${p['week_start']}'.compareTo(weekStartOf(from)) >= 0 &&
              '${p['week_start']}'.compareTo(to) <= 0,
        ))
          p['week_start'],
      ],
      'shifts': shifts,
      'open_shifts': db[TeamTables.openShifts].query(
        where: (o) =>
            o['branch_id'] == branchId &&
            (o['status'] == 'open' || o['status'] == 'claimed') &&
            '${o['on_date']}'.compareTo(from) >= 0 &&
            '${o['on_date']}'.compareTo(to) <= 0,
        sort: 'on_date',
      ),
      'work_shifts': [
        for (final w in db['work_shifts'].query(
          filters: {'org_id': orgId},
          sort: 'start_time',
        ))
          if (w['is_active'] != false &&
              (w['branch_id'] == null || w['branch_id'] == branchId))
            {
              'id': w['id'],
              'name': w['name'],
              'branch_id': w['branch_id'],
              'start_time': _sec('${w['start_time']}'),
              'end_time': _sec('${w['end_time']}'),
              'crosses_midnight':
                  _min('${w['end_time']}') <= _min('${w['start_time']}'),
              'grace_minutes': w['grace_minutes'] ?? 0,
              'checkin_window_minutes': w['checkin_window_minutes'] ?? 60,
              'valid_days': w['valid_days'] ?? const [0, 1, 2, 3, 4, 5, 6],
              'day_times': [
                for (final d
                    in ((w['day_times'] as List?) ?? const []).cast<Map>())
                  {
                    'day_of_week': d['day_of_week'],
                    'start_time': _sec('${d['start_time']}'),
                    'end_time': _sec('${d['end_time']}'),
                  },
              ],
            },
      ],
      'staff': [
        for (final e in staff)
          {
            'employee_id': e['id'],
            'name': e['name'],
            'gender': e['gender'],
            'pref_time': e['pref_time'],
            'cant_work_days': e['cant_work_days'] ?? const <int>[],
            'department_id': e['department_id'],
            'prefs_set_by': e['prefs_set_by'] ?? 'employee',
          },
      ],
      'holidays': [
        for (final h in db[ScheduleTables.holidays].query(
          where: (h) =>
              h['org_id'] == orgId &&
              '${h['on_date']}'.compareTo(from) >= 0 &&
              '${h['on_date']}'.compareTo(to) <= 0,
          sort: 'on_date',
        ))
          _holiday(h),
      ],
      'warnings': _warnings(orgId, staff, from, to),
      // The backend says true until a lawyer confirms the limits; a test
      // sets `limits_confirmed` on the settings row to see the other words.
      'limits_unconfirmed': settings(orgId)?['limits_confirmed'] != true,
      'date_sets': dateSets,
      'elsewhere': elsewhere,
    };
  }

  /// Labour-limit warnings (RU-13) for [people] on [from]…[to], counting
  /// every hour wherever worked: hours a day, presence a day, rest between
  /// shifts, hours a week, a weekly day off. Never a refusal.
  List<MockRow> _warnings(
    String? orgId,
    List<MockRow> people,
    String from,
    String to,
  ) {
    final s = settings(orgId);
    int cap(String k, num fallback) =>
        (((s?[k] as num?) ?? fallback) * 60).round();
    final dayCap = cap('limit_day_hours', 12);
    final presenceCap = cap('limit_presence_hours', 14);
    final restCap = cap('limit_rest_hours', 11);
    final weekCap = cap('limit_week_hours', 60);
    final out = <MockRow>[];
    for (final e in people) {
      final id = e['id']! as String;
      // Spans of a date in minutes from its midnight.
      List<(int, int)> spans(String d) => [
        for (final sh in shiftsOn(e, d))
          (
            _min('${sh['start_time']}'),
            _min('${sh['end_time']}') +
                (sh['crosses_midnight'] == true ? 1440 : 0),
          ),
      ];
      MockRow w(String d, String kind, int minutes, int limit) => {
        'employee_id': id,
        'date': d,
        'kind': kind,
        'minutes': minutes,
        'limit_minutes': limit,
      };
      final weekFrom = weekStartOf(from);
      final weekTo = addDays(weekStartOf(to), 6);
      final worked = <String, int>{};
      for (final d in _dates(weekFrom, weekTo)) {
        final sp = spans(d);
        worked[d] = sp.fold(0, (a, x) => a + x.$2 - x.$1);
        if (d.compareTo(from) < 0 || d.compareTo(to) > 0 || sp.isEmpty) {
          continue;
        }
        if (worked[d]! > dayCap) out.add(w(d, 'day_hours', worked[d]!, dayCap));
        final first = sp.map((x) => x.$1).reduce((a, b) => a < b ? a : b);
        final last = sp.map((x) => x.$2).reduce((a, b) => a > b ? a : b);
        if (sp.length > 1 && last - first > presenceCap) {
          out.add(w(d, 'presence', last - first, presenceCap));
        }
        final before = spans(addDays(d, -1));
        if (before.isNotEmpty) {
          final end = before.map((x) => x.$2).reduce((a, b) => a > b ? a : b);
          final gap = first + 1440 - end;
          if (gap >= 0 && gap < restCap) out.add(w(d, 'rest', gap, restCap));
        }
      }
      for (var week = weekFrom; week.compareTo(weekTo) <= 0;) {
        final days = weekDays(week);
        final total = days.fold(0, (a, d) => a + (worked[d] ?? 0));
        final lastWorked = days.lastWhere(
          (d) => (worked[d] ?? 0) > 0,
          orElse: () => '',
        );
        bool inRange(String d) =>
            d.isNotEmpty && d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
        if (total > weekCap && inRange(lastWorked)) {
          out.add(w(lastWorked, 'week_hours', total, weekCap));
        }
        if (days.every((d) => (worked[d] ?? 0) > 0) && inRange(days.last)) {
          out.add(w(days.last, 'weekly_rest', 7 * 1440, 6 * 1440));
        }
        week = addDays(week, 7);
      }
    }
    return out;
  }

  // ── suggestions ─────────────────────────────────────────────────────

  /// The week's suggestions at [branchId] still to decide: the cover gaps
  /// from today on (three at most, one per person and date), then the
  /// pattern ones the engine keeps.
  List<MockRow> suggestions(MockRequest req, String branchId, String week) {
    final today = MockClock.cairoDate(req.now);
    final staff = staffAt(branchId);
    final blocks = [
      for (final w in db['work_shifts'].query(
        filters: {'org_id': req.orgId},
        sort: 'start_time',
      ))
        if (w['is_active'] != false &&
            (w['branch_id'] == null || w['branch_id'] == branchId))
          w,
    ];
    final days = weekDays(week);
    final decided = {
      for (final d in db[ScheduleTables.decisions].where(
        (d) => d['branch_id'] == branchId,
      ))
        d['suggestion_id'],
    };
    final gaps = <MockRow>[];
    final used = <String>{};
    for (final w in blocks) {
      int count(String d) => [
        for (final e in staff)
          for (final s in shiftsOn(e, d))
            if (s['branch_id'] == branchId && s['work_shift_id'] == w['id']) s,
      ].length;
      final counts = {
        for (final d in days)
          if (_validOn(w, weekdayOf(d))) d: count(d),
      };
      if (counts.isEmpty) continue;
      // The usual cover: the most frequent count, the larger on a tie.
      final freq = <int, int>{};
      for (final c in counts.values) {
        freq[c] = (freq[c] ?? 0) + 1;
      }
      final usual = freq.entries
          .reduce(
            (a, b) => b.value > a.value || (b.value == a.value && b.key > a.key)
                ? b
                : a,
          )
          .key;
      final morning = _min('${w['start_time']}') < 12 * 60;
      for (final MapEntry(key: d, value: c) in counts.entries) {
        if (d.compareTo(today) < 0 || c >= usual) continue;
        final dow = weekdayOf(d);
        final free = [
          for (final e in staff)
            if (e['on_payroll'] != false &&
                shiftsOn(e, d).isEmpty &&
                !_onLeave('${e['id']}', d) &&
                !((e['cant_work_days'] as List?) ?? const []).contains(dow) &&
                db[ScheduleTables.daySets].find('${e['id']}|$d') == null &&
                !used.contains('${e['id']}|$d'))
              e,
        ];
        if (free.isEmpty) continue;
        free.sort((a, b) {
          int fit(MockRow e) =>
              e['pref_time'] == (morning ? 'morning' : 'evening') ? 0 : 1;
          final f = fit(a) - fit(b);
          return f != 0 ? f : '${a['name']}'.compareTo('${b['name']}');
        });
        final e = free.first;
        used.add('${e['id']}|$d');
        final fits = e['pref_time'] == (morning ? 'morning' : 'evening');
        final at = timesOn(w, dow);
        gaps.add({
          'id': 'add|$d|${w['id']}|${e['id']}',
          'date': d,
          'employee_id': e['id'],
          'employee_name': e['name'],
          'shift_name': w['name'],
          'work_shift_id': w['id'],
          'start_time': at.$1,
          'end_time': at.$2,
          'reason_key': 'staff.sg_gap',
          'reason_args': {'shift': w['name'], 'short': usual - c},
          'confidence': fits ? 72 : 58,
          'by_default': e['pref_time'] == null,
          'from_employee_id': null,
          'from_employee_name': null,
        });
      }
    }
    gaps.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final kept = [
      for (final s in db[ScheduleTables.suggestions].where(
        (s) => s['branch_id'] == branchId && s['week_start'] == week,
      ))
        {
          for (final MapEntry(:key, :value) in s.entries)
            if (key != 'branch_id' && key != 'week_start') key: value,
        },
    ];
    return [
      for (final s in [...gaps.take(3), ...kept])
        if (!decided.contains(s['id'])) s,
    ];
  }

  /// Accepting changes that date only, or (a pattern one) the standing week.
  void apply(MockRow s, String branchId) {
    final id = '${s['id']}';
    final emp = db['employees'].find('${s['employee_id']}')!;
    final date = '${s['date']}';
    final dow = weekdayOf(date);
    if (id.startsWith('pattern|')) {
      final assignments = db[TeamTables.assignments];
      assignments.removeWhere(
        (a) =>
            a['employee_id'] == emp['id'] &&
            a['day_of_week'] == dow &&
            a['branch_id'] == branchId,
      );
      if (s['reason_key'] != 'staff.sg_pattern_off') {
        assignments.insert({
          'org_id': emp['org_id'],
          'employee_id': emp['id'],
          'branch_id': branchId,
          'work_shift_id': s['work_shift_id'],
          'work_shift_name': s['shift_name'],
          'day_of_week': dow,
          'effective_from': date,
        });
      }
      return;
    }
    final day = dayOf('${emp['id']}', date);
    db[ScheduleTables.daySets].put({
      'id': '${emp['id']}|$date',
      'employee_id': emp['id'],
      'on_date': date,
      'blocks': [
        ...day,
        {
          'work_shift_id': s['work_shift_id'],
          'start_time': null,
          'end_time': null,
          'branch_id': branchId,
        },
      ],
    });
  }

  // ── fairness ────────────────────────────────────────────────────────

  MockRow _fairRows(List<MockRow> people, List<String> dates, String? branch) {
    final rows = <MockRow>[];
    final share = <String, double>{};
    for (final g in const ['f', 'm', null]) {
      final group = [
        for (final e in people)
          if (e['gender'] == g) e,
      ];
      if (group.isEmpty) continue;
      var shifts = 0;
      var nights = 0;
      for (final e in group) {
        for (final d in dates) {
          for (final s in shiftsOn(e, d)) {
            if (branch != null && s['branch_id'] != branch) continue;
            shifts++;
            final end =
                _min('${s['end_time']}') +
                (s['crosses_midnight'] == true ? 1440 : 0);
            // The night window (22:00–06:00) touched.
            if (end > 22 * 60 || _min('${s['start_time']}') < 6 * 60) nights++;
          }
        }
      }
      rows.add({
        'gender': g,
        'people': group.length,
        'willing': group.where((e) => e['pref_time'] == 'evening').length,
        'shifts': shifts,
        'night_shifts': nights,
      });
      if (g != null) share[g] = shifts == 0 ? 0 : nights / shifts;
    }
    return {
      'rows': rows,
      'gap': ((share['m'] ?? 0) - (share['f'] ?? 0)).abs() * 100,
    };
  }

  MockRow fairness(MockRequest req, String month) {
    final first = DateTime.parse(month);
    final last = DateTime.utc(first.year, first.month + 1, 0);
    final dates = _dates(month, last.toIso8601String().substring(0, 10));
    final people = [
      for (final e in db['employees'].where(
        (e) =>
            e['org_id'] == req.orgId &&
            e['employment_status'] == 'active' &&
            e['on_payroll'] != false,
      ))
        e,
    ];
    final since = req.now.subtract(const Duration(days: 28));
    final branches = <MockRow>[];
    var decided = 0;
    var accepted = 0;
    for (final b in db['branches'].query(
      filters: {'org_id': req.orgId},
      sort: 'name',
    )) {
      final id = b['id']! as String;
      final mine = [
        for (final e in people)
          if (_branchesOf(e).contains(id)) e,
      ];
      if (mine.isEmpty) continue;
      final f = _fairRows(mine, dates, id);
      final ds = db[ScheduleTables.decisions].where(
        (d) =>
            d['branch_id'] == id &&
            DateTime.parse('${d['decided_at']}').isAfter(since),
      );
      final acc = ds.where((d) => d['accept'] == true).length;
      decided += ds.length;
      accepted += acc;
      final gap = (f['gap']! as double).round();
      branches.add({
        'branch_id': id,
        'branch_name': b['name'],
        'rows': f['rows'],
        'gap_points': gap,
        'flagged': gap > 20,
        'by_default_decided': ds.where((d) => d['by_default'] == true).length,
        'decided': ds.length,
        'accepted': acc,
        'learning_frozen': ds.length >= 10 && acc * 100 < 40 * ds.length,
      });
    }
    return {
      'month': month,
      'rows': _fairRows(people, dates, null)['rows'],
      'branches': branches,
      'decided_4w': decided,
      'accepted_4w': accepted,
      'learning_frozen': decided >= 10 && accepted * 100 < 40 * decided,
    };
  }
}

// ── the unit's seed ──────────────────────────────────────────────────────

/// Sabah's week as the mock clock finds it (Thursday 8 October 2026): this
/// week (from Saturday 3 October) published at Zamalek, Heliopolis and
/// Maadi; at Zamalek a split day (Youssef, Monday: past two labour limits),
/// an evening with its own times (Laila, Wednesday, to midnight), a day off
/// by date (Mariam, Friday) and an evening posted open on Friday; the
/// Armed Forces Day holiday (6 October) not decided yet; September's
/// fairness audits; Hassan's preferences last set by a manager.
void _seed(MockDb db) {
  if (db.hasTable(ScheduleTables.loaded)) return;
  db.table(ScheduleTables.loaded);
  String emp(String key) => SeedIds.employee(key);
  final morning = TeamSeedIds.workShift('sabah', 'morning');
  final evening = TeamSeedIds.workShift('sabah', 'evening');
  const week = '2026-10-03';

  for (final b in [
    SeedIds.zamalek,
    SeedIds.heliopolis,
    SeedIds.maadi,
    SeedIds.dokki,
  ]) {
    db[ScheduleTables.publications].put({
      'id': '$b|$week',
      'branch_id': b,
      'week_start': week,
    });
  }

  MockRow block(String shift, {String? start, String? end}) => {
    'work_shift_id': shift,
    'start_time': start,
    'end_time': end,
    'branch_id': SeedIds.zamalek,
  };
  for (final (key, date, blocks) in [
    ('youssef', '2026-10-05', [block(morning), block(evening)]),
    (
      'laila',
      '2026-10-07',
      [block(evening, start: '16:00:00', end: '00:00:00')],
    ),
    ('mariam', '2026-10-09', <MockRow>[]),
  ]) {
    db[ScheduleTables.daySets].put({
      'id': '${emp(key)}|$date',
      'employee_id': emp(key),
      'on_date': date,
      'blocks': blocks,
    });
    db[ScheduleTables.changed].put({'id': '${emp(key)}|$date'});
  }

  db[TeamTables.openShifts].insert({
    'id': TeamSeedIds.openShift('zamalek-friday-evening'),
    'branch_id': SeedIds.zamalek,
    'work_shift_id': evening,
    'shift_name': 'Evening',
    'on_date': '2026-10-09',
    'start_at': _instant('2026-10-09', '15:00').toIso8601String(),
    'end_at': _instant('2026-10-09', '23:00').toIso8601String(),
    'status': 'open',
  }, timestamps: false);

  for (final org in [SeedIds.sabahOrg, SeedIds.nakhlaOrg]) {
    db[ScheduleTables.holidays].put({
      'id': '$org|2026-10-06',
      'org_id': org,
      'on_date': '2026-10-06',
      'name_en': 'Armed Forces Day',
      'name_ar': 'عيد القوات المسلحة',
      'decision': null,
      'decided_by': null,
      'decided_at': null,
    });
  }

  db[ScheduleTables.suggestions].put({
    'id': 'pattern|2026-10-09|off|${emp('mariam')}',
    'branch_id': SeedIds.zamalek,
    'week_start': week,
    'date': '2026-10-09',
    'employee_id': emp('mariam'),
    'employee_name': 'Mariam Fathy',
    'shift_name': 'Evening',
    'work_shift_id': evening,
    'start_time': '15:00:00',
    'end_time': '23:00:00',
    'reason_key': 'staff.sg_pattern_off',
    'reason_args': {'name': 'Mariam Fathy', 'weeks': 4},
    'confidence': 81,
    'by_default': false,
    'from_employee_id': null,
    'from_employee_name': null,
  });

  // The last four weeks' decisions: Zamalek's managers took 3 of 10.
  for (var i = 0; i < 10; i++) {
    db[ScheduleTables.decisions].put({
      'id': '${SeedIds.zamalek}|past-$i',
      'branch_id': SeedIds.zamalek,
      'suggestion_id': 'past-$i',
      'accept': i < 3,
      'by_default': i.isEven,
      'decided_at': TeamSeed.now
          .subtract(Duration(days: 2 + i * 2))
          .toIso8601String(),
    });
  }
  for (var i = 0; i < 4; i++) {
    db[ScheduleTables.decisions].put({
      'id': '${SeedIds.maadi}|past-$i',
      'branch_id': SeedIds.maadi,
      'suggestion_id': 'past-$i',
      'accept': true,
      'by_default': false,
      'decided_at': TeamSeed.now
          .subtract(Duration(days: 3 + i * 5))
          .toIso8601String(),
    });
  }

  for (final (branch, name, gap) in [
    (SeedIds.heliopolis, 'Heliopolis', 9),
    (SeedIds.maadi, 'Maadi', 14),
    (SeedIds.newCairo, 'New Cairo', 22),
    (SeedIds.zamalek, 'Zamalek', 26),
  ]) {
    db[ScheduleTables.audits].insert({
      'org_id': SeedIds.sabahOrg,
      'branch_id': branch,
      'month': '2026-09-01',
      'flagged': gap > 20,
      'computed_at': DateTime.utc(2026, 10, 1).toIso8601String(),
      'report': {
        'branch_id': branch,
        'branch_name': name,
        'rows': const <Object>[],
        'gap_points': gap,
        'flagged': gap > 20,
        'by_default_decided': 1,
        'decided': 6,
        'accepted': 4,
        'learning_frozen': false,
      },
    }, timestamps: false);
  }

  final hassan = db['employees'].find(emp('hassan'));
  hassan?['prefs_set_by'] = 'manager';
  db[ScheduleTables.prefLog].insertAll([
    {
      'employee_id': emp('hassan'),
      'source': 'employee',
      'pref_time': 'morning',
      'cant_work_days': const <int>[],
      'changed_by_name': null,
      'note': null,
      'created_at': DateTime.utc(2026, 9, 2, 8).toIso8601String(),
    },
    {
      'employee_id': emp('hassan'),
      'source': 'manager',
      'pref_time': 'evening',
      'cant_work_days': const <int>[],
      'changed_by_name': 'Karim Adel',
      'note': 'Closes the kitchen this month',
      'created_at': DateTime.utc(2026, 9, 20, 9).toIso8601String(),
    },
  ]);
  hassan?['pref_time'] = 'evening';
}
