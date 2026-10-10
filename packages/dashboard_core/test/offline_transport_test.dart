// The offline seam below the pages: the saved-answer store (its owner, its
// size bound, its index) and OfflineTransport (what is saved, what is served
// and when, the derivations online and offline, the refusal of a write).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host implements OfflineHost {
  @override
  OfflineScope? scope = const OfflineScope('u1', org: 'o1');
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
  late OfflineStore store;
  late OfflineTransport t;
  var items = <String>['a', 'b'];

  setUp(() async {
    ensureTimeZones();
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
    store = await OfflineStore.open(MemoryBlobs(), clock: () => host.clock);
    await store.claim('u1');
    t = OfflineTransport(server, store: store, host: host);
  });

  group('the store', () {
    test('past its bound the least recently used answers go', () async {
      final s = await OfflineStore.open(
        MemoryBlobs(),
        maxBytes: 100,
        clock: () => host.clock,
      );
      await s.claim('u1');
      for (var i = 0; i < 4; i++) {
        host.clock = host.clock.add(const Duration(minutes: 1));
        await s.write('u1', 'k$i', List.filled(30, i), host.clock);
      }
      // 120 bytes > 100: the oldest went, down to 90 % of the bound.
      expect(s.bytes, lessThanOrEqualTo(90));
      expect(s.savedAt('k0'), isNull);
      expect(s.savedAt('k3'), isNotNull);
      // A read makes an answer recent: the next eviction spares it.
      host.clock = host.clock.add(const Duration(minutes: 1));
      expect(await s.read('k1'), isNotNull);
      host.clock = host.clock.add(const Duration(minutes: 1));
      await s.write('u1', 'k4', List.filled(30, 4), host.clock);
      expect(s.savedAt('k1'), isNotNull);
      expect(s.savedAt('k2'), isNull);
      // One answer bigger than the whole bound is never saved.
      await s.write('u1', 'big', List.filled(101, 0), host.clock);
      expect(s.savedAt('big'), isNull);
    });

    test('one person at a time; reopened from its index', () async {
      final blobs = MemoryBlobs();
      final s = await OfflineStore.open(blobs, clock: () => host.clock);
      await s.claim('u1');
      await s.write('u1', 'k', utf8.encode('[1]'), host.clock);
      // A late answer for someone else is dropped.
      await s.write('u2', 'k2', utf8.encode('[2]'), host.clock);
      expect(s.length, 1);
      final again = await OfflineStore.open(blobs, clock: () => host.clock);
      expect(again.owner, 'u1');
      expect(utf8.decode((await again.read('k'))!.body), '[1]');
      expect((await again.read('k'))!.savedAt, host.clock);
      // Another person: everything of the first goes.
      await again.claim('u2');
      expect(again.length, 0);
      expect(blobs.files.keys, ['index.json']);
      await again.wipe();
      expect(again.owner, isNull);
      expect(blobs.files, isEmpty);
    });

    test('an unreadable index starts empty; stray files go', () async {
      final blobs = MemoryBlobs()
        ..files['index.json'] = utf8.encode('{nope')
        ..files['a0.json'] = utf8.encode('[1]');
      final s = await OfflineStore.open(blobs);
      expect(s.length, 0);
      expect(blobs.files, isEmpty);
      final b2 = MemoryBlobs()..files['a9.json'] = utf8.encode('[1]');
      await OfflineStore.open(b2);
      expect(b2.files, isEmpty);
    });
  });

  group('the transport', () {
    test('online: every GET answer is saved, never served instead', () async {
      expect(_json(await t.send(_get('/probe'))), ['a', 'b']);
      await pumpEventQueue();
      expect(store.length, 1);
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
      await pumpEventQueue();
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
      await pumpEventQueue();
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
        await pumpEventQueue();
        expect(store.length, 0);
        // And signed out, nothing either.
        host.scope = null;
        await t.send(_get('/probe'));
        await pumpEventQueue();
        expect(store.length, 0);
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
          final t2 = OfflineTransport(server, store: null, host: host);
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
        await pumpEventQueue();
        server.offline = true;
        host.clock = host.clock.add(const Duration(hours: 1));
        final derived = _json(await t.send(_get(path, query: narrow)));
        expect(derived, hasLength(4));
        expect(host.shown, [wideAt]);
        // The narrow one saved later (online again) wins over the wide one.
        server.offline = false;
        host.clock = host.clock.add(const Duration(hours: 1));
        await t.send(_get(path, query: narrow));
        await pumpEventQueue();
        final narrowAt = host.clock;
        server.offline = true;
        await t.send(_get(path, query: narrow));
        expect(host.shown.last, narrowAt);
        // ...until a later wide one.
        server.offline = false;
        host.clock = host.clock.add(const Duration(hours: 1));
        final laterWideAt = host.clock;
        await t.send(_get(path, query: wide));
        await pumpEventQueue();
        // Past 30 s, so the narrow one is not a fresh hit on the wide one.
        host.clock = host.clock.add(const Duration(minutes: 1));
        server.offline = true;
        await t.send(_get(path, query: narrow));
        expect(host.shown.last, laterWideAt);
      });
    });
  });
}
