// Intent warming on the wizard: pointing at a step in the navigator warms
// its panel's reads, and pointing at "Add a menu item" / "Add an
// ingredient" warms the editor's, so each press asks the server nothing more.
import 'package:dashboard_admin/src/onboarding/step_navigator.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Every GET so far, as `template` strings.
List<String?> _gets(MockServer s) => [
  for (final c in s.calls)
    if (c.method == 'GET') c.template,
];

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _rest(DashHarness h, TestGesture mouse, Finder target) async {
  await h.tester.ensureVisible(target);
  await h.settle();
  await mouse.moveTo(h.tester.getCenter(target));
  await h.settle();
}

Finder _step(String title) => find.descendant(
  of: find.byType(OnbStepNavigator),
  matching: find.bySemanticsLabel(RegExp(title)),
);

void main() {
  testWidgets('ADM-ONB-009/021 a step warms its panel; Add a menu item warms the '
      'item editor', (tester) async {
    final s = onboardingServer();
    freshCafe(s.db);
    addCategory(s.db);
    final h = await pumpOnboarding(tester, server: s.server, db: s.db);
    // The session's branches and org, which the app's shell holds (core's
    // offline layer reads them on the editor's first call), not this page's.
    h.container
      ..listen(branchesProvider, (_, _) {})
      ..listen(currentOrgProvider, (_, _) {});
    await h.settle();
    final mouse = await _mouse(tester);
    expect(_gets(h.server), isNot(contains('/categories')));

    await _rest(h, mouse, _step('Build your menu'));
    expect(_gets(h.server).where((t) => t == '/categories'), hasLength(1),
        reason: 'the step\'s categories read is warmed');
    await h.tap(_step('Build your menu'));
    expect(_gets(h.server).where((t) => t == '/categories'), hasLength(1),
        reason: 'the panel opened from the cache');

    final add = buttonOf('Add a menu item');
    final before = _gets(h.server).length;
    await _rest(h, mouse, add);
    final warmed = _gets(h.server);
    expect(warmed.length, greaterThan(before), reason: 'the editor is warmed');
    await h.tap(add);
    expect(inSurface('New item'), findsOneWidget);
    expect(_gets(h.server), warmed, reason: 'the editor opened from cache');
  });

  testWidgets('ADM-ONB-017 Add an ingredient warms the ingredient editor',
      (tester) async {
    final s = onboardingServer();
    freshCafe(s.db);
    final h = await pumpOnboarding(tester, server: s.server, db: s.db);
    final mouse = await _mouse(tester);
    await h.tap(_step('Stock your pantry'));
    final add = buttonOf('Add an ingredient');
    final before = _gets(h.server).length;
    await _rest(h, mouse, add);
    final warmed = _gets(h.server);
    expect(warmed.length, greaterThan(before), reason: 'the editor is warmed');
    await h.tap(add);
    expect(_gets(h.server), warmed, reason: 'the editor opened from cache');
  });
}
