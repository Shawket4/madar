import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart' show RealtimeFrame;
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/data/core_transport.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart' as rb;

/// A core that answers from the test and records what it was asked.
class FakeCore implements CoreApi {
  final calls = <rb.ApiCall>[];
  final streams = <String, StreamController<rb.ApiStreamItem>>{};
  final cancelled = <String>[];
  Future<rb.ApiReply> Function(rb.ApiCall call)? answer;

  @override
  Future<rb.ApiReply> apiRequest(rb.ApiCall call) {
    calls.add(call);
    return answer!(call);
  }

  @override
  Stream<rb.ApiStreamItem> apiStream(rb.ApiCall call, String streamId) {
    calls.add(call);
    return (streams[streamId] = StreamController<rb.ApiStreamItem>()).stream;
  }

  @override
  void apiStreamCancel(String streamId) => cancelled.add(streamId);

  StreamController<rb.ApiStreamItem> get last => streams.values.last;
}

rb.ApiStreamItem opened() =>
    const rb.ApiStreamItem(opened: true, event: '', data: '');

rb.ApiStreamItem frame(String event, String data, [String? id]) =>
    rb.ApiStreamItem(opened: false, event: event, data: data, id: id);

rb.ApiStreamItem failed(rb.ApiFailure f) =>
    rb.ApiStreamItem(opened: false, event: '', data: '', failure: f);

rb.ApiFailure failure({
  int status = 422,
  String? code,
  String message = 'name is required',
  rb.ApiFailureKind kind = rb.ApiFailureKind.validation,
  String? body,
}) => rb.ApiFailure(
  status: status,
  code: code,
  message: message,
  kind: kind,
  body: body,
);

void main() {
  group('a request reaches the core whole', () {
    test('query pairs repeat in order, headers and a JSON body', () {
      final call = coreCallOf(
        ApiRequest(
          method: 'post',
          path: '/orders/o1/void',
          query: {
            'status': ['open', 'paid'],
            'q': ['قهوة'],
          },
          headers: {'X-Madar-Export': '1'},
          body: {
            'reason': 'Wrong table',
            'at': DateTime.utc(2026, 10, 8, 12),
            'lines': [1, 2],
          },
        ),
      );
      expect(call.method, 'POST');
      expect(call.path, '/orders/o1/void');
      expect(
        [for (final p in call.query) '${p.key}=${p.value}'],
        ['status=open', 'status=paid', 'q=قهوة'],
      );
      expect(call.headers.single.key, 'X-Madar-Export');
      expect(jsonDecode(call.jsonBody!), {
        'reason': 'Wrong table',
        'at': '2026-10-08T12:00:00.000Z',
        'lines': [1, 2],
      });
      expect(call.formFields, isEmpty);
      expect(call.files, isEmpty);
    });

    test('no body sends none', () {
      final call = coreCallOf(const ApiRequest(method: 'GET', path: '/x'));
      expect(call.jsonBody, isNull);
    });

    test('files make it multipart, the body map its fields', () {
      final call = coreCallOf(
        ApiRequest(
          method: 'POST',
          path: '/orgs',
          body: {
            'name': 'Sabah Coffee',
            'tax_rate': 0.14,
            'tax_inclusive': true,
            'receipt_footer': null,
            'tags': ['a', null, 'b'],
            'settings': {'x': 1},
          },
          files: const [
            ApiFilePart(
              field: 'logo',
              filename: 'logo.png',
              bytes: [1, 2, 3],
              contentType: 'image/png',
            ),
          ],
        ),
      );
      expect(call.jsonBody, isNull);
      expect(
        [for (final p in call.formFields) '${p.key}=${p.value}'],
        [
          'name=Sabah Coffee',
          'tax_rate=0.14',
          'tax_inclusive=true',
          'tags=a',
          'tags=b',
          'settings={"x":1}',
        ],
      );
      final file = call.files.single;
      expect(
        (file.field, file.filename, file.contentType),
        ('logo', 'logo.png', 'image/png'),
      );
      expect(file.bytes, Uint8List.fromList([1, 2, 3]));
    });

    test('a multipart body that is not a map is a programming error', () {
      expect(() => formFieldsOf('text'), throwsArgumentError);
      expect(formFieldsOf(null), isEmpty);
    });

    test('the branch event stream asks like the web', () {
      final r = realtimeRequest(
        branchId: 'b1',
        topics: 'floor,tickets',
        lastEventId: '41',
      );
      expect((r.method, r.path), ('GET', '/realtime/stream'));
      expect(r.query, {
        'branch_id': ['b1'],
        'topics': ['floor,tickets'],
      });
      expect(r.headers, {'Last-Event-ID': '41'});
      expect(realtimeRequest(branchId: 'b1', topics: 't').headers, isEmpty);
    });
  });

  group('answers', () {
    test('a reply keeps its bytes; repeated headers fold', () {
      final r = apiResponseOf(
        rb.ApiReply(
          status: 201,
          headers: const [
            rb.ApiPair(key: 'Content-Type', value: 'application/json'),
            rb.ApiPair(key: 'vary', value: 'origin'),
            rb.ApiPair(key: 'Vary', value: 'accept'),
          ],
          body: Uint8List.fromList(utf8.encode('{"id":"x"}')),
        ),
      );
      expect(r.status, 201);
      expect(r.ok, isTrue);
      expect(r.headers, {
        'content-type': 'application/json',
        'vary': 'origin, accept',
      });
      expect(utf8.decode(r.bodyBytes), '{"id":"x"}');
    });

    test('a refusal keeps its status, code, words and envelope', () {
      final body =
          '{"error":"Bad request: name is required","code":"FIELD_REQUIRED","vars":{"field":"name"}}';
      final e = apiExceptionOf(failure(code: 'FIELD_REQUIRED', body: body));
      expect(
        (e.status, e.code, e.message),
        (422, 'FIELD_REQUIRED', 'name is required'),
      );
      expect(e.details, {
        'error': 'Bad request: name is required',
        'code': 'FIELD_REQUIRED',
        'vars': {'field': 'name'},
      });
    });

    test('the web\'s sentence for a code wins when the host has one', () {
      final body =
          '{"error":"x","code":"SHIFTS_OVERLAP","vars":{"a":"Morning"}}';
      String? words(String code, Map<String, Object?> vars) =>
          code == 'SHIFTS_OVERLAP' ? 'Overlaps ${vars['a']}' : null;
      final e = apiExceptionOf(
        failure(status: 409, code: 'SHIFTS_OVERLAP', body: body),
        refusalWords: words,
      );
      expect(e.message, 'Overlaps Morning');
      final unknown = apiExceptionOf(
        failure(code: 'NEW_CODE', body: '{"code":"NEW_CODE"}'),
        refusalWords: words,
      );
      expect(unknown.message, 'name is required');
    });

    test('nothing from our server reads as status 0, never a refusal', () {
      String words(String code, Map<String, Object?> vars) => 'refused';
      final blocked = apiExceptionOf(
        failure(
          status: 403,
          message: 'Something on this network is blocking the Madar server.',
          kind: rb.ApiFailureKind.blockedUpstream,
          body: '<html>Access denied</html>',
        ),
        refusalWords: words,
      );
      expect(blocked.status, 0);
      expect(blocked.message, startsWith('Something on this network'));
      expect(blocked.details, isNull);
      final portal = apiExceptionOf(
        failure(status: 401, kind: rb.ApiFailureKind.offline),
      );
      expect(portal.status, 0);
      final offline = apiExceptionOf(
        failure(status: 0, kind: rb.ApiFailureKind.offline),
      );
      expect(offline.status, 0);
    });
  });

  group('CoreTransport', () {
    late FakeCore core;
    late CoreTransport transport;

    setUp(() {
      core = FakeCore();
      transport = CoreTransport(core);
    });

    test(
      'send returns the reply and throws a refusal as ApiException',
      () async {
        core.answer = (call) async => rb.ApiReply(
          status: 200,
          headers: const [],
          body: Uint8List.fromList(utf8.encode('[]')),
        );
        final ok = await transport.send(
          const ApiRequest(method: 'GET', path: '/branches'),
        );
        expect(ok.status, 200);
        expect(core.calls.single.path, '/branches');

        core.answer = (call) async => throw failure(code: 'FIELD_REQUIRED');
        await expectLater(
          transport.send(const ApiRequest(method: 'POST', path: '/menu-items')),
          throwsA(
            isA<ApiException>()
                .having((e) => e.status, 'status', 422)
                .having((e) => e.code, 'code', 'FIELD_REQUIRED'),
          ),
        );
      },
    );

    test(
      'events carry names; a drop is an ApiException; cancel stops the core',
      () async {
        final got = <RealtimeFrame>[];
        final errors = <Object>[];
        var opens = 0;
        final sub = transport
            .events(
              const ApiRequest(method: 'GET', path: '/realtime/stream'),
              onOpen: () => opens++,
            )
            .listen(got.add, onError: errors.add);
        await pumpEventQueue();
        final id = core.streams.keys.single;
        core.last
          ..add(opened())
          ..add(frame('booking.created', '{"id":"b1"}', '7'))
          ..add(frame('message', '', '8'))
          ..add(failed(failure(status: 0, kind: rb.ApiFailureKind.offline)));
        await pumpEventQueue();
        expect(opens, 1);
        expect(
          [for (final f in got) (f.event, f.data, f.id)],
          [('booking.created', '{"id":"b1"}', '7'), ('message', '', '8')],
        );
        expect(
          errors.single,
          isA<ApiException>().having((e) => e.status, 'status', 0),
        );
        await sub.cancel();
        expect(core.cancelled, [id]);
      },
    );

    test('stream yields the data of frames that carry any', () async {
      final data = <String>[];
      final done = Completer<void>();
      transport
          .stream(const ApiRequest(method: 'POST', path: '/basira/ask'))
          .listen(data.add, onDone: done.complete);
      await pumpEventQueue();
      core.last
        ..add(opened())
        ..add(frame('message', 'one'))
        ..add(frame('message', '', '3'))
        ..add(frame('message', 'two'));
      await core.last.close();
      await done.future;
      expect(data, ['one', 'two']);
    });

    test('the realtime gateway opens once the server accepted', () async {
      final gateway = CoreRealtimeGateway(transport);
      final connecting = gateway.connect(
        branchId: 'b1',
        topics: 'floor',
        lastEventId: '9',
      );
      await pumpEventQueue();
      final asked = core.calls.single;
      expect(asked.path, '/realtime/stream');
      expect(asked.headers.single.value, '9');
      core.last
        ..add(opened())
        ..add(frame('floor.updated', '{}', '10'));
      final frames = await connecting;
      final first = await frames.first;
      expect((first.event, first.id), ('floor.updated', '10'));
      await pumpEventQueue();
      expect(core.cancelled, hasLength(1), reason: 'taking one frame cancels');
    });

    test('a refused realtime stream fails connect with the refusal', () async {
      final connecting = CoreRealtimeGateway(
        transport,
      ).connect(branchId: 'b1', topics: 'floor');
      await pumpEventQueue();
      core.last.add(
        failed(
          failure(
            status: 403,
            code: 'NO_TOPICS',
            message: 'no topics',
            kind: rb.ApiFailureKind.forbidden,
          ),
        ),
      );
      await expectLater(
        connecting,
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 403)
              .having((e) => e.message, 'message', 'no topics'),
        ),
      );
    });
  });
}
