// The web's `prefetchRoute('/inventory/settings')`: pointing at the sidebar's
// inventory Settings row warms the page's first reads, so opening it asks for
// them no second time. And intent warming: the delete dialog reads nothing
// of its own (it lists the page's cached categories), so resting on the trash
// button and pressing it asks the server nothing.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final Finder _row = find.descendant(
  of: find.byType(DashSidebar),
  matching: find.byWidgetPredicate(
    (w) => w is PrefetchOnIntent && w.to == settingsPath,
  ),
);

void main() {
  testWidgets('INV-SET-003 (prefetch) hovering Settings warms the org '
      'settings and categories; opening it reads nothing again', (
    tester,
  ) async {
    final h = await pumpSettings(tester, path: '/inventory/waste');
    int n(String r) => h.server.callsTo(r, method: 'GET').length;
    expect(n(settingsRoute), 0);
    await tester.scrollUntilVisible(
      _row,
      200,
      scrollable: find
          .descendant(
            of: find.byType(DashSidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await h.settle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(_row));
    await h.settle();
    expect(n(settingsRoute), 1, reason: 'warmed on hover');
    expect(
      h.server.callsTo(settingsRoute).single.path,
      '/inventory/orgs/$org/settings',
    );
    final cats = n(categoriesRoute);
    expect(cats, greaterThanOrEqualTo(1));

    await h.tap(_row);
    expect(h.location.path, settingsPath);
    expect(n(settingsRoute), 1, reason: 'served from the cache');
    expect(n(categoriesRoute), cats, reason: 'served from the cache');
    expect(inList(find.text('General')), findsOneWidget);
  });

  testWidgets('INV-SET-013 (intent) resting on a trash button and pressing '
      'it opens the dialog with no request', (tester) async {
    final h = await pumpSettings(tester);
    final before = h.server.calls.length;
    final trash = inRow('milk', byKey('inv-category-delete-${cat('milk')}'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(trash));
    await h.settle();
    await h.tap(trash);
    expect(dialog, findsOneWidget);
    expect(h.server.calls.length, before, reason: 'nothing asked');
    expect(h.server.callsTo(categoriesRoute, method: 'GET'), hasLength(1));
  });

  testWidgets('a platform admin with no organization: hovering warms '
      'nothing', (tester) async {
    final h = await pumpSettings(
      tester,
      path: '/inventory/waste',
      persona: Persona.platform,
    );
    await tester.scrollUntilVisible(
      _row,
      200,
      scrollable: find
          .descendant(
            of: find.byType(DashSidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(_row));
    await h.settle();
    expect(h.server.callsTo(settingsRoute), isEmpty);
  });
}
