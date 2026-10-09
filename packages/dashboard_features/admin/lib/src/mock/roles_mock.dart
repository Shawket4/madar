/// `/access/roles` Roles & Permissions (ADM-ROL rows): POST /authz/roles,
/// PATCH/DELETE /authz/roles/{id}, PUT /authz/roles/{id}/grants, GET/PUT
/// /authz/policy (seed: the core `roles` table, [RolesSeed] and
/// `AdminSeed.policy`). `GET /authz/roles` is the Users unit's handler over
/// the same `roles` table (one endpoint, one handler).
///
/// Handlers behave like the backend (MadarRust `authz/api.rs`, the
/// `madar_authz::guard::may_edit_role` guard): org first, then the
/// capability (403 envelope), then validation (400/409), not-found, and
/// state over the shared [MockDb] (a create shows in the next list).
library;

import 'dart:convert' show utf8;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show CapabilityMeta, capabilityRegistry;

import '../area_seed.dart';
import 'users_mock.dart' show UsersTables;

/// A role Sabah made itself: nobody holds it yet, so it can be deleted.
abstract final class RolesSeed {
  static final String seniorCashier = mockUuid('role:sabah:senior-cashier');

  /// The ordinary cashier's grants, plus voiding and refunds up to EGP 1,000.
  static Map<String, Object?> get seniorCashierRow => {
    'id': seniorCashier,
    'org_id': SeedIds.sabahOrg,
    'key': 'senior_cashier_5c1e7a',
    'kind': 'teller',
    'name_en': 'Senior cashier',
    'name_ar': 'كاشير أول',
    'is_system': false,
    'editable': true,
    'members': 0,
    'grants': [
      for (final c in _template('teller'))
        _grant(c, c.key == 'refunds.create' ? {'max_amount': 100000} : null),
      if (!_template('teller').any((c) => c.key == 'orders.void'))
        _grant(_meta('orders.void')!, null),
    ],
  };
}

const List<String> _kinds = ['branch_manager', 'teller', 'waiter', 'kitchen'];

/// The backend's list order: built-in first, by kind, then by English name.
const List<String> _kindOrder = [
  'org_admin',
  'branch_manager',
  'teller',
  'waiter',
  'kitchen',
];

CapabilityMeta? _meta(String key) =>
    capabilityRegistry.firstWhereOrNull((c) => c.key == key);

bool _core(CapabilityMeta c, String kind) => c.core.contains(kind);

/// `template_grants("restaurant", kind) − core_set(kind)`, legacy left out.
List<CapabilityMeta> _template(String kind) => [
  for (final c in capabilityRegistry)
    if (c.tier != 'legacy' &&
        !c.key.startsWith('platform.') &&
        c.defaults.contains(kind) &&
        !_core(c, kind))
      c,
];

Map<String, Object?> _grant(CapabilityMeta c, Map<String, Object?>? limits) =>
    {'capability': c.key, 'limits': limits ?? const {}, 'source': 'custom'};

/// `Limits::restricted_to(meta.limits)`: only the limits it takes.
Map<String, Object?> _restrict(LimitsView? l, CapabilityMeta meta) => {
  if (l != null)
    for (final MapEntry(:key, :value) in l.toJson().entries)
      if (value != null && meta.limits.contains(key)) key: value,
};

void registerRolesMocks(MockServer server, MockDb db) {
  loadAdminSeed(db);
  final roles = db['roles'];
  final policy = db[AdminTables.policy];
  if (roles.find(RolesSeed.seniorCashier) == null) {
    roles.insert(RolesSeed.seniorCashierRow, timestamps: false);
  }

  /// `members`: distinct live people with a role assignment (the Users
  /// unit's table), and the backend's order. Kept on the rows, so the list
  /// handler answers them as they are.
  void tidy() {
    if (db.hasTable(UsersTables.assignments)) {
      final holders = <Object?, Set<Object?>>{};
      for (final a in db[UsersTables.assignments].rows) {
        final u = db['users'].find(a['user_id']! as String);
        if (u == null || u['deleted_at'] != null) continue;
        (holders[a['role_id']] ??= {}).add(a['user_id']);
      }
      for (final r in roles.rows) {
        r['members'] = holders[r['id']]?.length ?? 0;
      }
    }
    int rank(MockRow r) => _kindOrder.indexOf(r['kind']! as String);
    roles.rows.sort((a, b) {
      final system = (b['is_system'] == true ? 1 : 0).compareTo(
        a['is_system'] == true ? 1 : 0,
      );
      if (system != 0) return system;
      final kind = rank(a).compareTo(rank(b));
      if (kind != 0) return kind;
      return (a['name_en']! as String).compareTo(b['name_en']! as String);
    });
    roles.removeWhere((_) => false); // re-index after the in-place sort
  }

  tidy();

  /// `org_of`: the org acted in.
  String orgOf(MockRequest req) =>
      req.orgId ?? req.fail(MockResponse.forbidden('No organization selected'));

  /// `one_role`: the role, in the org (the core seed's rows are Sabah's).
  MockRow roleIn(MockRequest req, String org, String id) {
    final r = roles.find(id);
    if (r == null || (r['org_id'] ?? SeedIds.sabahOrg) != org) {
      req.notFound('Role not found');
    }
    return r;
  }

  MockResponse answer(MockRow row, [int status = 200]) {
    tidy();
    return MockResponse.json(status, RoleView.fromJson(row).toJson());
  }

  /// `cap_of`: a known capability that is not kept for older tablets.
  CapabilityMeta capOf(MockRequest req, String key) {
    final meta = _meta(key);
    if (meta == null) req.badRequest('Unknown capability $key');
    if (meta.tier == 'legacy') {
      req.badRequest('$key is kept for older tablets and cannot be changed');
    }
    return meta;
  }

  /// `may_edit_role`'s "only what is ADDED must be held".
  void held(MockRequest req, Iterable<String> added) {
    for (final key in added) {
      if (!req.persona.can(key)) {
        req.fail(
          MockResponse.forbidden(
            'You can only grant what you hold yourself ($key)',
          ),
        );
      }
    }
  }

  server.on('POST', '/authz/roles', (req) {
    final org = orgOf(req);
    req.requireCap('staff.roles.manage');
    final body = req.bodyAs(CreateRoleRequest.fromJson);
    if (!_kinds.contains(body.kind)) {
      req.badRequest('kind must be branch_manager, teller, waiter or kitchen');
    }
    final en = body.nameEn.trim(), ar = body.nameAr.trim();
    // `str::len` counts bytes: an Arabic letter is two.
    if (en.isEmpty ||
        ar.isEmpty ||
        utf8.encode(en).length > 80 ||
        utf8.encode(ar).length > 80) {
      req.badRequest('A role needs an English and an Arabic name');
    }
    final copy = body.copyFrom;
    final caps = copy == null
        ? [for (final c in _template(body.kind)) c.key]
        : [
            for (final g in roleIn(req, org, copy)['grants']! as List)
              if (_meta((g as Map)['capability']! as String)?.tier != 'legacy')
                g['capability']! as String,
          ];
    held(req, caps);
    final slug = en.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '_');
    final id = db.newId('roles');
    final row = roles.insert({
      'id': id,
      'org_id': org,
      'key':
          '${slug.substring(0, slug.length.clamp(0, 40)).replaceAll(RegExp(r'^_+|_+$'), '')}'
          '_${id.substring(0, 6)}',
      'kind': body.kind,
      'name_en': en,
      'name_ar': ar,
      'is_system': false,
      'editable': true,
      'members': 0,
      // Copied grants keep the capabilities, not their limits (`role_caps`).
      'grants': [for (final k in caps) _grant(_meta(k)!, null)],
    }, timestamps: false);
    return answer(row, 201);
  });

  server.on('PATCH', '/authz/roles/{id}', (req) {
    final org = orgOf(req);
    req.requireCap('staff.roles.manage');
    final role = roleIn(req, org, req.param('id'));
    final body = req.bodyAs(RenameRoleRequest.fromJson);
    final en = body.nameEn?.trim() ?? role['name_en']! as String;
    final ar = body.nameAr?.trim() ?? role['name_ar']! as String;
    if (en.isEmpty || ar.isEmpty) {
      req.badRequest('A role needs an English and an Arabic name');
    }
    role['name_en'] = en;
    role['name_ar'] = ar;
    return answer(role);
  });

  server.on('PUT', '/authz/roles/{id}/grants', (req) {
    final org = orgOf(req);
    req.requireCap('staff.roles.manage');
    final body = req.bodyAs(SetGrantRequest.fromJson);
    final meta = capOf(req, body.capability);
    final role = roleIn(req, org, req.param('id'));
    if (role['editable'] != true) {
      req.conflict('The owner role holds everything and cannot be edited');
    }
    final kind = role['kind']! as String;
    final grants = (role['grants']! as List).cast<Map<String, Object?>>();
    final before = {
      for (final g in grants) g['capability']! as String,
      for (final c in capabilityRegistry)
        if (_core(c, kind)) c.key,
    };
    if (!body.granted && _core(meta, kind)) {
      req.fail(
        MockResponse.forbidden(
          "${meta.key} is always on for this role and can't be removed",
        ),
      );
    }
    if (body.granted && !before.contains(meta.key)) held(req, [meta.key]);
    // ponytail: no `LimitAbove` check; the mock's personas hold no limits.
    final rest = [
      for (final g in grants)
        if (g['capability'] != meta.key) g,
    ];
    if (body.granted) {
      final limits = _restrict(body.limits, meta);
      // Always on already and unlimited: nothing to store.
      if (_core(meta, kind) && limits.isEmpty) return answer(role);
      rest.add(_grant(meta, limits));
    }
    role['grants'] = rest;
    return answer(role);
  });

  server.on('DELETE', '/authz/roles/{id}', (req) {
    final org = orgOf(req);
    req.requireCap('staff.roles.manage');
    tidy();
    final role = roleIn(req, org, req.param('id'));
    if (role['is_system'] == true) {
      req.conflict('Built-in roles cannot be deleted');
    }
    if ((role['members']! as int) > 0) {
      req.conflict(
        'People still hold this role. Move them to another role first.',
      );
    }
    roles.delete(role['id']! as String);
    return MockResponse.empty();
  });

  /// `get_policy`: every approval capability of the registry, asked or not.
  List<Map<String, Object?>> policyOf(String org) => [
    for (final c in capabilityRegistry)
      if (c.approval)
        PolicyEntry(
          capability: c.key,
          askManager: policy.rows.any(
            (p) =>
                p['org_id'] == org &&
                p['capability'] == c.key &&
                p['ask_manager'] == true,
          ),
        ).toJson(),
  ];

  // Any member of the org may read it (the POS shows the ask step by it).
  server.on('GET', '/authz/policy', (req) => MockResponse.ok(policyOf(orgOf(req))));

  server.on('PUT', '/authz/policy', (req) {
    final org = orgOf(req);
    req.requireCap('staff.roles.manage');
    final body = req.bodyAs(PolicyEntry.fromJson);
    final meta = capOf(req, body.capability);
    if (!meta.approval) {
      req.badRequest('${meta.key} cannot be approved by a manager');
    }
    final row = policy.firstWhere(
      (p) => p['org_id'] == org && p['capability'] == meta.key,
    );
    if (row == null) {
      policy.insert({
        'org_id': org,
        'capability': meta.key,
        'ask_manager': body.askManager,
      }, timestamps: false);
    } else {
      row['ask_manager'] = body.askManager;
    }
    return MockResponse.ok(policyOf(org));
  });
}
