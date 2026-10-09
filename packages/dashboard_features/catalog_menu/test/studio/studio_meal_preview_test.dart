// The studio's "Make it a meal" and Preview sections (MENU-STUDIO-090..111,
// 113). The meal tests seed a "Breakfast Combo" (EGP 150): a Hot drink slot
// taking the Hot coffee category (Regular included, Large +EGP 15) and a
// Pastry slot (Butter Croissant by default). Latte alone at Regular is EGP
// 115, so the till offers "Make it a meal +EGP 35.00".
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _latte = item('latte');

/// The open list's option [name] (not the search box).
Finder option(String name) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.byWidgetPredicate((w) => w is Text && w.data == name),
);

/// A preview chip whose words are [label].
Finder chip(String label) =>
    inStudio(find.widgetWithText(DashChoiceChip, label));

bool selected(WidgetTester t, String label) =>
    t.widget<DashChoiceChip>(chip(label)).selected;

/// The meal section's select labelled [label] (its trigger).
Finder mealSelect(DashHarness h, String label) => find.descendant(
  of: inSection(h.t('combos.meal.title'), find.byType(DashFormField<String?>)),
  matching: find.byType(DashSelectTrigger),
);

Future<void> openCombo(DashHarness h) async {
  final triggers = inSection(
    h.t('combos.meal.title'),
    find.byType(DashSelectTrigger),
  );
  await h.tap(triggers.first);
}

Future<void> openSlot(DashHarness h) async {
  final triggers = inSection(
    h.t('combos.meal.title'),
    find.byType(DashSelectTrigger),
  );
  await h.tap(triggers.last);
}

Map<String, Object?> lastPreview(DashHarness h) => lastBody(h, 'POST', previewT);

void main() {
  group('MENU-STUDIO-090..098 make it a meal', () {
    testWidgets('MENU-STUDIO-090 reads: the item, the combos, the menu', (
      tester,
    ) async {
      final s = studioServer();
      seedBreakfastCombo(s.db);
      final h = await pumpStudio(tester, seeded: s);
      expect(lastCall(h, 'GET', itemT).path, '/menu-items/$_latte');
      expect(lastCall(h, 'GET', combosT).query, {
        'per_page': ['200'],
      });
      expect(
        h.server
            .callsTo(itemsT, method: 'GET')
            .where((c) => c.query['full']?.single == 'true'),
        isNotEmpty,
      );
      expect(h.server.callsTo('/branches'), isNotEmpty);
    });

    testWidgets('MENU-STUDIO-091 a combo item points at the combo editor', (
      tester,
    ) async {
      final s = studioServer();
      seedBreakfastCombo(s.db);
      final h = await pumpStudio(
        tester,
        path: '/menu/items/${comboId('breakfast')}',
        seeded: s,
      );
      expect(studioText(h.t('combos.meal.isCombo')), findsOneWidget);
      h.allowUnmatched = true;
      await h.tap(studioText(h.t('combos.meal.openEditor')));
      expect(h.location.path, '/menu/combos/${comboId('breakfast')}');
    });

    testWidgets('MENU-STUDIO-092 no combos: the note and "Combos →"', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(studioText(h.t('combos.meal.noCombos')), findsOneWidget);
      h.allowUnmatched = true;
      await h.tap(studioText(h.t('combos.title')));
      expect(h.location.path, '/menu/combos');
    });

    testWidgets('MENU-STUDIO-093..096 pick a combo: the one slot is chosen, '
        'the "+X", Apply', (tester) async {
      final s = studioServer();
      seedBreakfastCombo(s.db);
      final h = await pumpStudio(tester, seeded: s);
      expect(studioText(h.t('combos.meal.none')), findsOneWidget);
      // Nothing changed: the button reads "Turn off" and is disabled.
      final off = tester.widget<DashButton>(
        inSection(
          h.t('combos.meal.title'),
          find.widgetWithText(DashButton, h.t('combos.meal.turnOff')),
        ),
      );
      expect(off.onPressed, isNull);
      await openCombo(h);
      await h.tap(option('Breakfast Combo'));
      expect(lastCall(h, 'GET', comboT).path, '/combos/${comboId('breakfast')}');
      // The only slot that takes the item is chosen by itself.
      expect(studioText('Hot drink'), findsOneWidget);
      expect(
        studioText(
          h.t('combos.meal.preview', args: {'delta': '+EGP 35.00'}),
        ),
        findsOneWidget,
      );
      await h.shot('studio/meal-picked');
      await h.tap(studioText(h.t('combos.meal.apply')));
      expect(lastBody(h, 'PUT', mealT), {
        'combo_id': comboId('breakfast'),
        'slot_id': slotId('breakfast', 'drink'),
      });
      await h.expectToast(h.t('combos.meal.saved'));
      expect(
        h.server.callsTo(itemT, method: 'GET').where(
          (c) => c.path == '/menu-items/$_latte',
        ),
        hasLength(2),
      );
      // Saved: no Discard; the button is disabled again.
      expect(studioText(h.t('combos.discard')), findsNothing);
    });

    testWidgets('MENU-STUDIO-094 a combo with no slot for this item', (
      tester,
    ) async {
      final s = studioServer();
      seedBreakfastCombo(s.db, drinkSlot: false, key: 'box', name: 'Pastry Box');
      final h = await pumpStudio(tester, seeded: s);
      await openCombo(h);
      await h.tap(option('Pastry Box'));
      expect(
        studioText(h.t('errors.codes.MEAL_TARGET_INVALID')),
        findsOneWidget,
      );
      final apply = tester.widget<DashButton>(
        inSection(
          h.t('combos.meal.title'),
          find.widgetWithText(DashButton, h.t('combos.meal.apply')),
        ),
      );
      expect(apply.onPressed, isNull);
    });

    testWidgets('MENU-STUDIO-094 "Loading…" while the combo loads', (
      tester,
    ) async {
      final s = studioServer();
      seedBreakfastCombo(s.db);
      final gate = s.server.hold('GET', comboT);
      final h = await pumpStudio(tester, seeded: s);
      await openCombo(h);
      await h.tap(option('Breakfast Combo'));
      expect(studioText(h.t('common.loading')), findsOneWidget);
      gate.release();
      await h.settle();
      expect(studioText('Hot drink'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-093/097 changing the combo clears the slot; '
        'Discard restores the saved target', (tester) async {
      final s = studioServer();
      seedBreakfastCombo(s.db);
      seedBreakfastCombo(s.db, key: 'brunch', name: 'Brunch Combo');
      s.db[MenuTables.menuItems].update(_latte, {
        'meal': {
          'combo_id': comboId('breakfast'),
          'slot_id': slotId('breakfast', 'drink'),
        },
      });
      final h = await pumpStudio(tester, seeded: s);
      expect(studioText('Breakfast Combo'), findsOneWidget);
      await openCombo(h);
      await h.tap(option('Brunch Combo'));
      expect(studioText(h.t('combos.discard')), findsOneWidget);
      await h.tap(studioText(h.t('combos.discard')));
      expect(studioText('Breakfast Combo'), findsOneWidget);
      expect(studioText(h.t('combos.discard')), findsNothing);
    });

    testWidgets('MENU-STUDIO-096 Turn off sends nulls', (tester) async {
      final s = studioServer();
      seedBreakfastCombo(s.db);
      s.db[MenuTables.menuItems].update(_latte, {
        'meal': {
          'combo_id': comboId('breakfast'),
          'slot_id': slotId('breakfast', 'drink'),
        },
      });
      final h = await pumpStudio(tester, seeded: s);
      await openCombo(h);
      await h.tap(option(h.t('combos.meal.none')));
      await h.tap(studioText(h.t('combos.meal.turnOff')));
      expect(lastBody(h, 'PUT', mealT), {'combo_id': null, 'slot_id': null});
      await h.expectToast(h.t('combos.meal.cleared'));
      expect(s.db[MenuTables.menuItems].find(_latte)!['meal'], isNull);
    });

    testWidgets('MENU-STUDIO-096 a refusal toasts the server', (tester) async {
      final s = studioServer();
      seedBreakfastCombo(s.db);
      final refusal = MockResponse.error(
        400,
        'That combo has no slot for this item.',
        code: 'MEAL_TARGET_INVALID',
      );
      s.server.fail('PUT', mealT, refusal);
      final h = await pumpStudio(tester, seeded: s);
      await openCombo(h);
      await h.tap(option('Breakfast Combo'));
      await h.tap(studioText(h.t('combos.meal.apply')));
      await h.expectToast(h.refusalWords(refusal));
    });

    testWidgets('MENU-STUDIO-098 refusal (manager): disabled, no buttons', (
      tester,
    ) async {
      final s = studioServer(persona: Persona.manager);
      seedBreakfastCombo(s.db);
      final h = await pumpStudio(tester, persona: Persona.manager, seeded: s);
      final trigger = tester.widget<DashSelectTrigger>(
        inSection(h.t('combos.meal.title'), find.byType(DashSelectTrigger)).first,
      );
      expect(trigger.enabled, isFalse);
      expect(studioText(h.t('combos.meal.turnOff')), findsNothing);
      expect(studioText(h.t('combos.meal.apply')), findsNothing);
    });
  });

  group('MENU-STUDIO-099..111, 113 preview', () {
    testWidgets('MENU-STUDIO-099/100 a dry run of the SAVED item; the '
        'defaults come back and are asked for', (tester) async {
      final h = await pumpStudio(tester);
      final calls = h.server.callsTo(previewT);
      expect(calls.first.body, {
        'option_ids': <Object?>[],
        'quantity': 1,
        'service_mode': 'takeaway',
      });
      expect(calls.first.path, '/menu-items/$_latte/preview');
      await h.flushTimers();
      expect(
        (lastPreview(h)['option_ids']! as List),
        contains(MenuSeedIds.option('milk', 'full')),
      );
      // An unsaved edit does not change the dry run.
      final before = h.server.callsTo(previewT).length;
      await h.enterText(fieldWithText('115'), '119');
      await h.flushTimers();
      expect(h.server.callsTo(previewT).length, before);
      expect(chip('Regular'), findsOneWidget);
      expect(studioHas('115 = 115'), findsOneWidget);
      // Saving refreshes it.
      await tapSave(h);
      await h.flushTimers();
      expect(h.server.callsTo(previewT).length, greaterThan(before));
      expect(studioHas('119 = 119'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-100 asked 300 ms after the last change, keeping '
        'the last answer meanwhile', (tester) async {
      final h = await pumpStudio(tester);
      await h.flushTimers();
      final before = h.server.callsTo(previewT).length;
      await tester.ensureVisible(chip('Large'));
      await tester.pump();
      await tester.tap(chip('Large'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.server.callsTo(previewT).length, before);
      expect(studioHas('115 = 115'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      await h.settle();
      expect(h.server.callsTo(previewT).length, before + 1);
      expect(lastPreview(h)['size_label'], 'Large');
      expect(studioHas('135 = 135'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-101 sizes: the server\'s choice until one is '
        'picked', (tester) async {
      final h = await pumpStudio(tester);
      expect(selected(tester, 'Regular'), isTrue);
      expect(selected(tester, 'Large'), isFalse);
      await h.tap(chip('Large'));
      expect(selected(tester, 'Large'), isTrue);
      expect(selected(tester, 'Regular'), isFalse);
    });

    testWidgets('MENU-STUDIO-102/106 a single choice replaces; the price line', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(chip('Full cream ${h.t('modeling.preview.default')}'), findsOneWidget);
      await h.tap(chip('Oat milk +25'));
      expect(selected(tester, 'Oat milk +25'), isTrue);
      expect(
        selected(tester, 'Full cream ${h.t('modeling.preview.default')}'),
        isFalse,
      );
      expect(
        inStudio(find.byKey(const ValueKey('preview-price-line'))),
        findsOneWidget,
      );
      expect(studioHas('115 + 25 = 140'), findsOneWidget);
      // Multi choice: toggles.
      await h.tap(chip('Extra shot +30'));
      expect(studioHas('115 + 25 + 30 = 170'), findsOneWidget);
      await h.tap(chip('Extra shot +30'));
      expect(studioHas('115 + 25 = 140'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-102 a required single choice cannot be cleared; '
        'required groups are starred', (tester) async {
      final s = studioServer();
      final link = s.db[MenuTables.groupLinks].firstWhere(
        (l) =>
            l['menu_item_id'] == _latte &&
            l['group_id'] == MenuSeedIds.group('milk'),
      )!;
      link['is_required_override'] = true;
      final h = await pumpStudio(tester, seeded: s);
      expect(studioHas('Milk *'), findsOneWidget);
      final full = 'Full cream ${h.t('modeling.preview.default')}';
      await h.tap(chip(full));
      expect(selected(tester, full), isTrue);
    });

    testWidgets('MENU-STUDIO-102 a single choice that is not required clears', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final full = 'Full cream ${h.t('modeling.preview.default')}';
      await h.tap(chip(full));
      expect(selected(tester, full), isFalse);
    });

    testWidgets('MENU-STUDIO-103 item options', (tester) async {
      final s = studioServer();
      seedItemOptions(s, 'latte', [
        {'name': 'Extra foam', 'price': 500, 'is_active': true},
        {'name': 'Hidden', 'price': 0, 'is_active': false},
      ]);
      final h = await pumpStudio(tester, seeded: s);
      expect(studioText(h.t('modeling.preview.itemOptions')), findsOneWidget);
      expect(chip('Hidden'), findsNothing);
      await h.tap(chip('Extra foam +5'));
      expect(selected(tester, 'Extra foam +5'), isTrue);
      final ids = lastPreview(h)['option_ids']! as List;
      expect(ids.length, greaterThanOrEqualTo(2));
    });

    testWidgets('MENU-STUDIO-104/107 dine-in skips packaging (struck through)', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(studioPlain('12oz paper cup · 1'), findsOneWidget);
      expect(studioHas(h.t('modeling.preview.source.packaging')), findsWidgets);
      await h.tap(chip(h.t('modeling.preview.dineIn')));
      expect(lastPreview(h)['service_mode'], 'dine_in');
      final cup = tester.widget<Text>(
        studioPlain('12oz paper cup · 1').first,
      );
      expect(cup.style?.decoration, TextDecoration.lineThrough);
      expect(studioHas('skipped on dine-in'), findsWidgets);
    });

    testWidgets('MENU-STUDIO-105 the quantity stepper', (tester) async {
      final h = await pumpStudio(tester);
      final dec = studioLabel(h.t('modeling.preview.decrease'));
      expect(
        tester
            .widget<DashIconButton>(
              find.ancestor(of: dec, matching: find.byType(DashIconButton)).first,
            )
            .onPressed,
        isNull,
      );
      await h.tap(studioLabel(h.t('modeling.preview.increase')));
      expect(lastPreview(h)['quantity'], 2);
      expect(studioHas('(115) × 2 = 230'), findsOneWidget);
      expect(studioPlain('Full cream milk · 360'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-107 nothing to deduct', (tester) async {
      final h = await pumpStudio(tester, key: 'cookie');
      expect(studioText(h.t('modeling.preview.noDeductions')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-108 cost and margin; partial when costs miss', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(
        studioHas(
          'EGP 27.06 · ${h.t('modeling.preview.margin', args: {'pct': '76.5%'})}',
        ),
        findsOneWidget,
      );
      await h.go(studioPath('pistachio_latte'));
      expect(studioHas(h.t('modeling.preview.costPartial')), findsOneWidget);
      expect(studioHas(h.t('modeling.preview.margin', args: {'pct': ''})), findsNothing);
    });

    testWidgets('MENU-STUDIO-109 warnings with their rule; none: "No issues '
        'found"', (tester) async {
      final s = studioServer();
      s.db[MenuTables.groupLinks].insert({
        'menu_item_id': item('americano'),
        'group_id': MenuSeedIds.group('milk'),
        'sort': 5,
      }, timestamps: false);
      final h = await pumpStudio(tester, key: 'americano', seeded: s);
      expect(studioHas('F4'), findsOneWidget);
      expect(studioHas('swaps the drink\'s milk'), findsOneWidget);
      expect(studioText(h.t('modeling.preview.noIssues')), findsNothing);
      await h.shot('studio/preview-warning');
      await h.go(studioPath('latte'));
      expect(studioText(h.t('modeling.preview.noIssues')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-110 loading: two skeleton lines; failure: the '
        'reason', (tester) async {
      final s = studioServer();
      final gate = s.server.hold('POST', previewT);
      final h = await pumpStudio(tester, seeded: s);
      expect(
        inSection(h.t('modeling.preview.title'), find.byType(DashSkeleton)),
        findsNWidgets(2),
      );
      gate.release();
      await h.settle();
      expect(
        inSection(h.t('modeling.preview.title'), find.byType(DashSkeleton)),
        findsNothing,
      );
    });

    testWidgets('MENU-STUDIO-110 a failed preview with no answer yet', (
      tester,
    ) async {
      final s = studioServer();
      final failure = MockResponse.error(500, 'boom');
      s.server.fail('POST', previewT, failure, times: null);
      final h = await pumpStudio(tester, seeded: s);
      expect(
        studioText(
          h.t('modeling.preview.error', args: {'error': h.refusalWords(failure)}),
        ),
        findsOneWidget,
      );
      await h.shot('studio/preview-failed');
    });

    testWidgets('MENU-STUDIO-111 phone: each label sits above its chips', (
      tester,
    ) async {
      final h = await pumpStudio(tester, size: DashSize.phone);
      await h.scrollUntilVisible(chip('Large'));
      final label = studioText(h.t('modeling.preview.size'));
      expect(
        tester.getBottomLeft(label.last).dy,
        lessThanOrEqualTo(tester.getTopLeft(chip('Regular')).dy),
      );
      await h.shot('studio/preview-phone');
    });

    testWidgets('MENU-STUDIO-113 raw labels: "one_size", raw group names', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'cortado', locale: 'ar');
      expect(chip('one_size'), findsOneWidget);
      expect(studioText('Milk'), findsWidgets);
      expect(h.t('modeling.preview.size'), isNotEmpty);
    });
  });
}
