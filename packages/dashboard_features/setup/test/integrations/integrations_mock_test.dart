// The Integrations mock against MadarRust `src/integrations/handlers.rs`:
// gates, scope, validation, conflicts, state.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A request acting in Sabah (a platform admin's header) unless [noOrg].
Future<ApiResponse> _send(
  MockServer s,
  String method,
  String path, {
  Object? body,
  bool noOrg = false,
}) => s.send(
  ApiRequest(
    method: method,
    path: path,
    body: body,
    headers: noOrg ? const {} : {'X-Org-Id': SeedIds.sabahOrg},
  ),
);

/// The status the request ends with (a refusal throws its [ApiException]).
Future<int> _status(Future<ApiResponse> f) async {
  try {
    return (await f).status;
  } on ApiException catch (e) {
    return e.status;
  }
}

Object? _json(ApiResponse r) => jsonDecode(utf8.decode(r.bodyBytes));

void main() {
  late MockServer s;
  late MockDb db;

  void as(Persona p) {
    final m = integrationsServer(persona: p);
    s = m.server;
    db = m.db;
  }

  const list = '/integrations/credentials';
  final rue = IntegrationsSeed.id('rue');

  test('SET-INT-005 the org\'s credentials, newest first, no secret', () async {
    as(Persona.owner);
    final r = await _send(s, 'GET', list);
    expect(r.status, 200);
    final rows = (_json(r)! as List).cast<Map<String, Object?>>();
    expect([for (final c in rows) c['name']], [
      'Talabat Insights',
      'Rue — One Ninety',
      'Cairo Analytics Co.',
    ]);
    expect(rows[1]['branch_name'], 'Zamalek');
    expect(rows[0]['last_used_at'], isNull);
    expect(rows[2]['revoked_at'], isNotNull);
    for (final c in rows) {
      expect(c.containsKey('secret'), isFalse);
    }
  });

  test('SET-INT-001 the list needs integrations.read', () async {
    as(Persona.manager);
    expect(await _status(_send(s, 'GET', list)), 403);
    as(Persona.limited);
    expect(await _status(_send(s, 'GET', list)), 403);
  });

  test('SET-INT-002 a platform admin without an org is a 400', () async {
    as(Persona.platform);
    expect(await _status(_send(s, 'GET', list, noOrg: true)), 400);
  });

  test('SET-INT-030 every write is super admin only', () async {
    as(Persona.owner);
    final body = {
      'name': 'X',
      'branch_id': SeedIds.maadi,
      'username': 'xyz-abcdef',
    };
    expect(await _status(_send(s, 'POST', list, body: body)), 403);
    expect(await _status(_send(s, 'POST', '$list/$rue/rotate')), 403);
    expect(await _status(_send(s, 'DELETE', '$list/$rue')), 403);
    expect(db[IntegrationsSeed.table].find(rue)!['revoked_at'], isNull);
  });

  test('SET-INT-019 create: 201 with the secret once; the next list shows '
      'it', () async {
    as(Persona.platform);
    final r = await _send(
      s,
      'POST',
      list,
      body: {
        'name': '  Nile Data  ',
        'branch_id': SeedIds.maadi,
        'username': ' nile-data-q2w3e4 ',
      },
    );
    expect(r.status, 201);
    final c = _json(r)! as Map<String, Object?>;
    expect(c['name'], 'Nile Data');
    expect(c['username'], 'nile-data-q2w3e4');
    expect(c['branch_name'], 'Maadi');
    expect(c['secret'], matches(RegExp(r'^[0-9a-f]{64}$')));
    final rows = _json(await _send(s, 'GET', list))! as List;
    expect(rows, hasLength(4));
    expect((rows.first as Map)['name'], 'Nile Data');
    expect((rows.first as Map).containsKey('secret'), isFalse);
  });

  test('SET-INT-019 create refusals: blank name, username length, a branch '
      'of another org, a taken username (case-blind)', () async {
    as(Persona.platform);
    Future<int> post(Map<String, Object?> b) async =>
        await _status(_send(s, 'POST', list, body: b));
    final ok = {
      'name': 'Nile',
      'branch_id': SeedIds.maadi,
      'username': 'nile-abcdef',
    };
    expect(await post({...ok, 'name': '   '}), 400);
    expect(await post({...ok, 'username': 'ab'}), 400);
    expect(await post({...ok, 'username': 'a' * 65}), 400);
    expect(await post({...ok, 'branch_id': SeedIds.dokki}), 404);
    expect(await post({...ok, 'username': 'RUE-ONE-NINETY-K7M2XQ'}), 409);
    expect(await post(ok), 201);
  });

  test('SET-INT-012 rotate: a new secret each time; a revoked or unknown '
      'credential is 404', () async {
    as(Persona.platform);
    final a = _json(await _send(s, 'POST', '$list/$rue/rotate'))! as Map;
    final b = _json(await _send(s, 'POST', '$list/$rue/rotate'))! as Map;
    expect(a['id'], rue);
    expect(a['secret'], isNot(b['secret']));
    final revoked = IntegrationsSeed.id('cairo-analytics');
    expect(await _status(_send(s, 'POST', '$list/$revoked/rotate')), 404);
    expect(
      await _status(_send(s, 'POST', '$list/${mockUuid('nope')}/rotate')),
      404,
    );
  });

  test('SET-INT-013 revoke: 204, idempotent, kept as a record; unknown '
      '404', () async {
    as(Persona.platform);
    expect(await _status(_send(s, 'DELETE', '$list/$rue')), 204);
    final at = db[IntegrationsSeed.table].find(rue)!['revoked_at'];
    expect(at, isNotNull);
    expect(await _status(_send(s, 'DELETE', '$list/$rue')), 204);
    expect(db[IntegrationsSeed.table].find(rue)!['revoked_at'], at);
    expect(
      await _status(_send(s, 'DELETE', '$list/${mockUuid('nope')}')),
      404,
    );
    final rows = _json(await _send(s, 'GET', list))! as List;
    expect(rows, hasLength(3));
  });
}
