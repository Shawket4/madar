/// The mock backend of the Employees incl. the Excel import (`/staff/employees`, TEAM-EMP and TEAM-ALL rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET|POST /staff/employees` (GET replaces the core's)
/// - `GET /staff/employees/linkable`
/// - `GET|PUT|DELETE /staff/employees/{employee_id}`
/// - `DELETE /staff/employees/{employee_id}/device`
/// - `GET|POST /staff/departments` (the list is shared: team_reads_mock.dart)
/// - `PATCH|DELETE /staff/departments/{id}`
///
/// As MadarRust `src/staff/directory.rs` and `dawam/presence.rs`
/// (`revoke_device`): the capability gate, the caller's branches
/// (`access::in_scope`), salary redaction per caller (`hr.payroll.read`),
/// pay written only by someone holding `hr.payroll.edit` at every branch,
/// org-wide department acts, the 400/404/409 refusals in the backend's
/// words, and the phone sign-in rules (a new number, app access off or a
/// status other than active signs the phone out, RO-10).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

/// A few people signed in to the staff app on their phone (the backend's
/// `staff_devices`), so the phone column and "Sign the phone out" have rows.
const Map<String, (String, String)> _devices = {
  'mariam': ('Samsung Galaxy A54', '2026-09-02T07:41:00Z'),
  'ali': ('iPhone 13', '2026-08-20T06:55:00Z'),
  'malak': ('OPPO A78', '2026-09-14T05:30:00Z'),
  'seif': ('Redmi Note 12', '2026-07-30T04:12:00Z'),
};

/// Madar users who are not employees yet: the Add dialog's "Madar user"
/// list (every seeded Sabah user already is one).
final List<Map<String, Object?>> _linkableUsers = [
  {
    'id': mockUuid('user:mostafa-kamal'),
    'name': 'Mostafa Kamal',
    'email': 'mostafa@sabah.test',
    'phone': '+201110010101',
    'role': 'teller',
    'org_id': SeedIds.sabahOrg,
    'branch_id': SeedIds.heliopolis,
    'is_active': true,
  },
  {
    'id': mockUuid('user:nadia-farouk'),
    'name': 'Nadia Farouk',
    'email': 'nadia@sabah.test',
    'phone': null,
    'role': 'waiter',
    'org_id': SeedIds.sabahOrg,
    'branch_id': SeedIds.zamalek,
    'is_active': true,
  },
];

const String _loaded = '_employees_seed';

/// Adds this unit's rows on top of the core and area seeds (once per db).
void loadEmployeesSeed(MockDb db) {
  if (db.hasTable(_loaded)) return;
  db.table(_loaded);
  for (final e in _devices.entries) {
    final row = db['employees'].find(SeedIds.employee(e.key));
    if (row == null) continue;
    row
      ..['device_model'] = e.value.$1
      ..['device_since'] = e.value.$2
      ..['device_last_seen'] = '2026-10-08T06:58:00Z';
  }
  for (final u in _linkableUsers) {
    if (db['users'].find(u['id']! as String) == null) {
      db['users'].insert(u, timestamps: false);
    }
  }
}

// ── rules shared by the handlers ──────────────────────────────────────────

List<String> _branchesOf(MockRow e) =>
    (e['branch_ids'] as List?)?.cast<String>() ?? const [];

/// `kind`, as the server derives it on every read.
String _kindOf(MockRow e) => e['user_id'] != null
    ? 'linked'
    : e['app_access'] == true
    ? 'app'
    : 'manual';

/// Whether the caller holds [cap] at every branch (`require_everywhere`):
/// an org-wide act a branch manager may not make.
bool _everywhere(MockRequest req, String cap) =>
    req.persona.can(cap) && req.persona.branchIds == null;

/// The employee as the caller reads it: `kind` derived, and the salary (with
/// the advance cap it reveals) nulled unless the caller may read pay for one
/// of their branches (`redact_salary`). `salary_set` is never hidden.
MockRow _asRead(MockRequest req, MockRow e) {
  final scoped = req.persona.branchIds;
  final mayPay =
      req.persona.can('hr.payroll.read') &&
      (scoped == null || _branchesOf(e).any(scoped.contains));
  return {
    ...e,
    'kind': _kindOf(e),
    'salary_set': e['base_salary_piastres'] != null,
    if (!mayPay) ...{
      'base_salary_piastres': null,
      'advance_cap_piastres': null,
    },
  };
}

/// The employee [id] in the caller's org that the caller may act on
/// (`access::subject` + `require_for`): 404 outside the org, 403 outside the
/// caller's branches.
MockRow _subject(MockRequest req, MockDb db, String id, String cap) {
  final e = db['employees'].find(id);
  if (e == null || e['org_id'] != req.orgId) req.notFound('Employee not found');
  final scoped = req.persona.branchIds;
  if (scoped != null && !_branchesOf(e).any(scoped.contains)) {
    req.fail(MockResponse.denied(cap));
  }
  return e;
}

String _validateStatus(MockRequest req, String status) {
  if (!const {'active', 'suspended', 'terminated'}.contains(status)) {
    req.badRequest(
      "Unknown employment status '$status' — expected active, suspended, or "
      'terminated',
    );
  }
  return status;
}

/// Blank becomes null (`blank_to_none`).
String? _blank(Object? v) {
  final s = v is String ? v.trim() : null;
  return s == null || s.isEmpty ? null : s;
}

/// The canonical phone digits (`phone_canonical`), or null when not a phone.
String? _canonical(String raw) {
  if (raw.runes.length > 32) return null;
  var d = raw
      .replaceAllMapped(RegExp('[٠-٩]'), (m) {
        return String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x0660 + 0x30);
      })
      .replaceAll(RegExp('[^0-9]'), '');
  if (d.startsWith('00')) {
    d = d.substring(2);
  } else if (d.startsWith('20')) {
  } else if (d.startsWith('0')) {
    d = '20${d.substring(1)}';
  } else if (d.length == 10 && d.startsWith('1')) {
    d = '20$d';
  }
  if (d.length < 10 || d.length > 15) return null;
  if (RegExp('^201[0125]').hasMatch(d) && d.length != 12) return null;
  return d;
}

/// `clean_phone`: `+` and the canonical digits; blank is none; a non-phone
/// is a 400.
String? _cleanPhone(MockRequest req, Object? raw) {
  final p = _blank(raw);
  if (p == null) return null;
  final c = _canonical(p);
  if (c == null) req.badRequest('phone number looks invalid');
  return '+$c';
}

/// `phone_taken`: someone else in the org signs in to the app with it.
bool _phoneTaken(MockDb db, String org, String phone, String? except) {
  final key = _canonical(phone);
  return db['employees'].rows.any(
    (e) =>
        e['org_id'] == org &&
        e['id'] != except &&
        e['app_access'] == true &&
        e['employment_status'] != 'terminated' &&
        e['phone'] is String &&
        _canonical(e['phone']! as String) == key,
  );
}

Never _phoneTakenRefusal(MockRequest req, String phone) => req.fail(
  MockResponse.error(
    409,
    'Someone here already signs in with $phone.',
    code: 'PHONE_TAKEN',
    vars: {'phone': phone},
  ),
);

/// Every branch exists in the org (`check_branches`, 404) and the caller
/// may [cap] at each (`require_at`).
void _checkBranches(MockRequest req, MockDb db, Iterable<String> ids) {
  for (final b in ids) {
    final row = db['branches'].find(b);
    if (row == null || row['org_id'] != req.orgId) {
      req.notFound('Branch not found');
    }
  }
}

void _requireAt(MockRequest req, String cap, Iterable<String> ids) {
  for (final b in ids) {
    req.requireCap(cap, branchId: b);
  }
}

String? _departmentName(MockRequest req, MockDb db, String? id) {
  if (id == null) return null;
  final d = db[TeamTables.departments].find(id);
  if (d == null || d['org_id'] != req.orgId) {
    req.notFound('Department not found');
  }
  return d['name'] as String?;
}

/// RO-4: every phone signed out at once.
void _revokeDevices(MockRow e) {
  e
    ..['device_model'] = null
    ..['device_since'] = null
    ..['device_last_seen'] = null;
}

List<String> _dedup(Iterable<String> ids) {
  final seen = <String>{};
  return [
    for (final b in ids)
      if (seen.add(b)) b,
  ];
}

int _byName(MockRow a, MockRow b) =>
    '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());

// ── handlers ──────────────────────────────────────────────────────────────

void registerEmployeesMocks(MockServer server, MockDb db) {
  loadEmployeesSeed(db);

  server.on('GET', '/staff/employees', (req) {
    final branchId = req.q('branch_id');
    req.requireCap('hr.staff.read', branchId: branchId);
    final status = req.q('employment_status');
    if (status != null) _validateStatus(req, status);
    final kind = req.q('kind');
    if (kind != null && !const {'linked', 'app', 'manual'}.contains(kind)) {
      req.badRequest('kind is linked, app or manual');
    }
    final rows = db['employees'].query(
      filters: {
        'org_id': req.orgId,
        'employment_status': status,
        'department_id': req.q('department_id'),
      },
      where: (e) {
        final ids = _branchesOf(e);
        if (branchId != null && !ids.contains(branchId)) return false;
        if (kind != null && _kindOf(e) != kind) return false;
        final scoped = req.persona.branchIds;
        return scoped == null || ids.any(scoped.contains);
      },
      search: req.q('search'),
      searchFields: const ['name', 'employee_code', 'job_title'],
    )..sort(_byName);
    return MockResponse.ok([for (final e in rows) _asRead(req, e)]);
  });

  server.on('GET', '/staff/employees/linkable', (req) {
    req.requireCap('hr.staff.create');
    final employed = {
      for (final e in db['employees'].rows)
        if (e['user_id'] != null) e['user_id'],
    };
    final scoped = req.persona.branchIds;
    final rows = db['users'].where(
      (u) =>
          u['org_id'] == req.orgId &&
          u['is_active'] == true &&
          u['deleted_at'] == null &&
          u['role'] != 'super_admin' &&
          !employed.contains(u['id']) &&
          (scoped == null || scoped.contains(u['branch_id'])),
    )..sort(_byName);
    return MockResponse.ok([
      for (final u in rows)
        {
          'user_id': u['id'],
          'name': u['name'],
          'role': u['role'],
          'phone': u['phone'],
          'email': u['email'],
        },
    ]);
  });

  server.on('GET', '/staff/employees/{employee_id}', (req) {
    req.requireCap('hr.staff.read');
    final e = _subject(req, db, req.param('employee_id'), 'hr.staff.read');
    return MockResponse.ok(_asRead(req, e));
  });

  server.on('POST', '/staff/employees', (req) {
    req.requireCap('hr.staff.create');
    final b = req.json;
    final branches = _dedup([
      if (b['branch_id'] is String) b['branch_id']! as String,
      ...((b['branch_ids'] as List?)?.cast<String>() ?? const []),
    ]);
    if (branches.isEmpty) req.badRequest('Pick the branch they work at');
    _checkBranches(req, db, branches);
    _requireAt(req, 'hr.staff.create', branches);

    final userId = b['user_id'] as String?;
    MockRow? user;
    if (userId != null) {
      user = db['users'].find(userId);
      if (user == null ||
          user['org_id'] != req.orgId ||
          user['deleted_at'] != null ||
          user['role'] == 'super_admin') {
        req.notFound('User not found');
      }
      if (db['employees'].rows.any((e) => e['user_id'] == userId)) {
        req.fail(
          MockResponse.error(
            409,
            'That user is already an employee.',
            code: 'ALREADY_EMPLOYEE',
          ),
        );
      }
    }
    final name = _blank(b['name']) ?? user?['name'] as String?;
    if (name == null) req.badRequest('name is required');
    // A linked user's number is the default; a non-phone there is dropped.
    String? phone;
    if (_blank(b['phone']) != null) {
      phone = _cleanPhone(req, b['phone']);
    } else if (user != null && user['phone'] is String) {
      final c = _canonical(user['phone']! as String);
      phone = c == null ? null : '+$c';
    }
    final appAccess = b['app_access'] as bool? ?? phone != null;
    if (appAccess && phone == null) {
      req.badRequest('The staff app needs their WhatsApp number.');
    }
    if (appAccess &&
        phone != null &&
        _phoneTaken(db, req.orgId!, phone, null)) {
      _phoneTakenRefusal(req, phone);
    }
    final salary = b['base_salary_piastres'] as num?;
    if (salary != null && salary < 0) {
      req.badRequest('Salary cannot be negative');
    }
    // Without the pay right the figure is ignored: "not set", never 0 (D9).
    final pay = _everywhere(req, 'hr.payroll.edit') ? salary?.toInt() : null;
    final departmentId = b['department_id'] as String?;
    final departmentName = _departmentName(req, db, departmentId);
    final now = req.now.toIso8601String();
    final row = db['employees'].insert({
      'id': db.newId('employees'),
      'org_id': req.orgId,
      'user_id': userId,
      'name': name,
      'phone': phone,
      'app_access': appAccess,
      'role': user?['role'],
      'email': user?['email'],
      'department_id': departmentId,
      'department_name': departmentName,
      'employee_code': _blank(b['employee_code']),
      'job_title': _blank(b['job_title']),
      'hire_date': b['hire_date'] as String? ?? MockClock.cairoDate(req.now),
      'termination_date': null,
      'employment_status': 'active',
      'base_salary_piastres': pay,
      'salary_set': pay != null,
      'national_id': null,
      'photo_url': null,
      'emergency_contact_name': null,
      'emergency_contact_phone': null,
      'notes': null,
      'gender': _blank(b['gender']),
      'pay_method': 'cash',
      'pay_account': null,
      'on_payroll': true,
      'advance_cap_piastres': null,
      'advance_within_cap': true,
      'pref_time': null,
      'cant_work_days': <int>[],
      'branch_ids': branches,
      'device_model': null,
      'device_since': null,
      'device_last_seen': null,
      'created_at': now,
      'updated_at': now,
    });
    return MockResponse.json(201, _asRead(req, row));
  });

  server.on('PUT', '/staff/employees/{employee_id}', (req) {
    req.requireCap('hr.staff.edit');
    final id = req.param('employee_id');
    final e = _subject(req, db, id, 'hr.staff.edit');
    final b = req.json;
    final status = _validateStatus(
      req,
      b['employment_status'] as String? ?? 'active',
    );
    final termination = b['termination_date'] as String?;
    if (status == 'terminated' && termination == null) {
      req.badRequest('A terminated employee needs a termination date');
    }
    if (status != 'terminated' && termination != null) {
      req.badRequest('Only a terminated employee may carry a termination date');
    }
    final departmentId = b['department_id'] as String?;
    final departmentName = _departmentName(req, db, departmentId);

    final oldKey = e['phone'] is String
        ? _canonical(e['phone']! as String)
        : null;
    final oldApp = e['app_access'] == true;
    // Omitted keeps the number; "" clears it; anything else must be a phone.
    final phoneSent = b['phone'] != null;
    final phone = phoneSent ? _cleanPhone(req, b['phone']) : null;
    final newKey = phoneSent ? phone?.substring(1) : oldKey;
    final appAccess =
        (b['app_access'] as bool? ?? oldApp) && status != 'terminated';
    if (appAccess && newKey == null) {
      req.badRequest('The staff app needs their WhatsApp number.');
    }
    final signInChanged = newKey != oldKey || appAccess != oldApp;
    if (appAccess && phone != null && _phoneTaken(db, req.orgId!, phone, id)) {
      _phoneTakenRefusal(req, phone);
    }

    final wanted = b['branch_ids'] == null
        ? null
        : _dedup((b['branch_ids']! as List).cast<String>());
    if (wanted != null) {
      if (wanted.isEmpty) {
        req.badRequest('An employee works at one branch at least');
      }
      _checkBranches(req, db, wanted);
      final had = _branchesOf(e);
      _requireAt(req, 'hr.staff.edit', [
        for (final x in wanted)
          if (!had.contains(x)) x,
        for (final x in had)
          if (!wanted.contains(x)) x,
      ]);
    }

    final salary = b['base_salary_piastres'] as num?;
    if (salary != null && salary < 0) {
      req.badRequest('Salary cannot be negative');
    }
    // A branch manager saving a job title cannot award a raise.
    final mayPay = _everywhere(req, 'hr.payroll.edit');
    final name = b['name'] == null ? null : _blank(b['name']);
    if (b['name'] != null && name == null) req.badRequest('name is required');
    final payMethod = _blank(b['pay_method']) ?? e['pay_method'] as String?;

    e
      ..['name'] = name ?? e['name']
      ..['phone'] = phoneSent ? phone : e['phone']
      ..['app_access'] = appAccess
      ..['department_id'] = departmentId
      ..['department_name'] = departmentName
      ..['employee_code'] = _blank(b['employee_code'])
      ..['job_title'] = _blank(b['job_title'])
      ..['hire_date'] = b['hire_date']
      ..['termination_date'] = termination
      ..['employment_status'] = status
      ..['national_id'] = _blank(b['national_id'])
      ..['photo_url'] = _blank(b['photo_url'])
      ..['emergency_contact_name'] = _blank(b['emergency_contact_name'])
      ..['emergency_contact_phone'] = _blank(b['emergency_contact_phone'])
      ..['notes'] = _blank(b['notes'])
      ..['pay_method'] = payMethod
      ..['updated_at'] = req.now.toIso8601String();
    if (mayPay && salary != null) e['base_salary_piastres'] = salary.toInt();
    e['salary_set'] = e['base_salary_piastres'] != null;
    if (mayPay && b['on_payroll'] is bool) e['on_payroll'] = b['on_payroll'];
    // Sent (even null) replaces; omitted keeps.
    if (b.containsKey('gender')) e['gender'] = _blank(b['gender']);
    // A cash payee has no account.
    if (payMethod == 'cash') {
      e['pay_account'] = null;
    } else if (b.containsKey('pay_account')) {
      e['pay_account'] = _blank(b['pay_account']);
    }
    if (wanted != null) e['branch_ids'] = wanted;
    if (signInChanged || status != 'active') _revokeDevices(e);
    return MockResponse.ok(_asRead(req, e));
  });

  server.on('DELETE', '/staff/employees/{employee_id}', (req) {
    req.requireCap('hr.staff.delete');
    final e = _subject(req, db, req.param('employee_id'), 'hr.staff.delete');
    // Never a delete: attendance and payslips outlive the employment (AT-6).
    if (e['employment_status'] != 'terminated') {
      final today = MockClock.cairoDate(req.now);
      final hired = e['hire_date'] as String?;
      e
        ..['employment_status'] = 'terminated'
        ..['app_access'] = false
        ..['termination_date'] = hired != null && hired.compareTo(today) > 0
            ? hired
            : today
        ..['updated_at'] = req.now.toIso8601String();
    }
    _revokeDevices(e);
    return MockResponse.empty();
  });

  server.on('DELETE', '/staff/employees/{employee_id}/device', (req) {
    req.requireCap('hr.staff.edit');
    _revokeDevices(
      _subject(req, db, req.param('employee_id'), 'hr.staff.edit'),
    );
    return MockResponse.empty();
  });

  // ── departments ──────────────────────────────────────────────────────

  MockRow departmentAsRead(MockRow d) {
    final manager = d['manager_user_id'] == null
        ? null
        : db['users'].find(d['manager_user_id']! as String);
    return {
      ...d,
      'manager_name': manager?['name'] ?? d['manager_name'],
      // Live people: everyone not terminated.
      'employee_count': db['employees'].rows
          .where(
            (e) =>
                e['department_id'] == d['id'] &&
                e['employment_status'] != 'terminated',
          )
          .length,
    };
  }

  server.on('GET', '/staff/departments', (req) {
    req.requireCap('hr.staff.read');
    final rows = db[TeamTables.departments].where(
      (d) => d['org_id'] == req.orgId,
    )..sort(_byName);
    return MockResponse.ok([for (final d in rows) departmentAsRead(d)]);
  });

  String departmentName(MockRequest req) {
    final name = _blank(req.json['name']);
    if (name == null) req.badRequest('Department name is required');
    final manager = req.json['manager_user_id'] as String?;
    if (manager != null) {
      final u = db['users'].find(manager);
      if (u == null || u['org_id'] != req.orgId) req.notFound('User not found');
    }
    return name;
  }

  void requireEverywhere(MockRequest req, String cap) {
    if (!_everywhere(req, cap)) req.fail(MockResponse.denied(cap));
  }

  server.on('POST', '/staff/departments', (req) {
    requireEverywhere(req, 'hr.staff.create');
    final name = departmentName(req);
    final now = req.now.toIso8601String();
    final row = db[TeamTables.departments].insert({
      'id': db.newId(TeamTables.departments),
      'org_id': req.orgId,
      'name': name,
      'manager_user_id': req.json['manager_user_id'],
      'manager_name': null,
      'employee_count': 0,
      'created_at': now,
      'updated_at': now,
    });
    return MockResponse.json(201, {
      ...row,
      'manager_name': null,
      'employee_count': 0,
    });
  });

  server.on('PATCH', '/staff/departments/{id}', (req) {
    requireEverywhere(req, 'hr.staff.edit');
    final name = departmentName(req);
    final d = db[TeamTables.departments].find(req.param('id'));
    if (d == null || d['org_id'] != req.orgId) {
      req.notFound('Department not found');
    }
    d
      ..['name'] = name
      ..['manager_user_id'] = req.json['manager_user_id']
      ..['updated_at'] = req.now.toIso8601String();
    for (final e in db['employees'].rows) {
      if (e['department_id'] == d['id']) e['department_name'] = name;
    }
    return MockResponse.ok({...d, 'manager_name': null, 'employee_count': 0});
  });

  server.on('DELETE', '/staff/departments/{id}', (req) {
    requireEverywhere(req, 'hr.staff.delete');
    final id = req.param('id');
    final occupied = db['employees'].rows
        .where(
          (e) =>
              e['department_id'] == id &&
              e['org_id'] == req.orgId &&
              e['employment_status'] != 'terminated',
        )
        .length;
    if (occupied > 0) {
      req.badRequest(
        '$occupied employee(s) are still in this department — move them '
        'first',
      );
    }
    final d = db[TeamTables.departments].find(id);
    if (d == null || d['org_id'] != req.orgId) {
      req.notFound('Department not found');
    }
    db[TeamTables.departments].delete(id);
    return MockResponse.empty();
  });
}
