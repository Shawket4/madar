/// `/access/users` Users (ADM-USR rows): /users CRUD, /users/pin-suggestion,
/// /users/{id}/branches (seed: the `user_branches` table), /authz/users/{id}
/// access, overrides, assignments, /authz/explain, GET /authz/roles for the
/// access sheet and GET /staff/employees/linkable for Make employee.
///
/// Handlers behave like the backend (MadarRust `users/handlers.rs`,
/// `authz/api.rs`, `permissions/guard.rs`): the capability checks the
/// inventory's `srv:` gates name (403 envelope), validation (400/409),
/// not-found, and state over the shared [MockDb] (a create shows in the next
/// list). People's PINs, role assignments and per-person overrides live in
/// this unit's own tables ([UsersTables]), seeded from the core seed's people.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show CapabilityMeta, capabilityRegistry;

import '../area_seed.dart';

/// The tables this unit adds.
abstract final class UsersTables {
  /// `{id: <user id>, pin}`: the PIN each person signs in with at a till
  /// (the server keeps only a fingerprint; the mock keeps the digits).
  static const String pins = 'user_pins';

  /// `{id, user_id, role_id, kind, all_branches, branch_ids}`: who holds
  /// which role where (`role_assignments` + `role_assignment_branches`).
  static const String assignments = 'role_assignments';

  /// `{id, user_id, capability, effect, branch_id, limits, reason}`: a
  /// person's allow / deny (`user_overrides`, revoked rows dropped).
  static const String overrides = 'user_overrides';
}

/// The seed's per-person overrides: Omar may refund up to EGP 500 anywhere;
/// Youssef may not void at Zamalek.
abstract final class UsersSeed {
  static List<Map<String, Object?>> get overrides => [
    {
      'id': mockUuid('override:omar:refunds.create'),
      'user_id': SeedIds.user('omar'),
      'capability': 'refunds.create',
      'effect': 'allow',
      'branch_id': null,
      'limits': const {'max_amount': 50000},
      'reason': 'Covers the evening refunds at New Cairo',
    },
    {
      'id': mockUuid('override:youssef:orders.void'),
      'user_id': SeedIds.user('youssef'),
      'capability': 'orders.void',
      'effect': 'deny',
      'branch_id': SeedIds.zamalek,
      'limits': null,
      'reason': null,
    },
  ];
}

const _tillRoles = {'teller', 'waiter', 'kitchen'};

/// Role rank for "strictly below" (`may_give_kind`, `NotAbove`).
int _rank(String role) => switch (role) {
  'super_admin' => 4,
  'org_admin' => 3,
  'branch_manager' => 2,
  _ => 1,
};

String _roleId(String kind) => mockUuid('role:sabah:$kind');

void _loadUsersSeed(MockDb db) {
  if (db.hasTable(UsersTables.pins)) return;
  loadAdminSeed(db);
  db[UsersTables.pins].insertAll([
    for (final p in sabahStaff)
      if (p.pin != null) {'id': SeedIds.user(p.key), 'pin': p.pin},
  ]);
  final branchesOf = <String, List<String>>{};
  for (final r in db[AdminTables.userBranches].rows) {
    (branchesOf[r['user_id']! as String] ??= []).add(r['branch_id']! as String);
  }
  db[UsersTables.assignments].insertAll([
    for (final p in sabahStaff)
      {
        'id': mockUuid('assignment:${p.key}'),
        'user_id': SeedIds.user(p.key),
        'role_id': _roleId(p.role),
        'kind': p.role,
        'all_branches': p.role == 'org_admin',
        'branch_ids': p.role == 'org_admin'
            ? const <String>[]
            : branchesOf[SeedIds.user(p.key)] ?? const <String>[],
      },
  ]);
  db[UsersTables.overrides].insertAll(UsersSeed.overrides);
}

void registerUsersMocks(MockServer server, MockDb db) {
  _loadUsersSeed(db);
  final users = db['users'];
  final links = db[AdminTables.userBranches];

  /// `deleted_at IS NULL`: a deleted account is kept (its orders and tills
  /// stay on record) but is gone from every read.
  bool live(Map<String, Object?>? u) => u != null && u['deleted_at'] == null;

  List<String> branchesOfUser(String userId) => [
    for (final r in links.rows)
      if (r['user_id'] == userId) r['branch_id']! as String,
  ];

  /// `guard::share_a_branch`.
  bool shareABranch(String a, String b) {
    final mine = branchesOfUser(b).toSet();
    return branchesOfUser(a).any(mine.contains);
  }

  bool isManager(MockRequest req) => req.persona.role == 'branch_manager';

  Map<String, Object?> userIn(MockRequest req, String id) {
    final u = users.find(id);
    if (!live(u)) req.notFound('User not found');
    req.requireSameOrg(u!['org_id'] as String?);
    return u;
  }

  /// `guard::require_dominance`: someone at or above your role is not yours
  /// to change (an owner changes anyone but is changed only by an owner).
  void requireDominance(MockRequest req, Map<String, Object?> target) {
    final role = target['role']! as String;
    if (req.persona.isPlatform) return;
    if (role == 'org_admin' && req.persona.isOwner) return;
    if (_rank(role) >= _rank(req.persona.role)) {
      req.fail(
        MockResponse.forbidden('You cannot manage a user with this role'),
      );
    }
  }

  /// `guard::require_can_create`.
  void requireCanCreate(MockRequest req, String role) {
    if (req.persona.isPlatform) return;
    if (role == 'super_admin' ||
        !(req.persona.isOwner || _rank(role) < _rank(req.persona.role))) {
      req.fail(
        MockResponse.forbidden('You cannot manage a user with this role'),
      );
    }
  }

  bool pinTaken(String? orgId, String pin, {String? except}) {
    for (final p in db[UsersTables.pins].rows) {
      if (p['pin'] != pin || p['id'] == except) continue;
      final u = users.find(p['id']! as String);
      if (live(u) && u!['org_id'] == orgId) return true;
    }
    return false;
  }

  void checkNewPin(MockRequest req, String pin) {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      req.badRequest('A new PIN must be 6 digits');
    }
  }

  bool emailTaken(String email, {String? except}) => users.rows.any(
    (u) =>
        live(u) &&
        u['id'] != except &&
        (u['email'] as String?)?.toLowerCase() == email.trim().toLowerCase(),
  );

  // ── /users ───────────────────────────────────────────────────────────

  server.on('GET', '/users', (req) {
    req.requireCap('staff.users.read');
    final p = req.persona;
    final orgId = p.isPlatform ? req.q('org_id') : p.orgId;
    if (!p.isPlatform && orgId == null) req.fail(MockResponse.forbidden('No org assigned'));
    final rows = users.query(
      filters: {'org_id': orgId},
      where: (u) {
        if (!live(u)) return false;
        if (!isManager(req)) return true;
        final id = u['id']! as String;
        return id == p.userId || shareABranch(id, p.userId);
      },
      sort: 'name',
    );
    return MockResponse.ok(rows);
  });

  server.on('POST', '/users', (req) {
    req.requireCap('staff.users.create');
    final body = req.bodyAs(CreateUserRequest.fromJson);
    req.requireSameOrg(body.orgId);
    final role = body.role.toJson();
    requireCanCreate(req, role);
    final branchIds = body.branchIds ?? const <String>[];
    if (isManager(req)) {
      final mine = branchesOfUser(req.persona.userId);
      for (final b in branchIds) {
        if (!mine.contains(b)) {
          req.fail(
            MockResponse.forbidden(
              'You cannot assign a user to branch $b because it is not '
              'assigned to you',
            ),
          );
        }
      }
    }
    for (final b in branchIds) {
      if (db['branches'].find(b)?['org_id'] != body.orgId) {
        req.badRequest('Every branch must belong to the user\'s organization');
      }
    }
    final pin = body.pin;
    if (_tillRoles.contains(role)) {
      if (pin == null) {
        req.badRequest('Tellers, waiters and kitchen users require a PIN');
      }
      checkNewPin(req, pin);
      if (pinTaken(body.orgId, pin)) {
        req.conflict('Someone in this organization already uses that PIN');
      }
    } else {
      if (pin != null) {
        checkNewPin(req, pin);
        if (pinTaken(body.orgId, pin)) {
          req.conflict('Someone in this organization already uses that PIN');
        }
      }
      if (body.password == null) {
        req.badRequest('Admins and managers require a password');
      }
      if (body.email == null) {
        req.badRequest('Admins and managers require an email');
      }
    }
    final email = body.email;
    if (email != null && emailTaken(email)) {
      req.conflict('Email already in use');
    }
    if (_tillRoles.contains(role) &&
        users.rows.any(
          (u) =>
              live(u) &&
              u['org_id'] == body.orgId &&
              _tillRoles.contains(u['role']) &&
              (u['name']! as String).toLowerCase() == body.name.toLowerCase(),
        )) {
      req.conflict(
        'A teller, waiter or kitchen user with this name already exists in '
        'this organization',
      );
    }
    final id = db.newId('users');
    final user = UserPublic(
      id: id,
      name: body.name,
      email: email?.trim().toLowerCase(),
      phone: body.phone,
      role: body.role,
      orgId: body.orgId,
      isActive: true,
    );
    users.insert(user.toJson(), timestamps: false);
    if (pin != null) db[UsersTables.pins].put({'id': id, 'pin': pin});
    for (final b in branchIds) {
      links.insert({
        'id': AdminSeed.assignmentId(id, b),
        'user_id': id,
        'branch_id': b,
      }, timestamps: false);
    }
    db[UsersTables.assignments].insert({
      'user_id': id,
      'role_id': _roleId(role),
      'kind': role,
      'all_branches': role == 'org_admin' || branchIds.isEmpty,
      'branch_ids': branchIds,
    }, timestamps: false);
    return MockResponse.created(CreateUserResponse(user: user));
  });

  server.on('GET', '/users/pin-suggestion', (req) {
    req.requireCap('staff.users.create');
    final orgId = req.orgId;
    if (orgId == null) req.badRequest('Choose an organization first');
    // Deterministic, and never one somebody in the org already holds.
    for (var n = 402913; ; n = (n + 104729) % 1000000) {
      final pin = n.toString().padLeft(6, '0');
      if (!pinTaken(orgId, pin)) return MockResponse.ok(PinSuggestion(pin: pin));
    }
  });

  server.on('GET', '/users/{id}', (req) {
    req.requireCap('staff.users.read');
    return MockResponse.ok(userIn(req, req.param('id')));
  });

  server.on('PATCH', '/users/{id}', (req) {
    req.requireCap('staff.users.edit');
    final id = req.param('id');
    final existing = userIn(req, id);
    final body = req.bodyAs(UpdateUserRequest.fromJson);
    final self = id == req.persona.userId;
    final role = body.role?.toJson();
    if (self) {
      if ((role != null && role != existing['role']) ||
          body.isActive == false) {
        req.fail(
          MockResponse.forbidden(
            'You cannot change your own role or deactivate yourself',
          ),
        );
      }
    } else {
      requireDominance(req, existing);
      if (role != null) requireCanCreate(req, role);
      if (isManager(req) && !shareABranch(id, req.persona.userId)) {
        req.fail(MockResponse.forbidden('You do not have access to this user'));
      }
    }
    final demotes =
        existing['role'] == 'org_admin' &&
        existing['is_active'] == true &&
        ((role != null && role != 'org_admin') || body.isActive == false);
    if (demotes &&
        !users.rows.any(
          (u) =>
              live(u) &&
              u['id'] != id &&
              u['org_id'] == existing['org_id'] &&
              u['role'] == 'org_admin' &&
              u['is_active'] == true,
        )) {
      req.conflict(
        "This is the organization's last active owner. Add another owner "
        'first.',
      );
    }
    final pin = body.pin;
    if (pin != null) {
      checkNewPin(req, pin);
      if (pinTaken(existing['org_id'] as String?, pin, except: id)) {
        req.conflict('Someone in this organization already uses that PIN');
      }
    }
    final email = body.email;
    if (email != null && emailTaken(email, except: id)) {
      req.conflict('Email already in use');
    }
    // `COALESCE($n, column)`: a null keeps what is stored.
    users.update(id, {
      'name': ?body.name,
      'email': ?email?.trim().toLowerCase(),
      'phone': ?body.phone,
      'role': ?role,
      'is_active': ?body.isActive,
    });
    if (pin != null) db[UsersTables.pins].put({'id': id, 'pin': pin});
    return MockResponse.ok(users.get(id));
  });

  server.on('DELETE', '/users/{id}', (req) {
    req.requireCap('staff.users.delete');
    final id = req.param('id');
    final user = userIn(req, id);
    if (id == req.persona.userId) {
      req.fail(MockResponse.forbidden('You cannot delete yourself'));
    }
    requireDominance(req, user);
    if (isManager(req) && !shareABranch(id, req.persona.userId)) {
      req.fail(
        MockResponse.forbidden(
          'You can only delete users assigned to your branches',
        ),
      );
    }
    // Soft delete (`deleted_at`), as the backend: past orders keep the name.
    users.update(id, {'deleted_at': db.nowIso, 'is_active': false});
    db[UsersTables.pins].delete(id);
    links.removeWhere((r) => r['user_id'] == id);
    return MockResponse.empty();
  });

  // ── branch assignments ───────────────────────────────────────────────

  server.on('GET', '/users/{id}/branches', (req) {
    req.requireCap('staff.users.read');
    final id = req.param('id');
    if (isManager(req) &&
        id != req.persona.userId &&
        !shareABranch(id, req.persona.userId)) {
      req.fail(MockResponse.forbidden('You do not have access to this user'));
    }
    return MockResponse.ok([
      for (final b in branchesOfUser(id))
        if (db['branches'].find(b) case final row?)
          UserBranch(branchId: b, branchName: row['name']! as String),
    ]);
  });

  Map<String, Object?> branchFor(MockRequest req, String branchId) {
    final b = db['branches'].get(branchId, what: 'Branch not found');
    req.requireSameOrg(b['org_id'] as String?);
    return b;
  }

  server.on('POST', '/users/{id}/branches', (req) {
    req.requireCap('staff.permissions.edit');
    final id = req.param('id');
    final user = userIn(req, id);
    final branchId = req.bodyAs(AssignBranchRequest.fromJson).branchId;
    branchFor(req, branchId);
    if (id != req.persona.userId) requireDominance(req, user);
    if (isManager(req) &&
        !branchesOfUser(req.persona.userId).contains(branchId)) {
      req.fail(
        MockResponse.forbidden(
          'You cannot assign a user to a branch you are not assigned to',
        ),
      );
    }
    links.put({
      'id': AdminSeed.assignmentId(id, branchId),
      'user_id': id,
      'branch_id': branchId,
    });
    return MockResponse.empty();
  });

  server.on('DELETE', '/users/{id}/branches/{branchId}', (req) {
    req.requireCap('staff.permissions.edit');
    final id = req.param('id');
    final user = userIn(req, id);
    if (id != req.persona.userId) requireDominance(req, user);
    final branchId = req.param('branchId');
    branchFor(req, branchId);
    if (isManager(req) &&
        !branchesOfUser(req.persona.userId).contains(branchId)) {
      req.fail(
        MockResponse.forbidden(
          'You cannot unassign a user from a branch you are not assigned to',
        ),
      );
    }
    links.delete(AdminSeed.assignmentId(id, branchId));
    return MockResponse.empty();
  });

  // ── people's access (authz/api.rs) ───────────────────────────────────

  server.on('GET', '/authz/roles', (req) {
    req.requireAnyCap(const ['staff.permissions.read', 'staff.roles.manage']);
    return MockResponse.ok(db['roles'].rows);
  });

  /// `org_of` + `target_row`: the person, in the org acted in.
  Map<String, Object?> targetIn(MockRequest req, String id) {
    final org = req.orgId;
    if (org == null) req.fail(MockResponse.forbidden('No organization selected'));
    final u = users.find(id);
    if (!live(u) || u!['org_id'] != org) req.notFound('User not found');
    return u;
  }

  server.on('GET', '/authz/users/{id}', (req) {
    final id = req.param('id');
    if (id != req.persona.userId) {
      req.requireAnyCap(const [
        'staff.permissions.read',
        'staff.permissions.edit',
      ]);
    }
    targetIn(req, id);
    return MockResponse.ok(_access(db, req, id, req.q('branch_id')));
  });

  void branchInOrg(MockRequest req, String branchId) {
    if (db['branches'].find(branchId)?['org_id'] != req.orgId) {
      req.badRequest('Unknown branch');
    }
  }

  server.on('PUT', '/authz/users/{id}/overrides', (req) {
    req.requireCap('staff.permissions.edit');
    final body = req.bodyAs(SetOverrideRequest.fromJson);
    final meta = _meta(body.capability);
    if (meta == null) req.badRequest('Unknown capability ${body.capability}');
    if (meta.tier == 'legacy') {
      req.badRequest(
        '${body.capability} is kept for older tablets and cannot be changed',
      );
    }
    final id = req.param('id');
    final target = targetIn(req, id);
    final branchId = body.branchId;
    if (branchId != null) branchInOrg(req, branchId);
    _mayTouch(req, id, target);
    final effect = body.effect;
    if (effect != 'inherit' && effect != 'allow' && effect != 'deny') {
      req.badRequest('effect must be inherit, allow or deny');
    }
    if (effect != 'inherit' && !req.persona.can(meta.key)) {
      req.fail(
        MockResponse.forbidden(
          'You can only grant what you hold yourself (${meta.key})',
        ),
      );
    }
    if (isCoreForKind(meta, target['role']! as String)) {
      req.fail(
        MockResponse.forbidden(
          '${meta.key} is always on for this role and can\'t be removed',
        ),
      );
    }
    final table = db[UsersTables.overrides];
    table.removeWhere(
      (o) =>
          o['user_id'] == id &&
          o['capability'] == meta.key &&
          o['branch_id'] == branchId,
    );
    if (effect != 'inherit') {
      final limits = body.limits;
      table.insert({
        'user_id': id,
        'capability': meta.key,
        'effect': effect,
        'branch_id': branchId,
        // `restricted_to(cap.meta().limits)`: only the limits it takes.
        'limits': limits == null ? null : _restrict(limits, meta).toJson(),
        'reason': body.reason?.trim(),
      }, timestamps: false);
    }
    return MockResponse.ok(_access(db, req, id, branchId));
  });

  server.on('PUT', '/authz/users/{id}/assignments', (req) {
    req.requireCap('staff.users.edit');
    final id = req.param('id');
    final target = targetIn(req, id);
    final body = req.bodyAs(SetAssignmentsRequest.fromJson);
    if (body.assignments.isEmpty) {
      req.badRequest('A person needs at least one role');
    }
    final rows = <Map<String, Object?>>[];
    for (final a in body.assignments) {
      final role = db['roles'].find(a.roleId);
      if (role == null) req.badRequest('Unknown role');
      final kind = role['kind']! as String;
      if (!(req.persona.isOwner || _rank(kind) < _rank(req.persona.role))) {
        req.fail(
          MockResponse.forbidden(
            'You can only change people whose role is below yours',
          ),
        );
      }
      _mayTouch(req, id, target);
      final branches = a.branchIds ?? const <String>[];
      if (!a.allBranches && branches.isEmpty) {
        req.badRequest('Choose the branches, or all branches');
      }
      for (final b in branches) {
        branchInOrg(req, b);
      }
      rows.add({
        'user_id': id,
        'role_id': a.roleId,
        'kind': kind,
        'all_branches': a.allBranches,
        'branch_ids': a.allBranches ? const <String>[] : branches,
      });
    }
    final stays = rows.any((r) => r['kind'] == 'org_admin');
    if (target['role'] == 'org_admin' &&
        !stays &&
        !users.rows.any(
          (u) =>
              live(u) &&
              u['id'] != id &&
              u['org_id'] == target['org_id'] &&
              u['role'] == 'org_admin' &&
              u['is_active'] == true,
        )) {
      req.conflict(
        "This is the organization's last active owner. Add another owner "
        'first.',
      );
    }
    final table = db[UsersTables.assignments];
    table.removeWhere((r) => r['user_id'] == id);
    for (final r in rows) {
      table.insert(r, timestamps: false);
    }
    return MockResponse.ok(_access(db, req, id, null));
  });

  server.on('GET', '/authz/explain', (req) {
    final userId = req.q('user_id');
    final key = req.q('capability');
    if (userId == null || key == null) {
      req.badRequest('Query deserialize error: missing field `user_id`');
    }
    if (userId != req.persona.userId) {
      req.requireCap('staff.permissions.read');
    }
    final target = targetIn(req, userId);
    final meta = _meta(key);
    if (meta == null) req.badRequest('Unknown capability');
    return MockResponse.ok(
      _explain(db, target, meta, req.q('branch_id')),
    );
  });

  // ── Make employee (ADM-USR-014) ──────────────────────────────────────

  // The team area owns this read; it is registered here only when that
  // area is not loaded (this unit's tests), with the team's own rules.
  if (!server.handles('GET', '/staff/employees/linkable')) {
    server.on('GET', '/staff/employees/linkable', (req) {
      req.requireCap('hr.staff.create');
      final linked = {
        for (final e in db['employees'].rows)
          if (e['user_id'] case final String id) id,
      };
      final scoped = req.persona.branchIds;
      return MockResponse.ok([
        for (final u in users.query(
          filters: {'org_id': req.orgId, 'is_active': true},
          where: (u) =>
              live(u) &&
              u['role'] != 'super_admin' &&
              !linked.contains(u['id']) &&
              (scoped == null || scoped.contains(u['branch_id'])),
          sort: 'name',
        ))
          LinkableUser(
            userId: u['id']! as String,
            name: u['name']! as String,
            email: u['email'] as String?,
            phone: u['phone'] as String?,
            role: u['role']! as String,
          ),
      ]);
    });
  }
}

// ── the access resolver (a small `madar_authz::resolve`) ─────────────────

CapabilityMeta? _meta(String key) =>
    capabilityRegistry.firstWhereOrNull((c) => c.key == key);

/// Whether [meta] is always on for a person whose role is [kind].
bool isCoreForKind(CapabilityMeta meta, String kind) => meta.core.contains(kind);

LimitsView _restrict(LimitsView l, CapabilityMeta meta) => LimitsView(
  maxAmount: meta.limits.contains('max_amount') ? l.maxAmount : null,
  maxPercent: meta.limits.contains('max_percent') ? l.maxPercent : null,
  maxValue: meta.limits.contains('max_value') ? l.maxValue : null,
  maxAgeMinutes: meta.limits.contains('max_age_minutes')
      ? l.maxAgeMinutes
      : null,
  own: meta.limits.contains('own') ? l.own : null,
);

/// `g::may_touch`, in the order the backend checks: yourself, an owner, a
/// person not below you, the authority to edit at all.
String? _lockedReason(MockRequest req, String id, Map<String, Object?> t) {
  final p = req.persona;
  if (id == p.userId) return 'self';
  if (p.isPlatform) return null;
  final role = t['role']! as String;
  if (role == 'org_admin' && !p.isOwner) return 'owner';
  if (!p.isOwner && _rank(role) >= _rank(p.role)) return 'not_above';
  if (!p.can('staff.permissions.edit')) return 'missing_authority';
  return null;
}

void _mayTouch(MockRequest req, String id, Map<String, Object?> target) {
  final why = _lockedReason(req, id, target);
  final message = switch (why) {
    null || 'missing_authority' => null,
    'self' => 'You cannot change your own access',
    'owner' => "Only an owner can change an owner's access",
    _ => 'You can only change people whose role is below yours',
  };
  if (message != null) req.fail(MockResponse.forbidden(message));
}

class _Resolved {
  _Resolved(this.assignments, this.roles, this.overrides);

  final List<Map<String, Object?>> assignments;
  final Map<String, Map<String, Object?>> roles;
  final List<Map<String, Object?>> overrides;

  List<Map<String, Object?>> covering(String? branchId) => [
    for (final a in assignments)
      if (branchId == null ||
          a['all_branches'] == true ||
          (a['branch_ids'] as List).contains(branchId))
        a,
  ];

  bool roleGrants(Map<String, Object?> a, String cap) {
    final role = roles[a['role_id']];
    final grants = (role?['grants'] as List?) ?? const [];
    return grants.any((g) => (g as Map)['capability'] == cap);
  }

  String roleName(Map<String, Object?> a, {bool ar = false}) =>
      (roles[a['role_id']]?[ar ? 'name_ar' : 'name_en'] as String?) ?? '';

  /// The override that decides at [branchId]: the branch's own first, then
  /// the every-branch one.
  Map<String, Object?>? overrideAt(String cap, String? branchId) =>
      overrides.firstWhereOrNull(
        (o) => o['capability'] == cap && o['branch_id'] == branchId,
      ) ??
      overrides.firstWhereOrNull(
        (o) => o['capability'] == cap && o['branch_id'] == null,
      );
}

_Resolved _resolve(MockDb db, String userId) => _Resolved(
  db[UsersTables.assignments].where((a) => a['user_id'] == userId),
  {for (final r in db['roles'].rows) r['id']! as String: r},
  db[UsersTables.overrides].where((o) => o['user_id'] == userId),
);

UserAccess _access(MockDb db, MockRequest req, String id, String? branchId) {
  final target = db['users'].get(id, what: 'User not found');
  final role = target['role']! as String;
  final owner = role == 'org_admin' || role == 'super_admin';
  final active = target['is_active'] == true;
  final r = _resolve(db, id);
  final covering = r.covering(branchId);
  final locked = _lockedReason(req, id, target);

  bool effectiveOf(CapabilityMeta m) {
    if (!active) return false;
    if (owner) return true;
    if (isCoreForKind(m, role)) return true;
    final o = r.overrideAt(m.key, branchId);
    if (o != null) return o['effect'] == 'allow';
    return covering.any((a) => r.roleGrants(a, m.key));
  }

  final caps = <CapabilityAccess>[];
  for (final m in capabilityRegistry) {
    if (m.tier == 'legacy') continue;
    final fromRoles = [
      for (final a in covering)
        if (r.roleGrants(a, m.key)) r.roleName(a),
    ];
    final own = [
      for (final o in r.overrides)
        if (o['capability'] == m.key)
          OverrideView(
            effect: o['effect']! as String,
            branchId: o['branch_id'] as String?,
            limits: o['limits'] == null
                ? null
                : LimitsView.fromJson((o['limits']! as Map).cast()),
          ),
    ];
    final core = isCoreForKind(m, role);
    final decided = r.overrideAt(m.key, branchId);
    final source = owner
        ? 'owner'
        : core
        ? 'core'
        : decided != null
        ? decided['effect']! as String
        : fromRoles.isNotEmpty
        ? 'role'
        : 'none';
    final effective = effectiveOf(m);
    final limits = decided?['limits'];
    caps.add(
      CapabilityAccess(
        capability: m.key,
        effective: effective,
        source: source,
        fromRoles: fromRoles,
        overrides: own,
        limits: effective && limits is Map
            ? LimitsView.fromJson(limits.cast())
            : null,
        editable:
            locked == null &&
            !core &&
            !(owner && m.isProtected) &&
            (req.persona.can(m.key) || effective),
      ),
    );
  }
  return UserAccess(
    userId: id,
    name: target['name']! as String,
    isOwner: owner,
    branchId: branchId,
    canEdit: locked == null,
    lockedReason: locked,
    assignments: [
      for (final a in r.assignments)
        AssignmentView(
          id: a['id']! as String,
          roleId: a['role_id']! as String,
          roleNameEn: r.roleName(a),
          roleNameAr: r.roleName(a, ar: true),
          kind: a['kind']! as String,
          allBranches: a['all_branches'] == true,
          branchIds: [for (final b in a['branch_ids']! as List) b as String],
        ),
    ],
    capabilities: caps,
  );
}

Explanation _explain(
  MockDb db,
  Map<String, Object?> target,
  CapabilityMeta m,
  String? branchId,
) {
  final id = target['id']! as String;
  final role = target['role']! as String;
  final owner = role == 'org_admin' || role == 'super_admin';
  final active = target['is_active'] == true;
  final r = _resolve(db, id);
  final o = r.overrideAt(m.key, branchId);
  final covering = r.covering(branchId);
  final effective =
      active &&
      (owner ||
          isCoreForKind(m, role) ||
          (o != null
              ? o['effect'] == 'allow'
              : covering.any((a) => r.roleGrants(a, m.key))));
  final policy = db[AdminTables.policy].firstWhere(
    (p) => p['capability'] == m.key,
  );
  final ask = !effective && policy?['ask_manager'] == true;
  return Explanation(
    capability: m.key,
    labelEn: m.en,
    labelAr: m.ar,
    effective: effective,
    askManager: ask,
    steps: [
      if (!active) const ExplainStep(kind: 'inactive'),
      if (owner) const ExplainStep(kind: 'owner'),
      for (final a in r.assignments)
        ExplainStep(
          kind: m.core.contains(a['kind']) ? 'core' : 'assignment',
          roleName: r.roleName(a),
          roleNameAr: r.roleName(a, ar: true),
          appliesHere: covering.contains(a),
          grants: r.roleGrants(a, m.key) || m.core.contains(a['kind']),
        ),
      for (final x in r.overrides)
        if (x['capability'] == m.key)
          ExplainStep(
            kind: x['effect'] == 'allow' ? 'override_allow' : 'override_deny',
            branchId: x['branch_id'] as String?,
          ),
      if (owner && m.isProtected) const ExplainStep(kind: 'protected'),
      if (effective && o?['limits'] != null) const ExplainStep(kind: 'limit'),
      if (ask) const ExplainStep(kind: 'ask_manager'),
      if (!effective) const ExplainStep(kind: 'not_held'),
    ],
  );
}
