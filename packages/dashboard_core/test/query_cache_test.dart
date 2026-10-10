// The web's React Query defaults on a Riverpod read (`ref.webCache()`): kept
// after the page leaves, refetched in the background once stale, swept after
// the gc time, cleared on sign-out; and the web's retry policy.
import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, ApiRequest, ApiResponse, ApiTransport;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late int fetches;
  late ProviderContainer c;

  final read = FutureProvider.autoDispose.family<int, String>((ref, key) {
    ref.webCache();
    return ++fetches;
  });
  // A read that answers a turn later, so its loading state shows.
  final slow = FutureProvider.autoDispose<int>((ref) async {
    ref.webCache();
    await Future<void>.delayed(Duration.zero);
    return ++fetches;
  });
  // Another read, to drive a sweep.
  final other = FutureProvider.autoDispose<int>((ref) {
    ref.webCache();
    return 0;
  });

  setUp(() {
    now = DateTime.utc(2026, 10, 8, 12);
    fetches = 0;
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    addTearDown(c.dispose);
  });

  /// One page visit: watch the read until it answers, then leave.
  Future<int> visit(String key) async {
    final sub = c.listen(read(key), (_, _) {});
    final v = await c.read(read(key).future);
    await Future<void>.delayed(Duration.zero);
    final settled = c.read(read(key)).value ?? v;
    sub.close();
    return settled;
  }

  test('kept after the page leaves: a second visit fetches nothing', () async {
    expect(await visit('a'), 1);
    now = now.add(const Duration(seconds: 29));
    expect(await visit('a'), 1);
    expect(fetches, 1);
  });

  test(
    'ADM-APP-116: stale after 30 s: a visit refetches in the background',
    () async {
      expect(await visit('a'), 1);
      now = now.add(kQueryStaleTime);
      expect(await visit('a'), 2);
      expect(fetches, 2);
    },
  );

  test('a rebuild re-listening (close, then listen again in the same turn) '
      'is not a new mount: no refetch, even when stale', () async {
    // The page watches the read and listens to it.
    final watch = c.listen(read('a'), (_, _) {});
    var sub = c.listen(read('a'), (_, _) {});
    await c.read(read('a').future);
    now = now.add(kQueryStaleTime);
    // flutter_riverpod's rebuild: old `ref.listen` closed, new one added,
    // the watch kept.
    sub.close();
    sub = c.listen(read('a'), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(fetches, 1);
    sub.close();
    watch.close();
    // A real later mount still refetches.
    await Future<void>.delayed(Duration.zero);
    expect(await visit('a'), 2);
  });

  test('warming a stale read keeps its value: the page opening on it shows '
      'the old data while it refetches (the web prefetchQuery)', () async {
    final first = c.listen(slow, (_, _) {});
    expect(await c.read(slow.future), 1);
    first.close();
    now = now.add(kQueryStaleTime);
    DashPrefetcher(c)(slow);
    await Future<void>.delayed(Duration.zero);
    final seen = <AsyncValue<int>>[];
    final page = c.listen(slow, (_, n) => seen.add(n), fireImmediately: true);
    await c.read(slow.future);
    await Future<void>.delayed(Duration.zero);
    expect(seen.every((s) => s.hasValue), isTrue, reason: '$seen');
    expect(seen.first.value, 1);
    expect(page.read().value, 2);
    expect(fetches, 2);
    page.close();
  });

  test('a one-shot read of a stale read keeps it cached', () async {
    expect(await visit('a'), 1);
    now = now.add(kQueryStaleTime);
    expect(await c.read(read('a').future), 1);
    await Future<void>.delayed(Duration.zero);
    expect(c.exists(read('a')), isTrue);
    expect(c.read(read('a')).value, 1);
  });

  test('warming a fresh read makes no request', () async {
    expect(await visit('a'), 1);
    now = now.add(const Duration(seconds: 29));
    DashPrefetcher(c)(read('a'));
    await Future<void>.delayed(Duration.zero);
    expect(await visit('a'), 1);
    expect(fetches, 1);
  });

  test('each key is its own entry (the scope is the key)', () async {
    await visit('a');
    await visit('b');
    await visit('a');
    expect(fetches, 2);
  });

  test('swept once unwatched past the gc time', () async {
    await visit('a');
    now = now.add(kQueryGcTime + const Duration(seconds: 1));
    // Any read built or let go sweeps.
    c.read(other);
    await Future<void>.delayed(Duration.zero);
    expect(c.exists(read('a')), isFalse);
  });

  test('a sign-out clears it: the next person fetches afresh', () async {
    await visit('a');
    // What `SessionNotifier.signOut` does.
    c.read(queryCacheProvider).clear();
    await Future<void>.delayed(Duration.zero);
    expect(c.exists(read('a')), isFalse);
    expect(await visit('a'), 2);
  });

  test('a refresh by hand refetches what is shown, fresh or not; never what '
      'nobody shows', () async {
    final shown = c.listen(read('a'), (_, _) {});
    await c.read(read('a').future);
    await visit('b');
    expect(fetches, 2);
    expect(await c.read(queryCacheProvider).refetchActive(), isNull);
    expect(c.read(read('a')).value, 3);
    expect(fetches, 3);
    shown.close();
  });

  test(
    'a refresh waits for the reads it set off, and names a failure',
    () async {
      final server = _SlowServer();
      final transport = c.read(queryCacheProvider).track(server);
      final remote = FutureProvider.autoDispose<int>((ref) async {
        ref.webCache();
        await transport.send(const ApiRequest(method: 'GET', path: '/x'));
        return server.answered;
      });
      final shown = c.listen(remote, (_, _) {});
      expect(await c.read(remote.future), 1);

      expect(await c.read(queryCacheProvider).refetchActive(), isNull);
      expect(c.read(remote).value, 2);

      server.fail = true;
      final failure = await c.read(queryCacheProvider).refetchActive();
      expect(failure, isA<ApiException>());
      // What was shown stays.
      expect(c.read(remote).value, 2);
      shown.close();
    },
  );

  test('ADM-APP-116: the web retry policy', () {
    ApiException e(int s) => ApiException(status: s, message: '');
    for (final s in [401, 403, 404, 422]) {
      expect(webRetry(0, e(s)), isNull, reason: '$s');
    }
    expect(webRetry(0, e(429)), const Duration(seconds: 2));
    expect(webRetry(2, e(429)), const Duration(seconds: 8));
    expect(webRetry(3, e(429)), isNull);
    expect(webRetry(0, e(500)), const Duration(seconds: 1));
    expect(webRetry(1, e(500)), isNull);
  });
}

/// A server that answers after a moment, or fails.
class _SlowServer implements ApiTransport {
  int answered = 0;
  bool fail = false;

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (fail) throw const ApiException(status: 500, message: 'down');
    answered++;
    return const ApiResponse(status: 200);
  }

  @override
  Stream<String> stream(ApiRequest request) => const Stream.empty();
}
