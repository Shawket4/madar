// The items unit's screenshot matrix: `/menu/items` at {phone, tablet,
// desktop} x {en light, ar dark}, scrolled through; and the other states
// (loading, failed, empty, the Add-ons and Categories tabs, reorder, the
// branch toggles, every dialog and the confirm) at desktop-en-light and
// phone-ar-light. Written only with FDASH_SHOTS set; the pages still render
// (and must not overflow) without.
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show MenuItem;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/items/item_dialog.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];

/// Shoots the page top to bottom: `<shot>-1`, `<shot>-2`, …
Future<void> shootPage(DashHarness h, String shot) async {
  final scroll = find
      .descendant(
        of: page,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('$shot-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

/// Shoots the open dialog, scrolled through when it is long.
Future<void> shootDialog(DashHarness h, String shot) async {
  final scrolls = find.descendant(
    of: surface,
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  if (scrolls.evaluate().isEmpty) {
    await h.shot('$shot-1');
    return;
  }
  final position = h.tester.state<ScrollableState>(scrolls.first).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('$shot-$i');
    if (y >= position.maxScrollExtent || i >= 6) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

/// The two states-and-dialogs modes.
const _detail = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('items default, $tag', (tester) async {
        final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'items/default');
      });
    }
  }

  for (final (size, lang, dark) in _detail) {
    final tag = '${size.name} $lang';

    testWidgets('loading, $tag', (tester) async {
      final s = itemsServer();
      final gate = s.server.hold('GET', catalogPath);
      final h = await pumpItems(
        tester,
        seeded: s,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('items/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = itemsServer();
      s.server.fail(
        'GET',
        catalogPath,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpItems(
        tester,
        seeded: s,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('items/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final s = itemsServer();
      for (final m in liveItems(s.db)) {
        m['deleted_at'] = '2026-09-01T09:00:00Z';
      }
      final h = await pumpItems(
        tester,
        seeded: s,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('items/empty');
    });

    testWidgets('branch toggles, $tag', (tester) async {
      final h = await pumpItems(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branchId: SeedIds.zamalek,
      );
      await h.tap(find.bySemanticsLabel(h.t('common.next')));
      await shootPage(h, 'items/branch');
    });

    testWidgets('add-ons tab, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      await openTab(h, 'addons');
      await shootPage(h, 'items/addons');
    });

    testWidgets('categories tab and reorder, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      await openTab(h, 'categories');
      await shootPage(h, 'items/categories');
      await h.tap(inPage(find.text(h.t('menu.categoriesReorder'))));
      await shootPage(h, 'items/reorder');
    });

    testWidgets('card menu and delete confirm, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      final name = lang == 'ar' ? 'كورتادو' : 'Cortado';
      await h.scrollUntilVisible(cardOf(name));
      await openCardMenu(h, name);
      await h.shot('items/card-menu');
      await pickMenu(h, h.t('common.delete'));
      await h.shot('items/delete-confirm');
    });

    testWidgets('new item dialog, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      await h.tap(inPage(find.text(h.t('menu.newItem'))));
      await h.tap(inSurface(find.text(h.t('common.save'))));
      await shootDialog(h, 'items/item-dialog-new');
      await h.tap(inSurface(find.text(h.t('menu.addSize'))));
      await shootDialog(h, 'items/item-dialog-sizes');
    });

    testWidgets('edit item dialog, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      final row = h.db![MenuTables.menuItems].find(item('latte'))!;
      unawaited(
        showMenuItemDialog(
          tester.element(page),
          orgId: sabahOrg,
          item: MenuItem.fromJson(row),
        ),
      );
      await h.settle();
      await shootDialog(h, 'items/item-dialog-edit');
    });

    testWidgets('add-on dialogs, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      await openTab(h, 'addons');
      await h.tap(inPage(find.text(h.t('menu.newAddon'))));
      await h.tap(inSurface(find.text(h.t('common.save'))));
      await shootDialog(h, 'items/addon-dialog-new');
      await h.tap(inSurface(find.text(h.t('common.cancel'))));
      final name = lang == 'ar' ? 'شوت إضافي' : 'Extra shot';
      await openCardMenu(h, name);
      await pickMenu(h, h.t('common.edit'));
      await shootDialog(h, 'items/addon-dialog-edit');
      await h.tap(inSurface(find.text(h.t('common.cancel'))));
      await openCardMenu(h, name);
      await pickMenu(h, h.t('menu.addonRecipe.edit'));
      await shootDialog(h, 'items/addon-recipe');
    });

    testWidgets('category dialog, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      await openTab(h, 'categories');
      await h.tap(inPage(find.text(h.t('menu.newCategory'))));
      await h.tap(inSurface(find.text(h.t('common.save'))));
      await shootDialog(h, 'items/category-dialog');
    });

    testWidgets('paste dialog, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      await h.tap(inPage(find.text(h.t('grid.pasteRows'))));
      await h.enterText(
        fieldIn(surface, h.t('grid.pasteTitle')),
        'Rose Latte\t125\tHot Coffee\tSteamed milk and rose\n'
        '\t40\tHot Coffee\n'
        'Dates Shake\tabc\tFresh Juice\n',
      );
      await shootDialog(h, 'items/paste-1');
      await h.tap(inSurface(find.text(h.t('common.next'))));
      await shootDialog(h, 'items/paste-2');
    });
  }
}
