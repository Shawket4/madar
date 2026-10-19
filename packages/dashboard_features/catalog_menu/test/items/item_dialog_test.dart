// The item dialog (MENU-ITEMS-072..092, 112, 115, MENU-AREA-013/014): create
// from the page and edit, driven through the shell.
import 'dart:async';
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' show MenuItem;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/items/item_dialog.dart';
import 'package:dashboard_catalog_menu/src/mock/items_mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A 1×1 PNG.
final List<int> _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<void> _openNew(DashHarness h) => h.tapText('New item');

/// Opens the dialog in edit mode on seeded item [key], or on the copy
/// [stale] the opener holds.
Future<void> _openEdit(DashHarness h, String key, {MenuItem? stale}) async {
  final row = h.db![MenuTables.menuItems].find(item(key))!;
  unawaited(
    showMenuItemDialog(
      h.tester.element(page),
      orgId: sabahOrg,
      item: stale ?? MenuItem.fromJson(row),
    ),
  );
  await h.settle();
}

Future<void> _pickCategory(DashHarness h, String name) =>
    chooseIn(h, surface, 'Category', name);

Future<void> _save(DashHarness h) => h.tap(inSurface(find.text('Save')));

String _text(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)).first,
    )
    .controller
    .text;

void main() {
  group('create', () {
    testWidgets('MENU-ITEMS-072 title, description, Cancel; reset on open', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      expect(inSurface(find.text('New item')), findsOneWidget);
      expect(
        inSurface(find.text('Define the product, price and category.')),
        findsOneWidget,
      );
      await h.enterText(fieldIn(surface, 'Name'), 'Flat White Oat');
      await h.tap(inSurface(find.text('Cancel')));
      expect(find.byType(DashSurface), findsNothing);
      await _openNew(h);
      expect(_text(tester, fieldIn(surface, 'Name')), '');
      expect(_text(tester, fieldIn(surface, 'Price (EGP)')), '0');
    });

    testWidgets('MENU-ITEMS-074 reads the ingredient catalog, add-ons and '
        'groups while open', (tester) async {
      final h = await pumpItems(tester);
      final groups = callsOf(h, 'GET', '/modifier-groups').length;
      await _openNew(h);
      expect(
        lastCall(h, 'GET', '/inventory/orgs/{org_id}/catalog').path,
        '/inventory/orgs/$sabahOrg/catalog',
      );
      expect(callsOf(h, 'GET', '/modifier-groups').length, groups + 1);
      expect(lastCall(h, 'GET', '/modifier-groups').query, {
        'org_id': [sabahOrg],
      });
    });

    testWidgets('MENU-ITEMS-077 the category and its "+" take the first of '
        'two columns (sm:grid-cols-2)', (tester) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      final select = selectIn(surface, 'Category');
      expect(select, findsOneWidget);
      expect(
        tester.getSize(select).width,
        lessThan(tester.getSize(surface).width / 2),
      );
    });

    testWidgets('MENU-ITEMS-075 / 077 name and category required', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      await _save(h);
      expect(inSurface(find.text('This field is required')), findsNWidgets(2));
      expect(callsOf(h, 'POST', '/menu-items'), isEmpty);
      expect(inSurface(find.text('Select category')), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-076 / 079 / 084 / 091 / 092 / 115 create: the '
        'payloads in order, toast, close', (tester) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      await _openNew(h);
      await h.enterText(fieldIn(surface, 'Name'), 'Rose Latte');
      await h.enterText(fieldIn(surface, 'Description'), 'Steamed milk, rose');
      await _pickCategory(h, 'Hot Coffee');
      await h.tap(switchIn(surface, 'Active'));
      await h.enterText(fieldIn(surface, 'Price (EGP)'), '125.5');
      await _save(h);
      final create = lastCall(h, 'POST', '/menu-items');
      expect(create.body, {
        'base_price': 12550,
        'category_id': category('hot'),
        'description': 'Steamed milk, rose',
        'name': 'Rose Latte',
        'org_id': sabahOrg,
      });
      final row = s.db[MenuTables.menuItems].firstWhere(
        (m) => m['name'] == 'Rose Latte',
      )!;
      expect(row['is_active'], isTrue, reason: 'created active anyway');
      expect(lastCall(h, 'PUT', '/menu-items/{id}/sizes').body, {
        'sizes': [
          {'is_active': true, 'label': 'one_size', 'price': 12550, 'sort': 0},
        ],
      });
      expect(lastCall(h, 'PUT', '/menu-item-sizes/{size_id}/recipe').body, {
        'lines': <Object?>[],
      });
      expect(
        callsOf(h, 'PUT', '/menu-items/{id}/modifier-groups'),
        isEmpty,
        reason: 'the add-on selection did not change',
      );
      expect(callsOf(h, 'POST', '/uploads/menu-items/{menu_item_id}'), isEmpty);
      await h.expectToast('Changes saved');
      expect(find.byType(DashSurface), findsNothing);
    });

    testWidgets('MENU-ITEMS-076 / 115 Arabic boxes sent only when typed', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      await h.enterText(fieldIn(surface, 'Name'), 'Rose Latte');
      await h.enterText(fieldIn(surface, 'Name (ع)'), 'لاتيه الورد');
      await h.enterText(fieldIn(surface, 'Description (ع)'), 'حليب وورد');
      await _pickCategory(h, 'Hot Coffee');
      await _save(h);
      expect(lastCall(h, 'POST', '/menu-items').body, {
        'base_price': 0,
        'category_id': category('hot'),
        'description': null,
        'description_translations': {'ar': 'حليب وورد'},
        'name': 'Rose Latte',
        'name_translations': {'ar': 'لاتيه الورد'},
        'org_id': sabahOrg,
      });
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-078 "+" makes a category and selects it', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      await h.tap(labelIn(surface, 'New category'));
      expect(find.byType(DashSurface), findsNWidgets(2));
      await h.enterText(fieldIn(surface, 'Name'), 'Smoothies');
      await h.tap(inSurface(find.text('Save')));
      expect(lastCall(h, 'POST', '/categories').body, {
        'name': 'Smoothies',
        'org_id': sabahOrg,
      });
      expect(find.byType(DashSurface), findsOneWidget);
      expect(inSurface(find.text('Smoothies')), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-080 picture staged, uploaded after save', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      expect(inSurface(find.text('Image')), findsOneWidget);
      expect(
        inSurface(find.text('Uploads after the item is saved')),
        findsOneWidget,
      );
      h.files.imageQueue.add(
        PickedFile(name: 'rose.png', bytes: _png, mimeType: 'image/png'),
      );
      await h.tap(find.bySemanticsLabel('Choose Image'));
      expect(callsOf(h, 'POST', '/uploads/menu-items/{menu_item_id}'), isEmpty);
      await h.enterText(fieldIn(surface, 'Name'), 'Rose Latte');
      await _pickCategory(h, 'Hot Coffee');
      await _save(h);
      final up = lastCall(h, 'POST', '/uploads/menu-items/{menu_item_id}');
      expect(up.files.single.field, 'image');
      expect(up.files.single.filename, 'rose.png');
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-080 Remove drops the staged picture', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      h.files.imageQueue.add(
        PickedFile(name: 'rose.png', bytes: _png, mimeType: 'image/png'),
      );
      await h.tap(find.bySemanticsLabel('Choose Image'));
      await h.tap(labelIn(surface, 'Remove'));
      await h.enterText(fieldIn(surface, 'Name'), 'Rose Latte');
      await _pickCategory(h, 'Hot Coffee');
      await _save(h);
      expect(callsOf(h, 'POST', '/uploads/menu-items/{menu_item_id}'), isEmpty);
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-083 the picker refuses non-images and big files', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      h.files.imageQueue.add(
        const PickedFile(
          name: 'menu.pdf',
          bytes: [1, 2, 3],
          mimeType: 'application/pdf',
        ),
      );
      await h.tap(find.bySemanticsLabel('Choose Image'));
      expect(
        inSurface(find.text('Selected file must be an image')),
        findsOneWidget,
      );
      h.files.imageQueue.add(
        PickedFile(
          name: 'huge.png',
          bytes: List.filled(5 * 1024 * 1024 + 1, 0),
          mimeType: 'image/png',
        ),
      );
      await h.tap(find.bySemanticsLabel('Choose Image'));
      expect(
        inSurface(find.text('Image size exceeds 5MB limit')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-ITEMS-084 one price: no size label anywhere', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      expect(inSurface(find.text('Price')), findsWidgets);
      expect(inSurface(find.text('Sizes')), findsNothing);
      expect(
        inSurface(
          find.text(
            'Add a size to charge different prices for different sizes.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        inSurface(find.byKey(const ValueKey('price-tax-hint'))),
        findsOneWidget,
      );
      expect(inSurface(find.text('one_size')), findsNothing);
      expect(h.t('recipes.oneSize'), isNotEmpty);
      expect(inSurface(find.text(h.t('recipes.oneSize'))), findsWidgets);
    });

    testWidgets('MENU-ITEMS-085 / 086 Add size: both sizes named, labels '
        'required, the last cannot go', (tester) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      await h.tap(inSurface(find.text('Add size')));
      expect(inSurface(find.text('Sizes')), findsOneWidget);
      final labels = fieldIn(surface, 'Label');
      expect(labels, findsNWidgets(2));
      expect(_text(tester, labels.first), '');
      await h.enterText(fieldIn(surface, 'Name'), 'Rose Latte');
      await _pickCategory(h, 'Hot Coffee');
      await _save(h);
      expect(inSurface(find.text('This field is required')), findsNWidgets(2));
      expect(callsOf(h, 'POST', '/menu-items'), isEmpty);
      await h.tap(labelIn(surface, 'Remove size').first);
      expect(fieldIn(surface, 'Label'), findsOneWidget);
      final remove = tester.widget<DashIconButton>(
        find
            .ancestor(
              of: labelIn(surface, 'Remove size'),
              matching: find.byType(DashIconButton),
            )
            .first,
      );
      expect(remove.onPressed, isNull);
      expect(
        inSurface(find.text('Sizes')),
        findsOneWidget,
        reason: 'one blank-labelled size is not the one-price mode',
      );
    });

    testWidgets(
      'MENU-ITEMS-086 / 091 two sizes: the from-price is the lowest',
      (tester) async {
        final h = await pumpItems(tester);
        await _openNew(h);
        await h.tap(inSurface(find.text('Add size')));
        await h.enterText(fieldIn(surface, 'Label').first, 'Regular');
        await h.enterText(fieldIn(surface, 'Price (EGP)').first, '120');
        await h.enterText(fieldIn(surface, 'Label').last, 'Large');
        await h.enterText(fieldIn(surface, 'Price (EGP)').last, '140');
        await h.enterText(fieldIn(surface, 'Name'), 'Rose Latte');
        await _pickCategory(h, 'Hot Coffee');
        await _save(h);
        expect(
          (lastCall(h, 'POST', '/menu-items').body! as Map)['base_price'],
          12000,
        );
        expect(lastCall(h, 'PUT', '/menu-items/{id}/sizes').body, {
          'sizes': [
            {'is_active': true, 'label': 'Regular', 'price': 12000, 'sort': 0},
            {'is_active': true, 'label': 'Large', 'price': 14000, 'sort': 1},
          ],
        });
        expect(
          callsOf(h, 'PUT', '/menu-item-sizes/{size_id}/recipe'),
          hasLength(2),
        );
        await h.flushTimers();
      },
    );

    testWidgets('MENU-ITEMS-088 / 091 recipe rows go to their size', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      expect(inSurface(find.text('Recipe')), findsOneWidget);
      expect(
        inSurface(find.text('What this item consumes, per size')),
        findsOneWidget,
      );
      expect(inSurface(find.text(h.t('recipes.newIngredient'))), findsNothing);
      await h.tap(inSurface(find.text(h.t('recipes.addIngredient'))).first);
      await h.tap(selectIn(surface, h.t('recipes.ingredient')).last);
      await h.enterText(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is DashOptionList),
          matching: find.byType(EditableText),
        ),
        'Sugar',
      );
      await pickOption(h, 'Sugar');
      await h.enterText(
        find.bySemanticsLabel(
          h.t(
            'modeling.grid.cellAria',
            args: {'ingredient': 'Sugar', 'size': h.t('recipes.oneSize')},
          ),
        ),
        '12',
      );
      await h.enterText(fieldIn(surface, 'Name'), 'Sweet Tea');
      await _pickCategory(h, 'Tea & More');
      await _save(h);
      expect(lastCall(h, 'PUT', '/menu-item-sizes/{size_id}/recipe').body, {
        'lines': [
          {
            'ingredient_id': MenuSeedIds.ingredient('sugar'),
            'quantity': 12.0,
            'unit': 'g',
          },
        ],
      });
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-089 / 090 the add-on picker: groups, select all, '
        'chips, search, attachments', (tester) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      await _openNew(h);
      expect(
        inSurface(find.text('Which addons customers can pick for this item')),
        findsOneWidget,
      );
      expect(
        inSurface(
          find.text('No addons selected — the full org catalog applies.'),
        ),
        findsOneWidget,
      );
      final milk = find.byKey(const ValueKey('addon-group-milk_type'));
      await h.scrollUntilVisible(
        milk,
        scrollable: find
            .descendant(of: surface, matching: find.byType(Scrollable))
            .first,
      );
      expect(
        find.descendant(
          of: milk,
          matching: find.textContaining(
            RegExp(r'^Milk +\(\D*6\D*\)$'),
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      await h.tap(find.descendant(of: milk, matching: find.text('Select all')));
      expect(
        find.descendant(of: milk, matching: find.text('Deselect all')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('addon-chip-${option('milk', 'oat')}')),
        findsOneWidget,
      );
      // A chip's × drops it again.
      await h.tap(
        find.descendant(
          of: find.byKey(ValueKey('addon-chip-${option('milk', 'skimmed')}')),
          matching: find.bySemanticsLabel('Remove'),
        ),
      );
      await h.tap(
        find.byKey(ValueKey('addon-pick-${option('extras', 'shot')}')),
      );
      await h.enterText(fieldIn(surface, 'Search addons…'), 'zzz');
      expect(inSurface(find.text('No addons match')), findsOneWidget);
      await h.enterText(fieldIn(surface, 'Search addons…'), '');
      await h.enterText(fieldIn(surface, 'Name'), 'Rose Latte');
      await _pickCategory(h, 'Hot Coffee');
      await _save(h);
      final milkIds = [
        for (final k in ['full', 'oat', 'almond', 'coconut', 'lactose_free'])
          option('milk', k),
      ];
      final body =
          lastCall(h, 'PUT', '/menu-items/{id}/modifier-groups').body! as Map;
      final groups = (body['groups']! as List).cast<Map>();
      expect(groups, hasLength(2));
      expect(groups[0]['group_id'], MenuSeedIds.group('milk'));
      expect(groups[0]['sort'], 0);
      expect(
        (groups[0]['included_option_ids'] as List).toSet(),
        milkIds.toSet(),
      );
      expect(groups[1]['group_id'], MenuSeedIds.group('extras'));
      expect(groups[1]['included_option_ids'], [option('extras', 'shot')]);
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-090 (divergence) in Arabic a type reads as its '
        "group's Arabic name", (tester) async {
      final h = await pumpItems(tester, locale: 'ar');
      await h.tap(inPage(find.text(h.t('menu.newItem'))));
      final milk = find.byKey(const ValueKey('addon-group-milk_type'));
      await h.scrollUntilVisible(
        milk,
        scrollable: find
            .descendant(of: surface, matching: find.byType(Scrollable))
            .first,
      );
      expect(
        find.descendant(
          of: milk,
          matching: find.textContaining('اللبن', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: milk,
          matching: find.textContaining('Milk', findRichText: true),
        ),
        findsNothing,
      );
    });

    testWidgets('MENU-ITEMS-090 (divergence) Arabic search finds the Arabic '
        'name the chips show, and still the raw one', (tester) async {
      final h = await pumpItems(tester, locale: 'ar');
      await h.tap(inPage(find.text(h.t('menu.newItem'))));
      final oat = find.byKey(ValueKey('addon-pick-${option('milk', 'oat')}'));
      final shot = find.byKey(
        ValueKey('addon-pick-${option('extras', 'shot')}'),
      );
      final search = fieldIn(surface, h.t('menu.searchAddons'));
      await h.enterText(search, 'الشوفان');
      expect(oat, findsOneWidget);
      expect(shot, findsNothing);
      expect(inSurface(find.text(h.t('menu.noAddonsMatch'))), findsNothing);
      await h.enterText(search, 'oat');
      expect(oat, findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-092 a failed step toasts its words and stays', (
      tester,
    ) async {
      final s = itemsServer();
      final bad = MockResponse.badRequest(
        "Duplicate size label 'Large' in request",
      );
      s.server.fail('PUT', '/menu-items/{id}/sizes', bad);
      final h = await pumpItems(tester, seeded: s);
      await _openNew(h);
      await h.enterText(fieldIn(surface, 'Name'), 'Rose Latte');
      await _pickCategory(h, 'Hot Coffee');
      await _save(h);
      await h.expectToast(h.refusalWords(bad));
      expect(inSurface(find.text('New item')), findsOneWidget);
      expect(
        callsOf(h, 'POST', '/menu-items'),
        hasLength(1),
        reason: 'earlier writes stand',
      );
    });

    testWidgets('MENU-ITEMS-092 a refused create (no menu.items.create)', (
      tester,
    ) async {
      final h = await pumpItems(tester, persona: Persona.manager);
      await _openNew(h);
      await h.enterText(fieldIn(surface, 'Name'), 'Rose Latte');
      await _pickCategory(h, 'Hot Coffee');
      await _save(h);
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.items.create')),
      );
      expect(inSurface(find.text('New item')), findsOneWidget);
    });

    testWidgets('MENU-AREA-013 Enter in the name submits', (tester) async {
      final h = await pumpItems(tester);
      await _openNew(h);
      await _pickCategory(h, 'Hot Coffee');
      await typeAndSubmit(h, fieldIn(surface, 'Name'), 'Rose Latte');
      expect(lastCall(h, 'POST', '/menu-items').body, isA<Map>());
      await h.flushTimers();
    });
  });

  group('edit', () {
    testWidgets('MENU-ITEMS-073 loads the full item: active sizes in pounds, '
        'recipe rows, offered add-ons', (tester) async {
      final h = await pumpItems(tester);
      await _openEdit(h, 'latte');
      expect(
        lastCall(h, 'GET', '/menu-items/{id}').path,
        '/menu-items/${item('latte')}',
      );
      expect(inSurface(find.text('Edit item')), findsOneWidget);
      expect(inSurface(find.text('Sizes')), findsOneWidget);
      expect(_text(tester, fieldIn(surface, 'Label').first), 'Regular');
      expect(_text(tester, fieldIn(surface, 'Price (EGP)').first), '115');
      expect(_text(tester, fieldIn(surface, 'Price (EGP)').last), '135');
      expect(
        find.bySemanticsLabel(
          h.t(
            'modeling.grid.cellAria',
            args: {'ingredient': 'Full cream milk', 'size': 'Regular'},
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('addon-chip-${option('milk', 'oat')}')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-ITEMS-073 (re-seed) opened on data older than 30 s: '
        'the fresh read shows; once edited, a refetch keeps the edit; Save '
        'sends the fresh values and the edit', (tester) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      final held = MenuItem.fromJson({
        ...s.db[MenuTables.menuItems].find(item('latte'))!,
      });
      await _openEdit(h, 'latte', stale: held);
      await h.tap(inSurface(find.text('Cancel')));
      // Changed elsewhere; the cached copy is now older than 30 s.
      s.db[MenuTables.menuItems].update(item('latte'), {
        'name': 'Caffè Latte Classico',
      });
      s.db[MenuTables.sizes].update(size('latte', 'Large'), {
        'price_override': 14000,
      });
      s.db.clock.advance(const Duration(seconds: 31));
      final gets = callsOf(h, 'GET', '/menu-items/{id}').length;
      await _openEdit(h, 'latte', stale: held);
      expect(callsOf(h, 'GET', '/menu-items/{id}'), hasLength(gets + 1));
      expect(_text(tester, fieldIn(surface, 'Name')), 'Caffè Latte Classico');
      expect(_text(tester, fieldIn(surface, 'Price (EGP)').last), '140');

      // The person edits; a refresh with newer data lands: the edit stays.
      await h.enterText(fieldIn(surface, 'Price (EGP)').first, '120');
      s.db[MenuTables.menuItems].update(item('latte'), {
        'name': 'Renamed elsewhere',
      });
      h.container.read(realtimeBusProvider).invalidate(const ['/menu-items']);
      await h.settle();
      expect(callsOf(h, 'GET', '/menu-items/{id}'), hasLength(gets + 2));
      expect(_text(tester, fieldIn(surface, 'Price (EGP)').first), '120');
      expect(_text(tester, fieldIn(surface, 'Name')), 'Caffè Latte Classico');

      await _save(h);
      expect(
        (lastCall(h, 'PATCH', '/menu-items/{id}').body! as Map)['name'],
        'Caffè Latte Classico',
      );
      expect(lastCall(h, 'PUT', '/menu-items/{id}/sizes').body, {
        'sizes': [
          {'is_active': true, 'label': 'Regular', 'price': 12000, 'sort': 0},
          {'is_active': true, 'label': 'Large', 'price': 14000, 'sort': 1},
        ],
      });
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-079 / 091 edit: patch with is_active, no '
        'base_price; recipes per size; groups untouched', (tester) async {
      final h = await pumpItems(tester);
      await _openEdit(h, 'latte');
      await h.tap(switchIn(surface, 'Active'));
      await _save(h);
      expect(lastCall(h, 'PATCH', '/menu-items/{id}').body, {
        'category_id': category('hot'),
        'description': null,
        'is_active': false,
        'name': 'Caffè Latte',
        'name_translations': {'ar': 'لاتيه'},
      });
      final recipes = callsOf(h, 'PUT', '/menu-item-sizes/{size_id}/recipe');
      expect(recipes.map((c) => c.path), [
        '/menu-item-sizes/${size('latte', 'Regular')}/recipe',
        '/menu-item-sizes/${size('latte', 'Large')}/recipe',
      ]);
      expect(recipes.first.body, {
        'lines': [
          {
            'ingredient_id': MenuSeedIds.ingredient('full_milk'),
            'quantity': 180.0,
            'unit': 'ml',
          },
        ],
      });
      expect(callsOf(h, 'PUT', '/menu-items/{id}/modifier-groups'), isEmpty);
      await h.expectToast('Changes saved');
    });

    testWidgets('MENU-ITEMS-091 an emptied selection detaches every group', (
      tester,
    ) async {
      final h = await pumpItems(tester);
      await _openEdit(h, 'cortado');
      final milk = find.byKey(const ValueKey('addon-group-milk_type'));
      await h.scrollUntilVisible(
        milk,
        scrollable: find
            .descendant(of: surface, matching: find.byType(Scrollable))
            .first,
      );
      await h.tap(
        find.descendant(of: milk, matching: find.text('Deselect all')),
      );
      for (final type in ['extra', 'coffee_type']) {
        final g = find.byKey(ValueKey('addon-group-$type'));
        await h.tap(
          find.descendant(of: g, matching: find.text('Deselect all')),
        );
      }
      await _save(h);
      expect(lastCall(h, 'PUT', '/menu-items/{id}/modifier-groups').body, {
        'groups': <Object?>[],
      });
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-091 (divergence) a changed selection waits for '
        'the groups read: no save, the words and Retry', (tester) async {
      final s = itemsServer();
      s.server.fail(
        'GET',
        '/modifier-groups',
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpItems(tester, seeded: s);
      await _openEdit(h, 'cortado');
      await h.tap(
        find.byKey(ValueKey('addon-pick-${option('extras', 'vanilla')}')),
      );
      final patches = callsOf(h, 'PATCH', '/menu-items/{id}').length;
      await _save(h);
      final words = find.byKey(const ValueKey('addon-groups-missing'));
      expect(
        find.descendant(
          of: words,
          matching: find.text(h.t('menu.addonGroupsNotReady')),
        ),
        findsOneWidget,
      );
      expect(callsOf(h, 'PATCH', '/menu-items/{id}'), hasLength(patches));
      expect(callsOf(h, 'PUT', '/menu-items/{id}/modifier-groups'), isEmpty);
      expect(inSurface(find.text('Edit item')), findsOneWidget);
      s.server.clearFailures();
      await h.tap(find.descendant(of: words, matching: find.text('Retry')));
      expect(words, findsNothing);
      await _save(h);
      final groups =
          (lastCall(h, 'PUT', '/menu-items/{id}/modifier-groups').body!
                  as Map)['groups']!
              as List;
      expect(groups, isNotEmpty);
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-081 a picked picture uploads now and is followed '
        'until processed', (tester) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      await _openEdit(h, 'cortado');
      expect(inSurface(find.text('PNG/JPG/WebP, up to 5 MB')), findsOneWidget);
      h.files.imageQueue.add(
        PickedFile(name: 'cortado.png', bytes: _png, mimeType: 'image/png'),
      );
      await h.tap(find.bySemanticsLabel('Choose Image'));
      expect(
        lastCall(h, 'POST', '/uploads/menu-items/{menu_item_id}').path,
        '/uploads/menu-items/${item('cortado')}',
      );
      expect(inSurface(find.text('Processing…')), findsOneWidget);
      expect(callsOf(h, 'GET', '/assets/jobs/{id}'), hasLength(1));
      final catalogReads = callsOf(h, 'GET', catalogPath).length;
      await tester.pump(assetPollEvery);
      await h.settle();
      expect(callsOf(h, 'GET', '/assets/jobs/{id}'), hasLength(2));
      expect(inSurface(find.text('Processing…')), findsNothing);
      expect(
        callsOf(h, 'GET', catalogPath).length,
        greaterThan(catalogReads),
        reason: 'the settled job refetches the catalog',
      );
      expect(
        s.db[MenuTables.menuItems].find(item('cortado'))!['image_url'],
        isNotNull,
      );
    });

    testWidgets('MENU-ITEMS-081 a failed job says so under the box', (
      tester,
    ) async {
      final s = itemsServer();
      final h = await pumpItems(tester, seeded: s);
      await _openEdit(h, 'cortado');
      h.files.imageQueue.add(
        PickedFile(name: 'cortado.png', bytes: _png, mimeType: 'image/png'),
      );
      await h.tap(find.bySemanticsLabel('Choose Image'));
      s.db[assetJobsTable].rows.single['fail'] = 'Unsupported image';
      await tester.pump(assetPollEvery);
      await h.settle();
      expect(inSurface(find.text('Unsupported image')), findsOneWidget);
      expect(inSurface(find.text('Processing…')), findsNothing);
    });

    testWidgets('MENU-ITEMS-082 Remove clears the picture at once', (
      tester,
    ) async {
      final s = itemsServer();
      s.db[MenuTables.menuItems].update(item('cortado'), {
        'image_url': 'https://cdn.madar.test/cortado.webp',
      });
      final h = await pumpItems(tester, seeded: s);
      await _openEdit(h, 'cortado');
      await h.tap(labelIn(surface, 'Remove'));
      final call = lastCall(h, 'PATCH', '/menu-items/{id}');
      expect(call.body, {'image_url': null});
      expect(
        s.db[MenuTables.menuItems].find(item('cortado'))!['image_url'],
        isNull,
      );
    });

    testWidgets('MENU-ITEMS-083 (divergence) a failed upload shows the '
        "server's words under the box", (tester) async {
      final s = itemsServer();
      final bad = MockResponse.badRequest('No image field found in upload');
      s.server.fail('POST', '/uploads/menu-items/{menu_item_id}', bad);
      final h = await pumpItems(tester, seeded: s);
      await _openEdit(h, 'cortado');
      h.files.imageQueue.add(
        PickedFile(name: 'cortado.png', bytes: _png, mimeType: 'image/png'),
      );
      await h.tap(find.bySemanticsLabel('Choose Image'));
      expect(inSurface(find.text(h.refusalWords(bad))), findsOneWidget);
    });

    testWidgets('MENU-ITEMS-087 (divergence) no sizes yet: Save says why', (
      tester,
    ) async {
      final s = itemsServer();
      s.server.fail(
        'GET',
        '/menu-items/{id}',
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpItems(tester, seeded: s);
      await _openEdit(h, 'latte');
      expect(inSurface(find.text('Sizes')), findsOneWidget);
      expect(fieldIn(surface, 'Label'), findsNothing);
      await _save(h);
      expect(
        inSurface(find.text('An item needs at least one price.')),
        findsOneWidget,
      );
      expect(callsOf(h, 'PATCH', '/menu-items/{id}'), isEmpty);
    });

    testWidgets('MENU-ITEMS-112 a renamed size keeps its rows under the old '
        'label; the new label saves its own (empty) section', (tester) async {
      final h = await pumpItems(tester);
      await _openEdit(h, 'latte');
      await h.enterText(fieldIn(surface, 'Label').first, 'Small');
      expect(
        find.bySemanticsLabel(
          h.t(
            'modeling.grid.cellAria',
            args: {'ingredient': 'Full cream milk', 'size': 'Regular'},
          ),
        ),
        findsOneWidget,
      );
      await _save(h);
      final small = h.db![MenuTables.sizes].firstWhere(
        (r) => r['menu_item_id'] == item('latte') && r['label'] == 'Small',
      )!;
      final call = callsOf(
        h,
        'PUT',
        '/menu-item-sizes/{size_id}/recipe',
      ).firstWhere((c) => c.path == '/menu-item-sizes/${small['id']}/recipe');
      expect(call.body, {'lines': <Object?>[]});
      await h.flushTimers();
    });
  });

  testWidgets('MENU-AREA-014 until the ingredient catalog lands, rows read '
      'their saved name and fill in after', (tester) async {
    final st = itemsServer();
    final gate = st.server.hold('GET', '/inventory/orgs/{org_id}/catalog');
    final h = await pumpItems(tester, seeded: st);
    await _openEdit(h, 'latte');
    expect(
      find.bySemanticsLabel(
        h.t(
          'modeling.grid.cellAria',
          args: {'ingredient': 'Full cream milk', 'size': 'Regular'},
        ),
      ),
      findsOneWidget,
    );
    gate.release();
    await h.settle();
    expect(inSurface(find.textContaining('Full cream milk')), findsWidgets);
  });
}
