// The offline seam below the pages: OfflineTransport over the core's saved
// answers (what is saved, what is served and when, the derivations online
// and offline, the refusal of a write). The cache itself (its owner, its size
// bound, the keys and the derivers) is tested in madar-core `api_cache`.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart'
    show ApiPair, CacheRequest;

class _Host implements OfflineHost {
  @override
  CacheScope? scope = const CacheScope(user: 'u1', org: 'o1');
  DateTime clock = DateTime.utc(2026, 10, 8, 7);
  final List<DateTime> shown = [];
  int reached = 0;

  @override
  DateTime now() => clock;

  @override
  String? zoneFor(String? branchId) => 'Africa/Cairo';

  @override
  String get cantSaveWords => "You're offline, so this can't be saved.";

  @override
  void showedSaved(DateTime savedAt) => shown.add(savedAt);

  @override
  void reachedServer() => reached++;
}

ApiRequest _get(
  String path, {
  Map<String, List<String>> query = const {},
  Map<String, String> headers = const {},
}) => ApiRequest(method: 'GET', path: path, query: query, headers: headers);

Object? _json(ApiResponse r) => jsonDecode(utf8.decode(r.bodyBytes));

/// Tills opened every 6 hours from 1 Oct, Cairo time.
List<Map<String, Object?>> _tills() => [
  for (var h = 0; h < 8 * 24; h += 6)
    {
      'till_id': 't$h',
      'opened_at': DateTime.utc(
        2026,
        9,
        30,
        21,
      ).add(Duration(hours: h)).toIso8601String(),
    },
];

void main() {
  late _Host host;
  late MockServer server;
  late OfflineCache cache;
  late OfflineTransport t;
  var items = <String>['a', 'b'];

  setUp(() async {
    host = _Host();
    server = MockServer();
    items = ['a', 'b'];
    server
      ..on('GET', '/probe', (req) => MockResponse.ok(items))
      ..on('POST', '/probe', (req) => MockResponse.created(items))
      ..on('GET', '/auth/me', (req) => MockResponse.ok({'user': 'x'}))
      ..on('GET', '/gone', (req) => MockResponse.notFound())
      ..on('GET', '/reports/branches/{id}/tills', (req) {
        final from = req.qDateTime('from')!;
        final to = req.qDateTime('to')!;
        return MockResponse.ok([
          for (final r in _tills().reversed)
            if (!DateTime.parse(r['opened_at']! as String).isBefore(from) &&
                !DateTime.parse(r['opened_at']! as String).isAfter(to))
              r,
        ]);
      })
      ..onStream('GET', '/stream', (req) => Stream.value('x'));
    cache = memoryOfflineCache()..claim(userId: 'u1');
    t = OfflineTransport(server, cache: cache, host: host);
  });

  /// Whether an answer to [path] is saved for u1.
  bool kept(String path) =>
      cache.saved(
        scope: const CacheScope(user: 'u1', org: 'o1'),
        request: CacheRequest(
          method: 'GET',
          path: path,
          query: const <ApiPair>[],
          headers: const <ApiPair>[],
        ),
      ) !=
      null;

  group('the transport', () {
    test('online: every GET answer is saved, never served instead', () async {
      expect(_json(await t.send(_get('/probe'))), ['a', 'b']);
      expect(kept('/probe'), isTrue);
      items = ['c'];
      // The saved answer is older; online, the server's answer stands.
      expect(_json(await t.send(_get('/probe'))), ['c']);
      expect(server.callsTo('/probe'), hasLength(2));
      expect(host.shown, isEmpty);
      expect(host.reached, 2);
    });

    test('offline: the saved answer, with when it was saved', () async {
      final savedAt = host.clock;
      await t.send(_get('/probe'));
      host.clock = host.clock.add(const Duration(hours: 2));
      server.offline = true;
      expect(_json(await t.send(_get('/probe'))), ['a', 'b']);
      expect(host.shown, [savedAt]);
      // Nothing saved for this one: the offline error stands.
      await expectLater(
        t.send(
          _get(
            '/probe',
            query: {
              'q': ['x'],
            },
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)),
      );
    });

    test('a 403 without the envelope is offline; with it, a refusal', () async {
      await t.send(_get('/probe'));
      server.fail('GET', '/probe', const MockResponse(403));
      expect(_json(await t.send(_get('/probe'))), ['a', 'b']);
      expect(host.shown, hasLength(1));
      server.fail('GET', '/probe', MockResponse.forbidden('No'));
      await expectLater(
        t.send(_get('/probe')),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
      expect(host.shown, hasLength(1));
    });

    test(
      'exports, sign-in, streams, writes and refusals are never saved',
      () async {
        await t.send(_get('/probe', headers: {'X-Madar-Export': '1'}));
        await t.send(_get('/auth/me'));
        await t.stream(_get('/stream')).toList();
        await t.send(const ApiRequest(method: 'POST', path: '/probe'));
        await expectLater(t.send(_get('/gone')), throwsA(isA<ApiException>()));
        for (final p in ['/probe', '/auth/me', '/stream', '/gone']) {
          expect(kept(p), isFalse, reason: p);
        }
        // And signed out, nothing either.
        host.scope = null;
        await t.send(_get('/probe'));
        expect(kept('/probe'), isFalse);
      },
    );

    test('a write offline fails at once, in words that say so', () async {
      server.offline = true;
      await expectLater(
        t.send(const ApiRequest(method: 'POST', path: '/probe')),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 0)
              .having(
                (e) => e.message,
                'message',
                "You're offline, so this can't be saved.",
              ),
        ),
      );
      expect(server.calls, isEmpty);
    });

    group('a narrower range', () {
      const path = '/reports/branches/b1/tills';
      Map<String, List<String>> range(DateTime from, DateTime to) => {
        'from': [from.toIso8601String()],
        'to': [to.toIso8601String()],
      };
      final wide = range(
        DateTime.utc(2026, 9, 30, 21),
        DateTime.utc(2026, 10, 8, 21),
      );
      final narrow = range(
        DateTime.utc(2026, 10, 2, 21),
        DateTime.utc(2026, 10, 3, 20, 59),
      );

      test(
        'online: from a wide answer read under 30 s ago, as a hit',
        () async {
          await t.send(_get(path, query: wide));
          final live = server.callsTo('/reports/branches/{id}/tills').length;
          host.clock = host.clock.add(const Duration(seconds: 20));
          final derived = _json(await t.send(_get(path, query: narrow)));
          expect(
            server.callsTo('/reports/branches/{id}/tills'),
            hasLength(live),
          );
          server.offline = false;
          // What the server itself says for the narrow range.
          final t2 = OfflineTransport(server, cache: null, host: host);
          expect(derived, _json(await t2.send(_get(path, query: narrow))));
          expect(derived, hasLength(4));
          expect(host.shown, isEmpty);
        },
      );

      test(
        'online: never from an answer 30 s old, after a write, or twice',
        () async {
          int calls() => server.callsTo('/reports/branches/{id}/tills').length;
          await t.send(_get(path, query: wide));
          host.clock = host.clock.add(const Duration(seconds: 30));
          await t.send(_get(path, query: narrow));
          expect(calls(), 2);
          // Fresh wide again; a write in between: what was read may differ.
          await t.send(_get(path, query: wide));
          await t.send(const ApiRequest(method: 'POST', path: '/probe'));
          await t.send(_get(path, query: narrow));
          expect(calls(), 4);
          // Derived once; asked again inside 30 s it is a refetch: live.
          await t.send(_get(path, query: wide));
          await t.send(_get(path, query: narrow));
          expect(calls(), 5);
          await t.send(_get(path, query: narrow));
          expect(calls(), 6);
          // A realtime nudge forgets too.
          await t.send(_get(path, query: wide));
          t.forgetRecent();
          await t.send(
            _get(
              path,
              query: range(
                DateTime.utc(2026, 10, 1),
                DateTime.utc(2026, 10, 2),
              ),
            ),
          );
          expect(calls(), 8);
        },
      );

      test('offline: from a saved wide answer, the later saved wins', () async {
        final wideAt = host.clock;
        await t.send(_get(path, query: wide));
        server.offline = true;
        host.clock = host.clock.add(const Duration(hours: 1));
        final derived = _json(await t.send(_get(path, query: narrow)));
        expect(derived, hasLength(4));
        expect(host.shown, [wideAt]);
        // The narrow one saved later (online again) wins over the wide one.
        server.offline = false;
        host.clock = host.clock.add(const Duration(hours: 1));
        await t.send(_get(path, query: narrow));
        final narrowAt = host.clock;
        server.offline = true;
        await t.send(_get(path, query: narrow));
        expect(host.shown.last, narrowAt);
        // ...until a later wide one.
        server.offline = false;
        host.clock = host.clock.add(const Duration(hours: 1));
        final laterWideAt = host.clock;
        await t.send(_get(path, query: wide));
        // Past 30 s, so the narrow one is not a fresh hit on the wide one.
        host.clock = host.clock.add(const Duration(minutes: 1));
        server.offline = true;
        await t.send(_get(path, query: narrow));
        expect(host.shown.last, laterWideAt);
      });
    });
  });
}
