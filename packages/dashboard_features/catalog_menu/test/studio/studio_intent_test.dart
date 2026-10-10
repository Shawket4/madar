// Intent warming on the Menu Studio (owner rule): a control whose press
// makes a read warms that read when the pointer rests on it, so the press
// asks the server nothing more. One test per kind: a link to another item,
// a button that opens a dialog, a select's option, a link to another page.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show ScopePrefKeys;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _animationT = '/recipes/step-presets/{slug}/animation';
const String _ingCategoriesT = '/inventory/orgs/{org_id}/categories';
const String _costingT = '/costing/catalog';

/// A mouse resting on [f] (past the intent dwell).
Future<void> _rest(DashHarness h, Finder f) async {
  final tester = h.tester;
  await tester.ensureVisible(f.first);
  await h.settle();
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(f.first));
  await h.settle();
}

int _get(DashHarness h, String template, [String? path]) => [
  for (final c in h.server.callsTo(template, method: 'GET'))
    if (path == null || c.path == path) c,
].length;

void main() {
  testWidgets('MENU-STUDIO-056 intent: a linked copy\'s link warms its '
      'studio; opening it asks nothing more', (tester) async {
    final s = studioServer();
    linkCopy(s.db, 'iced_spanish', 'spanish');
    final h = await pumpStudio(tester, key: 'spanish', seeded: s);
    final copy = item('iced_spanish');
    expect(_get(h, studioT, '/menu-items/$copy/studio'), 0);

    await _rest(h, studioText('Iced Spanish Latte'));
    expect(_get(h, studioT, '/menu-items/$copy/studio'), 1);
    expect(_get(h, linkT, '/menu-items/$copy/recipe-link'), 1);

    await h.tap(studioText('Iced Spanish Latte'));
    expect(h.location.path, '/menu/items/$copy');
    expect(fieldWithText('Iced Spanish Latte'), findsOneWidget);
    expect(_get(h, studioT, '/menu-items/$copy/studio'), 1);
    expect(_get(h, linkT, '/menu-items/$copy/recipe-link'), 1);
  });

  testWidgets('MENU-STUDIO-069/070 intent: "Add a step" warms the library '
      'and its animations; the picker asks nothing more', (tester) async {
    final h = await pumpStudio(tester);
    final rows = _get(h, _animationT);
    final add = studioText(h.t('menu.studio.steps.addFromLibrary'));

    await _rest(h, add);
    final warmed = _get(h, _animationT);
    expect(warmed, greaterThan(rows), reason: 'the tiles\' animations');
    final presets = _get(h, presetsT);

    await h.tap(add);
    expect(find.byKey(const ValueKey('step-preset-blend')), findsOneWidget);
    expect(_get(h, _animationT), warmed);
    expect(_get(h, presetsT), presets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });

  testWidgets('MENU-STUDIO-083 intent: "New group" warms the editor\'s '
      'ingredient categories', (tester) async {
    final h = await pumpStudio(tester);
    expect(_get(h, _ingCategoriesT), 0);
    final add = studioText(h.t('menu.groups.new'));

    await _rest(h, add);
    expect(_get(h, _ingCategoriesT), 1);

    await h.tap(add);
    expect(find.text(h.t('menu.groups.editor.newTitle')), findsWidgets);
    expect(_get(h, _ingCategoriesT), 1);
  });

  testWidgets('MENU-STUDIO-093 intent: a combo option warms that combo; '
      'picking it asks nothing more', (tester) async {
    final s = studioServer();
    seedBreakfastCombo(s.db);
    final h = await pumpStudio(tester, seeded: s);
    await h.tap(
      inSection(h.t('combos.meal.title'), find.byType(DashSelectTrigger)).first,
    );
    final option = find.descendant(
      of: find.byWidgetPredicate((w) => w is DashOptionList),
      matching: find.text('Breakfast Combo'),
    );
    expect(_get(h, comboT), 0);

    await _rest(h, option);
    expect(_get(h, comboT, '/combos/${comboId('breakfast')}'), 1);

    await h.tap(option);
    expect(studioText('Hot drink'), findsOneWidget);
    expect(_get(h, comboT), 1);
  });

  testWidgets('MENU-STUDIO-004 intent: Back warms the items page; going '
      'back reads no catalog page again', (tester) async {
    final h = await pumpStudio(tester);
    final back = find.bySemanticsLabel('Back');
    final before = _get(h, _costingT);

    await _rest(h, back);
    final warmed = _get(h, _costingT);
    expect(warmed, greaterThan(before));

    await h.tap(back);
    expect(h.location.path, '/menu/items');
    expect(_get(h, _costingT), warmed);
  });

  testWidgets('MENU-STUDIO-005 intent: the pricing link warms the pricing '
      'page; opening it reads no catalog page again', (tester) async {
    // The pricing page reads a branch's overrides: a branch is in scope.
    final h = await pumpStudio(
      tester,
      prefs: {
        ScopePrefKeys.branch: jsonEncode({
          'org': SeedIds.sabahOrg,
          'branch': SeedIds.zamalek,
        }),
      },
    );
    final link = studioText(h.t('menu.studio.pricingLink'));
    final before = _get(h, _costingT);

    await _rest(h, link);
    final warmed = _get(h, _costingT);
    expect(warmed, greaterThan(before));

    await h.tap(link);
    expect(h.location.path, '/menu/pricing');
    expect(_get(h, _costingT), warmed);
  });
}
