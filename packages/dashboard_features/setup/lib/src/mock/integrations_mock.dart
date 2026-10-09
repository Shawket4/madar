/// The mock backend for Integrations (`/settings/integrations`, SET-INT
/// rows), as MadarRust `src/integrations/handlers.rs` answers.
///
/// - `GET /integrations/credentials`: `integrations.read`; the org in scope
///   (a platform admin's `X-Org-Id`, else 400 "No organization in scope");
///   newest first; the secret never included.
/// - `POST /integrations/credentials` (201): super admin only; a blank name
///   or a username outside 3–64 characters is 400; a branch outside the org
///   404; a username taken anywhere (case-blind) 409.
/// - `POST /integrations/credentials/{id}/rotate`: super admin only; a new
///   secret; a revoked or unknown credential 404.
/// - `DELETE /integrations/credentials/{id}` (204): super admin only; a soft,
///   idempotent revoke; unknown 404.
///
/// Data ([IntegrationsSeed]): Sabah has three partners — Talabat Insights
/// on Heliopolis (newest, never used), Rue — One Ninety on Zamalek (used two
/// hours ago) and Cairo Analytics Co. on Maadi (revoked).
library;

import 'package:dashboard_api/mock.dart';

import 'support.dart';

/// The routes, for tests.
abstract final class IntegrationsRoutes {
  static const String list = '/integrations/credentials';
  static const String create = '/integrations/credentials';
  static const String rotate = '/integrations/credentials/{id}/rotate';
  static const String revoke = '/integrations/credentials/{id}';
}

/// The backend's refusal sentences (tests build the same responses).
abstract final class IntegrationsRefusals {
  static const String noOrg = 'No organization in scope';
  static const String nameRequired = '`name` is required';
  static const String usernameLength = '`username` must be 3–64 characters';
  static const String branchNotFound = 'Branch not found';
  static const String taken = 'That username is already taken';
  static const String notFound = 'Credential not found';
}

abstract final class IntegrationsSeed {
  static const String table = 'integration_credentials';

  static String id(String key) => mockUuid('integration-credential:$key');

  static final DateTime _now = MockClock.defaultNow;

  static MockRow _row(
    String key, {
    required String branch,
    required String name,
    required String username,
    required Duration age,
    Duration? lastUsed,
    Duration? revoked,
  }) => {
    'id': id(key),
    'org_id': SeedIds.sabahOrg,
    'branch_id': MockSeed.branchIdOf(branch),
    'name': name,
    'username': username,
    'created_at': _now.subtract(age).toIso8601String(),
    'last_used_at': lastUsed == null
        ? null
        : _now.subtract(lastUsed).toIso8601String(),
    'revoked_at': revoked == null
        ? null
        : _now.subtract(revoked).toIso8601String(),
  };

  static List<MockRow> get rows => [
    _row(
      'rue',
      branch: 'zamalek',
      name: 'Rue — One Ninety',
      username: 'rue-one-ninety-k7m2xq',
      age: const Duration(days: 41),
      lastUsed: const Duration(hours: 2),
    ),
    _row(
      'talabat',
      branch: 'heliopolis',
      name: 'Talabat Insights',
      username: 'talabat-insights-9fh3wd',
      age: const Duration(days: 12),
    ),
    _row(
      'cairo-analytics',
      branch: 'maadi',
      name: 'Cairo Analytics Co.',
      username: 'cairo-analytics-co-p4n8tz',
      age: const Duration(days: 96),
      lastUsed: const Duration(days: 58),
      revoked: const Duration(days: 52),
    ),
  ];
}

/// The org a credentials request acts in (`scope_org`).
String _scopeOrg(MockRequest req) =>
    req.orgId ?? req.badRequest(IntegrationsRefusals.noOrg);

/// The live branch [id] of [orgId], or null.
MockRow? _branch(MockDb db, String orgId, Object? id) => db['branches']
    .firstWhere(
      (b) => b['id'] == id && b['org_id'] == orgId && b['deleted_at'] == null,
    );

/// `CredentialSummary` (+ `secret` when [secret] is given).
MockRow _summary(MockDb db, MockRow r, {String? secret}) => {
  'id': r['id'],
  'name': r['name'],
  'username': r['username'],
  'branch_id': r['branch_id'],
  'branch_name': db['branches'].find(r['branch_id']! as String)?['name'],
  'created_at': r['created_at'],
  'last_used_at': r['last_used_at'],
  'revoked_at': r['revoked_at'],
  'secret': ?secret,
};

/// A fresh 64-hex secret (`generate_secret`: two v4 UUIDs, simple form).
String _secret(MockDb db) {
  final n = db.newId('integration-secret');
  return '${mockUuid('secret-a:$n')}${mockUuid('secret-b:$n')}'.replaceAll(
    '-',
    '',
  );
}

void registerIntegrationsMocks(MockServer server, MockDb db) {
  seedTableIfAbsent(db, IntegrationsSeed.table, () => IntegrationsSeed.rows);
  final table = db[IntegrationsSeed.table];

  server.on('GET', IntegrationsRoutes.list, (req) {
    req.requireCap('integrations.read');
    final org = _scopeOrg(req);
    final rows = table.where((r) => r['org_id'] == org)
      ..sort(
        (a, b) => (b['created_at']! as String).compareTo(
          a['created_at']! as String,
        ),
      );
    return MockResponse.ok([for (final r in rows) _summary(db, r)]);
  });

  server.on('POST', IntegrationsRoutes.create, (req) {
    req.requirePlatform();
    final org = _scopeOrg(req);
    final body = req.json;
    final name = (body['name'] as String? ?? '').trim();
    final username = (body['username'] as String? ?? '').trim();
    if (name.isEmpty) req.badRequest(IntegrationsRefusals.nameRequired);
    if (username.length < 3 || username.length > 64) {
      req.badRequest(IntegrationsRefusals.usernameLength);
    }
    final branch = _branch(db, org, body['branch_id']);
    if (branch == null) req.notFound(IntegrationsRefusals.branchNotFound);
    final lower = username.toLowerCase();
    if (table.rows.any(
      (r) => (r['username']! as String).toLowerCase() == lower,
    )) {
      req.conflict(IntegrationsRefusals.taken);
    }
    final row = table.insert({
      'org_id': org,
      'branch_id': branch['id'],
      'name': name,
      'username': username,
      'created_at': db.nowIso,
      'last_used_at': null,
      'revoked_at': null,
    }, timestamps: false);
    return MockResponse.created(_summary(db, row, secret: _secret(db)));
  });

  server.on('POST', IntegrationsRoutes.rotate, (req) {
    req.requirePlatform();
    final org = _scopeOrg(req);
    final row = table.find(req.param('id'));
    if (row == null || row['org_id'] != org || row['revoked_at'] != null) {
      req.notFound(IntegrationsRefusals.notFound);
    }
    return MockResponse.ok(_summary(db, row, secret: _secret(db)));
  });

  server.on('DELETE', IntegrationsRoutes.revoke, (req) {
    req.requirePlatform();
    final org = _scopeOrg(req);
    final row = table.find(req.param('id'));
    if (row == null || row['org_id'] != org) {
      req.notFound(IntegrationsRefusals.notFound);
    }
    if (row['revoked_at'] == null) {
      table.update(row['id']! as String, {'revoked_at': db.nowIso});
    }
    return MockResponse.empty();
  });
}
