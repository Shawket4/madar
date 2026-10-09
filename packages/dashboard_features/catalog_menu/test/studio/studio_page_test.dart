// `/menu/items/:itemId`, the Menu Studio's shell, load, header, deep links,
// dirty store, save bar and the batched save (MENU-STUDIO-001..022), driven
// through the real app shell on the seeded mock. Caffè Latte (seed): sizes
// Regular EGP 115 / Large EGP 135, own full cream milk 180 / 240 ml, the
// Espresso shot base, the hot cup rules, the Milk and Extras groups, three
// library steps.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/studio/studio_widgets.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _latte = item('latte');

void main() {
  group('MENU-STUDIO-001..008 load, header, sections', () {
    testWidgets('MENU-STUDIO-001 reads the item aggregate once', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final calls = h.server.callsTo(studioT, method: 'GET');
      expect(calls, hasLength(1));
      expect(calls.single.path, '/menu-items/$_latte/studio');
      expect(studioText('Caffè Latte'), findsWidgets);
    });

    testWidgets('MENU-STUDIO-002 loading: title skeleton and three blocks', (
      tester,
    ) async {
      final s = studioServer();
      final gate = s.server.hold('GET', studioT);
      final h = await pumpStudio(tester, seeded: s);
      expect(
        inStudio(find.byKey(const ValueKey('studio-title-skeleton'))),
        findsOneWidget,
      );
      expect(inStudio(find.byType(StudioLoadingSkeleton)), findsOneWidget);
      expect(studioLabel('Back'), findsOneWidget);
      gate.release();
      await h.settle();
      expect(inStudio(find.byType(StudioLoadingSkeleton)), findsNothing);
      expect(studioText(h.t('menu.studio.basics.title')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-003 error: "Menu item", the reason, Retry', (
      tester,
    ) async {
      final s = studioServer();
      s.server.fail(
        'GET',
        studioT,
        MockResponse.notFound('Menu item not found'),
        times: null,
      );
      final h = await pumpStudio(tester, seeded: s);
      expect(studioText('Menu item'), findsOneWidget);
      expect(studioText('Could not load this item'), findsOneWidget);
      expect(
        studioText(h.refusalWords(MockResponse.notFound('Menu item not found'))),
        findsOneWidget,
      );
      s.server.clearFailures();
      await h.tap(studioText(h.t('common.retry')));
      expect(h.server.callsTo(studioT), hasLength(2));
      expect(studioText(h.t('menu.studio.basics.title')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-004 header: title, Inactive pill, Back keeps '
        'the search params', (tester) async {
      final s = studioServer();
      s.db[MenuTables.menuItems].update(_latte, {'is_active': false});
      final h = await pumpStudio(
        tester,
        path: studioPath('latte', tab: 'steps'),
        seeded: s,
      );
      expect(studioText('Caffè Latte'), findsWidgets);
      expect(studioText(h.t('common.inactive')), findsOneWidget);
      await h.tap(studioLabel('Back'));
      expect(h.location.path, '/menu/items');
      expect(h.location.queryParameters, {'tab': 'steps'});
    });

    testWidgets('MENU-STUDIO-004 an active item has no pill; Arabic name', (
      tester,
    ) async {
      final h = await pumpStudio(tester, locale: 'ar');
      expect(studioText('لاتيه'), findsWidgets);
      expect(studioText(h.t('common.inactive')), findsNothing);
    });

    testWidgets('MENU-STUDIO-004 a blank name reads "Untitled item"', (
      tester,
    ) async {
      final s = studioServer();
      s.db[MenuTables.menuItems].update(_latte, {
        'name': '',
        'name_translations': const <String, Object?>{},
      });
      final h = await pumpStudio(tester, seeded: s);
      expect(studioText(h.t('menu.studio.untitled')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-005 "Branch & channel pricing" opens /menu/pricing', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.studio.pricingLink')));
      expect(h.location.path, '/menu/pricing');
    });

    testWidgets('MENU-STUDIO-006 Duplicate: confirm, copy, toast, its studio', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.grid.duplicate')));
      expect(find.text(h.t('menu.studio.duplicateTitle')), findsOneWidget);
      expect(find.text(h.t('menu.studio.duplicateDesc')), findsOneWidget);
      // The confirm button says "Duplicate" (the header's is behind it).
      await h.tap(find.text(h.t('menu.grid.duplicate')).last);
      final call = lastCall(h, 'POST', dupT);
      expect(call.path, '/menu-items/$_latte/duplicate');
      await h.expectToast(h.t('menu.studio.duplicated'));
      final copy = h.db![MenuTables.menuItems].firstWhere(
        (r) => r['name'] == 'Caffè Latte (Copy)',
      )!;
      expect(h.location.path, '/menu/items/${copy['id']}');
      expect(studioText('Caffè Latte (Copy)'), findsWidgets);
      // Not deactivated here (the grid's duplicate does).
      expect(copy['is_active'], isTrue);
    });

    testWidgets('MENU-STUDIO-006 Duplicate cancelled sends nothing', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.grid.duplicate')));
      await h.tap(find.text(h.t('common.cancel')).last);
      expect(h.server.callsTo(dupT), isEmpty);
      expect(h.location.path, '/menu/items/$_latte');
    });

    testWidgets('MENU-STUDIO-006 a refused duplicate toasts the server', (
      tester,
    ) async {
      final s = studioServer();
      final refusal = MockResponse.denied('menu.items.edit');
      s.server.fail('POST', dupT, refusal);
      final h = await pumpStudio(tester, seeded: s);
      await h.tap(studioText(h.t('menu.grid.duplicate')));
      await h.tap(find.text(h.t('menu.grid.duplicate')).last);
      await h.expectToast(h.refusalWords(refusal));
      expect(h.location.path, '/menu/items/$_latte');
    });

    for (final (tab, title) in [
      ('basics', 'Item details'),
      ('sizes', 'Sizes, price & recipe'),
      ('recipe', 'Sizes, price & recipe'),
      ('steps', "How it's made"),
      ('modifiers', 'Modifiers'),
      ('options', 'Options'),
    ]) {
      testWidgets('MENU-STUDIO-007 ?tab=$tab scrolls to "$title"', (
        tester,
      ) async {
        final h = await pumpStudio(
          tester,
          key: 'spanish',
          path: studioPath('spanish', tab: tab),
          size: DashSize.phone,
        );
        await h.settle();
        final top = tester.getTopLeft(studioText(title).first).dy;
        // The heading sits at the top of the viewport (under the app bar).
        expect(top, lessThan(200), reason: tab);
        if (tab != 'basics') {
          final scroll = inStudio(find.byType(Scrollable)).first;
          expect(
            tester.state<ScrollableState>(scroll).position.pixels,
            greaterThan(0),
          );
        }
      });
    }

    testWidgets('MENU-STUDIO-007 ?tab=availability stays at the top', (
      tester,
    ) async {
      final h = await pumpStudio(
        tester,
        path: studioPath('latte', tab: 'availability'),
        size: DashSize.phone,
      );
      await h.settle();
      final scroll = inStudio(find.byType(Scrollable)).first;
      expect(tester.state<ScrollableState>(scroll).position.pixels, 0);
    });

    testWidgets('MENU-STUDIO-008 sections in order with their descriptions', (
      tester,
    ) async {
      final s = studioServer();
      seedBreakfastCombo(s.db);
      final h = await pumpStudio(tester, seeded: s);
      final titles = [
        'menu.studio.basics.title',
        'menu.studio.sections.sizesTitle',
        'menu.studio.sections.stepsTitle',
        'menu.studio.tabs.modifiers',
        'menu.studio.tabs.options',
        'combos.meal.title',
        'modeling.preview.title',
      ];
      final ys = [
        for (final k in titles)
          tester.getTopLeft(find.descendant(
            of: find.byType(StudioSection),
            matching: find.text(h.t(k)),
          ).first).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      for (final k in [
        'menu.studio.basics.desc',
        'menu.studio.sections.sizesDesc',
        'menu.studio.sections.stepsDesc',
        'menu.studio.modifiers.desc',
        'menu.studio.options.desc',
        'combos.meal.desc',
        'modeling.preview.desc',
      ]) {
        expect(studioText(h.t(k)), findsOneWidget, reason: k);
      }
      expect(inStudio(find.byType(StudioSection)), findsNWidgets(7));
    });

    testWidgets('MENU-STUDIO-008/099 refusal: no preview without '
        'menu.items.read', (tester) async {
      final s = studioServer(persona: Persona.manager);
      overrideCaps(s.server, Persona.manager, remove: ['menu.items.read']);
      final h = await pumpStudio(tester, persona: Persona.manager, seeded: s);
      expect(studioText(h.t('modeling.preview.title')), findsNothing);
      expect(h.server.callsTo(previewT), isEmpty);
      expect(inStudio(find.byType(StudioSection)), findsNWidgets(6));
    });
  });

  group('MENU-STUDIO-009..013 the dirty store', () {
    testWidgets('MENU-STUDIO-009 an edited section shows "Unsaved"', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final unsaved = h.t('menu.studio.unsaved');
      expect(studioText(unsaved), findsNothing);
      await h.enterText(fieldWithText('Caffè Latte'), 'Caffè Latte Deluxe');
      expect(
        inSection(h.t('menu.studio.basics.title'), find.text(unsaved)),
        findsOneWidget,
      );
      expect(studioText(unsaved), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-010 the bar counts dirty SECTIONS', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(saveBar, findsNothing);
      await h.enterText(fieldWithText('Caffè Latte'), 'Latte');
      expect(inSaveBar(h.t('menu.studio.unsavedN', count: 1)), findsOneWidget);
      await h.enterText(fieldWithText('Latte'), 'Latte 2');
      expect(inSaveBar(h.t('menu.studio.unsavedN', count: 1)), findsOneWidget);
      await h.enterText(fieldWithText('115'), '120');
      expect(inSaveBar(h.t('menu.studio.unsavedN', count: 2)), findsOneWidget);
      expect(inSaveBar(h.t('menu.studio.discard')), findsOneWidget);
      expect(inSaveBar(h.t('common.save')), findsOneWidget);
      await h.shot('studio/save-bar');
    });

    testWidgets('MENU-STUDIO-010 Save and Discard are disabled while saving', (
      tester,
    ) async {
      final s = studioServer();
      final gate = s.server.hold('PATCH', itemT);
      final h = await pumpStudio(tester, seeded: s);
      await h.enterText(fieldWithText('Caffè Latte'), 'Latte');
      await h.tap(inSaveBar(h.t('common.save')));
      final discard = tester.widget<DashButton>(
        find.ancestor(
          of: inSaveBar(h.t('menu.studio.discard')),
          matching: find.byType(DashButton),
        ),
      );
      expect(discard.onPressed, isNull);
      final save = tester.widget<DashButton>(
        find.ancestor(
          of: inSaveBar(h.t('common.save')),
          matching: find.byType(DashButton),
        ),
      );
      expect(save.loading || save.onPressed == null, isTrue);
      gate.release();
      await h.settle();
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-011 Discard re-seeds every section', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('Caffè Latte'), 'Latte');
      await h.enterText(fieldWithText('115'), '99');
      await h.tap(inSaveBar(h.t('menu.studio.discard')));
      expect(saveBar, findsNothing);
      expect(fieldWithText('Caffè Latte'), findsOneWidget);
      expect(fieldWithText('115'), findsOneWidget);
      expect(h.server.callsTo(itemT, method: 'PATCH'), isEmpty);
    });

    testWidgets('MENU-STUDIO-012 a refetch re-seeds only clean sections', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('Caffè Latte'), 'Latte (draft)');
      // Elsewhere, the price changes on the server; then a refetch lands.
      final regular = h.db![MenuTables.sizes].find(
        MenuSeedIds.size('latte', 'Regular'),
      )!;
      regular['price_override'] = 12000;
      h.container.read(realtimeBusProvider).invalidate(const ['/menu-items']);
      await h.settle();
      expect(h.server.callsTo(studioT), hasLength(2));
      expect(fieldWithText('Latte (draft)'), findsOneWidget);
      expect(fieldWithText('120'), findsOneWidget);
      expect(inSaveBar(h.t('menu.studio.unsavedN', count: 1)), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-012 opening another item (a linked copy) with '
        'drafts pending replaces every draft', (tester) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final h = await pumpStudio(tester, key: 'spanish', seeded: s);
      await h.enterText(fieldWithText('Spanish Latte'), 'Spanish (draft)');
      await h.tap(studioText(h.t('menu.studio.steps.addCustom')));
      await h.tap(studioText(h.t('menu.studio.options.add')));
      expect(inSaveBar(h.t('menu.studio.unsavedN', count: 3)), findsOneWidget);

      await h.tap(studioText('Iced Spanish Latte'));
      expect(h.location.path, '/menu/items/${item('iced_spanish')}');
      expect(saveBar, findsNothing);
      expect(fieldWithText('Iced Spanish Latte'), findsOneWidget);
      expect(fieldWithText('Spanish (draft)'), findsNothing);
      expect(find.byKey(const ValueKey('studio-option-0')), findsNothing);
      expect(
        studioText(h.t('menu.studio.unsaved')),
        findsNothing,
        reason: 'no section is dirty',
      );
    });

    testWidgets('MENU-STUDIO-013 no in-app guard: Back leaves with edits', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('Caffè Latte'), 'Latte');
      await h.tap(studioLabel('Back'));
      expect(h.location.path, '/menu/items');
      expect(find.byType(DashConfirmDialog), findsNothing);
    });
  });

  group('MENU-STUDIO-014 validation', () {
    Future<void> expectRefused(DashHarness h, String words) async {
      await tapSave(h);
      await h.expectToast(words);
      for (final (m, tpl) in [
        ('PATCH', itemT),
        ('PUT', sizesT),
        ('PUT', stepsT),
        ('PUT', groupsT),
        ('PUT', optionsT),
      ]) {
        expect(h.server.callsTo(tpl, method: m), isEmpty, reason: tpl);
      }
    }

    testWidgets('MENU-STUDIO-014 a blank name', (tester) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('Caffè Latte'), '   ');
      await expectRefused(h, 'Item name is required');
    });

    testWidgets('MENU-STUDIO-014 a size with no label', (tester) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('Regular'), '');
      await expectRefused(h, 'Every size needs a label');
    });

    testWidgets('MENU-STUDIO-014 a repeated size label', (tester) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('Large'), 'Regular ');
      await expectRefused(
        h,
        h.t('menu.studio.validate.sizeLabelDup', args: {'label': 'Regular'}),
      );
    });

    testWidgets('MENU-STUDIO-014 a size price that is not a number', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('135'), '');
      await expectRefused(
        h,
        h.t('menu.studio.validate.priceFor', args: {'name': 'Large'}),
      );
    });

    testWidgets('MENU-STUDIO-014 a written step with no name', (tester) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.studio.steps.addCustom')));
      await expectRefused(h, 'Every written step needs a name');
    });

    testWidgets('MENU-STUDIO-014 an option with no name, then a bad price', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.studio.options.add')));
      await expectRefused(h, 'Every option needs a name');
      await h.enterText(
        studioLabel(h.t('common.name')).last,
        'Extra foam',
      );
      await h.enterText(studioLabel('${h.t('common.price')} (EGP)').last, '');
      await expectRefused(
        h,
        h.t('menu.studio.validate.priceFor', args: {'name': 'Extra foam'}),
      );
    });
  });

  group('MENU-STUDIO-015..022 the batched save', () {
    testWidgets('MENU-STUDIO-015 item details: the PATCH body', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('Caffè Latte'), 'Latte');
      await h.enterText(fieldWithText('لاتيه'), '');
      await tapSave(h);
      final body = lastBody(h, 'PATCH', itemT);
      expect(body, {
        'name': 'Latte',
        'name_translations': <String, Object?>{},
        'description': null,
        'description_translations': <String, Object?>{},
        'category_id': MenuSeedIds.category('hot'),
        'is_active': true,
      });
      expect(lastCall(h, 'PATCH', itemT).path, '/menu-items/$_latte');
      await h.expectToast(h.t('common.savedChanges'));
      // Only the item section was dirty.
      expect(h.server.callsTo(sizesT), isEmpty);
      expect(h.server.callsTo(stepsT, method: 'PUT'), isEmpty);
      expect(h.server.callsTo(groupsT), isEmpty);
      expect(h.server.callsTo(optionsT), isEmpty);
    });

    testWidgets('MENU-STUDIO-015 a description and an Arabic one', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final descs = inStudio(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.maxLines != 1,
        ),
      );
      await h.enterText(descs.at(0), 'Smooth and milky');
      await h.enterText(descs.at(1), 'ناعم وكريمي');
      await tapSave(h);
      final body = lastBody(h, 'PATCH', itemT);
      expect(body['description'], 'Smooth and milky');
      expect(body['description_translations'], {'ar': 'ناعم وكريمي'});
      expect(body['name_translations'], {'ar': 'لاتيه'});
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-015 a staged image uploads after the PATCH', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      h.files.imageQueue.add(
        PickedFile(name: 'latte.png', bytes: _png, mimeType: 'image/png'),
      );
      await h.tap(studioLabel(h.t('uploader.choose')));
      expect(h.server.callsTo(uploadT), isEmpty);
      expect(
        inSection(
          h.t('menu.studio.basics.title'),
          find.text(h.t('menu.studio.unsaved')),
        ),
        findsOneWidget,
      );
      await tapSave(h);
      // Only the image changed: no PATCH, just the upload.
      expect(h.server.callsTo(itemT, method: 'PATCH'), isEmpty);
      final up = lastCall(h, 'POST', uploadT);
      expect(up.path, '/uploads/menu-items/$_latte');
      expect(up.files.single.field, 'image');
      expect(up.files.single.filename, 'latte.png');
      await h.expectToast(h.t('common.savedChanges'));
      expect(saveBar, findsNothing);
    });

    testWidgets('MENU-STUDIO-015 a removed image sends image_url: null', (
      tester,
    ) async {
      final s = studioServer();
      s.db[MenuTables.menuItems].update(_latte, {
        'image_url': 'https://cdn.sabah.test/latte.webp',
      });
      final h = await pumpStudio(tester, seeded: s);
      await h.tap(studioLabel(h.t('uploader.remove')));
      await tapSave(h);
      final body = lastBody(h, 'PATCH', itemT);
      expect(body.containsKey('image_url'), isTrue);
      expect(body['image_url'], isNull);
      await h.flushTimers();
      expect(s.db[MenuTables.menuItems].find(_latte)!['image_url'], isNull);
    });

    testWidgets('MENU-STUDIO-016 sizes: the replace-set in column order', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('135'), '137.5');
      await tapSave(h);
      expect(lastBody(h, 'PUT', sizesT), {
        'sizes': [
          {'is_active': true, 'label': 'Regular', 'price': 11500, 'sort': 0},
          {'is_active': true, 'label': 'Large', 'price': 13750, 'sort': 1},
        ],
      });
      // A price change alone writes no recipe.
      expect(h.server.callsTo(recipeT), isEmpty);
      await h.expectToast(h.t('common.savedChanges'));
      expect(fieldWithText('137.5'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-016/017 a new size: sizes then its recipe', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('modeling.grid.addSize')));
      final labels = studioLabel(h.t('menu.sizeLabel'));
      await h.enterText(labels.last, 'Double');
      await h.enterText(
        studioLabel(h.t('modeling.grid.priceAria', args: {'size': 'Double'})),
        '150',
      );
      await h.enterText(
        studioLabel(
          h.t(
            'modeling.grid.cellAria',
            args: {'ingredient': 'Full cream milk', 'size': 'Double'},
          ),
        ),
        '300',
      );
      await tapSave(h);
      final sizes = (lastBody(h, 'PUT', sizesT)['sizes']! as List);
      expect(sizes.last, {
        'is_active': true,
        'label': 'Double',
        'price': 15000,
        'sort': 2,
      });
      final recipe = h.server.callsTo(recipeT);
      expect(recipe, hasLength(1));
      final newId = h.db![MenuTables.sizes].firstWhere(
        (z) => z['menu_item_id'] == _latte && z['label'] == 'Double',
      )!['id'];
      expect(recipe.single.path, '/menu-item-sizes/$newId/recipe');
      expect(recipe.single.body, {
        'lines': [
          {
            'ingredient_id': MenuSeedIds.ingredient('full_milk'),
            'quantity': 300.0,
            'unit': 'ml',
          },
        ],
      });
      await h.expectToast(h.t('common.savedChanges'));
    });

    testWidgets('MENU-STUDIO-017 only the changed size, only own lines', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.enterText(
        studioLabel(
          h.t(
            'modeling.grid.cellAria',
            args: {'ingredient': 'Full cream milk', 'size': 'Large'},
          ),
        ),
        '250',
      );
      await tapSave(h);
      final recipe = h.server.callsTo(recipeT);
      expect(recipe, hasLength(1));
      expect(
        recipe.single.path,
        '/menu-item-sizes/${MenuSeedIds.size('latte', 'Large')}/recipe',
      );
      expect(recipe.single.body, {
        'lines': [
          {
            'ingredient_id': MenuSeedIds.ingredient('full_milk'),
            'quantity': 250.0,
            'unit': 'ml',
          },
        ],
      });
      // Sizes always run first: the ids come from its answer.
      expect(h.server.callsTo(sizesT), hasLength(1));
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-017 a linked copy writes sizes, never a recipe', (
      tester,
    ) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final h = await pumpStudio(tester, key: 'iced_spanish', seeded: s);
      await h.enterText(fieldWithText('145'), '146');
      await tapSave(h);
      expect(h.server.callsTo(sizesT), hasLength(1));
      expect(h.server.callsTo(recipeT), isEmpty);
      await h.expectToast(h.t('common.savedChanges'));
    });

    testWidgets('MENU-STUDIO-018 steps: preset and written payloads', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'spanish');
      await h.enterText(
        fieldWithText('Stir in the condensed milk'),
        '  Stir the milk  ',
      );
      await tapSave(h);
      final body = lastBody(h, 'PUT', stepsT);
      expect(lastCall(h, 'PUT', stepsT).path, '/recipes/steps/${item('spanish')}');
      final steps = (body['steps']! as List).cast<Map<String, Object?>>();
      expect(steps, hasLength(4));
      expect(steps[0], {
        'kind': 'preset',
        'preset_slug': 'pull-espresso',
        // The library's note comes back as the step's (the server's read).
        'note': '18 g in, 36 g out in 25 to 30 seconds',
        'note_ar': '18 جم بن تعطي 36 جم في 25 إلى 30 ثانية',
      });
      expect(steps[1], {
        'kind': 'custom',
        'title': 'Stir the milk',
        'title_ar': 'قلّب الحليب المكثّف',
        'note': null,
        'note_ar': null,
      });
      await h.expectToast(h.t('common.savedChanges'));
    });

    testWidgets('MENU-STUDIO-018 refusal: without recipes.edit steps are '
        'skipped by the save', (tester) async {
      final s = studioServer();
      overrideCaps(s.server, Persona.owner, remove: ['recipes.edit']);
      final h = await pumpStudio(tester, seeded: s);
      await h.enterText(fieldWithText('Caffè Latte'), 'Latte');
      await tapSave(h);
      expect(h.server.callsTo(stepsT, method: 'PUT'), isEmpty);
      expect(h.server.callsTo(itemT, method: 'PATCH'), hasLength(1));
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-019 detaching every group sends groups: []', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final detach = studioLabel(h.t('menu.studio.modifiers.detach'));
      while (detach.evaluate().isNotEmpty) {
        await h.tap(detach.first);
      }
      await tapSave(h);
      expect(lastBody(h, 'PUT', groupsT), {'groups': <Object?>[]});
      expect(h.server.callsTo(itemT, method: 'PATCH'), isEmpty);
      expect(h.server.callsTo(sizesT), isEmpty);
      await h.expectToast(h.t('common.savedChanges'));
      expect(
        studioText(h.t('menu.studio.modifiers.empty')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-019 the set in order with the overrides', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final milk = MenuSeedIds.group('milk');
      final oat = MenuSeedIds.option('milk', 'oat');
      await h.tap(find.byKey(ValueKey('chip-$milk-$oat')));
      await h.tap(
        find.descendant(
          of: find.byKey(ValueKey('studio-group-$milk')),
          matching: find.bySemanticsLabel(h.t('menu.studio.modifiers.required')),
        ),
      );
      await tapSave(h);
      final groups = (lastBody(h, 'PUT', groupsT)['groups']! as List)
          .cast<Map<String, Object?>>();
      final m = groups.firstWhere((g) => g['group_id'] == milk);
      expect(m['sort'], 0);
      expect(m['is_required_override'], isTrue);
      expect(m['min_override'], isA<int>());
      expect(m.containsKey('max_override'), isTrue);
      expect((m['included_option_ids']! as List), isNot(contains(oat)));
      for (final g in groups.where((g) => g['group_id'] != milk)) {
        expect(g.containsKey('included_option_ids'), isTrue);
        expect(g['included_option_ids'], isNull);
      }
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-020 options: the replace-set', (tester) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('menu.studio.options.add')));
      await h.enterText(studioLabel(h.t('common.name')).last, ' Extra foam ');
      await h.enterText(
        studioLabel('${h.t('common.price')} (EGP)').last,
        '5.5',
      );
      await tapSave(h);
      expect(lastBody(h, 'PUT', optionsT), {
        'options': [
          {
            'is_active': true,
            'name': 'Extra foam',
            'price': 550,
            'recipe': <Object?>[],
          },
        ],
      });
      await h.expectToast(h.t('common.savedChanges'));
      // Saved: the row now carries its id and the section is clean.
      expect(saveBar, findsNothing);
      expect(fieldWithText('Extra foam'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-021 success: one toast, a refetch, a clean page', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.enterText(fieldWithText('Caffè Latte'), 'Latte');
      await h.enterText(fieldWithText('115'), '118');
      await tapSave(h);
      expect(h.server.callsTo(studioT), hasLength(2));
      expect(find.text(h.t('common.savedChanges')), findsOneWidget);
      await h.flushTimers();
      expect(saveBar, findsNothing);
      expect(studioText(h.t('menu.studio.unsaved')), findsNothing);
      expect(fieldWithText('Latte'), findsOneWidget);
      expect(fieldWithText('118'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-022 a failing step stops the save; a retry '
        're-runs only what is still dirty', (tester) async {
      final s = studioServer();
      final refusal = MockResponse.badRequest(
        "Duplicate size label 'Large' in request",
      );
      s.server.fail('PUT', sizesT, refusal);
      final h = await pumpStudio(tester, seeded: s);
      await h.enterText(fieldWithText('Caffè Latte'), 'Latte');
      await h.enterText(fieldWithText('115'), '118');
      await h.tap(studioText(h.t('menu.studio.steps.addCustom')));
      await h.enterText(
        studioLabel(h.t('menu.studio.steps.titleEn')),
        'Dust with cocoa',
      );
      await tapSave(h);
      await h.expectToast(
        h.t(
          'menu.studio.saveFailedIn',
          args: {
            'section': h.t('menu.studio.sections.sizesTitle'),
            'error': h.refusalWords(refusal),
          },
        ),
      );
      expect(h.server.callsTo(itemT, method: 'PATCH'), hasLength(1));
      expect(h.server.callsTo(stepsT, method: 'PUT'), isEmpty);
      // Item details saved; sizes and steps still dirty.
      expect(
        inSection(
          h.t('menu.studio.basics.title'),
          find.text(h.t('menu.studio.unsaved')),
        ),
        findsNothing,
      );
      expect(inSaveBar(h.t('menu.studio.unsavedN', count: 2)), findsOneWidget);
      await tapSave(h);
      expect(h.server.callsTo(itemT, method: 'PATCH'), hasLength(1));
      expect(h.server.callsTo(sizesT), hasLength(2));
      expect(h.server.callsTo(stepsT, method: 'PUT'), hasLength(1));
      await h.expectToast(h.t('common.savedChanges'));
    });

    testWidgets('MENU-STUDIO-022 each section names itself in the toast', (
      tester,
    ) async {
      final s = studioServer();
      for (final (m, tpl) in [
        ('PATCH', itemT),
        ('PUT', recipeT),
        ('PUT', stepsT),
        ('PUT', groupsT),
        ('PUT', optionsT),
      ]) {
        s.server.fail(m, tpl, MockResponse.error(500, 'boom'));
      }
      final h = await pumpStudio(tester, seeded: s);
      Future<void> failsAs(String section) async {
        await tapSave(h);
        await h.expectToast(
          h.t(
            'menu.studio.saveFailedIn',
            args: {
              'section': section,
              'error': h.refusalWords(MockResponse.error(500, 'boom')),
            },
          ),
        );
      }

      await h.enterText(fieldWithText('Caffè Latte'), 'Latte');
      await failsAs(h.t('menu.studio.basics.title'));
      await h.tap(inSaveBar(h.t('menu.studio.discard')));
      await h.enterText(
        studioLabel(
          h.t(
            'modeling.grid.cellAria',
            args: {'ingredient': 'Full cream milk', 'size': 'Regular'},
          ),
        ),
        '170',
      );
      await failsAs(
        h.t('menu.studio.sectionRecipeFor', args: {'label': 'Regular'}),
      );
      await h.tap(inSaveBar(h.t('menu.studio.discard')));
      await h.tap(studioText(h.t('menu.studio.steps.addCustom')));
      await h.enterText(studioLabel(h.t('menu.studio.steps.titleEn')), 'Stir');
      await failsAs(h.t('menu.studio.sectionSteps'));
      await h.tap(inSaveBar(h.t('menu.studio.discard')));
      await h.tap(studioLabel(h.t('menu.studio.modifiers.detach')).first);
      await failsAs(h.t('menu.studio.tabs.modifiers'));
      await h.tap(inSaveBar(h.t('menu.studio.discard')));
      await h.tap(studioText(h.t('menu.studio.options.add')));
      await h.enterText(studioLabel(h.t('common.name')).last, 'Foam');
      await failsAs(h.t('menu.studio.tabs.options'));
    });
  });
}

/// A 1×1 PNG.
const List<int> _png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];
