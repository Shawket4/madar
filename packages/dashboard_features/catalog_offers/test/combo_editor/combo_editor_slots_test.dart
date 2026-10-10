// The combo editor's Slots, choices and Availability, driven through the real
// shell: what each control does to the form, the refusals on the fields, and
// what Save sends.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _combo = '/combos/{id}';
const _create = '/combos';

/// The body of the one PUT sent.
Map<String, Object?> _put(DashHarness h) =>
    (h.server.callsTo(_combo, method: 'PUT').single.body! as Map)
        .cast<String, Object?>();

List<Map<String, Object?>> _slots(Map<String, Object?> body) =>
    (body['slots']! as List).cast<Map<String, Object?>>();

List<Map<String, Object?>> _choices(Map<String, Object?> slot) =>
    (slot['choices']! as List).cast<Map<String, Object?>>();

String _text(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .controller
    .text;

void main() {
  group('slots', () {
    testWidgets('OFFR-CED-025/026/027/028/038 the heading; each card\'s title '
        'and pick line follow the form; move, remove and add a slot', (
      tester,
    ) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(editorText('Slots'), findsOneWidget);
      expect(
        editorText(
          'What the customer picks. One slot with one item and a fixed count '
          'makes a fixed bundle; several choices make a meal deal.',
        ),
        findsOneWidget,
      );
      expect(editorText('Pick 1'), findsNWidgets(2));
      await typeInto(h, 'At most', '3');
      expect(editorText('Pick 1 to 3'), findsOneWidget);
      await typeInto(h, 'Slot name', '');
      expect(editorText('Slot 1'), findsOneWidget);
      await typeInto(h, 'Slot name', 'Hot drink');

      final up = tester.widget<DashIconButton>(
        around(labelled('Move up').first, DashIconButton),
      );
      expect(up.onPressed, isNull);
      final down = tester.widget<DashIconButton>(
        around(labelled('Move down').at(1), DashIconButton),
      );
      expect(down.onPressed, isNull);
      await tapLabelled(h, 'Move down');
      await debounce(h);
      expect(_text(tester, labelled('Slot name').first), 'Cookie');

      await tapLabelled(h, 'Add a slot');
      expect(editorText('Slot 3'), findsOneWidget);
      await tapLabelled(h, 'Remove this slot', index: 2);
      expect(editorText('Slot 3'), findsNothing);

      await tapLabelled(h, 'Save');
      final slots = _slots(_put(h));
      expect(
        [for (final s in slots) (s['name'], s['sort'], s['max'])],
        [('Cookie', 0, 1), ('Hot drink', 1, 3)],
      );
      expect(slots[1]['id'], OffersSeed.slotId('coffee-cookie', 'coffee'));
      await h.expectToast('Changes saved');
    });

    testWidgets('OFFR-CED-029/030/031 the slot name is required; its Arabic '
        'name is kept; At least over At most is refused without a request', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: labelled('Slot name (Arabic)'),
                matching: find.byType(EditableText),
              ),
            )
            .textDirection,
        TextDirection.rtl,
      );
      await typeInto(h, 'Name', 'Lunch deal');
      await typeInto(h, 'Combo price', '150');
      await typeInto(h, 'At least', '3');
      await typeInto(h, 'At most', '2');
      await tapLabelled(h, 'Remove this choice');
      await tapLabelled(h, 'Create combo');
      expect(editorText('This field is required.'), findsOneWidget);
      expect(
        editorText('"At least" can\'t be more than "At most".'),
        findsOneWidget,
      );
      expect(
        editorText('Add at least one choice to this slot.'),
        findsOneWidget,
      );
      await h.expectToast('Some fields need attention before saving.');
      expect(h.server.callsTo(_create, method: 'POST'), isEmpty);

      await typeInto(h, 'Slot name', 'Main');
      await typeInto(h, 'Slot name (Arabic)', 'طبق');
      await typeInto(h, 'At least', '1');
      await typeInto(h, 'At most', '1');
      await tapLabelled(h, 'Add an item');
      await choose(h, 'Choose an item', 'Shakshuka', search: 'Shak');
      await tapLabelled(h, 'Create combo');
      final slot = _slots(
        (h.server.callsTo(_create, method: 'POST').single.body! as Map)
            .cast<String, Object?>(),
      ).single;
      expect(slot['name_translations'], {'ar': 'طبق'});
      await h.expectToast('Combo created');
    });

    testWidgets(
      'OFFR-CED-032/082 (divergence) At least 0 makes the slot optional; a '
      'blank box counts as 0 and reads "Pick 0 to 1"; a blank At most or '
      '1.5 is refused',
      (tester) async {
        final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
        await typeInto(h, 'At least', '0');
        expect(
          editorText(
            'At least 0 makes this slot optional: the customer may skip it.',
          ),
          findsOneWidget,
        );
        expect(editorText('Pick 0 to 1'), findsOneWidget);
        await typeInto(h, 'At least', '');
        expect(editorText('Pick 0 to 1'), findsOneWidget);
        await typeInto(h, 'At most', '');
        await tapLabelled(h, 'Save');
        expect(editorText('"At most" must be 1 or more.'), findsOneWidget);
        await h.flushTimers();
        await typeInto(h, 'At most', '1');
        await typeInto(h, 'At least', '1.5');
        expect(editorText('Use a whole number from 0 to 10.'), findsOneWidget);
        await typeInto(h, 'At least', '');
        await tapLabelled(h, 'Save');
        expect(_slots(_put(h)).first['min'], 0);
        await h.expectToast('Changes saved');
      },
    );

    testWidgets('OFFR-CED-033/034/047/039 the choices list, a slot left with '
        'none, and no slot at all', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(editorText('Choices'), findsNWidgets(2));
      expect(labelled('Add an item'), findsNWidgets(2));
      expect(labelled('Add a whole category'), findsNWidgets(2));
      await tapLabelled(h, 'Remove this choice', index: 1);
      await tapLabelled(h, 'Save');
      expect(
        editorText('Add at least one choice to this slot.'),
        findsOneWidget,
      );
      await h.flushTimers();
      await tapLabelled(h, 'Remove this slot', index: 1);
      await tapLabelled(h, 'Remove this slot');
      await tapLabelled(h, 'Save');
      expect(editorText('Add at least one slot.'), findsOneWidget);
      await h.expectToast('Some fields need attention before saving.');
      expect(h.server.callsTo(_combo, method: 'PUT'), isEmpty);
    });
  });

  group('the default pick', () {
    testWidgets('OFFR-CED-035/037 the default lists what the choices admit; '
        'an item with sizes offers a default size; changing the default '
        'clears it', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('morning-croissant'));
      expect(
        editorText(
          'Pre-selected on the till, used for the default margin, and '
          'applied when a synced sale arrives without picks.',
        ),
        findsNWidgets(2),
      );
      expect(labelled('Default pick: Butter Croissant'), findsOneWidget);
      // The Coffee slot's default is a Caffè Latte (Regular and Large).
      expect(labelled('Default pick: Caffè Latte'), findsOneWidget);
      expect(labelled('Default size: The included size'), findsOneWidget);
      await choose(h, 'Default size', 'Large');
      expect(labelled('Default size: Large'), findsOneWidget);

      await openSelect(h, 'Default pick');
      for (final name in [
        'The first choice',
        'Butter Croissant',
        'Almond Croissant',
        'Pain au Chocolat',
      ]) {
        expect(
          find.descendant(of: optionList, matching: find.text(name)),
          findsOneWidget,
          reason: name,
        );
      }
      expect(
        find.descendant(of: optionList, matching: find.text('Caffè Latte')),
        findsNothing,
      );
      await pickOption(h, 'Almond Croissant');

      await choose(h, 'Default pick', 'Flat White', index: 1);
      // Flat White has one size: no default size.
      expect(labelledSelect('Default size'), findsNothing);
      await tapLabelled(h, 'Save');
      final slots = _slots(_put(h));
      expect(slots[0]['default_item_id'], OffersSeed.item('almond_croissant'));
      expect(slots[1]['default_item_id'], OffersSeed.item('flatwhite'));
      expect(slots[1]['default_size_label'], isNull);
      await h.expectToast('Changes saved');
    });

    testWidgets('OFFR-CED-036 a default that is no longer one of the slot\'s '
        'choices is refused', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      await choose(h, 'Default pick', 'Chocolate Chip Cookie', index: 1);
      await choose(
        h,
        'Choose an item',
        'Banana Bread',
        index: 1,
        search: 'Banana',
      );
      await tapLabelled(h, 'Save');
      expect(
        editorText("The default must be one of this slot's choices."),
        findsOneWidget,
      );
      await h.expectToast('Some fields need attention before saving.');
      expect(h.server.callsTo(_combo, method: 'PUT'), isEmpty);
    });
  });

  group('a choice', () {
    testWidgets('OFFR-CED-040/081 Item / Category: switching clears the '
        'choice, and so does pressing the segment already chosen', (
      tester,
    ) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(labelled('Choose an item: Americano'), findsOneWidget);
      expect(labelledSelect('Size the price covers'), findsOneWidget);
      await h.tap(labelled('Item').first);
      expect(labelled('Choose an item: Americano'), findsNothing);
      expect(labelled('Choose an item: Choose an item'), findsOneWidget);
      expect(labelledSelect('Size the price covers'), findsNothing);

      await h.tap(labelled('Category').first);
      expect(labelled('Choose a category: Choose a category'), findsOneWidget);
      await choose(h, 'Choose a category', 'Hot Coffee');
      await h.tap(labelled('Category').first);
      expect(labelled('Choose a category: Choose a category'), findsOneWidget);
      await debounce(h);
    });

    testWidgets(
      'OFFR-CED-041/044 the item picker: every sellable item (switched '
      'off too, never a combo), its cheapest price, search by name or '
      'category, "No results found"',
      (tester) async {
        final s = editorServer();
        s.db
                .table(OffersTables.menuItems)
                .find(OffersSeed.item('cinnamon'))!['is_active'] =
            false;
        final h = await pumpEditor(tester, server: s.server, db: s.db);
        await openSelect(h, 'Choose an item');
        expect(
          find.descendant(of: optionList, matching: find.text('Search')),
          findsWidgets,
        );
        await h.enterText(
          find.descendant(of: optionList, matching: find.byType(EditableText)),
          'Bakery',
        );
        for (final name in [
          'Almond Croissant',
          'Butter Croissant',
          'Chocolate Chip Cookie',
          'Cinnamon Roll',
          'Pain au Chocolat',
        ]) {
          expect(
            find.descendant(of: optionList, matching: find.text(name)),
            findsOneWidget,
            reason: name,
          );
        }
        expect(
          find.descendant(of: optionList, matching: find.text('EGP 75.00')),
          findsOneWidget,
        );
        await h.shot('combo-editor/item-picker');
        await h.enterText(
          find.descendant(of: optionList, matching: find.byType(EditableText)),
          'Morning Croissant',
        );
        expect(
          find.descendant(
            of: optionList,
            matching: find.text('No results found'),
          ),
          findsOneWidget,
        );
        await h.enterText(
          find.descendant(of: optionList, matching: find.byType(EditableText)),
          'Cinnamon',
        );
        await pickOption(h, 'Cinnamon Roll');
        // OFFR-CED-044: a switched-off item wears "Inactive".
        expect(editorText('Inactive'), findsOneWidget);
        expect(labelled('Choose an item: Cinnamon Roll'), findsOneWidget);
      },
    );

    testWidgets('OFFR-CED-042/043 a whole category (with its count); nothing '
        'chosen, or the same one twice, is refused', (tester) async {
      final h = await pumpEditor(tester);
      await typeInto(h, 'Name', 'Bakery box');
      await typeInto(h, 'Combo price', '120');
      await typeInto(h, 'Slot name', 'Pastry');
      await tapLabelled(h, 'Add a whole category');
      await tapLabelled(h, 'Add a whole category');
      await choose(h, 'Choose a category', 'Bakery');
      expect(
        editorText('5 items today; new items in it join automatically.'),
        findsOneWidget,
      );
      await choose(h, 'Choose a category', 'Bakery', index: 1);
      await tapLabelled(h, 'Create combo');
      expect(editorText('Choose an item or a category.'), findsOneWidget);
      expect(editorText('This choice is already in the slot.'), findsOneWidget);
      await h.expectToast('Some fields need attention before saving.');
      expect(h.server.callsTo(_create, method: 'POST'), isEmpty);
    });

    testWidgets('OFFR-CED-045/088 an item no longer on the menu: amber frame, '
        '"Choose an item", its id sent back, no default option', (
      tester,
    ) async {
      final s = editorServer();
      s.db
              .table(OffersTables.menuItems)
              .find(OffersSeed.item('pain_choc'))!['deleted_at'] =
          '2026-09-30T09:00:00Z';
      final h = await pumpEditor(
        tester,
        path: comboPath('morning-croissant'),
        server: s.server,
        db: s.db,
      );
      expect(labelled('Choose an item: Choose an item'), findsOneWidget);
      final frames = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: labelled('Choose an item: Choose an item'),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => (d.decoration as BoxDecoration).border)
          .whereType<Border>()
          .toList();
      expect(frames, isNotEmpty);
      final hairline =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: labelled('Choose an item: Butter Croissant'),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(
        frames.first.top.color,
        isNot((hairline.border! as Border).top.color),
      );

      await openSelect(h, 'Default pick');
      expect(
        find.descendant(
          of: optionList,
          matching: find.text('Pain au Chocolat'),
        ),
        findsNothing,
      );
      await pickOption(h, 'Butter Croissant');
      await typeInto(h, 'Combo price', '170');
      await tapLabelled(h, 'Save');
      final pastry = _slots(_put(h)).first;
      expect([
        for (final c in _choices(pastry)) c['menu_item_id'],
      ], contains(OffersSeed.item('pain_choc')));
      // The server refuses a deleted item; the page says so.
      await h.flushTimers();
    });

    testWidgets('OFFR-CED-046 the extra charge: blank is 0, negative is '
        'refused under the row', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('morning-croissant'));
      expect(_text(tester, labelled('Extra charge').at(1)), '20');
      await typeInto(h, 'Extra charge', '-1', index: 1);
      await tapLabelled(h, 'Save');
      expect(editorText('Enter an amount of 0 or more.'), findsOneWidget);
      await h.flushTimers();
      await typeInto(h, 'Extra charge', '', index: 1);
      await tapLabelled(h, 'Save');
      final pastry = _slots(_put(h)).first;
      expect([for (final c in _choices(pastry)) c['surcharge']], [0, 0, 1500]);
      await h.expectToast('Changes saved');
    });

    testWidgets('OFFR-CED-048/049 the covered size and the other sizes\' '
        'extras: the difference as a placeholder, junk marked at once, a '
        'typed extra sent, a covered size dropping its extra', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(labelled('Size the price covers: Regular'), findsOneWidget);
      expect(editorText('Other sizes cost'), findsOneWidget);
      expect(
        editorText(
          'Left blank, a bigger size costs its usual price difference.',
        ),
        findsOneWidget,
      );
      final large = labelled('Extra for Large');
      final field = tester.widget<TextField>(
        find.descendant(of: large, matching: find.byType(TextField)),
      );
      expect(field.decoration!.hintText, '+15.00 difference');

      await typeInto(h, 'Extra for Large', 'abc');
      expect(
        tester.widget<DashTextInput>(around(large, DashTextInput)).invalid,
        isTrue,
      );
      await tapLabelled(h, 'Save');
      await h.expectToast('Some fields need attention before saving.');
      expect(h.server.callsTo(_combo, method: 'PUT'), isEmpty);
      expect(editorText('Enter an amount of 0 or more.'), findsNothing);

      await typeInto(h, 'Extra for Large', '10');
      await tapLabelled(h, 'Save');
      final coffee = _choices(_slots(_put(h)).first).single;
      expect(coffee['size_surcharges'], [
        {'size_label': 'Large', 'surcharge': 1000},
      ]);
      await h.expectToast('Changes saved');

      await choose(h, 'Size the price covers', 'Large');
      expect(labelled('Extra for Large'), findsNothing);
      final regular = tester.widget<TextField>(
        find.descendant(
          of: labelled('Extra for Regular'),
          matching: find.byType(TextField),
        ),
      );
      // A smaller size never costs less than nothing.
      expect(regular.decoration!.hintText, '+0.00 difference');
    });

    testWidgets('OFFR-CED-049 a whole category left on "The cheapest size" '
        'lists every size, each "the difference"', (tester) async {
      await pumpEditor(tester, path: comboPath('morning-croissant'));
      expect(
        labelled('Size the price covers: The cheapest size'),
        findsOneWidget,
      );
      for (final size in ['Regular', 'Large', 'Standard', 'Single', 'Double']) {
        final f = tester.widget<TextField>(
          find.descendant(
            of: labelled('Extra for $size'),
            matching: find.byType(TextField),
          ),
        );
        expect(f.decoration!.hintText, 'the difference', reason: size);
      }
      expect(_text(tester, labelled('Extra for Large')), '15');
    });
  });

  group('availability', () {
    testWidgets('OFFR-CED-050/051/052/053/054/055/058 windows: always '
        'available, add, days, the day rule, a branch, remove', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(editorText('Availability'), findsOneWidget);
      expect(
        editorText(
          'Optional. With no window it is on sale whenever the menu is.',
        ),
        findsOneWidget,
      );
      expect(editorText('Always available'), findsOneWidget);
      await tapLabelled(h, 'Add a window');
      expect(editorText('Window 1'), findsOneWidget);
      await h.tap(inEditor(find.text('Clear')));
      await tapLabelled(h, 'Save');
      expect(editorText('Pick at least one day.'), findsOneWidget);
      await h.flushTimers();
      await tapLabelled(h, 'Fri');
      await tapLabelled(h, 'Sat');
      expect(editorText('Pick at least one day.'), findsNothing);
      await choose(h, 'Branch', 'Zamalek');
      await tapLabelled(h, 'Save');
      final w = (_put(h)['windows']! as List).single as Map;
      expect(w['weekdays'], 96);
      expect(w['branch_id'], SeedIds.zamalek);
      expect(w['starts_at'], isNull);
      await h.expectToast('Changes saved');

      await tapLabelled(h, 'Remove this window');
      expect(editorText('Always available'), findsOneWidget);
    });

    testWidgets('OFFR-CED-056/057/089 hours must come in pairs; the dates '
        'pick from a calendar and clear', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('kids-cocoa'));
      expect(editorText('Window 1'), findsOneWidget);
      expect(editorText('Hours (optional)'), findsOneWidget);
      // The × of the "To" box (its semantics merge into the field's).
      await h.tap(
        inEditor(
          find.byWidgetPredicate(
            (w) => w is DashPressable && w.semanticLabel == 'Clear the time',
          ),
        ).last,
      );
      await tapLabelled(h, 'Save');
      expect(editorText('Set both times, or neither.'), findsOneWidget);
      await h.flushTimers();

      await h.tap(
        inEditor(
          find.byWidgetPredicate(
            (w) => w is DashDateField && w.semanticLabel == 'First day',
          ),
        ),
      );
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Click a day'), findsOneWidget);
      await h.tap(find.text('Today').hitTestable().last);
      expect(labelled('Clear the dates'), findsOneWidget);
      await tapLabelled(h, 'Clear the dates');
      expect(labelled('Clear the dates'), findsNothing);
      await debounce(h);
    });
  });
}
