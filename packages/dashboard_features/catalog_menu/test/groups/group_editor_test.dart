// The choice-group editor, rows MENU-GRP-023..049, opened through the page's
// deep link. Seed facts used below: Milk swaps the milk (six options, each
// pouring its milk), Extras adds one line per option (Extra shot = 18 g of
// House espresso blend), Coffee beans swaps the beans (exactly 1), Sweetness
// moves no stock (exactly 1), Toppings adds syrup with a Large column (on
// Caramel Frappé and Iced Mocha, sizes Regular / Large). Five groups are
// active (Serving cup is not).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/groups/group_editor_dialog.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> openEditor(
  WidgetTester tester,
  String? groupId, {
  Persona persona = Persona.owner,
  ({MockServer server, MockDb db})? seeded,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
}) => pumpGroups(
  tester,
  path: '$groupsPath?edit=${groupId ?? 'new'}',
  persona: persona,
  seeded: seeded,
  size: size,
  locale: locale,
  dark: dark,
);

Finder editor() => find.byType(GroupEditorDialog);

Finder inEditor(Finder f) => find.descendant(of: editor(), matching: f);

Finder optionCards() => inEditor(
  find.byWidgetPredicate((w) => w.runtimeType.toString() == '_OptionCard'),
);

Finder card(int i) => optionCards().at(i);

/// The text field labelled [label] inside [scope].
Finder field(Finder scope, String label) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) => w is DashTextField && w.label == label,
  ),
);

/// The input a screen reader calls [label] inside [scope].
Finder input(Finder scope, String label) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) => w is DashTextInput && w.semanticLabel == label,
  ),
);

/// The select a screen reader calls [label] inside [scope].
Finder select(Finder scope, String label) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) => w is DashSelect && w.semanticLabel == label,
  ),
);

/// Opens [trigger] and picks [option] (searched for first).
Future<void> pick(DashHarness h, Finder trigger, String option) async {
  await h.tap(trigger);
  final list = find.byWidgetPredicate((w) => w is DashOptionList);
  final search = find.descendant(of: list, matching: find.byType(EditableText));
  if (search.evaluate().isNotEmpty) await h.enterText(search, option);
  await h.tap(find.descendant(of: list, matching: find.text(option)).last);
}

Future<void> save(DashHarness h) =>
    h.tap(inEditor(find.widgetWithText(DashButton, 'Save')));

Map<String, Object?> body(MockCall c) => (c.body! as Map).cast();

String opt(String group, String key) => MenuSeedIds.option(group, key);
String ing(String key) => MenuSeedIds.ingredient(key);

void main() {
  group('MENU-GRP-023..025 the dialog, its reads and seeding', () {
    testWidgets('MENU-GRP-023 titles, description, 768 wide', (tester) async {
      final h = await openEditor(tester, null);
      expect(inEditor(find.text('New choice group')), findsOneWidget);
      expect(
        inEditor(
          find.text(
            'A set of choices the cashier offers on an item, like Milk or '
            'Red Bull Type.',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(editor()).width, lessThanOrEqualTo(768));
      await h.shot('groups/editor-new');
      await h.tap(inEditor(find.text('Cancel')));
      await h.tap(labelIn(rowOf(milkId), 'Edit'));
      expect(inEditor(find.text('Edit choice group')), findsOneWidget);
    });

    testWidgets('MENU-GRP-024 reads: catalog, active groups, categories, and '
        "each attached item's sizes", (tester) async {
      final h = await openEditor(tester, toppingsId);
      final org = SeedIds.sabahOrg;
      expect(
        h.server.callsTo(catalogT).map((c) => c.path),
        contains('/inventory/orgs/$org/catalog'),
      );
      expect(
        h.server.callsTo(categoriesT).map((c) => c.path),
        contains('/inventory/orgs/$org/categories'),
      );
      expect(
        h.server
            .callsTo(listT)
            .where((c) => !c.query.containsKey('include_inactive')),
        hasLength(1),
      );
      expect(
        {for (final c in h.server.callsTo(itemT)) c.path},
        {
          '/menu-items/${MenuSeedIds.item('frappe')}',
          '/menu-items/${MenuSeedIds.item('iced_mocha')}',
        },
      );
    });

    testWidgets('MENU-GRP-025 an old swap group waits for the categories '
        '(spinner), then reads its category from the family', (tester) async {
      final s = groupsServer();
      groupRow(s.db, beansId)['swap_category_id'] = null;
      final gate = s.server.hold('GET', categoriesT);
      final h = await openEditor(tester, beansId, seeded: s);
      expect(inEditor(find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(field(editor(), 'Name'), findsNothing);
      await h.shot('groups/editor-loading');
      gate.release();
      await h.settle();
      expect(field(editor(), 'Name'), findsWidgets);
      final picker = tester.widget<DashSelect<String>>(
        select(editor(), 'Ingredient category'),
      );
      expect(picker.value, MenuSeedIds.ingredientCategory('coffee_bean'));
    });

    testWidgets('MENU-GRP-025 an untouched form re-seeds when a refresh '
        'lands', (tester) async {
      final h = await openEditor(tester, sweetnessId);
      final row = groupRow(h.db!, sweetnessId);
      row['name'] = 'Sugar';
      (row['options'] as List).removeLast();
      h.container.read(realtimeBusProvider).invalidate(const [
        '/modifier-groups',
      ]);
      await h.settle();
      expect(
        tester.widget<DashTextField>(field(editor(), 'Name').first).value,
        'Sugar',
      );
      expect(optionCards(), findsNWidgets(3));
      // Saving now patches against the refreshed group: nothing else moved.
      await save(h);
      expect(h.server.callsTo(optionT, method: 'PATCH'), isEmpty);
      expect(h.server.callsTo(optionT, method: 'DELETE'), isEmpty);
      await h.flushTimers();
    });

    testWidgets('MENU-GRP-025 seeded once: a refetch never wipes typing', (
      tester,
    ) async {
      final h = await openEditor(tester, sweetnessId);
      await h.enterText(field(editor(), 'Name'), 'Sugar level');
      h.container.read(realtimeBusProvider).invalidate(const [
        '/modifier-groups',
        '/inventory',
      ]);
      await h.settle();
      expect(
        tester.widget<DashTextField>(field(editor(), 'Name').first).value,
        'Sugar level',
      );
    });
  });

  group('MENU-GRP-026..033 name, effect, pick rule', () {
    testWidgets('MENU-GRP-026/044 (divergence) a failed Save scrolls the first '
        'invalid field into view', (tester) async {
      final h = await openEditor(tester, extrasId);
      await h.enterText(field(editor(), 'Name').first, '');
      final scroll = tester.state<ScrollableState>(
        inEditor(find.byType(Scrollable)).first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await h.settle();
      final view = tester.getRect(inEditor(find.byType(Scrollable)).first);
      bool shown() {
        final r = tester.getRect(field(editor(), 'Name').first);
        return r.top >= view.top && r.bottom <= view.bottom;
      }

      expect(shown(), isFalse);
      await save(h);
      expect(shown(), isTrue);
      expect(inEditor(find.text('This field is required')), findsOneWidget);
      expect(h.server.callsTo(groupT, method: 'PATCH'), isEmpty);
      // A line deep in the list: its own row comes into view.
      await h.enterText(field(editor(), 'Name').first, 'Extras');
      await h.enterText(input(card(4), 'Amount'), '0');
      scroll.position.jumpTo(0);
      await h.settle();
      await save(h);
      final line = tester.getRect(input(card(4), 'Amount'));
      expect(line.top >= view.top && line.bottom <= view.bottom, isTrue);
    });

    testWidgets('MENU-GRP-026 Name required (trimmed); Arabic name optional', (
      tester,
    ) async {
      final h = await openEditor(tester, null);
      expect(field(editor(), 'Name (ع)'), findsOneWidget);
      await h.enterText(field(editor(), 'Name'), '   ');
      await save(h);
      expect(inEditor(find.text('This field is required')), findsOneWidget);
      expect(h.server.callsTo(listT, method: 'POST'), isEmpty);
      await h.shot('groups/editor-required');
      await h.enterText(field(editor(), 'Name'), 'Flavour');
      expect(inEditor(find.text('This field is required')), findsNothing);
    });

    testWidgets('MENU-GRP-027 three effects; new = Adds; picking a category '
        'selects Swaps', (tester) async {
      final h = await openEditor(tester, null);
      expect(inEditor(find.text('What does choosing do?')), findsOneWidget);
      expect(
        inEditor(find.text('Nothing to stock (just a note or a price)')),
        findsOneWidget,
      );
      expect(inEditor(find.text("Swaps the drink's")), findsOneWidget);
      expect(inEditor(find.text('for the chosen one')), findsOneWidget);
      expect(
        inEditor(
          find.text(
            'These amounts are deducted on top of the drink\'s recipe '
            'whenever the option is chosen.',
          ),
        ),
        findsOneWidget,
      );
      await pick(h, select(editor(), 'Ingredient category'), 'Milk');
      expect(
        inEditor(
          find.text(
            'Exactly 1. A drink has one milk and one bean, so a swap group '
            'always takes exactly one choice.',
          ),
        ),
        findsOneWidget,
      );
      await h.tap(inEditor(find.text('Adds ingredients')));
      expect(inEditor(find.text('Any number')), findsOneWidget);
    });

    testWidgets('MENU-GRP-028 Swaps needs a category', (tester) async {
      final h = await openEditor(tester, null);
      await h.enterText(field(editor(), 'Name'), 'Syrup swap');
      await h.tap(inEditor(find.text("Swaps the drink's")));
      await save(h);
      expect(
        inEditor(find.text('Pick the ingredient category this group swaps')),
        findsOneWidget,
      );
      expect(h.server.callsTo(listT, method: 'POST'), isEmpty);
    });

    testWidgets('MENU-GRP-029 editing, Nothing: the lines-cleared note', (
      tester,
    ) async {
      final h = await openEditor(tester, extrasId);
      const note =
          'Saving as Nothing removes the ingredient lines from these options.';
      expect(inEditor(find.text(note)), findsNothing);
      await h.tap(
        inEditor(find.text('Nothing to stock (just a note or a price)')),
      );
      expect(inEditor(find.text(note)), findsOneWidget);
    });

    testWidgets('MENU-GRP-029 a new group never shows the note', (
      tester,
    ) async {
      final h = await openEditor(tester, null);
      await h.tap(
        inEditor(find.text('Nothing to stock (just a note or a price)')),
      );
      expect(
        inEditor(
          find.text(
            'Saving as Nothing removes the ingredient lines from these '
            'options.',
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('MENU-GRP-030 pick: swaps say Exactly 1; others choose, new '
        '= Any number', (tester) async {
      final h = await openEditor(tester, null);
      final seg = tester.widget<DashSegmentedControl<Object?>>(
        inEditor(find.byWidgetPredicate((w) => w is DashSegmentedControl)),
      );
      expect(seg.options.map((o) => o.label), [
        'Exactly 1',
        'Up to…',
        'Any number',
      ]);
      expect(seg.value.toString(), 'PickKind.any');
      await h.tap(inEditor(find.text('Up to…')));
      expect(input(editor(), 'Most choices'), findsOneWidget);
    });

    testWidgets('MENU-GRP-031 "Up to…": an emptied or zero count says '
        '"Must be at least 1"; digits only', (tester) async {
      final h = await openEditor(tester, null);
      await h.enterText(field(editor(), 'Name'), 'Flavours');
      await h.tap(inEditor(find.text('Up to…')));
      await h.enterText(input(editor(), 'Most choices'), '');
      await save(h);
      expect(inEditor(find.text('Must be at least 1')), findsOneWidget);
      await h.enterText(input(editor(), 'Most choices'), '-2.5');
      expect(
        tester.widget<DashTextInput>(input(editor(), 'Most choices')).value,
        '25',
      );
      await h.enterText(input(editor(), 'Most choices'), '0');
      expect(inEditor(find.text('Must be at least 1')), findsOneWidget);
      await h.enterText(input(editor(), 'Most choices'), '3');
      expect(inEditor(find.text('Must be at least 1')), findsNothing);
      expect(h.server.callsTo(listT, method: 'POST'), isEmpty);
    });

    testWidgets('MENU-GRP-032 the options help per effect', (tester) async {
      final h = await openEditor(tester, null);
      await h.tap(
        inEditor(find.text('Nothing to stock (just a note or a price)')),
      );
      expect(
        inEditor(
          find.text(
            'Choosing an option only changes the price and the ticket. No '
            'stock moves.',
          ),
        ),
        findsOneWidget,
      );
      await h.tap(inEditor(find.text("Swaps the drink's")));
      expect(
        inEditor(find.textContaining("The drink's own recipe decides")),
        findsOneWidget,
      );
      expect(inEditor(find.text('Options')), findsOneWidget);
    });

    testWidgets('MENU-GRP-033 swaps with nothing to offer: the red notes', (
      tester,
    ) async {
      final h = await openEditor(tester, null);
      await h.tap(inEditor(find.text("Swaps the drink's")));
      expect(
        inEditor(find.text('Pick the ingredient category this group swaps.')),
        findsOneWidget,
      );
      // Packaging holds only packaging lines: none of them is a swap here
      // once switched off.
      for (final i in h.db![MenuTables.ingredients].where(
        (i) => i['category_id'] == MenuSeedIds.ingredientCategory('bakery'),
      )) {
        i['is_active'] = false;
      }
      h.container.read(realtimeBusProvider).invalidate(const ['/inventory']);
      await h.settle();
      await pick(h, select(editor(), 'Ingredient category'), 'Bakery stock');
      expect(
        inEditor(
          find.text(
            'No active ingredient is in this category yet. Put them in it '
            'under Inventory settings.',
          ),
        ),
        findsOneWidget,
      );
      await pick(h, select(editor(), 'Ingredient category'), 'Milk');
      expect(
        inEditor(find.textContaining('No active ingredient')),
        findsNothing,
      );
    });
  });

  group('MENU-GRP-034..043 options', () {
    testWidgets('MENU-GRP-034 an option row: name (required), Arabic, price, '
        'Active, Default, Remove', (tester) async {
      final h = await openEditor(tester, null);
      await h.enterText(field(editor(), 'Name'), 'Flavours');
      await h.tap(inEditor(find.text('Add option')));
      final row = card(0);
      expect(field(row, 'Name'), findsOneWidget);
      expect(
        tester.widget<DashTextField>(field(row, 'Name')).placeholder,
        'e.g. Oat',
      );
      expect(field(row, 'Arabic name'), findsOneWidget);
      expect(tester.widget<DashTextField>(field(row, 'Adds (EGP)')).value, '0');
      expect(labelIn(row, 'Active'), findsOneWidget);
      expect(labelIn(row, 'Default'), findsOneWidget);
      expect(labelIn(row, 'Remove option'), findsOneWidget);
      await save(h);
      expect(
        find.descendant(of: row, matching: find.text('This field is required')),
        findsOneWidget,
      );
      await h.shot('groups/editor-option-errors');
      await h.tap(labelIn(row, 'Remove option'));
      expect(optionCards(), findsNothing);
    });

    testWidgets('MENU-GRP-034 the price takes digits and two decimals, no '
        'minus', (tester) async {
      final h = await openEditor(tester, sweetnessId);
      final price = field(card(0), 'Adds (EGP)');
      await h.enterText(price, '-12.345');
      expect(tester.widget<DashTextField>(price).value, '0');
      await h.enterText(price, '12.34');
      expect(tester.widget<DashTextField>(price).value, '12.34');
      await h.enterText(price, '.');
      await save(h);
      expect(
        find.descendant(
          of: card(0),
          matching: find.text('Invalid input: expected number, received NaN'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-GRP-035 (divergence) single choice keeps one default, '
        'also after typing "Up to 1"; multi keeps several', (tester) async {
      final h = await openEditor(tester, sweetnessId);
      bool on(int i) => tester
          .widget<DashSwitch>(
            find
                .descendant(of: card(i), matching: find.byType(DashSwitch))
                .at(1),
          )
          .value;
      expect([for (var i = 0; i < 4; i++) on(i)], [false, false, true, false]);
      await h.tap(labelIn(card(0), 'Default'));
      expect([for (var i = 0; i < 4; i++) on(i)], [true, false, false, false]);
      await h.tap(inEditor(find.text('Any number')));
      await h.tap(labelIn(card(3), 'Default'));
      expect([for (var i = 0; i < 4; i++) on(i)], [true, false, false, true]);
      await h.tap(inEditor(find.text('Up to…')));
      await h.enterText(input(editor(), 'Most choices'), '1');
      await h.tap(labelIn(card(1), 'Default'));
      expect([for (var i = 0; i < 4; i++) on(i)], [false, true, false, false]);
    });

    testWidgets('MENU-GRP-036 swaps: "Uses ingredient" offers the category\'s '
        'active ingredients; required', (tester) async {
      final h = await openEditor(tester, milkId);
      final oat = card(2);
      expect(
        tester.widget<DashSelect<String>>(select(oat, 'Uses ingredient')).value,
        ing('oat_milk'),
      );
      final offered = tester
          .widget<DashSelect<String>>(select(oat, 'Uses ingredient'))
          .options
          .map((o) => o.label)
          .toSet();
      expect(offered, {
        'Full cream milk',
        'Skimmed milk',
        'Oat milk',
        'Almond milk',
        'Coconut milk',
        'Lactose-free milk',
      });
      await h.tap(inEditor(find.text('Add option')));
      await h.enterText(field(card(6), 'Name'), 'Soy');
      await save(h);
      expect(
        find.descendant(
          of: card(6),
          matching: find.text('Pick the ingredient this option pours'),
        ),
        findsOneWidget,
      );
      expect(h.server.callsTo(groupT, method: 'PATCH'), isEmpty);
    });

    testWidgets('MENU-GRP-037 adds: "Deducts" and the per-size switch, on '
        'when a line has a size', (tester) async {
      final h = await openEditor(tester, toppingsId);
      expect(
        find.descendant(of: card(0), matching: find.text('Deducts')),
        findsOneWidget,
      );
      DashSwitch perSize(int i) => tester.widget(
        find.descendant(
          of: card(i),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DashSwitch &&
                w.semanticLabel == 'Different amounts per size',
          ),
        ),
      );
      expect(perSize(0).value, isTrue);
      expect(perSize(2).value, isFalse);
      await h.shot('groups/editor-per-size');
    });

    testWidgets('MENU-GRP-038 a line: picking sets the unit; amount above 0; '
        'duplicates; remove', (tester) async {
      final h = await openEditor(tester, extrasId);
      final shot = card(0);
      expect(tester.widget<DashTextInput>(input(shot, 'Amount')).value, '18');
      expect(
        find.descendant(of: shot, matching: find.text('g')),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(of: shot, matching: find.text('Add ingredient')),
      );
      await pick(h, select(shot, 'Ingredient').at(1), 'Vanilla syrup');
      expect(
        find.descendant(of: shot, matching: find.text('ml')),
        findsOneWidget,
      );
      await h.enterText(input(shot, 'Amount').at(1), '0');
      await h.tap(
        find.descendant(of: shot, matching: find.text('Add ingredient')),
      );
      await pick(h, select(shot, 'Ingredient').at(2), 'House espresso blend');
      await h.enterText(input(shot, 'Amount').at(2), '5');
      await save(h);
      expect(
        find.descendant(
          of: shot,
          matching: find.text('Enter an amount above 0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: shot,
          matching: find.text('This ingredient is already on this option'),
        ),
        findsOneWidget,
      );
      await h.shot('groups/editor-line-errors');
      await h.tap(labelIn(shot, 'Remove ingredient').at(2));
      await h.enterText(input(shot, 'Amount').at(1), '10');
      expect(
        find.descendant(of: shot, matching: find.textContaining('Enter an')),
        findsNothing,
      );
    });

    testWidgets('MENU-GRP-038 a blank line: "This field is required"', (
      tester,
    ) async {
      final h = await openEditor(tester, extrasId);
      await h.tap(
        find.descendant(of: card(1), matching: find.text('Add ingredient')),
      );
      await h.enterText(input(card(1), 'Amount').at(1), '4');
      await save(h);
      expect(
        find.descendant(
          of: card(1),
          matching: find.text('This field is required'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-GRP-039 Cost when every line is costed in its unit', (
      tester,
    ) async {
      final h = await openEditor(tester, extrasId);
      // Extra shot: 18 g × 95 pt/g = 1,710 pt.
      expect(
        find.descendant(of: card(0), matching: find.text('Cost EGP 17.10')),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(of: card(0), matching: find.text('Add ingredient')),
      );
      expect(
        find.descendant(of: card(0), matching: find.textContaining('Cost')),
        findsNothing,
      );
      await pick(h, select(card(0), 'Ingredient').at(1), 'Pistachio paste');
      await h.enterText(input(card(0), 'Amount').at(1), '5');
      // Pistachio paste has no unit cost yet.
      expect(
        find.descendant(of: card(0), matching: find.textContaining('Cost')),
        findsNothing,
      );
    });

    testWidgets('MENU-GRP-040 per size: All sizes + the items\' sizes and '
        'the lines\' labels; add and remove a column', (tester) async {
      final h = await openEditor(tester, toppingsId);
      final caramel = card(0);
      String cell(String size) => tester
          .widget<DashTextInput>(input(caramel, 'Caramel syrup in $size'))
          .value;
      expect(cell('All sizes'), '10');
      expect(cell('Large'), '15');
      expect(cell('Regular'), '');
      expect(
        find.descendant(
          of: caramel,
          matching: find.text(
            'A size column replaces the All sizes amount for that size. Tills '
            'that predate per-size amounts use All sizes.',
          ),
        ),
        findsOneWidget,
      );
      await h.enterText(
        find.descendant(
          of: caramel,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DashTextInput && w.placeholder == 'Size label, e.g. Cup',
          ),
        ),
        'Kids',
      );
      await h.tap(
        find.descendant(of: caramel, matching: find.text('Size column')),
      );
      expect(
        find.descendant(of: caramel, matching: find.text('Kids')),
        findsOneWidget,
      );
      await h.tap(labelIn(caramel, 'Remove column').last);
      expect(
        find.descendant(of: caramel, matching: find.text('Kids')),
        findsNothing,
      );
    });

    testWidgets('MENU-GRP-040 an empty grid: "No ingredients yet."', (
      tester,
    ) async {
      final h = await openEditor(tester, null);
      await h.tap(inEditor(find.text('Add option')));
      await h.tap(labelIn(card(0), 'Different amounts per size'));
      expect(
        find.descendant(
          of: card(0),
          matching: find.text('No ingredients yet.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card(0), matching: find.text('All sizes')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-GRP-041 per size off keeps the All sizes lines only', (
      tester,
    ) async {
      final h = await openEditor(tester, toppingsId);
      await h.tap(labelIn(card(0), 'Different amounts per size'));
      expect(input(card(0), 'Amount'), findsOneWidget);
      expect(
        tester.widget<DashTextInput>(input(card(0), 'Amount')).value,
        '10',
      );
      await save(h);
      final put = h.server.callsTo(recipeT, method: 'PUT').single;
      expect(
        put.path,
        '/modifier-options/${opt('toppings', 'caramel')}/recipe',
      );
      expect(put.body, [
        {
          'ingredient_id': ing('caramel_syrup'),
          'quantity': 10,
          'unit': 'ml',
          'size_label': null,
        },
      ]);
      await h.flushTimers();
    });

    testWidgets('MENU-GRP-042 Add option: empty, price 0, active, not '
        'default', (tester) async {
      final h = await openEditor(tester, beansId);
      await h.tap(inEditor(find.text('Add option')));
      final row = card(2);
      expect(tester.widget<DashTextField>(field(row, 'Name')).value, '');
      expect(tester.widget<DashTextField>(field(row, 'Adds (EGP)')).value, '0');
      final switches = tester
          .widgetList<DashSwitch>(
            find.descendant(of: row, matching: find.byType(DashSwitch)),
          )
          .toList();
      expect(switches[0].value, isTrue);
      expect(switches[1].value, isFalse);
    });

    testWidgets('MENU-GRP-043 "Used on N items" + Manage…', (tester) async {
      final h = await openEditor(tester, toppingsId);
      expect(inEditor(find.text('Used on 2 items')), findsOneWidget);
      await h.tap(inEditor(find.text('Manage…')));
      expect(find.text('Items offering Toppings'), findsOneWidget);
    });
  });

  group('MENU-GRP-044 footer and read-only', () {
    testWidgets('Cancel closes without a request', (tester) async {
      final h = await openEditor(tester, sweetnessId);
      await h.enterText(field(editor(), 'Name'), 'Sugar');
      await h.tap(inEditor(find.text('Cancel')));
      expect(editor(), findsNothing);
      expect(h.server.callsTo(groupT, method: 'PATCH'), isEmpty);
    });

    for (final persona in [Persona.manager, Persona.limited]) {
      testWidgets('${persona.name}: every control off, Close, no Save', (
        tester,
      ) async {
        final h = await openEditor(tester, extrasId, persona: persona);
        expect(inEditor(find.text('Close')), findsOneWidget);
        expect(inEditor(find.text('Save')), findsNothing);
        expect(
          tester.widget<DashTextField>(field(editor(), 'Name').first).enabled,
          isFalse,
        );
        expect(
          tester
              .widget<DashButton>(
                inEditor(find.widgetWithText(DashButton, 'Add option')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widgetList<DashSwitch>(inEditor(find.byType(DashSwitch)))
              .every((s) => !s.enabled),
          isTrue,
        );
        await h.tap(inEditor(find.text('Close')));
        expect(editor(), findsNothing);
      });
    }
  });

  group('MENU-GRP-045..048 Save', () {
    testWidgets('MENU-GRP-045 edit: the group PATCH; unchanged options and '
        'recipes send nothing', (tester) async {
      final h = await openEditor(tester, sweetnessId);
      await h.enterText(field(editor(), 'Name'), '  Sugar level ');
      await h.enterText(field(editor(), 'Name (ع)'), 'السكر');
      await save(h);
      final patch = h.server.callsTo(groupT, method: 'PATCH').single;
      expect(patch.path, '/modifier-groups/$sweetnessId');
      expect(body(patch), {
        'name': 'Sugar level',
        'name_translations': {'en': 'Sweetness', 'ar': 'السكر'},
        'selection_type': 'single',
        'min_selections': 1,
        'max_selections': 1,
        'is_required': true,
        'is_active': true,
        'effect': 'none',
        'swap_category_id': null,
      });
      expect(h.server.callsTo(optionT, method: 'PATCH'), isEmpty);
      expect(h.server.callsTo(recipeT, method: 'PUT'), isEmpty);
      await h.expectToast('Changes saved');
      expect(editor(), findsNothing);
      expect(textIn(rowOf(sweetnessId), 'Sugar level'), findsOneWidget);
    });

    testWidgets('MENU-GRP-045 edit: Any number clears the limit', (
      tester,
    ) async {
      final h = await openEditor(tester, toppingsId);
      await h.tap(inEditor(find.text('Any number')));
      await save(h);
      final b = body(h.server.callsTo(groupT, method: 'PATCH').single);
      expect(b['selection_type'], 'multi');
      expect(b['max_selections'], isNull);
      expect(b.containsKey('max_selections'), isTrue);
      await h.flushTimers();
      expect(textIn(rowOf(toppingsId), 'Pick any number'), findsOneWidget);
    });

    testWidgets('MENU-GRP-045/046/047 create: the group, its option and '
        'line; the sort is the active groups\' count', (tester) async {
      final h = await openEditor(tester, null);
      await h.enterText(field(editor(), 'Name'), 'Red Bull Type');
      await h.tap(inEditor(find.text('Up to…')));
      await h.enterText(input(editor(), 'Most choices'), '2');
      await h.tap(inEditor(find.text('Add option')));
      await h.enterText(field(card(0), 'Name'), 'Sugar free');
      await h.enterText(field(card(0), 'Arabic name'), 'بدون سكر');
      await h.enterText(field(card(0), 'Adds (EGP)'), '5.5');
      await h.tap(labelIn(card(0), 'Default'));
      await h.tap(
        find.descendant(of: card(0), matching: find.text('Add ingredient')),
      );
      await pick(h, select(card(0), 'Ingredient'), 'Sugar');
      await h.enterText(input(card(0), 'Amount'), '12');
      await save(h);
      final post = h.server.callsTo(listT, method: 'POST').single;
      expect(body(post), {
        'name': 'Red Bull Type',
        'name_translations': <String, Object?>{},
        'selection_type': 'multi',
        'min_selections': 0,
        'max_selections': 2,
        'is_required': false,
        'sort': 5,
        'effect': 'adds',
        'swap_category_id': null,
        'legacy_addon_type': 'red_bull_type',
      });
      final created = h.db![MenuTables.groups].rows.firstWhere(
        (g) => g['name'] == 'Red Bull Type',
      );
      final optPost = h.server.callsTo(optionsT, method: 'POST').single;
      expect(optPost.path, '/modifier-groups/${created['id']}/options');
      expect(body(optPost), {
        'name': 'Sugar free',
        'name_translations': {'ar': 'بدون سكر'},
        'price': 550,
        'is_active': true,
        'replaces_ingredient_id': null,
      });
      final option = (created['options'] as List).single as Map;
      final optPatch = h.server.callsTo(optionT, method: 'PATCH').single;
      expect(optPatch.path, '/modifier-options/${option['id']}');
      expect(body(optPatch), {'sort': 0, 'is_default': true});
      final put = h.server.callsTo(recipeT, method: 'PUT').single;
      expect(put.body, [
        {
          'ingredient_id': ing('sugar'),
          'quantity': 12,
          'unit': 'g',
          'size_label': null,
        },
      ]);
      await h.expectToast('Changes saved');
      expect(rowOf(created['id']! as String), findsOneWidget);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
    });

    testWidgets('MENU-GRP-045 create: a swap group sends no legacy type', (
      tester,
    ) async {
      final h = await openEditor(tester, null);
      await h.enterText(field(editor(), 'Name'), 'Milk two');
      await pick(h, select(editor(), 'Ingredient category'), 'Milk');
      await save(h);
      final b = body(h.server.callsTo(listT, method: 'POST').single);
      expect(b['effect'], 'swaps');
      expect(b['swap_category_id'], MenuSeedIds.ingredientCategory('milk'));
      expect(b['legacy_addon_type'], isNull);
      expect(b.containsKey('legacy_addon_type'), isTrue);
      expect(b['selection_type'], 'single');
      expect(b['max_selections'], 1);
      await h.flushTimers();
    });

    testWidgets('MENU-GRP-045 create: a name another group derives is '
        'suffixed', (tester) async {
      final h = await openEditor(tester, null);
      await h.enterText(field(editor(), 'Name'), 'Toppings');
      await save(h);
      expect(
        body(
          h.server.callsTo(listT, method: 'POST').single,
        )['legacy_addon_type'],
        'toppings_2',
      );
      await h.flushTimers();
    });

    testWidgets('MENU-GRP-046 options: removed deleted, changed patched, '
        'unchanged left alone', (tester) async {
      final h = await openEditor(tester, sweetnessId);
      await h.tap(labelIn(card(0), 'Remove option'));
      // Was "A hint of sugar" second, now first: its sort moves to 0.
      await h.enterText(field(card(0), 'Adds (EGP)'), '2');
      await save(h);
      expect(
        h.server.callsTo(optionT, method: 'DELETE').single.path,
        '/modifier-options/${opt('sweetness', 'plain')}',
      );
      final patches = h.server.callsTo(optionT, method: 'PATCH');
      expect(
        [for (final p in patches) p.path],
        [
          '/modifier-options/${opt('sweetness', 'hint')}',
          '/modifier-options/${opt('sweetness', 'medium')}',
          '/modifier-options/${opt('sweetness', 'sweet')}',
        ],
      );
      expect(body(patches.first), {
        'name': 'A hint of sugar',
        'name_translations': {'en': 'A hint of sugar', 'ar': 'على الريحة'},
        'price': 200,
        'is_active': true,
        'is_default': false,
        'sort': 0,
        'replaces_ingredient_id': null,
      });
      expect(body(patches[1])['sort'], 1);
      await h.flushTimers();
    });

    testWidgets('MENU-GRP-047 swaps: a new ingredient patches the option and '
        'pours one of it', (tester) async {
      final h = await openEditor(tester, milkId);
      await pick(h, select(card(2), 'Uses ingredient'), 'Almond milk');
      await save(h);
      final patch = h.server.callsTo(optionT, method: 'PATCH').single;
      expect(patch.path, '/modifier-options/${opt('milk', 'oat')}');
      expect(body(patch)['replaces_ingredient_id'], ing('almond_milk'));
      final put = h.server.callsTo(recipeT, method: 'PUT').single;
      expect(put.path, '/modifier-options/${opt('milk', 'oat')}/recipe');
      expect(put.body, [
        {
          'ingredient_id': ing('almond_milk'),
          'quantity': 1,
          'unit': 'ml',
          'size_label': null,
        },
      ]);
      await h.flushTimers();
    });

    testWidgets('MENU-GRP-047 adds: a changed amount re-writes that option '
        'only', (tester) async {
      final h = await openEditor(tester, extrasId);
      await h.enterText(input(card(0), 'Amount'), '20');
      await save(h);
      final put = h.server.callsTo(recipeT, method: 'PUT').single;
      expect(put.path, '/modifier-options/${opt('extras', 'shot')}/recipe');
      expect(put.body, [
        {
          'ingredient_id': ing('house_blend'),
          'quantity': 20,
          'unit': 'g',
          'size_label': null,
        },
      ]);
      await h.flushTimers();
    });

    testWidgets('MENU-GRP-047 per size: the grid writes size labels', (
      tester,
    ) async {
      final h = await openEditor(tester, toppingsId);
      await h.enterText(input(card(1), 'Chocolate sauce in Regular'), '12');
      await save(h);
      final put = h.server.callsTo(recipeT, method: 'PUT').single;
      expect(
        put.path,
        '/modifier-options/${opt('toppings', 'chocolate')}/recipe',
      );
      expect(put.body, [
        {
          'ingredient_id': ing('chocolate_sauce'),
          'quantity': 10,
          'unit': 'g',
          'size_label': null,
        },
        {
          'ingredient_id': ing('chocolate_sauce'),
          'quantity': 15,
          'unit': 'g',
          'size_label': 'Large',
        },
        {
          'ingredient_id': ing('chocolate_sauce'),
          'quantity': 12,
          'unit': 'g',
          'size_label': 'Regular',
        },
      ]);
      await h.flushTimers();
    });

    testWidgets('MENU-GRP-047 Nothing: every option with lines is emptied', (
      tester,
    ) async {
      final h = await openEditor(tester, extrasId);
      await h.tap(
        inEditor(find.text('Nothing to stock (just a note or a price)')),
      );
      await save(h);
      expect(
        body(h.server.callsTo(groupT, method: 'PATCH').single)['effect'],
        'none',
      );
      final puts = h.server.callsTo(recipeT, method: 'PUT');
      expect(puts, hasLength(5));
      expect(puts.every((p) => (p.body! as List).isEmpty), isTrue);
      await h.flushTimers();
    });

    testWidgets('MENU-GRP-048 success re-reads the groups and the page list', (
      tester,
    ) async {
      final h = await openEditor(tester, sweetnessId);
      final invalidated = recordInvalidations(h);
      final lists = h.server.callsTo(listT, method: 'GET');
      final active = lists.where(
        (c) => !c.query.containsKey('include_inactive'),
      );
      final all = lists.where((c) => c.query.containsKey('include_inactive'));
      final (a0, i0) = (active.length, all.length);
      await save(h);
      final after = h.server.callsTo(listT, method: 'GET');
      expect(
        after.where((c) => !c.query.containsKey('include_inactive')).length,
        a0 + 1,
      );
      expect(
        after.where((c) => c.query.containsKey('include_inactive')).length,
        i0 + 1,
      );
      expect(invalidated, containsAll(catalogPrefixes));
      // Not the groups: the web's `invalidateCatalog()` leaves them alone.
      expect(invalidated, isNot(contains('/modifier-groups')));
      await h.expectToast('Changes saved');
    });

    testWidgets("MENU-GRP-048 failure: the server's words, the dialog stays", (
      tester,
    ) async {
      final s = groupsServer();
      final refused = MockResponse.badRequest(
        'Swap category not found in this organization',
      );
      s.server.fail('PATCH', groupT, refused);
      final h = await openEditor(tester, sweetnessId, seeded: s);
      await save(h);
      expect(find.text(h.refusalWords(refused)), findsWidgets);
      expect(editor(), findsOneWidget);
      expect(
        tester
            .widget<DashButton>(
              inEditor(find.widgetWithText(DashButton, 'Save')),
            )
            .loading,
        isFalse,
      );
      await h.flushTimers();
    });

    testWidgets('MENU-AREA-013 Enter in the name saves', (tester) async {
      final h = await openEditor(tester, sweetnessId);
      await h.enterText(field(editor(), 'Name'), 'Sugar');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(h.server.callsTo(groupT, method: 'PATCH'), hasLength(1));
      await h.flushTimers();
    });
  });

  testWidgets('MENU-GRP-049 (divergence) a hidden field never blocks Save', (
    tester,
  ) async {
    final h = await openEditor(tester, extrasId);
    await h.tap(inEditor(find.text('Up to…')));
    await h.enterText(input(editor(), 'Most choices'), '');
    await h.tap(inEditor(find.text('Any number')));
    await h.enterText(input(card(0), 'Amount'), '0');
    await h.tap(
      inEditor(find.text('Nothing to stock (just a note or a price)')),
    );
    await save(h);
    expect(h.server.callsTo(groupT, method: 'PATCH'), hasLength(1));
    await h.expectToast('Changes saved');
  });
}
