// The web's React Query defaults on a Riverpod read (`ref.webCache()`): kept
// after the page leaves, refetched in the background once stale, swept after
// the gc time, cleared on sign-out; and the web's retry policy.
import 'package:dashboard_api/dashboard_api.dart' show ApiException;
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

  test('stale after 30 s: a visit refetches in the background', () async {
    expect(await visit('a'), 1);
    now = now.add(kQueryStaleTime);
    expect(await visit('a'), 2);
    expect(fetches, 2);
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

  test('the web retry policy', () {
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
