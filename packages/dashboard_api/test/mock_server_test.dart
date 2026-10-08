// The mock backend: routing, params, refusals in the backend's envelope,
// paging conventions, state, overrides and streams.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

ApiRequest _get(String path, [Map<String, List<String>> query = const {}]) =>
    ApiRequest(method: 'GET', path: path, query: query);

Matcher _refusal(int status, String error, {String? code}) =>
    isA<ApiException>()
        .having((e) => e.status, 'status', status)
        .having((e) => e.message, 'message', error)
        .having((e) => e.code, 'code', code)
        .having((e) => (e.details! as Map)['error'], 'envelope error', error);

void main() {
  group('routing', () {
    test(
      'path params are captured and decoded; literals beat params',
      () async {
        final server = MockServer()
          ..on(
            'GET',
            '/orders/{order_id}',
            (req) => MockResponse.ok({'by': 'id', 'id': req.param('order_id')}),
          )
          ..on(
            'GET',
            '/orders/export',
            (req) => MockResponse.ok({'by': 'export'}),
          )
          ..on(
            'GET',
            '/staff/payroll/periods/{id}/export.csv',
            (req) => MockResponse.text(req.param('id')),
          );
        expect((await server.send(_get('/orders/export'))).status, 200);
        expect(server.calls.last.template, '/orders/export');
        final r = await server.send(_get('/orders/a%20b'));
        expect(MockResponse(r.status, bodyBytes: r.bodyBytes).json, {
          'by': 'id',
          'id': 'a b',
        });
        expect(server.calls.last.operationId, 'get_order');
        final csv = await server.send(
          _get('/staff/payroll/periods/p1/export.csv'),
        );
        expect(String.fromCharCodes(csv.bodyBytes), 'p1');
      },
    );

    test('an unmatched route answers 501 and is recorded', () async {
      final server = MockServer();
      await expectLater(
        server.send(_get('/nowhere')),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 501)),
      );
      expect(server.unmatched.single.path, '/nowhere');
      expect(server.unmatched.single.status, 501);
      // The method matters too.
      server.on('GET', '/thing', (req) => MockResponse.ok(1));
      await expectLater(
        server.send(const ApiRequest(method: 'POST', path: '/thing')),
        throwsA(isA<ApiException>()),
      );
      expect(server.unmatched, hasLength(2));
    });

    test('a later registration replaces the earlier one', () async {
      final server = MockServer()
        ..on('GET', '/x', (req) => MockResponse.ok('core'))
        ..on('GET', '/x', (req) => MockResponse.ok('area'));
      final r = await server.send(_get('/x'));
      expect(MockResponse(200, bodyBytes: r.bodyBytes).json, 'area');
      expect(server.routes.where((r) => r == 'GET /x'), hasLength(1));
      expect(server.handles('get', '/x'), isTrue);
    });

    test('onOperation registers by operationId', () async {
      final server = MockServer()
        ..onOperation(
          'list_timezones',
          (req) => MockResponse.ok(['Africa/Cairo']),
        );
      expect(await DashboardApi(server).branches.listTimezones(), [
        'Africa/Cairo',
      ]);
      expect(
        () => server.onOperation('nope', (req) => MockResponse.ok(null)),
        throwsArgumentError,
      );
    });

    test('query parsing, JSON bodies through the wire, headers', () async {
      late MockRequest seen;
      final server = MockServer()
        ..on('POST', '/things', (req) {
          seen = req;
          return MockResponse.created({'ok': true});
        });
      await server.send(
        ApiRequest(
          method: 'POST',
          path: '/things',
          query: const {
            'status': ['open', 'paid'],
            'page': ['2'],
            'flagged': ['true'],
            'from': ['2026-10-01T21:00:00.000Z'],
          },
          body: {'at': DateTime.utc(2026, 10, 8).toIso8601String(), 'n': 1},
          headers: const {'X-Branch-Id': 'b1'},
        ),
      );
      expect(seen.qAll('status'), ['open', 'paid']);
      expect(seen.q('status'), 'open');
      expect(seen.qInt('page'), 2);
      expect(seen.qBool('flagged'), isTrue);
      expect(seen.qDateTime('from'), DateTime.utc(2026, 10, 1, 21));
      expect(seen.json, {'at': '2026-10-08T00:00:00.000Z', 'n': 1});
      expect(seen.branchHeader, 'b1');
      expect(seen.query, {
        'status': 'open',
        'page': '2',
        'flagged': 'true',
        'from': '2026-10-01T21:00:00.000Z',
      });
    });

    test('a malformed number in the query is a 400 like actix', () async {
      final server = MockServer()
        ..on('GET', '/p', (req) => MockResponse.ok(req.qInt('page')));
      await expectLater(
        server.send(
          _get('/p', {
            'page': ['two'],
          }),
        ),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
      );
    });
  });

  group('refusals in the backend envelope', () {
    test('requireCap answers 403 with the capability named', () async {
      final server = MockServer(persona: Persona.limited)
        ..on('POST', '/orders/{id}/void', (req) {
          req.requireCap('orders.void');
          return MockResponse.ok(null);
        });
      await expectLater(
        server.send(const ApiRequest(method: 'POST', path: '/orders/o1/void')),
        throwsA(
          _refusal(
            403,
            "Forbidden: You don't have permission to do this: Void orders (orders.void)",
          ),
        ),
      );
      expect(server.calls.single.status, 403);
      server.persona = Persona.owner;
      expect(
        (await server.send(
          const ApiRequest(method: 'POST', path: '/orders/o1/void'),
        )).status,
        200,
      );
    });

    test('a branch-scoped persona is refused at another branch', () async {
      final server = MockServer(persona: Persona.manager)
        ..on('GET', '/b/{id}', (req) {
          req.requireCap('orders.read', branchId: req.param('id'));
          return MockResponse.ok(null);
        });
      expect((await server.send(_get('/b/${SeedIds.zamalek}'))).status, 200);
      await expectLater(
        server.send(_get('/b/${SeedIds.maadi}')),
        throwsA(_refusal(403, 'Forbidden: Not assigned to this branch')),
      );
    });

    test('platform-only, same-org, not found, 400, 409, 422', () async {
      final server = MockServer()
        ..on('GET', '/platform', (req) {
          req.requirePlatform();
          return MockResponse.ok(null);
        })
        ..on('GET', '/org/{id}', (req) {
          req.requireSameOrg(req.param('id'));
          return MockResponse.ok(null);
        })
        ..on('GET', '/missing', (req) => req.notFound('Order'))
        ..on('GET', '/bad', (req) => req.badRequest('name must not be empty'))
        ..on(
          'GET',
          '/conflict',
          (req) => req.conflict(
            'A till is already open',
            code: 'TILL_OPEN_ELSEWHERE',
          ),
        )
        ..on(
          'GET',
          '/invalid',
          (req) => req.unprocessable(
            'This payment method is switched off.',
            code: 'PAYMENT_METHOD_UNAVAILABLE',
          ),
        );
      await expectLater(
        server.send(_get('/platform')),
        throwsA(_refusal(403, 'Forbidden: Super admin access required')),
      );
      expect((await server.send(_get('/org/${SeedIds.sabahOrg}'))).status, 200);
      await expectLater(
        server.send(_get('/org/${SeedIds.nakhlaOrg}')),
        throwsA(_refusal(403, 'Forbidden: Access to this org is not allowed')),
      );
      await expectLater(
        server.send(_get('/missing')),
        throwsA(_refusal(404, 'Not found: Order')),
      );
      await expectLater(
        server.send(_get('/bad')),
        throwsA(_refusal(400, 'Bad request: name must not be empty')),
      );
      await expectLater(
        server.send(_get('/conflict')),
        throwsA(
          _refusal(409, 'A till is already open', code: 'TILL_OPEN_ELSEWHERE'),
        ),
      );
      await expectLater(
        server.send(_get('/invalid')),
        throwsA(
          _refusal(
            422,
            'This payment method is switched off.',
            code: 'PAYMENT_METHOD_UNAVAILABLE',
          ),
        ),
      );
      server.persona = Persona.platform;
      expect((await server.send(_get('/platform'))).status, 200);
      expect(
        (await server.send(_get('/org/${SeedIds.nakhlaOrg}'))).status,
        200,
      );
    });

    test('vars and codes reach ApiException.details', () async {
      final server = MockServer()
        ..on(
          'POST',
          '/punch',
          (req) => MockResponse.error(
            403,
            'You are 340 m from the branch.',
            code: 'OUTSIDE_FENCE',
            vars: {'distance_m': 340, 'radius_m': 150},
          ),
        );
      await expectLater(
        server.send(const ApiRequest(method: 'POST', path: '/punch')),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'OUTSIDE_FENCE')
              .having((e) => (e.details! as Map)['vars'], 'vars', {
                'distance_m': 340,
                'radius_m': 150,
              }),
        ),
      );
    });

    test('a crashing handler is a 500 and is recorded', () async {
      final server = MockServer()
        ..on('GET', '/boom', (req) => throw StateError('handler bug'));
      await expectLater(
        server.send(_get('/boom')),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)),
      );
      expect(server.handlerErrors.single, isA<StateError>());
    });

    test('a body that does not fit the request model is a 400', () async {
      final server = MockServer()
        ..on('POST', '/auth/login', (req) {
          req.bodyAs(LoginRequest.fromJson);
          return MockResponse.ok(null);
        });
      await expectLater(
        server.send(
          const ApiRequest(
            method: 'POST',
            path: '/auth/login',
            body: {'email': 7},
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 400)
              .having(
                (e) => e.message,
                'message',
                startsWith('Bad request: Json deserialize error'),
              ),
        ),
      );
    });
  });

  group('overrides', () {
    test('fail() answers a canned error the given number of times', () async {
      final server = MockServer()..on('GET', '/x', (req) => MockResponse.ok(1));
      server.fail('GET', '/x', MockResponse.forbidden('Not today'), times: 2);
      await expectLater(
        server.send(_get('/x')),
        throwsA(_refusal(403, 'Forbidden: Not today')),
      );
      await expectLater(server.send(_get('/x')), throwsA(isA<ApiException>()));
      expect((await server.send(_get('/x'))).status, 200);
      server.fail(
        'GET',
        '/x',
        MockResponse.error(500, 'Internal error'),
        times: null,
      );
      for (var i = 0; i < 3; i++) {
        await expectLater(
          server.send(_get('/x')),
          throwsA(isA<ApiException>()),
        );
      }
      server.clearFailures();
      expect((await server.send(_get('/x'))).status, 200);
    });

    test(
      'hold() keeps a call pending until released (loading states)',
      () async {
        final server = MockServer()
          ..on('GET', '/x', (req) => MockResponse.ok(1));
        final gate = server.hold('GET', '/x');
        var done = false;
        final f = server.send(_get('/x')).then((_) => done = true);
        await Future<void>.delayed(Duration.zero);
        expect(done, isFalse);
        gate.release();
        await f;
        expect(done, isTrue);
      },
    );

    test('latency delays every answer', () async {
      final server = MockServer(latency: const Duration(milliseconds: 30))
        ..on('GET', '/x', (req) => MockResponse.ok(1));
      final sw = Stopwatch()..start();
      await server.send(_get('/x'));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(25));
    });
  });

  group('streams', () {
    test(
      'onStream routes server-sent events; channels carry published frames',
      () async {
        final server = MockServer()
          ..onStream(
            'GET',
            '/realtime/stream',
            (req) => req.server.channel('rt'),
          );
        final frames = <String>[];
        final sub = server.stream(_get('/realtime/stream')).listen(frames.add);
        server.publish('rt', '{"type":"floor.changed"}');
        await Future<void>.delayed(Duration.zero);
        expect(frames, ['{"type":"floor.changed"}']);
        expect(server.calls.single.stream, isTrue);
        await sub.cancel();
        await server.close();
      },
    );

    test('an unmatched stream errors with 501', () async {
      final server = MockServer();
      await expectLater(
        server.stream(_get('/realtime/stream')),
        emitsError(isA<ApiException>()),
      );
      expect(server.unmatched, hasLength(1));
    });
  });

  group('MockDb', () {
    test('create with deterministic ids and timestamps, update, delete', () {
      final db = MockDb();
      final t = db['suppliers'];
      final a = t.insert({'name': 'Delta Dairy'});
      final b = t.insert({'name': 'Nile Beans'});
      expect(a['id'], mockUuid('suppliers#1'));
      expect(b['id'], mockUuid('suppliers#2'));
      expect(a['created_at'], '2026-10-08T07:00:00.000Z');
      db.clock.advance(const Duration(minutes: 5));
      t.update(a['id']! as String, {'name': 'Delta Dairy Co.'});
      expect(t.get(a['id']! as String)['name'], 'Delta Dairy Co.');
      expect(
        t.get(a['id']! as String)['updated_at'],
        '2026-10-08T07:05:00.000Z',
      );
      expect(t.delete(b['id']! as String), isTrue);
      expect(t.delete(b['id']! as String), isFalse);
      expect(t.length, 1);
      expect(
        () => t.get('nope'),
        throwsA(
          isA<MockHttpError>().having((e) => e.response.status, 'status', 404),
        ),
      );
      // A second database mints the same ids: tests are reproducible.
      expect(MockDb()['suppliers'].insert({'name': 'x'})['id'], a['id']);
    });

    test('query: filters, search, date range, sort', () {
      final db = MockDb();
      final t = db['things']
        ..insertAll([
          {
            'id': '1',
            'name': 'Latte',
            'branch_id': 'z',
            'created_at': '2026-10-01T08:00:00Z',
            'price': 115,
          },
          {
            'id': '2',
            'name': 'Iced Latte',
            'branch_id': 'm',
            'created_at': '2026-10-05T08:00:00Z',
            'price': 130,
          },
          {
            'id': '3',
            'name': 'Espresso',
            'branch_id': 'z',
            'created_at': '2026-10-07T08:00:00Z',
            'price': 70,
          },
        ]);
      expect(
        t
            .query(filters: {'branch_id': 'z', 'status': null})
            .map((r) => r['id']),
        ['1', '3'],
      );
      expect(
        t.query(
          filters: {
            'branch_id': ['z', 'm'],
          },
        ),
        hasLength(3),
      );
      expect(t.query(search: 'LATTE').map((r) => r['id']), ['1', '2']);
      expect(
        t
            .query(
              from: DateTime.utc(2026, 10, 2),
              to: DateTime.utc(2026, 10, 7, 8),
            )
            .map((r) => r['id']),
        ['2'],
      );
      expect(t.query(sort: '-price').map((r) => r['id']), ['2', '1', '3']);
      expect(t.query(sort: 'name').map((r) => r['id']), ['3', '2', '1']);
      expect(t.query(filters: {'price': '70'}).single['id'], '3');
    });

    test(
      'pageOf: the backend page envelope, clamped like the backend',
      () async {
        final items = [for (var i = 0; i < 120; i++) i];
        late Map<String, Object?> page;
        final server = MockServer()
          ..on('GET', '/p', (req) {
            page = pageOf(items, req, defaultPerPage: 50, maxPerPage: 100);
            return MockResponse.ok(page);
          });
        await server.send(_get('/p'));
        expect(page['page'], 1);
        expect(page['per_page'], 50);
        expect(page['total'], 120);
        expect(page['total_pages'], 3);
        expect((page['data']! as List).first, 0);
        await server.send(
          _get('/p', {
            'page': ['3'],
          }),
        );
        expect(page['data'], [
          100,
          101,
          102,
          103,
          104,
          105,
          106,
          107,
          108,
          109,
          110,
          111,
          112,
          113,
          114,
          115,
          116,
          117,
          118,
          119,
        ]);
        await server.send(
          _get('/p', {
            'page': ['0'],
            'per_page': ['500'],
          }),
        );
        expect(page['page'], 1);
        expect(page['per_page'], 100);
        await server.send(
          _get('/p', {
            'page': ['9'],
          }),
        );
        expect(page['data'], isEmpty);
      },
    );

    test('sliceOf: limit/offset as a plain array', () async {
      final items = [for (var i = 0; i < 30; i++) i];
      late List<int> slice;
      final server = MockServer()
        ..on('GET', '/s', (req) {
          slice = sliceOf(items, req, defaultLimit: 10, maxLimit: 20);
          return MockResponse.ok(slice);
        });
      await server.send(_get('/s'));
      expect(slice, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      await server.send(
        _get('/s', {
          'limit': ['5'],
          'offset': ['27'],
        }),
      );
      expect(slice, [27, 28, 29]);
      await server.send(
        _get('/s', {
          'limit': ['1000'],
        }),
      );
      expect(slice, hasLength(20));
    });

    test(
      'the seeded database holds the seed as JSON rows; big tables load lazily',
      () {
        final db = MockDb.seeded();
        expect(
          db['branches'].query(filters: {'org_id': SeedIds.sabahOrg}),
          hasLength(4),
        );
        expect(db['menu_items'].length, 40);
        expect(db['orders'].length, MockSeed.instance.orders.length);
        expect(db['orders'].find(MockSeed.instance.orders.last.id), isNotNull);
        final created = db['orders'].insert({'branch_id': SeedIds.zamalek});
        expect(db['orders'].find(created['id']! as String), isNotNull);
        // Rows are copies: changing one db never touches another.
        db['branches'].update(SeedIds.maadi, {'name': 'Maadi Degla'});
        expect(MockDb.seeded()['branches'].get(SeedIds.maadi)['name'], 'Maadi');
      },
    );
  });

  test('personas carry the registry capabilities', () {
    expect(Persona.owner.can('orders.void'), isTrue);
    expect(Persona.owner.can('platform.orgs.create'), isFalse);
    expect(Persona.platform.can('platform.orgs.create'), isTrue);
    expect(Persona.manager.can('orders.void'), isTrue);
    expect(Persona.manager.can('branches.delete'), isFalse);
    expect(Persona.manager.seesBranch(SeedIds.zamalek), isTrue);
    expect(Persona.manager.seesBranch(SeedIds.maadi), isFalse);
    expect(Persona.limited.capabilities, unorderedEquals(limitedCapabilities));
    expect(Persona.dawamOnly.modules, ['dawam']);
    expect(Persona.dawamOnly.orgId, SeedIds.nakhlaOrg);
    expect(Persona.byEmail('KARIM@sabah.test '), Persona.manager);
    expect(Persona.byUserId(SeedIds.owner), Persona.owner);
    for (final p in Persona.values) {
      for (final c in p.capabilities) {
        expect(
          mockCapabilities.any((m) => m.key == c),
          isTrue,
          reason: '${p.name} $c',
        );
      }
    }
  });

  test('MockServer.toApiException keeps a non-envelope status readable', () {
    final e = MockServer.toApiException(
      MockResponse.text('<html>', status: 502),
    );
    expect(e.status, 502);
    expect(e.message, 'HTTP 502');
  });

  test('handlers may answer asynchronously', () async {
    final server = MockServer()
      ..on('GET', '/later', (req) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return MockResponse.ok('done');
      });
    final r = await server.send(_get('/later'));
    expect(MockResponse(200, bodyBytes: r.bodyBytes).json, 'done');
  });
}
