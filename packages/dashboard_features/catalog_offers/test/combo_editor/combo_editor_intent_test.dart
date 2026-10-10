// Intent warming on the combo editor: Back warms the list it returns to, the
// Pricing and combo-settings links warm their pages (`prefetchRoute`), so
// after the mouse rests the press asks the server nothing more.
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/combos/combos_page.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support.dart';

final _prefetched = <String>[];
void _pricing(DashPrefetcher _, Scope _) => _prefetched.add('/menu/pricing');
void _settings(DashPrefetcher _, Scope _) =>
    _prefetched.add('/settings/combos');
Widget _blank(BuildContext _, GoRouterState _) => const SizedBox();

/// Stand-ins for the two pages the links open, each with a prefetch.
const _linked = DashArea(
  key: 'linked',
  routes: [
    DashRoute(path: '/menu/pricing', builder: _blank, prefetch: _pricing),
    DashRoute(path: '/settings/combos', builder: _blank, prefetch: _settings),
  ],
);

Finder _link(String label) =>
    inEditor(find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}, ')));

void main() {
  for (final (kind, target, path) in <(String, Finder Function(), String)>[
    ('Back', () => labelled('Back'), '/menu/combos'),
    (
      'the Pricing link',
      () => _link('Branch prices and on/off'),
      '/menu/pricing',
    ),
    (
      'the combo settings link',
      () => _link('Where combos are sold'),
      '/settings/combos',
    ),
  ]) {
    testWidgets('intent: resting on $kind warms its page; the press asks '
        'nothing more', (tester) async {
      _prefetched.clear();
      final s = editorServer();
      final h = await DashHarness.pump(
        tester,
        areas: const [catalogOffersArea, _linked],
        path: comboPath('coffee-cookie'),
        server: s.server,
        db: s.db,
      );
      await debounce(h);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      int asked() => h.server.calls.where((c) => c.method == 'GET').length;
      // Older than 30 s: a press adding a reader would refetch.
      h.db!.clock.advance(const Duration(seconds: 31));
      final f = target();
      await tester.ensureVisible(f);
      await h.settle();
      final lists = h.server.callsTo('/combos', method: 'GET').length;
      await mouse.moveTo(tester.getCenter(f));
      await tester.pump(const Duration(milliseconds: 90));
      await h.settle();
      if (path == '/menu/combos') {
        expect(
          h.server.callsTo('/combos', method: 'GET'),
          hasLength(lists + 1),
          reason: 'the list is warmed',
        );
      } else {
        expect(_prefetched, [path]);
      }
      final warmed = asked();
      await h.tap(f);
      expect(h.location.path, path);
      if (path == '/menu/combos') {
        expect(find.byType(CombosPage), findsOneWidget);
      }
      expect(asked(), warmed);
      // The press's own pointer-down warms again (from the cache).
      expect(_prefetched.toSet(), path == '/menu/combos' ? isEmpty : {path});
    });
  }
}
