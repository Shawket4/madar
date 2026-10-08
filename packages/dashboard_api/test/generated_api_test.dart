// Coverage and behaviour of the generated client: every operation has a
// method and a table entry, every schema a model that round-trips its JSON,
// and every method builds the right request and decodes its answer.
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/operation_calls.dart';
import 'generated/schema_decoders.dart';

final Map<String, Object?> _spec =
    jsonDecode(File('spec/openapi.json').readAsStringSync())
        as Map<String, Object?>;
final Map<String, Object?> _fixtures =
    jsonDecode(File('test/generated/api_fixtures.json').readAsStringSync())
        as Map<String, Object?>;
final Map<String, Object?> _samples =
    _fixtures['schemas']! as Map<String, Object?>;
final Map<String, Object?> _responses =
    _fixtures['responses']! as Map<String, Object?>;
final Map<String, Object?> _multipartFiles =
    _fixtures['multipart_files']! as Map<String, Object?>;

Map<String, Object?> _sample(String schema) =>
    _samples[schema]! as Map<String, Object?>;

String _camel(String id) {
  final words = id
      .split(RegExp('[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return words.first[0].toLowerCase() +
      words.first.substring(1) +
      words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
}

const _eq = DeepCollectionEquality();

Object? _toJson(Object model) => (model as dynamic).toJson();

void main() {
  final specOps = <({String id, String method, String path, String tag})>[
    for (final MapEntry(key: path, value: item)
        in (_spec['paths']! as Map<String, Object?>).entries)
      for (final MapEntry(key: method, value: op)
          in (item! as Map<String, Object?>).entries)
        (
          id: (op! as Map)['operationId'] as String,
          method: method.toUpperCase(),
          path: path,
          tag: ((op as Map)['tags'] as List).first as String,
        ),
  ];
  final schemas =
      ((_spec['components']! as Map)['schemas']! as Map<String, Object?>).keys
          .toList();

  group('coverage', () {
    test(
      'the spec is the one the SPEC describes (621 operations, 773 schemas)',
      () {
        expect(specOps, hasLength(621));
        expect(schemas, hasLength(773));
      },
    );

    test(
      'every operationId has exactly one table entry, with its lowerCamel method name',
      () {
        final byId = groupBy(apiOperations, (ApiOperation o) => o.id);
        for (final op in specOps) {
          final entries = byId[op.id];
          expect(entries, hasLength(1), reason: op.id);
          final e = entries!.single;
          expect(
            (e.method, e.path, e.tag),
            (op.method, op.path, op.tag),
            reason: op.id,
          );
          expect(e.name, _camel(op.id), reason: op.id);
        }
        expect(apiOperations, hasLength(specOps.length));
      },
    );

    test('every operationId has a callable method', () {
      final calls = {for (final c in operationCalls) c.id};
      expect(calls, {for (final op in specOps) op.id});
    });

    test('every schema has a model (or an enum)', () {
      for (final name in schemas) {
        expect(
          schemaDecoders.containsKey(name) || enumDecoders.containsKey(name),
          isTrue,
          reason: name,
        );
      }
    });

    test('the facade has one getter per tag', () {
      final api = DashboardApi(MockServer());
      expect(api.orders, isA<OrdersApi>());
      expect(api.bookingsPublic, isA<BookingsPublicApi>());
      expect(api.floorTransfers, isA<FloorTransfersApi>());
      expect(api.orderNow, isA<OrderNowApi>());
      expect({for (final o in apiOperations) o.tag}, hasLength(47));
    });
  });

  group('models', () {
    test('every object schema round-trips its sample JSON', () {
      var checked = 0;
      for (final MapEntry(key: name, value: decode) in schemaDecoders.entries) {
        final sample = _sample(name);
        final model = decode(sample);
        var json = _toJson(model)! as Map<String, Object?>;
        var expected = sample;
        final files = (_multipartFiles[name] as List?)?.cast<String>();
        if (files != null) {
          expected = {
            for (final e in sample.entries)
              if (!files.contains(e.key)) e.key: e.value,
          };
        }
        json = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
        expect(
          _eq.equals(json, expected),
          isTrue,
          reason:
              '$name\n  got:      ${jsonEncode(json)}\n  expected: ${jsonEncode(expected)}',
        );
        checked++;
      }
      expect(checked, greaterThan(740));
    });

    test('every enum decodes its values and keeps unknown ones', () {
      for (final MapEntry(key: name, value: decode) in enumDecoders.entries) {
        final values =
            ((_spec['components']! as Map)['schemas'] as Map)[name]['enum']
                as List;
        for (final v in values) {
          final e = decode(v as String);
          expect(_toJson(e), v, reason: name);
          expect((e as dynamic).isKnown, isTrue, reason: '$name.$v');
        }
        final unknown = decode('from_a_newer_server');
        expect(_toJson(unknown), 'from_a_newer_server');
        expect((unknown as dynamic).isKnown, isFalse);
      }
      expect(TillStatus.fromJson('force_closed'), TillStatus.forceClosed);
      expect(
        TillStatus.fromJson('force_closed') == TillStatus.forceClosed,
        isTrue,
      );
    });

    test('unions dispatch on their tag and keep unknown variants', () {
      final answer = AiChatKind.fromJson({
        'kind': 'clarify',
        'question': 'Which branch?',
      });
      expect(answer, isA<AiChatKindClarify>());
      expect((answer as AiChatKindClarify).question, 'Which branch?');
      expect(answer.toJson(), {'kind': 'clarify', 'question': 'Which branch?'});
      final unknown = AiChatKind.fromJson({'kind': 'sketch', 'svg': '<svg/>'});
      expect(unknown, isA<AiChatKindUnknown>());
      expect(unknown.toJson(), {'kind': 'sketch', 'svg': '<svg/>'});
      // A union without a tag matches on the variant's required keys.
      final ref = AssetGroupRef.fromJson({
        'status': 'processing',
        'job_id': 'j1',
      });
      expect(ref, isA<AssetGroupRefProcessingGroupRef>());
      // allOf over a union: the union part decodes from the same object.
      final res = AiChatResponse.fromJson({
        'kind': 'clarify',
        'question': 'Which branch?',
        'provider': 'jev',
        'timezone': 'Africa/Cairo',
      });
      expect(res.aiChatKind, isA<AiChatKindClarify>());
      expect(res.toJson()['question'], 'Which branch?');
    });

    test(
      'nullability: required fields fail loudly, optional nulls are omitted unless asked',
      () {
        expect(
          () => Branch.fromJson(const {'id': 'b1'}),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', 'decode')
                .having(
                  (e) => e.message,
                  'message',
                  contains('Branch.created_at'),
                ),
          ),
        );
        const patch = UpdateBranchRequest(name: 'Zamalek');
        expect(patch.toJson(), {'name': 'Zamalek'});
        const clear = UpdateBranchRequest(
          name: 'Zamalek',
          explicitNulls: {'printer_ip'},
        );
        expect(clear.toJson(), {'name': 'Zamalek', 'printer_ip': null});
      },
    );

    test('date-times decode to UTC, numbers are lenient on int/double', () {
      final till = TillBrief.fromJson({
        'branch_id': 'b',
        'id': 't',
        'opened_at': '2026-10-08T10:00:00+03:00',
        'opened_while_another_open': false,
        'status': 'open',
        'teller_id': 'u',
        'teller_name': 'Mariam Fathy',
        'verification': 'server',
      });
      expect(till.openedAt, DateTime.utc(2026, 10, 8, 7));
      expect(till.openedAt.isUtc, isTrue);
      expect(
        PaymentLeg.fromJson(const {'amount': 1500.0, 'method': 'cash'}).amount,
        1500,
      );
      expect(
        TaxPolicyPublic.fromJson(const {
          'service_charge_rate': 0,
          'service_charge_taxable': true,
          'tax_inclusive': true,
          'tax_rate': 0,
        }).taxRate,
        0.0,
      );
    });
  });

  group('operations', () {
    test(
      'every method builds its request and decodes the sample answer',
      () async {
        final server = MockServer(persona: Persona.owner);
        for (final c in operationCalls) {
          if (c.result == 'stream') {
            server.onStream(
              c.method,
              c.template,
              (req) => Stream.fromIterable(['a', 'b']),
            );
            continue;
          }
          server.on(
            c.method,
            c.template,
            (req) => switch (c.result) {
              'json' => MockResponse.ok(_responses[c.id]),
              'text' => MockResponse.text('a,b\n1,2', contentType: 'text/csv'),
              'bytes' => MockResponse.bytes(const [
                137,
                80,
                78,
                71,
              ], contentType: 'image/png'),
              _ => MockResponse.empty(),
            },
          );
        }
        final api = DashboardApi(server);
        for (final c in operationCalls) {
          final before = server.calls.length;
          final result = c.call(api, _sample);
          Object? value;
          if (result is Stream<String>) {
            value = await result.toList();
            expect(value, ['a', 'b'], reason: c.id);
          } else {
            value = await (result! as Future<Object?>);
          }
          expect(server.calls.length, before + 1, reason: c.id);
          final call = server.calls.last;
          expect(call.method, c.method, reason: c.id);
          expect(call.path, c.path, reason: c.id);
          expect(call.template, c.template, reason: c.id);
          expect(call.operationId, c.id, reason: c.id);
          expect(call.query.keys.toSet(), c.query.toSet(), reason: c.id);
          for (final h in c.headers) {
            expect(
              call.headers.containsKey(h),
              isTrue,
              reason: '${c.id} header $h',
            );
          }
          if (c.result == 'json') {
            expect(value, isNotNull, reason: c.id);
            // The decoded answer re-encodes to the sample.
            final again = jsonDecode(jsonEncode(value));
            expect(_eq.equals(again, _responses[c.id]), isTrue, reason: c.id);
          }
          if (c.result == 'text') expect(value, 'a,b\n1,2');
          if (c.result == 'bytes') expect(value, [137, 80, 78, 71]);
        }
        expect(server.unmatched, isEmpty);
        expect(server.handlerErrors, isEmpty);
      },
    );

    test('query values are encoded as the backend reads them', () async {
      final server = MockServer()
        ..on(
          'GET',
          '/orders',
          (req) => MockResponse.ok(_responses['list_orders']),
        );
      await DashboardApi(server).orders.listOrders(
        branchId: 'b1',
        from: DateTime.utc(2026, 10, 1, 21),
        to: DateTime.parse('2026-10-08T23:59:59+03:00'),
        page: 2,
        includeItems: true,
      );
      expect(server.calls.single.query, {
        'branch_id': ['b1'],
        'from': ['2026-10-01T21:00:00.000Z'],
        'to': ['2026-10-08T20:59:59.000Z'],
        'page': ['2'],
        'include_items': ['true'],
      });
    });

    test('path parameters are percent-encoded', () async {
      final server = MockServer()
        ..on(
          'GET',
          '/branches/{id}',
          (req) =>
              MockResponse.ok({..._sample('Branch'), 'id': req.param('id')}),
        );
      final b = await DashboardApi(server).branches.getBranch(id: 'a b/c');
      expect(server.calls.single.path, '/branches/a%20b%2Fc');
      expect(b.id, 'a b/c');
    });

    test(
      'a body that does not fit the model is a decode ApiException with the status',
      () async {
        final server = MockServer()
          ..on('GET', '/orgs/{id}', (req) => MockResponse.ok({'id': 7}));
        await expectLater(
          DashboardApi(server).orgs.getOrg(id: 'x'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.status, 'status', 200)
                .having((e) => e.code, 'code', 'decode')
                .having(
                  (e) => (e.details! as Map)['operation'],
                  'operation',
                  'get_org',
                ),
          ),
        );
      },
    );

    test('non-JSON answers are decode errors too', () async {
      final server = MockServer()
        ..on('GET', '/orgs/{id}', (req) => MockResponse.text('<html>'));
      await expectLater(
        DashboardApi(server).orgs.getOrg(id: 'x'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'decode')),
      );
    });

    test('multipart bodies send files and form fields', () async {
      final server = MockServer()
        ..on('POST', '/orgs', (req) => MockResponse.created(_sample('Org')));
      await DashboardApi(server).orgs.createOrg(
        body: CreateOrgMultipart(
          name: 'Sabah Coffee',
          slug: 'sabah-coffee',
          logo: const ApiFilePart(
            field: 'x',
            filename: 'logo.png',
            bytes: [1, 2],
          ),
        ),
      );
      final call = server.calls.single;
      expect(call.body, {'name': 'Sabah Coffee', 'slug': 'sabah-coffee'});
      expect(call.files.single.filename, 'logo.png');
      expect(call.files.single.field, 'logo');
    });
  });
}
