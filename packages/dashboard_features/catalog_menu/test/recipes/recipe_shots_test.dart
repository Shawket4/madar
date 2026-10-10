// The recipes unit's screenshot matrix: the builder in both hosts at every
// size in English light and Arabic dark, then its other states (scaling,
// the picker, unsaved, loading, the create-ingredient dialog) at desktop
// English light and phone Arabic light. Written only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_host.dart';

Finder _inBuilder(Finder f) =>
    find.descendant(of: find.byType(RecipeBuilder), matching: f);

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('item builder, ${size.name} $lang', (tester) async {
        final h = await pumpRecipeHost(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await openLatte(h);
        await h.shot('recipes/item-builder');
      });

      testWidgets('add-on builder, ${size.name} $lang', (tester) async {
        final h = await pumpRecipeHost(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await openExtraShot(h);
        await h.shot('recipes/addon-builder');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    Future<DashHarness> pump(WidgetTester tester) =>
        pumpRecipeHost(tester, size: size, locale: lang);

    testWidgets('scaling panel, ${size.name} $lang', (tester) async {
      final h = await pump(tester);
      await openLatte(h, sizes: const ['Regular', 'Large', 'Double']);
      await h.tap(_inBuilder(find.byType(DashSwitch)));
      await h.enterText(
        find.byKey(const ValueKey('recipe-factor-Large')),
        '1.5',
      );
      await h.shot('recipes/scaling');
    });

    testWidgets('ingredient picker, ${size.name} $lang', (tester) async {
      final h = await pump(tester);
      await openExtraShot(h);
      await h.tap(ingredientPicker(h, 'House espresso blend'));
      await h.shot('recipes/picker');
    });

    testWidgets('unsaved, ${size.name} $lang', (tester) async {
      final h = await pump(tester);
      await openExtraShot(h);
      await h.tap(_inBuilder(find.text(h.t('recipes.addIngredient'))));
      await h.enterText(
        qtyBox(h, 'House espresso blend', h.t('recipes.oneSize')),
        '20',
      );
      await h.shot('recipes/unsaved');
    });

    testWidgets('loading catalog, ${size.name} $lang', (tester) async {
      final s = recipeServer();
      final gate = s.server.hold('GET', '/inventory/orgs/{org_id}/catalog');
      final h = await pumpRecipeHost(
        tester,
        size: size,
        locale: lang,
        seeded: s,
      );
      await openExtraShot(h);
      await h.shot('recipes/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('catalog failed, ${size.name} $lang', (tester) async {
      final s = recipeServer();
      s.server.fail(
        'GET',
        '/inventory/orgs/{org_id}/catalog',
        MockResponse.error(500, 'Service unavailable'),
        times: null,
      );
      final h = await pumpRecipeHost(
        tester,
        size: size,
        locale: lang,
        seeded: s,
      );
      await openExtraShot(h);
      await h.shot('recipes/catalog-failed');
    });

    testWidgets('create-ingredient dialog, ${size.name} $lang', (tester) async {
      final h = await pump(tester);
      await openExtraShot(h);
      await h.tap(_inBuilder(find.text(h.t('recipes.newIngredient'))));
      await h.shot('recipes/create-ingredient');
    });
  }
}
