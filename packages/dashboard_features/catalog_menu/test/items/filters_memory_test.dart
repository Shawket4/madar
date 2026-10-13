// The owner's rule (2026-10-11): a filter carries through navigation. The
// menu filtered by category, an item opened in the studio, and back — by
// the header's Back, the system back, after a save — lands on the same
// filtered menu (`DashListMemory`, `DashRememberedState`).
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/items/items_page.dart';
import 'package:dashboard_catalog_menu/src/shared/menu_providers.dart';
import 'package:dashboard_catalog_menu/src/studio/menu_studio_page.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../studio/support.dart' as studio;
import 'support.dart';

/// Filters the menu to Fresh Juice and opens Mango Juice's full editor.
Future<void> filterAndOpenMango(DashHarness h) async {
  await h.tap(find.byKey(const ValueKey('filter-category')));
  await pickOption(h, h.locale == 'ar' ? 'عصائر طازجة' : 'Fresh Juice');
  expect(inPage(find.text('Cortado')), findsNothing);
  final mango = h.locale == 'ar' ? 'عصير مانجو' : 'Mango Juice';
  await openCardMenu(h, mango);
  await pickMenu(h, h.t('menu.grid.fullEditor'));
  expect(find.byType(MenuStudioPage), findsOneWidget);
  expect(h.location.path, startsWith('/menu/items/'));
}

/// The menu is back, still filtered to Fresh Juice.
void expectStillFiltered(DashHarness h, {String label = 'Fresh Juice'}) {
  expect(h.location.path, itemsPath);
  expect(find.byType(MenuItemsPage), findsOneWidget);
  final filter = find.byKey(const ValueKey('filter-category'));
  expect(find.descendant(of: filter, matching: find.text(label)), findsWidgets);
  expect(lastCall(h, 'GET', catalogPath).query['category_id'], [
    category('juice'),
  ]);
  expect(inPage(find.text('Cortado')), findsNothing);
}

void main() {
  testWidgets('category filter → edit item → header Back keeps the filter', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    await filterAndOpenMango(h);
    await h.tap(find.bySemanticsLabel(h.t('common.back')).first);
    expectStillFiltered(h);
    expect(inPage(find.text('Mango Juice')), findsOneWidget);
  });

  testWidgets('category filter → edit item → system back keeps the filter', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    await filterAndOpenMango(h);
    final handled = await tester.binding.handlePopRoute();
    await h.settle();
    expect(handled, isTrue, reason: 'the system back is the page Back');
    expectStillFiltered(h);
  });

  testWidgets('system back closes a dialog over the studio first', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    await filterAndOpenMango(h);
    await h.tap(studio.studioText(h.t('menu.grid.duplicate')));
    expect(find.text(h.t('menu.studio.duplicateTitle')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await h.settle();
    expect(find.text(h.t('menu.studio.duplicateTitle')), findsNothing);
    expect(find.byType(MenuStudioPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await h.settle();
    expectStillFiltered(h);
  });

  testWidgets('edit → Save → Back: the filter and the saved name', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    await filterAndOpenMango(h);
    await h.enterText(studio.fieldWithText('Mango Juice'), 'Mango Smoothie');
    await studio.tapSave(h);
    await h.expectToast(h.t('common.savedChanges'));
    await h.tap(find.bySemanticsLabel(h.t('common.back')).first);
    expectStillFiltered(h);
    expect(inPage(find.text('Mango Smoothie')), findsOneWidget);
  });

  testWidgets('Arabic (RTL): the same round trip keeps the filter', (
    tester,
  ) async {
    final h = await pumpItems(tester, locale: 'ar');
    await filterAndOpenMango(h);
    await h.tap(find.bySemanticsLabel(h.t('common.back')).first);
    expectStillFiltered(h, label: 'عصائر طازجة');
  });

  testWidgets('tab, search and page come back from another page', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    // Items: page 2.
    await h.tap(find.bySemanticsLabel('Next'));
    expect(lastCall(h, 'GET', catalogPath).query['page'], ['2']);
    await h.go('/menu/groups');
    await h.go(itemsPath);
    expect(lastCall(h, 'GET', catalogPath).query['page'], ['2']);
    // Add-ons, searched.
    await openTab(h, 'addons');
    await h.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('menu-grid-addons')),
        matching: find.byType(DashSearchInput),
      ),
      'oat',
    );
    await h.settle();
    await h.go('/menu/pricing');
    await h.go(itemsPath);
    expect(find.byKey(const ValueKey('menu-grid-addons')), findsOneWidget);
    final search = tester.widget<DashSearchInput>(
      find.descendant(
        of: find.byKey(const ValueKey('menu-grid-addons')),
        matching: find.byType(DashSearchInput),
      ),
    );
    expect(search.value, 'oat');
  });

  testWidgets('a remembered category that was deleted is dropped', (
    tester,
  ) async {
    final s = itemsServer();
    final h = await pumpItems(tester, seeded: s);
    await h.tap(find.byKey(const ValueKey('filter-category')));
    await pickOption(h, 'Fresh Juice');
    await h.go('/menu/groups');
    // Gone while the person was elsewhere.
    s.db[MenuTables.categories].update(category('juice'), {
      'deleted_at': '2026-10-11T00:00:00Z',
    });
    h.container.invalidate(menuCategoriesProvider(sabahOrg));
    await h.go(itemsPath);
    final filter = find.byKey(const ValueKey('filter-category'));
    expect(
      find.descendant(of: filter, matching: find.text('All categories')),
      findsOneWidget,
    );
    expect(inPage(find.text('Cortado')), findsOneWidget);
  });

  testWidgets('another org forgets the menu filters', (tester) async {
    final h = await pumpItems(tester);
    await h.tap(find.byKey(const ValueKey('filter-category')));
    await pickOption(h, 'Fresh Juice');
    await h.go('/menu/groups');
    final memory = h.container.read(dashListMemoryProvider);
    expect(memory.recall('menu.items').string('category'), category('juice'));
    // Signing out (no org) wipes it; a later sign-in starts clean.
    await h.container.read(sessionProvider.notifier).signOut();
    await h.settle();
    expect(memory.recall('menu.items').isEmpty, isTrue);
  });
}
