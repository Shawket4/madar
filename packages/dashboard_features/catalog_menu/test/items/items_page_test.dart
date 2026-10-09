// The items page's shell, tabs and Items grid (MENU-ITEMS-001..028,
// 106..111) driven through the real shell over the mock backend.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('page shell', () {
    testWidgets('MENU-ITEMS-001 header: title, subtitle, the tax hint', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      expect(inPage(find.text('Menu')), findsWidgets);
      expect(inPage(find.text('Categories, items and addons')), findsOneWidget);
      expect(
        inPage(
          find.text(
            'Prices include tax (\u206614%\u2069) · branches may override',
          ),
        ),
        findsOneWidget,
      );
      expect(lastCall(h, 'GET', catalogPath).query, {
        'org_id': [sabahOrg],
        'page': ['1'],
        'per_page': ['24'],
      });
    });

    testWidgets('MENU-ITEMS-002 tax hint: exclusive, none, Arabic', (
      tester,
    ) async {
      final s = itemsServer();
      s.db['orgs'].update(sabahOrg, {'tax_inclusive': false});
      await pumpItems(tester, seeded: s);
      expect(
        inPage(
          find.text(
            'Tax (\u206614%\u2069) is added at checkout · branches may override',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-ITEMS-002 tax hint hidden when the org has no tax', (
      tester,
    ) async {
      final s = itemsServer();
      s.db['orgs'].update(sabahOrg, {'tax_rate': 0});
      await pumpItems(tester, seeded: s);
      expect(find.byKey(const ValueKey('price-tax-hint')), findsNothing);
    });

    testWidgets('MENU-ITEMS-002 tax hint in Arabic', (tester) async {
      final s = itemsServer();
      s.db['orgs'].update(sabahOrg, {'tax_inclusive': false});
      await pumpItems(tester, seeded: s, locale: 'ar');
      final hint = tester.widget<Text>(
        find.byKey(const ValueKey('price-tax-hint')),
      );
      expect(
        hint.data,
        startsWith('تُضاف الضريبة (\u206614%\u2069) عند الدفع'),
      );
    });

    testWidgets('MENU-ITEMS-003 tabs with counts; Items first; switching', (
      tester,
    ) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      final addons = CatalogMenuData(s.db).addonItems().length;
      expect(find.bySemanticsLabel('Items 40'), findsOneWidget);
      expect(find.bySemanticsLabel('Addons $addons'), findsOneWidget);
      expect(find.bySemanticsLabel('Categories 7'), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-grid-items')), findsOneWidget);
      await openTab(h, 'addons');
      expect(find.byKey(const ValueKey('menu-grid-addons')), findsOneWidget);
      await openTab(h, 'categories');
      expect(
        find.byKey(const ValueKey('menu-grid-categories')),
        findsOneWidget,
      );
      expect(h.location.path, itemsPath, reason: 'the tab is not in the URL');
    });

    testWidgets('MENU-ITEMS-004 branch hint without a branch; none with one', (
      tester,
    ) async {
      final hint =
          'Select a branch in the top bar to toggle per-branch '
          'availability here.';
      final h = await pumpItems(tester);
      expect(inPage(find.text(hint)), findsOneWidget);
      await openTab(h, 'addons');
      expect(inPage(find.text(hint)), findsOneWidget);
      await openTab(h, 'categories');
      expect(inPage(find.text(hint)), findsNothing);
      await openTab(h, 'items');
      await h.container.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
      await h.settle();
      expect(inPage(find.text(hint)), findsNothing);
    });

    testWidgets(
      'MENU-ITEMS-005 / MENU-AREA-010 no org: pick-org state, no reads',
      (tester) async {
        final h = await pumpItems(tester, persona: Persona.platform);
        expect(
          inPage(find.text('Select an organization to manage its menu')),
          findsOneWidget,
        );
        expect(inPage(find.text('Menu')), findsWidgets);
        expect(callsOf(h, 'GET', catalogPath), isEmpty);
        expect(callsOf(h, 'GET', '/categories'), isEmpty);
      },
    );
  });

  group('items grid', () {
    testWidgets('MENU-ITEMS-006 paged 24; the previous page stays while the '
        'next loads', (tester) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      expect(inPage(find.text('Almond Croissant')), findsOneWidget);
      expect(inPage(find.text('Iced Mocha')), findsOneWidget);
      expect(inPage(find.text('Iced Spanish Latte')), findsNothing);
      final gate = s.server.hold('GET', catalogPath);
      await h.tap(find.bySemanticsLabel('Next'));
      expect(
        inPage(find.text('Almond Croissant')),
        findsOneWidget,
        reason: 'kept on screen while page 2 loads',
      );
      expect(find.byType(DashSkeleton), findsNothing);
      gate.release();
      await h.settle();
      expect(lastCall(h, 'GET', catalogPath).query['page'], ['2']);
      expect(inPage(find.text('Iced Spanish Latte')), findsOneWidget);
      expect(inPage(find.text('Almond Croissant')), findsNothing);
    });

    testWidgets('MENU-ITEMS-007 loading: eight skeleton cards', (tester) async {
      final s = itemsServer();
      final gate = s.server.hold('GET', catalogPath);
      final h = await pumpItems(tester, seeded: s);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('menu-grid-items')),
          matching: find.byType(DashSkeleton),
        ),
        findsNWidgets(8),
      );
      gate.release();
      await h.settle();
      expect(find.byType(DashSkeleton), findsNothing);
    });

    testWidgets('MENU-ITEMS-008 empty: "No items yet", also for no match', (
      tester,
    ) async {
      final s = itemsServer();
      for (final m in liveItems(s.db)) {
        m['deleted_at'] = '2026-09-01T09:00:00Z';
      }
      await pumpItems(tester, seeded: s);
      expect(inPage(find.text('No items yet')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-008 a search that matches nothing reads the same', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await h.enterText(labelIn(page, 'Search'), 'zzzz');
      await tester.pump(const Duration(milliseconds: 350));
      await h.settle();
      expect(inPage(find.text('No items yet')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-009 (divergence) a failed read: its words and '
        'Retry, which refetches only the catalog', (tester) async {
      final s = itemsServer();
      final boom = MockResponse.error(500, 'Catalog unavailable');
      s.server.fail('GET', catalogPath, boom, times: null);
      final h = await pumpItems(tester, seeded: s);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(inPage(find.text('No items yet')), findsNothing);
      s.server.clearFailures();
      final categories = callsOf(h, 'GET', '/categories').length;
      await h.tap(inPage(find.text('Retry')));
      expect(inPage(find.text('Cortado')), findsOneWidget);
      expect(callsOf(h, 'GET', '/categories').length, categories);
    });

    testWidgets('MENU-ITEMS-009 while the retry runs: the error, spinning, '
        'never "No items yet"', (tester) async {
      final s = itemsServer();
      s.server.fail(
        'GET',
        catalogPath,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpItems(tester, seeded: s);
      s.server.clearFailures();
      final gate = s.server.hold('GET', catalogPath);
      await h.tap(inPage(find.text('Retry')));
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text('No items yet')), findsNothing);
      gate.release();
      await h.settle();
      expect(inPage(find.text('Cortado')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-010 search: debounced, server-side, page reset', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await h.tap(find.bySemanticsLabel('Next'));
      expect(lastCall(h, 'GET', catalogPath).query['page'], ['2']);
      final before = callsOf(h, 'GET', catalogPath).length;
      await h.tester.enterText(
        find
            .descendant(
              of: labelIn(page, 'Search'),
              matching: find.byType(EditableText),
              matchRoot: true,
            )
            .first,
        'latte',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        callsOf(h, 'GET', catalogPath).length,
        before,
        reason: 'not yet: debounced',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await h.settle();
      final q = lastCall(h, 'GET', catalogPath).query;
      expect(q['search'], ['latte']);
      expect(q['page'], ['1']);
      expect(inPage(find.text('Caffè Latte')), findsOneWidget);
      expect(inPage(find.text('Cortado')), findsNothing);
    });

    testWidgets('MENU-ITEMS-011 category filter: All categories + each, '
        'category_id, page reset', (tester) async {
      final h = await pumpItems(tester);
      await h.tap(find.bySemanticsLabel('Next'));
      final filter = find.byKey(const ValueKey('filter-category'));
      expect(
        find.descendant(of: filter, matching: find.text('All categories')),
        findsOneWidget,
      );
      await h.tap(filter);
      await pickOption(h, 'Fresh Juice');
      final q = lastCall(h, 'GET', catalogPath).query;
      expect(q['category_id'], [category('juice')]);
      expect(q['page'], ['1']);
      expect(inPage(find.text('Mango Juice')), findsOneWidget);
      expect(inPage(find.text('Cortado')), findsNothing);
      await h.tap(filter);
      await pickOption(h, 'All categories');
      // Back on the unfiltered page 1, still fresh in the cache.
      expect(inPage(find.text('Cortado')), findsOneWidget);
      expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
    });

    testWidgets(
      'MENU-ITEMS-012 recipe filter: Any / No recipe / Has a recipe',
      (tester) async {
        final h = await pumpItems(tester);
        final filter = find.byKey(const ValueKey('filter-recipe'));
        expect(
          find.descendant(of: filter, matching: find.text('Any recipe')),
          findsOneWidget,
        );
        await h.tap(filter);
        await pickOption(h, 'No recipe');
        expect(lastCall(h, 'GET', catalogPath).query['has_recipe'], ['false']);
        expect(inPage(find.text('Avocado Toast')), findsOneWidget);
        expect(inPage(find.text('Cortado')), findsNothing);
        expect(find.bySemanticsLabel('Items 10'), findsOneWidget);
        await h.tap(filter);
        await pickOption(h, 'Has a recipe');
        expect(lastCall(h, 'GET', catalogPath).query['has_recipe'], ['true']);
        expect(inPage(find.text('Cortado')), findsOneWidget);
        expect(inPage(find.text('Avocado Toast')), findsNothing);
      },
    );

    testWidgets('MENU-ITEMS-013 refusal: no recipes.read, no recipe filter and '
        'no has_recipe', (tester) async {
      final h = await pumpItems(tester, persona: Persona.limited);
      expect(find.byKey(const ValueKey('filter-recipe')), findsNothing);
      for (final c in callsOf(h, 'GET', catalogPath)) {
        expect(c.query.containsKey('has_recipe'), isFalse);
      }
      expect(inPage(find.text('Cortado')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-014 pager: Page x of y, Previous / Next', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
      final prev = tester.widget<DashIconButton>(
        find
            .ancestor(
              of: find.bySemanticsLabel('Previous'),
              matching: find.byType(DashIconButton),
            )
            .first,
      );
      expect(prev.onPressed, isNull);
      await h.tap(find.bySemanticsLabel('Next'));
      expect(inPage(find.text('Page 2 of 2')), findsOneWidget);
      final next = tester.widget<DashIconButton>(
        find
            .ancestor(
              of: find.bySemanticsLabel('Next'),
              matching: find.byType(DashIconButton),
            )
            .first,
      );
      expect(next.onPressed, isNull);
      await h.tap(find.bySemanticsLabel('Previous'));
      expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
      expect(inPage(find.text('Cortado')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-014 one page: no pager', (tester) async {
      final h = await pumpItems(tester);
      final filter = find.byKey(const ValueKey('filter-category'));
      await h.tap(filter);
      await pickOption(h, 'Bakery');
      expect(inPage(find.textContaining('Page ')), findsNothing);
    });

    testWidgets('MENU-ITEMS-015 card: tile, translated title, fields, footer; '
        'a multi-column grid on a desktop', (tester) async {
      await pumpItems(tester);
      final card = cardOf('Cappuccino');
      expect(inCard('Cappuccino', find.text('Price')), findsOneWidget);
      expect(inCard('Cappuccino', find.text('Category')), findsOneWidget);
      expect(inCard('Cappuccino', find.text('Active')), findsOneWidget);
      expect(inCard('Cappuccino', find.text('Hot Coffee')), findsOneWidget);
      expect(inCard('Cappuccino', find.text('EGP 110.00')), findsOneWidget);
      expect(card, findsOneWidget);
      final tops = [
        for (final n in [
          'Almond Croissant',
          'Americano',
          'Avocado Toast',
          'Banana Bread',
          'Butter Croissant',
        ])
          tester.getTopLeft(cardOf(n)).dy,
      ];
      // The kit's grid counts columns by its own width (3 here); the web's
      // viewport `xl` gives 4 (logged as a kit candidate).
      expect(tops.sublist(0, 3).toSet(), hasLength(1));
      expect(tops[4], greaterThan(tops[0]));
    });

    testWidgets('MENU-ITEMS-015 card in Arabic: the Arabic name', (
      tester,
    ) async {
      await pumpItems(tester, locale: 'ar');
      expect(inPage(find.text('كابتشينو')), findsOneWidget);
      expect(inCard('كابتشينو', find.text('قهوة ساخنة')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-016 inline rename: Enter commits, toast, refetch', (
      tester,
    ) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      await h.tap(labelIn(cardOf('Cortado'), 'Name: Cortado'));
      await typeAndSubmit(h, labelIn(page, 'Name'), 'Cortado Doble');
      final call = lastCall(h, 'PATCH', '/menu-items/{id}');
      expect(call.path, '/menu-items/${item('cortado')}');
      expect(call.body, {'name': 'Cortado Doble'});
      await h.expectToast('Changes saved');
      expect(inPage(find.text('Cortado Doble')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-016 inline rename: Esc cancels, unchanged sends '
        'nothing', (tester) async {
      final h = await pumpItems(tester);
      await h.tap(labelIn(cardOf('Cortado'), 'Name: Cortado'));
      await h.enterText(labelIn(page, 'Name'), 'Other');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(inPage(find.text('Cortado')), findsOneWidget);
      await h.tap(labelIn(cardOf('Cortado'), 'Name: Cortado'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(callsOf(h, 'PATCH', '/menu-items/{id}'), isEmpty);
    });

    testWidgets('MENU-ITEMS-016 a refused rename toasts the server words', (
      tester,
    ) async {
      final h = await pumpItems(tester, persona: Persona.manager);
      await h.tap(labelIn(cardOf('Cortado'), 'Name: Cortado'));
      await typeAndSubmit(h, labelIn(page, 'Name'), 'Cortado 2');
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.items.edit')),
      );
      expect(inPage(find.text('Cortado')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-017 price is read-only', (tester) async {
      final h = await pumpItems(tester);
      await h.tap(inCard('Cappuccino', find.text('EGP 110.00')));
      expect(
        find.descendant(
          of: cardOf('Cappuccino'),
          matching: find.byType(EditableText),
        ),
        findsNothing,
      );
    });

    testWidgets('MENU-ITEMS-018 inline category commits a different one', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await chooseIn(h, cardOf('Cortado'), 'Category', 'Iced Coffee');
      final call = lastCall(h, 'PATCH', '/menu-items/{id}');
      expect(call.body, {'category_id': category('iced')});
      await h.expectToast('Changes saved');
      expect(inCard('Cortado', find.text('Iced Coffee')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-019 inline Active switch commits', (tester) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      await h.tap(switchIn(cardOf('Cortado'), 'Active'));
      expect(lastCall(h, 'PATCH', '/menu-items/{id}').body, {
        'is_active': false,
      });
      await h.expectToast('Changes saved');
      expect(
        s.db[MenuTables.menuItems].find(item('cortado'))!['is_active'],
        isFalse,
      );
    });

    testWidgets('MENU-ITEMS-020 cost footer: per size, food-cost chip, the '
        'missing-cost link', (tester) async {
      final h = await pumpItems(tester, seeded: itemsServer());
      await h.tap(find.bySemanticsLabel('Next'));
      final card = cardOf('Pistachio Latte');
      expect(
        find.descendant(of: card, matching: find.text('Regular')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Large')),
        findsOneWidget,
      );
      final fix = labelIn(card, 'Add ingredient costs to compute this');
      expect(fix, findsWidgets);
      // A single-size item: one line, no size label.
      await h.tap(find.bySemanticsLabel('Previous'));
      expect(inCard('Cortado', find.byType(DashFoodCostChip)), findsOneWidget);
      expect(inCard('Cortado', find.text('one_size')), findsNothing);
      await h.tap(find.bySemanticsLabel('Next'));
      await h.tap(
        labelIn(
          cardOf('Pistachio Latte'),
          'Add ingredient costs to compute this',
        ),
      );
      expect(
        h.location.path,
        itemsPath,
        reason: '/menu/recipes?item= redirects to the items page',
      );
    });

    testWidgets('MENU-ITEMS-020 no SKUs (inactive item): a dash', (
      tester,
    ) async {
      final s = itemsServer();
      s.db[MenuTables.menuItems].update(item('cortado'), {'is_active': false});
      await pumpItems(tester, seeded: s);
      expect(inCard('Cortado', find.text('—')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-021 branch toggle shown with one branch, reading '
        'the overrides', (tester) async {
      final h = await pumpItems(tester, branchId: SeedIds.zamalek);
      expect(lastCall(h, 'GET', '/branch-menu-overrides').query['branch_id'], [
        SeedIds.zamalek,
      ]);
      DashSwitch sw(String name) => tester.widget<DashSwitch>(
        find
            .descendant(of: cardOf(name), matching: find.byType(DashSwitch))
            .last,
      );
      expect(sw('Cortado').value, isTrue);
      await h.tap(find.bySemanticsLabel('Next'));
      expect(sw('Pistachio Latte').value, isFalse);
      expect(sw('Spanish Latte').value, isTrue);
    });

    testWidgets('MENU-ITEMS-021 no toggles without a branch', (tester) async {
      final h = await pumpItems(tester);
      expect(inPage(find.text('Available at this branch')), findsNothing);
      expect(callsOf(h, 'GET', '/branch-menu-overrides'), isEmpty);
    });

    testWidgets('MENU-ITEMS-022 off at the branch: every size, prices kept', (
      tester,
    ) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s, branchId: SeedIds.zamalek);
      await h.tap(find.bySemanticsLabel('Next'));
      await h.tap(
        switchIn(cardOf('Spanish Latte'), 'Available at this branch'),
      );
      expect(
        lastCall(h, 'GET', '/menu-items/{id}/studio').path,
        '/menu-items/${item('spanish')}/studio',
      );
      final puts = callsOf(h, 'PUT', '/menu-price-overrides');
      expect(puts.map((c) => c.body), [
        {
          'branch_id': SeedIds.zamalek,
          'is_available': false,
          'price': 14000,
          'scope': 'branch',
          'target_id': size('spanish', 'Regular'),
          'target_type': 'menu_item_size',
        },
        {
          'branch_id': SeedIds.zamalek,
          'is_available': false,
          'price': 16000,
          'scope': 'branch',
          'target_id': size('spanish', 'Large'),
          'target_type': 'menu_item_size',
        },
      ]);
      await h.expectToast('Changes saved');
      final sw = tester.widget<DashSwitch>(
        find
            .descendant(
              of: cardOf('Spanish Latte'),
              matching: find.byType(DashSwitch),
            )
            .last,
      );
      expect(sw.value, isFalse);
    });

    testWidgets('MENU-ITEMS-023 on at the branch: price-less rows deleted, '
        'priced rows keep the price', (tester) async {
      final s = itemsServer();
      // Spanish Latte: priced at Zamalek; switch it off, then on.
      s.db[MenuTables.priceOverrides]
              .where((o) => o['target_id'] == size('spanish', 'Regular'))
              .single['is_available'] =
          false;
      s.db[MenuTables.priceOverrides]
              .where((o) => o['target_id'] == size('spanish', 'Large'))
              .single['is_available'] =
          false;
      final h = await pumpItems(tester, seeded: s, branchId: SeedIds.zamalek);
      await h.tap(find.bySemanticsLabel('Next'));
      await h.tap(
        switchIn(cardOf('Spanish Latte'), 'Available at this branch'),
      );
      expect(callsOf(h, 'PUT', '/menu-price-overrides').map((c) => c.body), [
        for (final l in ['Regular', 'Large'])
          {
            'branch_id': SeedIds.zamalek,
            'is_available': null,
            'price': l == 'Regular' ? 14000 : 16000,
            'scope': 'branch',
            'target_id': size('spanish', l),
            'target_type': 'menu_item_size',
          },
      ]);
      await h.flushTimers();
      // Pistachio Latte: availability only → the rows go.
      await h.tap(
        switchIn(cardOf('Pistachio Latte'), 'Available at this branch'),
      );
      expect(callsOf(h, 'DELETE', '/menu-price-overrides').map((c) => c.body), [
        for (final l in ['Regular', 'Large'])
          {
            'branch_id': SeedIds.zamalek,
            'scope': 'branch',
            'target_id': size('pistachio_latte', l),
            'target_type': 'menu_item_size',
          },
      ]);
      await h.expectToast('Changes saved');
    });

    testWidgets('MENU-ITEMS-022 a refused toggle toasts the server words', (
      tester,
    ) async {
      final h = await pumpItems(
        tester,
        persona: Persona.manager,
        branchId: SeedIds.zamalek,
      );
      await h.tap(switchIn(cardOf('Cortado'), 'Available at this branch'));
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.items.edit')),
      );
    });

    testWidgets('MENU-ITEMS-024 New item opens the dialog with the filter as '
        'its category', (tester) async {
      final h = await pumpItems(tester);
      await h.tap(find.byKey(const ValueKey('filter-category')));
      await pickOption(h, 'Bakery');
      await h.tapText('New item');
      expect(inSurface(find.text('New item')), findsOneWidget);
      expect(inSurface(find.text('Bakery')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-025 card actions; full editor opens the studio', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      h.allowUnmatched = true;
      await openCardMenu(h, 'Cortado');
      expect(
        find.text('Open full editor (sizes, translations)'),
        findsOneWidget,
      );
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await pickMenu(h, 'Open full editor (sizes, translations)');
      expect(h.location.path, '/menu/items/${item('cortado')}');
    });

    testWidgets('MENU-ITEMS-026 a combo: combo editor, no Duplicate', (
      tester,
    ) async {
      final s = itemsServer();
      s.db[MenuTables.menuItems].insert({
        ...s.db[MenuTables.menuItems].find(item('latte'))!,
        'id': 'combo-breakfast',
        'name': 'Breakfast Combo',
        'name_translations': {'en': 'Breakfast Combo', 'ar': 'كومبو الفطور'},
        'kind': 'combo',
      }, timestamps: false);
      final h = await pumpItems(tester, seeded: s);
      h.allowUnmatched = true;
      await openCardMenu(h, 'Breakfast Combo');
      expect(find.text('Duplicate'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
      await pickMenu(h, 'Open combo editor (slots, availability)');
      expect(h.location.path, '/menu/combos/combo-breakfast');
    });

    testWidgets('MENU-ITEMS-027 duplicate: deep copy, set inactive, toast', (
      tester,
    ) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      await openCardMenu(h, 'Cortado');
      await pickMenu(h, 'Duplicate');
      expect(
        lastCall(h, 'POST', '/menu-items/{id}/duplicate').path,
        '/menu-items/${item('cortado')}/duplicate',
      );
      final copy = s.db[MenuTables.menuItems].firstWhere(
        (m) => m['name'] == 'Cortado (Copy)',
      )!;
      expect(
        lastCall(h, 'PATCH', '/menu-items/{id}').path,
        '/menu-items/${copy['id']}',
      );
      expect(lastCall(h, 'PATCH', '/menu-items/{id}').body, {
        'is_active': false,
      });
      expect(copy['is_active'], isFalse);
      await h.expectToast('Duplicated Cortado');
      expect(inPage(find.text('Cortado (Copy)')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-027 a failed duplicate toasts the words', (
      tester,
    ) async {
      final s = itemsServer();
      final gone = MockResponse.notFound('Menu item not found');
      s.server.fail('POST', '/menu-items/{id}/duplicate', gone);
      final h = await pumpItems(tester, seeded: s);
      await openCardMenu(h, 'Cortado');
      await pickMenu(h, 'Duplicate');
      await h.expectToast(h.refusalWords(gone));
    });

    testWidgets('MENU-ITEMS-028 delete: destructive confirm, then DELETE', (
      tester,
    ) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      await openCardMenu(h, 'Cortado');
      await pickMenu(h, 'Delete');
      expect(find.text('Delete "Cortado"?'), findsOneWidget);
      expect(
        find.text(
          'It leaves the POS menu at every branch, with its sizes, '
          'recipe and branch prices. Past orders keep their lines.',
        ),
        findsOneWidget,
      );
      await h.tap(find.text('Cancel').last);
      expect(callsOf(h, 'DELETE', '/menu-items/{id}'), isEmpty);
      await openCardMenu(h, 'Cortado');
      await pickMenu(h, 'Delete');
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      expect(
        lastCall(h, 'DELETE', '/menu-items/{id}').path,
        '/menu-items/${item('cortado')}',
      );
      await h.expectToast('Changes saved');
      expect(inPage(find.text('Cortado')), findsNothing);
    });

    testWidgets('MENU-ITEMS-028 a refused delete toasts the words', (
      tester,
    ) async {
      final h = await pumpItems(tester, persona: Persona.manager);
      await openCardMenu(h, 'Cortado');
      await pickMenu(h, 'Delete');
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.items.delete')),
      );
    });
  });

  group('critic rows', () {
    testWidgets('MENU-ITEMS-109 a cleared title is sent as is', (tester) async {
      final h = await pumpItems(tester);
      await h.tap(labelIn(cardOf('Cortado'), 'Name: Cortado'));
      await typeAndSubmit(h, labelIn(page, 'Name'), '');
      expect(lastCall(h, 'PATCH', '/menu-items/{id}').body, {'name': ''});
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-110 (divergence) the delete confirm names the '
        'item in the active language', (tester) async {
      final h = await pumpItems(tester, locale: 'ar');
      await openCardMenu(h, 'كورتادو');
      await pickMenu(h, 'حذف');
      expect(find.text('حذف «كورتادو»؟'), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-106 pointing at a card warms the item and its '
        'studio; opening the full editor asks for neither again', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.ensureVisible(inPage(find.text('Cortado')));
      await h.settle();
      await mouse.moveTo(tester.getCenter(inPage(find.text('Cortado'))));
      await h.settle();
      expect(callsOf(h, 'GET', '/menu-items/{id}').map((c) => c.path), [
        '/menu-items/${item('cortado')}',
      ]);
      expect(callsOf(h, 'GET', '/menu-items/{id}/studio').map((c) => c.path), [
        '/menu-items/${item('cortado')}/studio',
      ]);
      await openCardMenu(h, 'Cortado');
      await pickMenu(h, 'Open full editor (sizes, translations)');
      expect(h.location.path, '/menu/items/${item('cortado')}');
      expect(
        callsOf(h, 'GET', '/menu-items/{id}/studio'),
        hasLength(1),
        reason: 'served from the cache',
      );
    });

    testWidgets('MENU-ITEMS-107 pointing at Next warms the next page; '
        'turning to it asks nothing more', (tester) async {
      final h = await pumpItems(tester);
      List<MockCall> page2() => [
        for (final c in callsOf(h, 'GET', catalogPath))
          if (c.query['page']?.single == '2') c,
      ];
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.ensureVisible(find.bySemanticsLabel('Next'));
      await h.settle();
      await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Next')));
      await h.settle();
      expect(page2(), hasLength(1));
      expect(page2().single.query, {
        'org_id': [sabahOrg],
        'page': ['2'],
        'per_page': ['24'],
      });
      await h.tap(find.bySemanticsLabel('Next'));
      expect(inPage(find.text('Iced Spanish Latte')), findsOneWidget);
      expect(page2(), hasLength(1), reason: 'served from the cache');
      // On the last page there is nothing to warm.
      final before = callsOf(h, 'GET', catalogPath).length;
      await mouse.moveTo(Offset.zero);
      await tester.ensureVisible(find.bySemanticsLabel('Next'));
      await h.settle();
      await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Next')));
      await h.settle();
      expect(callsOf(h, 'GET', catalogPath), hasLength(before));
    });
  });
}
