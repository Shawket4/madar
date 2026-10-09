// The Ingredients screenshot matrix: the page with a branch and with All
// branches at {phone, tablet, desktop} x {en light, ar dark}; loading, error,
// empty, the dialog (create, edit), the drawer and its history states at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// the pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];
const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  ScrollableState? state;
  for (final e in find
      .descendant(of: page, matching: find.byType(Scrollable))
      .evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0) {
      state = s;
      break;
    }
  }
  if (state == null) {
    await h.shot('ingredients/$name-1');
    return;
  }
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('ingredients/$name-$i');
    if (y >= position.maxScrollExtent || i >= 4) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, Zamalek, $tag', (tester) async {
        final h = await pumpIngredients(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          branch: SeedIds.zamalek,
        );
        await shootPage(h, 'default-zamalek');
      });
      testWidgets('default, all branches, $tag', (tester) async {
        final h = await pumpIngredients(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default-all');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    testWidgets('loading, $tag', (tester) async {
      final s = ingredientsServer();
      final gate = s.server.hold('GET', catalogRoute);
      final h = await pumpIngredients(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('ingredients/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('error, $tag', (tester) async {
      final s = ingredientsServer();
      s.server.fail(
        'GET',
        catalogRoute,
        MockResponse.error(500, 'The catalog is resting'),
        times: null,
      );
      final h = await pumpIngredients(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('ingredients/error');
    });

    testWidgets('empty, $tag', (tester) async {
      final s = ingredientsServer();
      s.db[InvTables.ingredients].removeWhere(
        (r) => r['org_id'] == SeedIds.sabahOrg,
      );
      final h = await pumpIngredients(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await h.shot('ingredients/empty');
    });

    testWidgets('dialog create (advanced open), $tag', (tester) async {
      final h = await pumpIngredients(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await openCreate(h);
      await pick(h, 'ingredient-category', h.t('inventory.catalog.newCategory'));
      await h.tap(inDialog(byKey('ingredient-advanced')));
      await h.shot('ingredients/dialog-create');
    });

    testWidgets('dialog edit (unit changed), $tag', (tester) async {
      final h = await pumpIngredients(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await openDrawer(h, 'Oat Milk');
      await h.tap(inDrawer(byKey('ingredient-drawer-edit')));
      await pick(h, 'ingredient-unit', h.t('units.l'));
      await h.shot('ingredients/dialog-edit');
    });

    testWidgets('drawer, Zamalek, $tag', (tester) async {
      final h = await pumpIngredients(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await openDrawer(h, 'Oat Milk');
      await h.shot('ingredients/drawer');
    });

    testWidgets('drawer, all branches, $tag', (tester) async {
      final h = await pumpIngredients(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await openDrawer(h, 'Dried Hibiscus');
      await h.shot('ingredients/drawer-all');
    });

    testWidgets('drawer history failed, $tag', (tester) async {
      final s = ingredientsServer();
      s.server.fail(
        'GET',
        movementsRoute,
        MockResponse.error(500, 'down'),
        times: null,
      );
      final h = await pumpIngredients(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await openDrawer(h, 'Oat Milk');
      await h.shot('ingredients/drawer-history-error');
    });

    testWidgets('drawer history loading, $tag', (tester) async {
      final s = ingredientsServer();
      final gate = s.server.hold('GET', movementsRoute);
      final h = await pumpIngredients(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await openDrawer(h, 'Oat Milk');
      await h.shot('ingredients/drawer-history-loading');
      gate.release();
      await h.settle();
    });

    testWidgets('filter Low stock, $tag', (tester) async {
      final h = await pumpIngredients(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await h.tap(inPage(find.text(h.t('inventory.reports.lowStock'))));
      await h.shot('ingredients/filter-low');
    });
  }
}
