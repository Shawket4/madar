// The Add-ons tab (MENU-ITEMS-039..055, 108) driven through the real shell.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _addons = '/addon-items';
const String _costs = '/costing/addon-items';
const String _option = '/modifier-options/{oid}';

/// Adds [n] more options to the Extras group (to pass one page).
void _moreExtras(MockDb db, int n) {
  final g = db[MenuTables.groups].find(MenuSeedIds.group('extras'))!;
  final opts = (g['options'] as List).cast<Map<String, Object?>>();
  for (var i = 0; i < n; i++) {
    opts.add({
      ...opts.first,
      'id': mockUuid('extra-more:$i'),
      'name': 'Syrup shot ${i + 1}',
      'name_translations': {'en': 'Syrup shot ${i + 1}'},
      'sort': 100 + i,
      'recipe': const <Object?>[],
    });
  }
}

Future<DashHarness> _open(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  ({MockServer server, MockDb db})? seeded,
  String? branchId,
  String locale = 'en',
}) async {
  final h = await pumpItems(
    tester,
    persona: persona,
    seeded: seeded,
    branchId: branchId,
    locale: locale,
  );
  await openTab(h, 'addons');
  return h;
}

void main() {
  testWidgets('MENU-ITEMS-039 add-ons read on mount, every one', (
    tester,
  ) async {
    final s = itemsServer();
    final h = await pumpItems(tester, seeded: s);
    expect(lastCall(h, 'GET', _addons).query, {
      'org_id': [sabahOrg],
    });
    await openTab(h, 'addons');
    expect(inPage(find.text('Oat milk')), findsOneWidget);
    expect(inPage(find.text('Extra shot')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-040 the cost rollup is read only on the tab', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    expect(callsOf(h, 'GET', _costs), isEmpty);
    await openTab(h, 'addons');
    expect(lastCall(h, 'GET', _costs).query, {
      'org_id': [sabahOrg],
    });
  });

  testWidgets('MENU-ITEMS-041 loading: eight skeleton cards', (tester) async {
    final s = itemsServer();
    final gate = s.server.hold('GET', _addons);
    final h = await _open(tester, seeded: s);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('menu-grid-addons')),
        matching: find.byType(DashSkeleton),
      ),
      findsNWidgets(8),
    );
    gate.release();
    await h.settle();
    expect(inPage(find.text('Oat milk')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-042 empty: "No add-ons yet"', (tester) async {
    final s = itemsServer();
    for (final g in s.db[MenuTables.groups].rows) {
      g['legacy_addon_type'] = null;
    }
    await _open(tester, seeded: s);
    expect(inPage(find.text('No add-ons yet')), findsOneWidget);
    expect(find.bySemanticsLabel('Addons 0'), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-042 (divergence) a failed read: words and Retry', (
    tester,
  ) async {
    final s = itemsServer();
    s.server.fail('GET', _addons, MockResponse.error(500, 'boom'), times: null);
    final h = await _open(tester, seeded: s);
    expect(inPage(find.text("Couldn't load this")), findsOneWidget);
    expect(inPage(find.text('No add-ons yet')), findsNothing);
    s.server.clearFailures();
    await h.tap(inPage(find.text('Retry')));
    expect(inPage(find.text('Oat milk')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-043 search: name and type, any case, page reset', (
    tester,
  ) async {
    final s = itemsServer();
    _moreExtras(s.db, 10);
    final h = await _open(tester, seeded: s);
    await h.tap(find.bySemanticsLabel('Next'));
    await h.enterText(labelIn(page, 'Search'), 'MILK_TYPE');
    await tester.pump(const Duration(milliseconds: 350));
    await h.settle();
    expect(inPage(find.text('Oat milk')), findsOneWidget);
    expect(inPage(find.text('Skimmed')), findsOneWidget);
    expect(inPage(find.text('Extra shot')), findsNothing);
    expect(inPage(find.textContaining('Page ')), findsNothing);
  });

  testWidgets('MENU-ITEMS-044 type filter: All types + each raw type', (
    tester,
  ) async {
    final h = await _open(tester);
    final filter = find.byKey(const ValueKey('filter-addon-type'));
    expect(
      find.descendant(of: filter, matching: find.text('All types')),
      findsOneWidget,
    );
    await h.tap(filter);
    for (final ty in ['coffee_type', 'extra', 'milk_type', 'toppings']) {
      expect(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is DashOptionList),
          matching: find.text(ty),
        ),
        findsOneWidget,
      );
    }
    await pickOption(h, 'milk_type');
    expect(inPage(find.text('Oat milk')), findsOneWidget);
    expect(inPage(find.text('Extra shot')), findsNothing);
  });

  testWidgets('MENU-ITEMS-044 no types: no filter', (tester) async {
    final s = itemsServer();
    for (final g in s.db[MenuTables.groups].rows) {
      g['legacy_addon_type'] = null;
    }
    await _open(tester, seeded: s);
    expect(find.byKey(const ValueKey('filter-addon-type')), findsNothing);
  });

  testWidgets('MENU-ITEMS-045 client pager past 24', (tester) async {
    final s = itemsServer();
    _moreExtras(s.db, 10);
    final h = await _open(tester, seeded: s);
    final total = CatalogMenuData(s.db).addonItems().length;
    expect(inPage(find.text('Page 1 of 2')), findsOneWidget);
    await h.tap(find.bySemanticsLabel('Next'));
    expect(inPage(find.text('Page 2 of 2')), findsOneWidget);
    expect(total, greaterThan(24));
  });

  testWidgets('MENU-ITEMS-046 card: Tag tile, translated title, Type / Price '
      '/ Active, cost footer', (tester) async {
    final h = await _open(tester);
    final card = cardOf('Extra shot');
    expect(
      find.descendant(of: card, matching: find.text('Type')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('extra')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('EGP 30.00')),
      findsOneWidget,
    );
    // 18 g of the house blend at 0.95 a gram = EGP 17.10, 57% of 30.
    expect(
      find.descendant(of: card, matching: find.text('EGP 17.10')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(DashFoodCostChip)),
      findsOneWidget,
    );
    expect(h.t('menu.addonType'), 'Type');
  });

  testWidgets('MENU-ITEMS-046 card in Arabic: the Arabic name', (tester) async {
    await _open(tester, locale: 'ar');
    expect(inPage(find.text('حليب الشوفان')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-047 inline rename patches the option', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.tap(labelIn(cardOf('Oat milk'), 'Name: Oat milk'));
    await typeAndSubmit(h, fieldIn(page, 'Name'), 'Oat');
    final call = lastCall(h, 'PATCH', _option);
    expect(call.path, '/modifier-options/${option('milk', 'oat')}');
    expect(call.body, {'name': 'Oat'});
    await h.expectToast('Changes saved');
  });

  testWidgets('MENU-ITEMS-048 inline price in pounds → piastres; invalid '
      'dropped', (tester) async {
    final h = await _open(tester);
    await h.tap(labelIn(cardOf('Oat milk'), 'Price: 2500'));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: cardOf('Oat milk'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '25',
    );
    await typeAndSubmit(h, fieldIn(page, 'Price'), '27.5');
    expect(lastCall(h, 'PATCH', _option).body, {'price': 2750});
    await h.flushTimers();
    await h.tap(labelIn(cardOf('Oat milk'), 'Price: 2750'));
    await typeAndSubmit(h, fieldIn(page, 'Price'), '-3');
    expect(callsOf(h, 'PATCH', _option), hasLength(1));
  });

  testWidgets('MENU-ITEMS-049 inline Active', (tester) async {
    final h = await _open(tester);
    await h.tap(switchIn(cardOf('Oat milk'), 'Active'));
    expect(lastCall(h, 'PATCH', _option).body, {'is_active': false});
    await h.expectToast('Changes saved');
  });

  testWidgets('MENU-ITEMS-050 a Type edit sends an empty patch and still '
      'says saved', (tester) async {
    final h = await _open(tester);
    await h.tap(labelIn(cardOf('Oat milk'), 'Type: milk_type'));
    await typeAndSubmit(h, fieldIn(page, 'Type'), 'extra');
    expect(lastCall(h, 'PATCH', _option).body, <String, Object?>{});
    await h.expectToast('Changes saved');
    expect(inCard('Oat milk', find.text('milk_type')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-051 branch toggle: off keeps the price, on with no '
      'price deletes', (tester) async {
    final s = itemsServer();
    final h = await _open(tester, seeded: s, branchId: SeedIds.zamalek);
    expect(lastCall(h, 'GET', '/branch-addon-overrides').query['branch_id'], [
      SeedIds.zamalek,
    ]);
    await h.tap(switchIn(cardOf('Oat milk'), 'Available at this branch'));
    expect(lastCall(h, 'PUT', '/menu-price-overrides').body, {
      'branch_id': SeedIds.zamalek,
      'is_available': false,
      'price': 3000,
      'scope': 'branch',
      'target_id': option('milk', 'oat'),
      'target_type': 'modifier_option',
    });
    await h.expectToast('Changes saved');
    await h.tap(switchIn(cardOf('Oat milk'), 'Available at this branch'));
    expect(lastCall(h, 'PUT', '/menu-price-overrides').body, {
      'branch_id': SeedIds.zamalek,
      'is_available': null,
      'price': 3000,
      'scope': 'branch',
      'target_id': option('milk', 'oat'),
      'target_type': 'modifier_option',
    });
    await h.flushTimers();
    await h.tap(switchIn(cardOf('Skimmed'), 'Available at this branch'));
    expect(lastCall(h, 'PUT', '/menu-price-overrides').body, {
      'branch_id': SeedIds.zamalek,
      'is_available': false,
      'price': null,
      'scope': 'branch',
      'target_id': option('milk', 'skimmed'),
      'target_type': 'modifier_option',
    });
    await h.flushTimers();
    await h.tap(switchIn(cardOf('Skimmed'), 'Available at this branch'));
    expect(lastCall(h, 'DELETE', '/menu-price-overrides').body, {
      'branch_id': SeedIds.zamalek,
      'scope': 'branch',
      'target_id': option('milk', 'skimmed'),
      'target_type': 'modifier_option',
    });
    await h.expectToast('Changes saved');
  });

  testWidgets('MENU-ITEMS-052 New add-on opens the dialog', (tester) async {
    final h = await _open(tester);
    await h.tapText('New add-on');
    expect(inSurface(find.text('New add-on')), findsOneWidget);
    expect(
      inSurface(
        find.text('Add-ons are modifiers like extra shots or milk types.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('MENU-ITEMS-053 actions: Edit, Edit recipe, Delete', (
    tester,
  ) async {
    final h = await _open(tester);
    await openCardMenu(h, 'Extra shot');
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Edit recipe'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await pickMenu(h, 'Edit');
    expect(inSurface(find.text('Edit add-on')), findsOneWidget);
    await h.tap(inSurface(find.text('Cancel')));
    await openCardMenu(h, 'Extra shot');
    await pickMenu(h, 'Edit recipe');
    expect(inSurface(find.text('Add-on recipe')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-054 delete: confirm, DELETE the option', (
    tester,
  ) async {
    final h = await _open(tester);
    await openCardMenu(h, 'Oat milk');
    await pickMenu(h, 'Delete');
    expect(find.text('Delete "Oat milk"?'), findsOneWidget);
    expect(
      find.text(
        'It is removed from every item that offers it. If orders used '
        'it, it is deactivated instead so history stays intact.',
      ),
      findsOneWidget,
    );
    await h.tap(
      find.descendant(
        of: find.byType(DashConfirmDialog),
        matching: find.text('Delete'),
      ),
    );
    expect(
      lastCall(h, 'DELETE', _option).path,
      '/modifier-options/${option('milk', 'oat')}',
    );
    await h.expectToast('Changes saved');
  });

  testWidgets('MENU-ITEMS-055 pointing at the Add-ons tab warms its reads', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    final addons = callsOf(h, 'GET', _addons).length;
    expect(callsOf(h, 'GET', _costs), isEmpty);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('menu-tab-addons'))),
    );
    await h.settle();
    expect(callsOf(h, 'GET', _costs), hasLength(1));
    expect(
      callsOf(h, 'GET', _addons),
      hasLength(addons),
      reason: 'the list is fresh in the cache',
    );
    await openTab(h, 'addons');
    expect(callsOf(h, 'GET', _costs), hasLength(1), reason: 'served warm');
  });

  testWidgets('MENU-ITEMS-108 one search and page for Add-ons and '
      'Categories', (tester) async {
    final h = await _open(tester);
    await h.enterText(labelIn(page, 'Search'), 'milk');
    await tester.pump(const Duration(milliseconds: 350));
    await h.settle();
    await openTab(h, 'categories');
    final box = tester.widget<EditableText>(
      find
          .descendant(
            of: labelIn(page, 'Search'),
            matching: find.byType(EditableText),
          )
          .first,
    );
    expect(box.controller.text, 'milk');
    expect(inPage(find.text('No categories yet')), findsOneWidget);
    await openTab(h, 'items');
    final itemsBox = tester.widget<EditableText>(
      find
          .descendant(
            of: labelIn(page, 'Search'),
            matching: find.byType(EditableText),
          )
          .first,
    );
    expect(itemsBox.controller.text, '', reason: 'Items has its own search');
  });

  testWidgets('MENU-ITEMS-109 a blank or negative price is dropped', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.tap(labelIn(cardOf('Oat milk'), 'Price: 2500'));
    await typeAndSubmit(h, fieldIn(page, 'Price'), '');
    expect(callsOf(h, 'PATCH', _option), isEmpty);
  });
}
