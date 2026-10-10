// Intent warming on the home: pointing at an in-page link warms the page it
// opens (its route's prefetch), so following it asks the server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_overview/dashboard_overview.dart';
import 'package:dashboard_overview/src/home/home_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support.dart';

// Each stand-in page reads one branch's open tills that the home never reads.
String _tillsTarget() => SeedIds.zamalek;
String _opsTarget() => SeedIds.newCairo;

void _warmTills(DashPrefetcher warm, Scope scope) =>
    warm(homeOpenTillsProvider(_tillsTarget()));
void _warmOps(DashPrefetcher warm, Scope scope) =>
    warm(homeOpenTillsProvider(_opsTarget()));
Widget _tillsPage(BuildContext context, GoRouterState state) =>
    _Reads(_tillsTarget());
Widget _opsPage(BuildContext context, GoRouterState state) =>
    _Reads(_opsTarget());

class _Reads extends ConsumerWidget {
  const _Reads(this.branchId);
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(homeOpenTillsProvider(branchId));
    return const SizedBox();
  }
}

/// Stand-ins for the other areas' pages: a page and its prefetch, same read.
const _targets = DashArea(
  key: 'targets',
  routes: [
    DashRoute(path: '/tills', builder: _tillsPage, prefetch: _warmTills),
    DashRoute(
      path: '/reports/operations',
      builder: _opsPage,
      prefetch: _warmOps,
    ),
  ],
);

void main() {
  for (final (label, path, to, branch) in [
    ('View all', '/?branchId=${SeedIds.maadi}', '/tills', _tillsTarget),
    ('Menu profitability', '/', '/reports/operations', _opsTarget),
  ]) {
    testWidgets('OVW-HOME-048/092 resting on "$label" warms $to; the press '
        'opens it from the cache', (tester) async {
      final h = await DashHarness.pump(
        tester,
        areas: const [overviewArea, _targets],
        path: path,
        persona: Persona.owner,
      );
      int reads() => h.server
          .callsTo('/tills/branches/{branchId}/open', method: 'GET')
          .where((c) => c.path.contains(branch()))
          .length;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      final link = homeText(label);
      await tester.ensureVisible(link);
      await h.settle();
      expect(reads(), 0);
      await mouse.moveTo(tester.getCenter(link));
      await tester.pump(const Duration(milliseconds: 90));
      await h.settle();
      expect(reads(), 1, reason: 'the target page is warmed');

      await h.tap(link);
      expect(h.location.path, to);
      expect(find.byType(_Reads), findsOneWidget);
      expect(reads(), 1, reason: 'the page opened from the cache');
    });
  }
}
