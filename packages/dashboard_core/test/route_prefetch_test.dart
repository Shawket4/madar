// The route registry's prefetch (`prefetchRouteIn`, what every `to:` on a
// kit control and every sidebar or palette row runs on intent): a location
// is matched to its route (a detail path by segment, its parameters and
// query handed over), throttled per location and scope, and a warm of fresh
// data asks the server nothing.
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

late int fetches;
final _list = FutureProvider.autoDispose.family<int, String>((ref, branch) {
  ref.webCache();
  return ++fetches;
});
final _detail = FutureProvider.autoDispose.family<int, String>((ref, id) {
  ref.webCache();
  return ++fetches;
});
final warmed = <String>[];

void _warmList(DashPrefetcher warm, Scope s) {
  warmed.add('list:${s.scopeBranchId}:${warm.query['status'] ?? '-'}');
  warm(_list(s.scopeBranchId));
}

void _warmDetail(DashPrefetcher warm, Scope s) {
  warmed.add('detail:${warm.params['thingId']}');
  warm(_detail(warm.params['thingId']!));
}

void _warmNew(DashPrefetcher warm, Scope s) => warmed.add('new');

const _area = DashArea(
  key: 'things',
  routes: [
    DashRoute(
      path: '/things',
      prefetch: _warmList,
      children: [
        DashRoute(path: 'new', prefetch: _warmNew),
        DashRoute(path: ':thingId', prefetch: _warmDetail),
      ],
    ),
  ],
);

void main() {
  late DateTime now;
  late ProviderContainer c;
  late Scope scope;

  setUp(() {
    fetches = 0;
    warmed.clear();
    now = DateTime.utc(2026, 10, 8, 12);
    scope = const Scope(
      orgId: 'org',
      branchId: 'b1',
      preset: ScopePreset.today,
      range: PeriodRange('2026-10-08', '2026-10-08'),
      timezone: 'Africa/Cairo',
    );
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        dashAreasProvider.overrideWithValue(const [_area]),
        currentScopeProvider.overrideWith((ref) => scope),
      ],
    );
    addTearDown(c.dispose);
  });

  Future<void> land() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a static path wins over a templated one; a detail path hands over '
      'its parameters, a location its query', () async {
    prefetchRouteIn(c, '/things/new');
    prefetchRouteIn(c, '/things/abc');
    prefetchRouteIn(c, '/things/?status=open');
    prefetchRouteIn(c, '/elsewhere');
    await land();
    expect(warmed, ['new', 'detail:abc', 'list:b1:open']);
    expect(fetches, 2);
  });

  test(
    'pointing at the same link again and again: one warm, one request',
    () async {
      for (var i = 0; i < 20; i++) {
        prefetchRouteIn(c, '/things/abc');
        now = now.add(const Duration(milliseconds: 50));
      }
      await land();
      expect(warmed, ['detail:abc'], reason: 'throttled per location');
      expect(fetches, 1);
    },
  );

  test('after the throttle, a fresh read is warmed again but not fetched; '
      'a stale one is fetched once', () async {
    prefetchRouteIn(c, '/things');
    await land();
    now = now.add(kRoutePrefetchThrottle);
    prefetchRouteIn(c, '/things');
    await land();
    expect(warmed, hasLength(2));
    expect(fetches, 1, reason: 'fresh (under kQueryStaleTime): the cache');
    now = now.add(kQueryStaleTime);
    prefetchRouteIn(c, '/things');
    await land();
    expect(fetches, 2, reason: 'stale: read again in the background');
  });

  test('another scope is another key: warmed for it', () async {
    prefetchRouteIn(c, '/things');
    await land();
    scope = const Scope(
      orgId: 'org',
      branchId: 'b2',
      preset: ScopePreset.today,
      range: PeriodRange('2026-10-08', '2026-10-08'),
      timezone: 'Africa/Cairo',
    );
    c.invalidate(currentScopeProvider);
    prefetchRouteIn(c, '/things');
    await land();
    expect(warmed, ['list:b1:-', 'list:b2:-']);
    expect(fetches, 2);
  });

  test('sign-out (the cache cleared) forgets the throttle too', () async {
    prefetchRouteIn(c, '/things/abc');
    await land();
    c.read(queryCacheProvider).clear();
    await land();
    prefetchRouteIn(c, '/things/abc');
    await land();
    expect(warmed, ['detail:abc', 'detail:abc']);
    expect(fetches, 2);
  });

  test('a page opened bare warms with the filters it will get back '
      '(rememberQuery), not the bare key', () {
    var branch = 'b1';
    final memory = DashListMemory(() => (org: 'org', branch: branch));
    const route = DashRoute(
      path: '/things',
      rememberQuery: ['status', 'teller'],
      branchQuery: ['teller'],
    );
    memory.rememberQuery('/things', {'status': 'open', 'teller': 't1'});
    Map<String, String> q(String to, {String? from}) => landingQuery(
      memory,
      route,
      Uri.parse(to),
      from: from == null ? null : Uri.parse(from),
    );
    expect(q('/things', from: '/elsewhere'), {
      'status': 'open',
      'teller': 't1',
    });
    expect(q('/things?status=void'), {'status': 'void'}, reason: 'explicit');
    expect(q('/things', from: '/things?x=1'), isEmpty, reason: 'on the page');
    branch = 'b2';
    expect(q('/things'), {'status': 'open'}, reason: 'the branch-bound go');
  });
}
