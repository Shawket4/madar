// The shared pattern behind the owner's rule (2026-10-11: "all filters carry
// state into navigation across the whole dashboard"): `DashListMemory` with
// its three ways in — a page's own filters (`DashRememberedState`), filters
// held in the URL (`DashRoute.rememberQuery`) and the kit's own widgets (the
// page's PageStorage bucket) — plus a detail page's Back (header and system)
// returning to the list it was opened from.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A list with a page-held status (org-wide) and teller (branch-bound).
class _ListPage extends ConsumerStatefulWidget {
  const _ListPage();

  @override
  ConsumerState<_ListPage> createState() => _ListPageState();
}

class _ListPageState extends ConsumerState<_ListPage> with DashRememberedState {
  String? _status;
  String? _teller;

  @override
  String get memoryKey => 'test.list';

  @override
  Map<String, Object?> get rememberedValues => {
    'status': _status,
    'teller': _teller,
  };

  @override
  void restoreRemembered(DashMemo m) {
    _status = m.string('status');
    _teller = m.sameBranch ? m.string('teller') : null;
  }

  @override
  Widget build(BuildContext context) => DashPageScaffold(
    title: 'List',
    body: Column(
      children: [
        Text('status: ${_status ?? 'all'}'),
        Text('teller: ${_teller ?? 'all'}'),
        TextButton(
          onPressed: () => setState(() => _status = 'open'),
          child: const Text('only open'),
        ),
        TextButton(
          onPressed: () => setState(() => _teller = 't1'),
          child: const Text('only t1'),
        ),
        TextButton(
          onPressed: () {
            ref.dashOpenedFrom(context, '/list/42');
            context.go('/list/42');
          },
          child: const Text('open 42'),
        ),
        for (var i = 0; i < 40; i++)
          SizedBox(height: 60, child: Text('row $i')),
      ],
    ),
  );
}

class _DetailPage extends ConsumerWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) => DashPageScaffold(
    title: 'Detail',
    onBack: () => context.go(ref.dashBackTarget('/list/42', '/list')),
    body: const Text('detail 42'),
  );
}

Widget _query(BuildContext context, GoRouterState state) =>
    Text('query: ${state.uri.query}');

final _area = DashArea(
  key: 'list_memory_test',
  routes: [
    DashRoute(
      path: '/list',
      titleFallback: 'List',
      builder: (_, _) => const _ListPage(),
    ),
    DashRoute(
      path: '/list/:id',
      titleFallback: 'Detail',
      builder: (_, _) => const _DetailPage(),
    ),
    const DashRoute(
      path: '/q',
      titleFallback: 'Query',
      builder: _query,
      rememberQuery: ['status', 'teller'],
      branchQuery: ['teller'],
    ),
    DashRoute(
      path: '/other',
      titleFallback: 'Other',
      builder: (_, _) => const Text('other page'),
    ),
  ],
);

Future<DashHarness> _pump(WidgetTester tester, {String path = '/list'}) =>
    DashHarness.pump(tester, areas: [_area], path: path);

void main() {
  group('a page’s own filters (DashRememberedState)', () {
    testWidgets('come back after another page', (tester) async {
      final h = await _pump(tester);
      await h.tapText('only open');
      expect(find.text('status: open'), findsOneWidget);
      await h.go('/other');
      expect(find.text('other page'), findsOneWidget);
      await h.go('/list');
      expect(find.text('status: open'), findsOneWidget);
    });

    testWidgets('detail → header Back returns to the filtered list', (
      tester,
    ) async {
      final h = await _pump(tester);
      await h.tapText('only open');
      await h.tapText('open 42');
      expect(find.text('detail 42'), findsOneWidget);
      await h.tap(find.bySemanticsLabel(h.t('common.back')).first);
      expect(h.location.path, '/list');
      expect(find.text('status: open'), findsOneWidget);
    });

    testWidgets('detail → system back returns to the filtered list', (
      tester,
    ) async {
      final h = await _pump(tester);
      await h.tapText('only open');
      await h.tapText('open 42');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await h.settle();
      expect(h.location.path, '/list');
      expect(find.text('status: open'), findsOneWidget);
    });

    testWidgets('a detail opened from a link (no list) goes back to its '
        'fallback', (tester) async {
      final h = await _pump(tester, path: '/list/42');
      await h.tap(find.bySemanticsLabel(h.t('common.back')).first);
      expect(h.location.path, '/list');
      expect(find.text('status: all'), findsOneWidget);
    });

    testWidgets('the page scroll comes back too', (tester) async {
      final h = await _pump(tester);
      final scrollable = find
          .descendant(
            of: find.byType(DashPageScaffold),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(700);
      await h.settle();
      await h.go('/other');
      await h.go('/list');
      expect(tester.state<ScrollableState>(scrollable).position.pixels, 700);
    });

    testWidgets('a branch change resets only the branch-bound filter', (
      tester,
    ) async {
      final h = await _pump(tester);
      await h.tapText('only open');
      await h.tapText('only t1');
      expect(find.text('teller: t1'), findsOneWidget);
      // Live, on the page.
      await h.container.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
      await h.settle();
      expect(find.text('teller: all'), findsOneWidget);
      expect(find.text('status: open'), findsOneWidget);
      // And while away.
      await h.tapText('only t1');
      await h.go('/other');
      await h.container.read(scopeProvider.notifier).setBranch(SeedIds.zamalek);
      await h.settle();
      await h.go('/list');
      expect(find.text('teller: all'), findsOneWidget);
      expect(find.text('status: open'), findsOneWidget);
    });

    testWidgets('signing out forgets every list', (tester) async {
      final h = await _pump(tester);
      await h.tapText('only open');
      final memory = h.container.read(dashListMemoryProvider);
      expect(memory.recall('test.list').string('status'), 'open');
      await h.container.read(sessionProvider.notifier).signOut();
      await h.settle();
      expect(memory.recall('test.list').isEmpty, isTrue);
    });
  });

  group('filters held in the URL (DashRoute.rememberQuery)', () {
    testWidgets('opened bare from another page, the page gets them back', (
      tester,
    ) async {
      final h = await _pump(tester, path: '/q?status=open&teller=t1');
      await h.go('/other');
      await h.go('/q');
      expect(h.location.queryParameters, {'status': 'open', 'teller': 't1'});
    });

    testWidgets('cleared on the page, they stay cleared', (tester) async {
      final h = await _pump(tester, path: '/q?status=open');
      await h.go('/q');
      expect(h.location.queryParameters, isEmpty);
      await h.go('/other');
      await h.go('/q');
      expect(h.location.queryParameters, isEmpty);
    });

    testWidgets('a link that names its own filters wins', (tester) async {
      final h = await _pump(tester, path: '/q?status=open');
      await h.go('/other');
      await h.go('/q?status=closed');
      expect(h.location.queryParameters, {'status': 'closed'});
    });

    testWidgets('a branch change drops the branch-bound ones', (tester) async {
      final h = await _pump(tester, path: '/q?status=open&teller=t1');
      await h.container.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
      await h.settle();
      expect(h.location.queryParameters, {'status': 'open'});
    });
  });
}
