/// The mock backend of the Rules (`/staff/rules`, TEAM-RUL rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET|PUT /staff/attendance/settings` (GET replaces the core's)
/// - `GET /staff/attendance/settings/branches`
/// - `DELETE /staff/attendance/settings/branches/{branch_id}`
///
/// Ported from `MadarRust/src/staff/attendance.rs` (`RULE_FIELDS`,
/// `effective_settings_sql`, `get_attendance_settings`, `list_branch_rules`,
/// `put_attendance_settings`, `check_setting_ranges`, `delete_branch_rules`)
/// and `rules.rs` (`validate_tiers`):
///
/// - the business's row is the core seed's `attendance_settings` row of the
///   org; a branch's overrides live in [rulesBranchTable], one row per
///   branch with a value only for the rules it sets itself;
/// - a read answers the EFFECTIVE rules: built-in defaults, under the
///   business's row, under the branch's overrides, with `overridden` naming
///   the branch's own rules and the server's `suggested_tiers`;
/// - seeing the rules needs `hr.rules.view` (at the branch asked about);
///   changing them `hr.rules.edit` everywhere, the gender mode
///   `hr.roster.settings` everywhere too;
/// - a save is refused the way the backend refuses it: an impossible ladder
///   (400 "Late tiers overlap at N minutes"), a figure out of range (400
///   `SETTING_OUT_OF_RANGE` with `{field, min, max, …}` or `{field,
///   allowed}`), a business-only setting or a bad `inherit` from a branch,
///   `inherit` from the business;
/// - saving the ladder and the absence cost together is the step that lets
///   people clock in (`rules_saved_at`, kept once set).
///
/// The seed: Zamalek runs its own day limit (10 h) and auto-close (90 min);
/// the other branches follow the business.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

/// The table of branch overrides (one row per branch that sets a rule).
const String rulesBranchTable = 'attendance_branch_rules';

/// One stored rule: its wire name, the built-in default, and whether a
/// branch may override it (`RULE_FIELDS`, in the backend's order).
typedef _RuleField = ({String name, Object? fallback, bool branch});

const List<_RuleField> _ruleFields = [
  (name: 'late_deduction_tiers', fallback: <Object?>[], branch: true),
  (name: 'absence_deduction_days', fallback: 1.0, branch: true),
  (name: 'default_overtime_multiplier', fallback: 1.5, branch: true),
  (name: 'auto_checkout_buffer_minutes', fallback: 120, branch: true),
  (name: 'working_days_per_month', fallback: 30.0, branch: true),
  (name: 'require_geofence', fallback: true, branch: true),
  (name: 'excused_time_paid_default', fallback: true, branch: true),
  (name: 'period_start_day', fallback: 26, branch: false),
  (name: 'overtime_mode', fallback: 'off', branch: true),
  (name: 'overtime_day_multiplier', fallback: 1.35, branch: true),
  (name: 'overtime_night_multiplier', fallback: 1.7, branch: true),
  (name: 'holiday_multiplier', fallback: 2.0, branch: true),
  (name: 'advance_cap_percent', fallback: 50.0, branch: false),
  (name: 'half_day_leave_counts', fallback: 'half_shift', branch: true),
  (name: 'night_start', fallback: '22:00:00', branch: true),
  (name: 'night_end', fallback: '06:00:00', branch: true),
  (name: 'gender_mode', fallback: 'soft', branch: false),
  (name: 'limit_day_hours', fallback: 8.0, branch: true),
  (name: 'limit_week_hours', fallback: 48.0, branch: true),
  (name: 'limit_presence_hours', fallback: 10.0, branch: true),
  (name: 'limit_rest_hours', fallback: 12.0, branch: true),
  (name: 'limit_overtime_day_hours', fallback: 2.0, branch: true),
  (name: 'orders_per_staff', fallback: 12, branch: true),
  (name: 'cover_pay_mode', fallback: 'minute_rate', branch: true),
];

/// The rules a branch may override, by wire name.
final List<String> branchRuleFields = [
  for (final f in _ruleFields)
    if (f.branch) f.name,
];

/// The ladder the set-up step starts from (`suggested_tiers`, RU-1).
const List<Map<String, Object?>> suggestedTiers = [
  {'from_minutes': 1, 'to_minutes': 15, 'kind': 'minutes', 'value': 15},
  {'from_minutes': 16, 'to_minutes': 30, 'kind': 'day_fraction', 'value': 0.25},
  {'from_minutes': 31, 'to_minutes': 60, 'kind': 'day_fraction', 'value': 0.5},
  {'from_minutes': 61, 'to_minutes': null, 'kind': 'day_fraction', 'value': 1},
];

const String _zeroUuid = '00000000-0000-0000-0000-000000000000';

/// The business row of [orgId] (the core seed's, one per org), or null.
MockRow? businessRulesRow(MockDb db, String? orgId) => db['attendance_settings']
    .firstWhere((r) => r['org_id'] == orgId && r['branch_id'] == null);

/// The override row of [branchId] in [orgId], or null.
MockRow? branchRulesRow(MockDb db, String? orgId, String branchId) =>
    db[rulesBranchTable].firstWhere(
      (r) => r['org_id'] == orgId && r['branch_id'] == branchId,
    );

/// "22:00" → "22:00:00": the backend's `NaiveTime`.
Object? _wireTime(Object? v) => v is String && v.length == 5 ? '$v:00' : v;

/// The rules [branchId] (null: the business) runs on in [orgId], as the
/// backend's resolver reads them (`load_settings` + `suggested_tiers`).
Map<String, Object?> effectiveRules(
  MockDb db,
  String orgId,
  String? branchId, {
  required String nowIso,
}) {
  final o = businessRulesRow(db, orgId);
  final b = branchId == null ? null : branchRulesRow(db, orgId, branchId);
  final out = <String, Object?>{
    'id': b?['id'] ?? o?['id'] ?? _zeroUuid,
    'org_id': orgId,
    'branch_id': branchId,
  };
  for (final f in _ruleFields) {
    final own = f.branch ? (b?[f.name]) : null;
    out[f.name] = own ?? o?[f.name] ?? f.fallback;
  }
  out['night_start'] = _wireTime(out['night_start']);
  out['night_end'] = _wireTime(out['night_end']);
  out['rules_saved_at'] = o?['rules_saved_at'];
  out['created_at'] = b?['created_at'] ?? o?['created_at'] ?? nowIso;
  out['updated_at'] = b?['updated_at'] ?? o?['updated_at'] ?? nowIso;
  out['overridden'] = [
    for (final f in _ruleFields)
      if (f.branch && b?[f.name] != null) f.name,
  ];
  out['suggested_tiers'] = suggestedTiers;
  return out;
}

/// `rules::validate_tiers`: the ladder the backend refuses at the door.
String? tierRefusal(List<Object?> tiers) {
  final sorted =
      [
        for (final t in tiers)
          if (t is Map) t,
      ]..sort(
        (a, b) =>
            (a['from_minutes'] as num).compareTo(b['from_minutes'] as num),
      );
  num? previousEnd;
  for (final t in sorted) {
    final from = t['from_minutes'] as num;
    final to = t['to_minutes'] as num?;
    final value = t['value'] as num;
    if (from < 0) return 'Late tier from_minutes cannot be negative';
    if (to != null && to < from) {
      return 'Late tier $from–$to ends before it starts';
    }
    if (value < 0) return 'Late tier value cannot be negative';
    if (previousEnd != null && from <= previousEnd) {
      return 'Late tiers overlap at $from minutes';
    }
    previousEnd = to ?? 2147483647;
  }
  return null;
}

/// `check_setting_ranges`: (field, min, min inclusive, max, max inclusive).
const List<(String, num, bool, num, bool)> _ranges = [
  ('overtime_day_multiplier', 1, true, 100, false),
  ('overtime_night_multiplier', 1, true, 100, false),
  ('holiday_multiplier', 1, true, 100, false),
  ('default_overtime_multiplier', 1, true, 100, false),
  ('advance_cap_percent', 0, true, 100, true),
  ('absence_deduction_days', 0, true, 31, true),
  ('working_days_per_month', 0, false, 31, true),
  ('limit_day_hours', 0, false, 168, true),
  ('limit_week_hours', 0, false, 168, true),
  ('limit_presence_hours', 0, false, 168, true),
  ('limit_rest_hours', 0, true, 168, true),
  ('limit_overtime_day_hours', 0, true, 168, true),
  ('auto_checkout_buffer_minutes', 0, true, 1440, true),
];

const List<(String, List<String>)> _choices = [
  ('cover_pay_mode', ['minute_rate', 'full_block']),
  ('overtime_mode', ['off', 'automatic', 'approval']),
  ('half_day_leave_counts', ['half_shift', 'whole_day']),
  ('gender_mode', ['off', 'soft', 'hard']),
];

/// The `SETTING_OUT_OF_RANGE` refusal of [body], or null.
MockResponse? settingRefusal(Map<String, Object?> body) {
  MockResponse out(String field, String why, Map<String, Object?> vars) =>
      MockResponse.error(
        400,
        why,
        code: 'SETTING_OUT_OF_RANGE',
        vars: {...vars, 'field': field},
      );
  for (final (field, min, minIn, max, maxIn) in _ranges) {
    final v = body[field];
    if (v is! num) continue;
    final low = minIn ? v < min : v <= min;
    final high = maxIn ? v > max : v >= max;
    if (low || high) {
      final lo = minIn ? 'from' : 'above';
      final hi = maxIn ? 'up to' : 'below';
      return out(field, '$field must be $lo $min and $hi $max', {
        'min': min,
        'max': max,
        'min_inclusive': minIn,
        'max_inclusive': maxIn,
      });
    }
  }
  final perStaff = body['orders_per_staff'];
  if (perStaff is num && (perStaff < 1 || perStaff > 1000)) {
    return out(
      'orders_per_staff',
      'orders_per_staff must be from 1 and up to 1000',
      {'min': 1, 'max': 1000},
    );
  }
  final day = body['period_start_day'];
  if (day is num && (day < 1 || day > 28)) {
    return out(
      'period_start_day',
      'period_start_day must be from 1 and up to 28',
      {'min': 1, 'max': 28},
    );
  }
  for (final (field, allowed) in _choices) {
    final v = body[field];
    if (v is String && !allowed.contains(v)) {
      return out(field, '$field is one of ${allowed.join(', ')}', {
        'allowed': allowed,
      });
    }
  }
  return null;
}

/// `access::require_everywhere`: the right at EVERY branch (a branch-scoped
/// person never holds it everywhere).
void _requireEverywhere(MockRequest req, String cap) {
  if (!req.persona.can(cap) || req.persona.branchIds != null) {
    req.fail(MockResponse.denied(cap));
  }
}

/// The branch [branchId] of the caller's org (404 otherwise).
MockRow _branchOf(MockRequest req, MockDb db, String branchId) {
  final b = db['branches'].find(branchId);
  if (b == null || b['org_id'] != req.orgId || b['deleted_at'] != null) {
    req.notFound('Branch not found');
  }
  return b;
}

String _orgOf(MockRequest req) =>
    req.orgId ?? req.badRequest('Pick an organization first');

/// The seed's business ladder made one the backend would have stored: the
/// core seed's rungs share their ends (15–30, 30–60, 60+), which
/// `validate_tiers` refuses; each rung starts a minute after the last ends.
/// Pricing is unchanged (the first rung holding the minutes wins).
List<Object?> _validLadder(List<Object?> tiers) {
  final out = <Object?>[];
  num? previousEnd;
  for (final t in tiers) {
    if (t is! Map) continue;
    final rung = Map<String, Object?>.from(t.cast<String, Object?>());
    final from = rung['from_minutes'] as num;
    if (previousEnd != null && from <= previousEnd) {
      rung['from_minutes'] = previousEnd + 1;
    }
    previousEnd = rung['to_minutes'] as num? ?? 2147483647;
    out.add(rung);
  }
  return out;
}

void registerRulesMocks(MockServer server, MockDb db) {
  _seedRules(db);

  server.on('GET', '/staff/attendance/settings', (req) {
    final orgId = _orgOf(req);
    final branchId = req.q('branch_id');
    req.requireCap('hr.rules.view', branchId: branchId);
    if (branchId != null) _branchOf(req, db, branchId);
    return MockResponse.ok(
      effectiveRules(db, orgId, branchId, nowIso: db.nowIso),
    );
  });

  server.on('GET', '/staff/attendance/settings/branches', (req) {
    final orgId = _orgOf(req);
    req.requireCap('hr.rules.view');
    final scope = req.persona.branchIds;
    final rows =
        db['branches'].where(
          (b) =>
              b['org_id'] == orgId &&
              b['deleted_at'] == null &&
              (scope == null || scope.contains(b['id'])),
        )..sort((a, b) {
          final c = '${a['name']}'.toLowerCase().compareTo(
            '${b['name']}'.toLowerCase(),
          );
          return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
        });
    return MockResponse.ok([
      for (final b in rows)
        () {
          final own = branchRulesRow(db, orgId, b['id']! as String);
          return BranchRules(
            branchId: b['id']! as String,
            branchName: b['name']! as String,
            overridden: [
              for (final f in _ruleFields)
                if (f.branch && own?[f.name] != null) f.name,
            ],
            updatedAt: own == null
                ? null
                : DateTime.parse(own['updated_at']! as String),
          );
        }(),
    ]);
  });

  server.on('PUT', '/staff/attendance/settings', (req) {
    final orgId = _orgOf(req);
    _requireEverywhere(req, 'hr.rules.edit');
    // The body must fit the request's shape (actix's JSON extractor).
    req.bodyAs(PutAttendanceSettingsRequest.fromJson);
    final body = req.json;
    final branchId = body['branch_id'] as String?;
    if (branchId != null) {
      req.requireBranch(branchId);
      _branchOf(req, db, branchId);
    }
    final tiers = body['late_deduction_tiers'];
    if (tiers is List) {
      final why = tierRefusal(tiers);
      if (why != null) req.badRequest(why);
    }
    final range = settingRefusal(body);
    if (range != null) req.fail(range);
    if (body['gender_mode'] != null) {
      _requireEverywhere(req, 'hr.roster.settings');
    }
    final inherit = [
      for (final n in (body['inherit'] as List?) ?? const []) '$n',
    ];
    bool sent(String name) => body[name] != null;
    if (branchId != null) {
      for (final f in _ruleFields) {
        if (!f.branch && sent(f.name)) {
          req.badRequest("${f.name} is the business's setting, not a branch's");
        }
      }
      for (final n in inherit) {
        if (!branchRuleFields.contains(n)) {
          req.badRequest("'$n' is not a rule a branch can override");
        }
      }
    } else if (inherit.isNotEmpty) {
      req.badRequest("Only a branch can go back to the business's rules");
    }

    final now = db.nowIso;
    if (branchId == null) {
      // Saving the ladder and the absence cost together lets people clock
      // in (RU-1); a one-field save never does.
      final savesRules =
          sent('late_deduction_tiers') && sent('absence_deduction_days');
      var row = businessRulesRow(db, orgId);
      row ??= db['attendance_settings'].insert({
        'org_id': orgId,
        for (final f in _ruleFields) f.name: f.fallback,
        'rules_saved_at': null,
      });
      for (final f in _ruleFields) {
        if (sent(f.name)) row[f.name] = body[f.name];
      }
      if (savesRules) row['rules_saved_at'] ??= now;
      row['updated_at'] = now;
    } else {
      var row = branchRulesRow(db, orgId, branchId);
      row ??= db[rulesBranchTable].insert({
        'org_id': orgId,
        'branch_id': branchId,
        for (final n in branchRuleFields) n: null,
      });
      for (final n in branchRuleFields) {
        if (inherit.contains(n)) {
          row[n] = null;
        } else if (sent(n)) {
          row[n] = body[n];
        }
      }
      row['updated_at'] = now;
    }
    return MockResponse.ok(effectiveRules(db, orgId, branchId, nowIso: now));
  });

  server.on('DELETE', '/staff/attendance/settings/branches/{branch_id}', (req) {
    final orgId = _orgOf(req);
    _requireEverywhere(req, 'hr.rules.edit');
    final branchId = req.param('branch_id');
    _branchOf(req, db, branchId);
    db[rulesBranchTable].removeWhere(
      (r) => r['org_id'] == orgId && r['branch_id'] == branchId,
    );
    return MockResponse.empty();
  });
}

/// The rules data the unit adds to the seed (once per database).
void _seedRules(MockDb db) {
  if (db.hasTable(rulesBranchTable)) return;
  final table = db.table(rulesBranchTable);
  for (final row in db['attendance_settings'].rows) {
    final tiers = row['late_deduction_tiers'];
    if (tiers is List) row['late_deduction_tiers'] = _validLadder(tiers);
  }
  // Zamalek, open late on the river: a shorter day and a quicker auto-close.
  final zamalek = db['branches'].find(SeedIds.zamalek);
  if (zamalek == null) return;
  const at = '2026-09-15T08:00:00.000Z';
  table.insert({
    'org_id': zamalek['org_id'],
    'branch_id': SeedIds.zamalek,
    for (final n in branchRuleFields) n: null,
    'limit_day_hours': 10.0,
    'auto_checkout_buffer_minutes': 90,
    'created_at': at,
    'updated_at': at,
  }, timestamps: false);
}
