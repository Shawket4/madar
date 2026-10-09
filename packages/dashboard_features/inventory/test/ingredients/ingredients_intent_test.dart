// Intent warming on Ingredients: pointing at a row warms the drawer's
// movements, at "New ingredient" or the drawer's Edit the dialog's lists,
// so the press asks the server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _rest(
  WidgetTester tester,
  DashHarness h,
  TestGesture mouse,
  Finder f,
) async {
  await tester.ensureVisible(f);
  await h.settle();
  await mouse.moveTo(tester.getCenter(f));
  await tester.pump(const Duration(milliseconds: 90));
  await h.settle();
}

void main() {
  testWidgets('INV-ING-010/038 (intent) a row warms its drawer\'s movements; '
      'opening it asks nothing more', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    int n() => h.server.callsTo(movementsRoute, method: 'GET').length;
    final mouse = await _mouse(tester);
    await search(h, 'House Blend Beans');
    expect(n(), 0);
    await _rest(tester, h, mouse, cellText('House Blend Beans'));
    expect(n(), 1, reason: 'the movements are warmed');
    await h.tap(cellText('House Blend Beans'));
    expect(drawer, findsOneWidget);
    expect(n(), 1, reason: 'the drawer opened from the cache');
  });

  testWidgets('INV-ING-004 (intent) "New ingredient" warms the dialog\'s '
      'categories and suppliers; opening it asks nothing more', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    int n(String r) => h.server.callsTo(r, method: 'GET').length;
    final mouse = await _mouse(tester);
    expect((n(categoriesRoute), n(suppliersRoute)), (0, 0));
    await _rest(tester, h, mouse, inPage(byKey('ingredients-new')));
    expect((n(categoriesRoute), n(suppliersRoute)), (1, 1));
    await h.tap(inPage(byKey('ingredients-new')));
    expect(dialog, findsOneWidget);
    expect((n(categoriesRoute), n(suppliersRoute)), (1, 1));
  });

  testWidgets('INV-ING-042 (intent) the drawer\'s Edit warms the dialog\'s '
      'lists; the edit dialog asks nothing more', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    int n(String r) => h.server.callsTo(r, method: 'GET').length;
    await openDrawer(h, 'House Blend Beans');
    final mouse = await _mouse(tester);
    expect((n(categoriesRoute), n(suppliersRoute)), (0, 0));
    await _rest(tester, h, mouse, inDrawer(byKey('ingredient-drawer-edit')));
    expect((n(categoriesRoute), n(suppliersRoute)), (1, 1));
    await h.tap(inDrawer(byKey('ingredient-drawer-edit')));
    expect(dialog, findsOneWidget);
    expect((n(categoriesRoute), n(suppliersRoute)), (1, 1));
  });
}
