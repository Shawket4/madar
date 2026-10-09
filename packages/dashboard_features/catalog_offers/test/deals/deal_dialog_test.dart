// The deal dialog (OFFR-DEA-024..049; OFFR-ALL-017, 019 as the dialog shows
// them), driven through the real shell on the mock server. One test per
// inventory row, its id first in the name.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/deals/pool_editor.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _new = '$dealsPath?edit=new';
String _edit(String key) => '$dealsPath?edit=${dealId(key)}';

/// The text box (or number box) a screen reader calls [label].
DashTextInput field(WidgetTester tester, String label) => tester.widget(
  find
      .ancestor(of: labelled(label).first, matching: find.byType(DashTextInput))
      .first,
);

/// The [index]th pool editor of the dialog (0 = "Items that count").
Finder pool([int index = 0]) => inDialog(find.byType(PoolEditor)).at(index);

/// Every pool editor of the dialog.
Finder get pools => inDialog(find.byType(PoolEditor));

/// [matching] inside the [index]th pool editor.
Finder inPool(Finder matching, [int index = 0]) =>
    find.descendant(of: pool(index), matching: matching);

/// The submit button ("Create deal" / "Save").
DashButton submitButton(WidgetTester tester, String label) => tester.widget(
  find
      .ancestor(
        of: inDialog(find.text(label)),
        matching: find.byType(DashButton),
      )
      .first,
);

/// A new deal with a name, price 90 and the Bakery category: ready to save.
Future<void> fillNew(
  DashHarness h, {
  String name = 'Any 2 bites for 90',
}) async {
  await typeInto(h, 'Name', name);
  await typeInto(h, 'Price', '90');
  await tapInDialog(h, 'Category');
  await choose(h, 'Choose a category', 'Bakery');
}

void main() {
  group('frame', () {
    testWidgets('OFFR-DEA-024 title "New deal" / "Edit deal", the hint, 672 '
        'wide on a wide screen', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      expect(inDialog(find.text('New deal')), findsOneWidget);
      expect(inDialog(find.text(h.t('deals.dialogHint'))), findsOneWidget);
      // The surface inside its hairline frame.
      expect(
        tester.getSize(dialog).width,
        inInclusiveRange(
          DashMetrics.dialogWide - Space.xs,
          DashMetrics.dialogWide,
        ),
      );
      await tapInDialog(h, 'Cancel');
      await h.go(_edit('pastry-pair'));
      expect(inDialog(find.text('Edit deal')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-024 the dialog scrolls inside when it is taller '
        'than the window', (tester) async {
      final h = await pumpDeals(tester, path: _edit('weekend-breakfast'));
      final scroll = find.descendant(
        of: dialog,
        matching: find.byType(Scrollable),
      );
      expect(scroll, findsWidgets);
      expect(
        tester.getSize(dialog).height,
        lessThanOrEqualTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
      await h.scrollUntilVisible(
        inDialog(find.text('Deal is on')),
        scrollable: scroll.first,
      );
      expect(inDialog(find.text('Deal is on')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-025 a new deal opens on the defaults, every time', (
      tester,
    ) async {
      final h = await pumpDeals(tester, path: _new);
      expect(field(tester, 'Name').value, '');
      expect(field(tester, 'How many').value, '2');
      expect(field(tester, 'Price').value, '');
      expect(field(tester, 'Most times per order').value, '');
      expect(
        tester
            .widget<DashSegmentedControl<String>>(
              inDialog(find.byType(DashSegmentedControl<String>)),
            )
            .value,
        'n_for_price',
      );
      expect(inPool(find.text('Choose an item')), findsOneWidget);
      expect(inDialog(find.text('Always available')), findsOneWidget);
      expect(tester.widget<DashSwitch>(switchOf('Deal is on')).value, isTrue);
      for (final b in ['Heliopolis', 'Maadi', 'New Cairo', 'Zamalek']) {
        expect(labelledSelect(b), findsOneWidget, reason: b);
        expect(
          find.descendant(
            of: labelledSelect(b),
            matching: find.text('Follow the deal'),
          ),
          findsOneWidget,
          reason: b,
        );
      }

      // What was typed is gone the next time it opens.
      await typeInto(h, 'Name', 'Half-typed');
      await tapInDialog(h, 'Cancel');
      await h.tap(inPage(find.text('New deal')).first);
      expect(field(tester, 'Name').value, '');
    });

    testWidgets('OFFR-DEA-025 an existing deal opens on its own values', (
      tester,
    ) async {
      await pumpDeals(tester, path: _edit('coffee-cookie-free'));
      expect(field(tester, 'Name').value, 'Buy 2 coffees, get a cookie free');
      expect(
        field(tester, 'Name (Arabic)').value,
        'اشترِ قهوتين واحصل على كوكيز مجانًا',
      );
      expect(field(tester, 'Buy').value, '2');
      expect(field(tester, 'Get').value, '1');
      expect(field(tester, 'Percent off').value, '100');
      expect(field(tester, 'Most times per order').value, '2');
      expect(inPool(find.text('Hot Coffee')), findsOneWidget);
      expect(inPool(find.text('Chocolate Chip Cookie'), 1), findsOneWidget);
      expect(
        find.descendant(
          of: labelledSelect('Zamalek'),
          matching: find.text('Off here'),
        ),
        findsOneWidget,
      );
    });
  });

  group('fields', () {
    testWidgets('OFFR-DEA-026 Name is required, on the field', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      expect(field(tester, 'Name').placeholder, 'Any 2 bites for 90');
      await tapInDialog(h, 'Create deal');
      expect(inDialog(find.text('This field is required.')), findsOneWidget);
      expect(field(tester, 'Name').invalid, isTrue);
      await typeInto(h, 'Name', 'Pastry pair');
      expect(inDialog(find.text('This field is required.')), findsNothing);
      expect(callsTo(h, 'POST', listRoute), isEmpty);
    });

    testWidgets('OFFR-DEA-027 Name (Arabic) is right to left and optional; '
        'it goes out as name_translations.ar', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      expect(field(tester, 'Name (Arabic)').textDirection, TextDirection.rtl);
      await fillNew(h);
      await typeInto(h, 'Name (Arabic)', ' أي قطعتين بـ 90 ');
      await tapInDialog(h, 'Create deal');
      expect(bodiesTo(h, 'POST', listRoute).single['name_translations'], {
        'ar': 'أي قطعتين بـ 90',
      });
      await h.flushTimers();
    });

    testWidgets('OFFR-DEA-028 Kind switches the number fields', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      expect(labelled('How many'), findsOneWidget);
      expect(labelled('Price'), findsOneWidget);
      expect(labelled('Buy'), findsNothing);
      await tapInDialog(h, 'Buy X get Y');
      expect(labelled('Buy'), findsOneWidget);
      expect(labelled('Get'), findsOneWidget);
      expect(labelled('Percent off'), findsOneWidget);
      expect(inDialog(find.text('100 = free')), findsOneWidget);
      expect(labelled('Price'), findsNothing);
      expect(labelled('How many'), findsNothing);
      await tapInDialog(h, 'N for a price');
      expect(labelled('How many'), findsOneWidget);
    });

    testWidgets('OFFR-DEA-029 N for a price: 2 to 20, and a price of 0 or '
        'more', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await typeInto(h, 'Name', 'Pair');
      await typeInto(h, 'How many', '1');
      await tapInDialog(h, 'Create deal');
      expect(
        inDialog(find.text('Use a whole number from 2 to 20.')),
        findsOneWidget,
      );
      expect(
        inDialog(find.text('Enter a price of 0 or more.')),
        findsOneWidget,
      );
      await typeInto(h, 'How many', '2.5');
      expect(
        inDialog(find.text('Use a whole number from 2 to 20.')),
        findsOneWidget,
      );
      await typeInto(h, 'How many', '21');
      expect(
        inDialog(find.text('Use a whole number from 2 to 20.')),
        findsOneWidget,
      );
      await typeInto(h, 'How many', '20');
      expect(
        inDialog(find.text('Use a whole number from 2 to 20.')),
        findsNothing,
      );
      await typeInto(h, 'Price', '-5');
      expect(
        inDialog(find.text('Enter a price of 0 or more.')),
        findsOneWidget,
      );
      await typeInto(h, 'Price', '0');
      expect(inDialog(find.text('Enter a price of 0 or more.')), findsNothing);
      expect(callsTo(h, 'POST', listRoute), isEmpty);
    });

    testWidgets('OFFR-DEA-030 Buy X get Y: Buy and Get 1 to 20, a percent '
        'from 1 to 100; 150 is refused on the field and nothing is sent', (
      tester,
    ) async {
      final h = await pumpDeals(tester, path: _new);
      await typeInto(h, 'Name', 'Coffee deal');
      await tapInDialog(h, 'Buy X get Y');
      await typeInto(h, 'Buy', '0');
      await typeInto(h, 'Get', '21');
      await typeInto(h, 'Percent off', '150');
      await choose(h, 'Choose an item', 'Americano', search: 'Americano');
      await tapInDialog(h, 'Create deal');
      expect(
        inDialog(find.text('Use a whole number from 1 to 20.')),
        findsNWidgets(2),
      );
      expect(
        inDialog(find.text('Use a percentage from 1 to 100.')),
        findsOneWidget,
      );
      expect(field(tester, 'Percent off').invalid, isTrue);
      expect(inDialog(find.text('100 = free')), findsNothing);
      expect(callsTo(h, 'POST', listRoute), isEmpty);
    });

    testWidgets('OFFR-DEA-031 the preview reads the rule as the list will', (
      tester,
    ) async {
      final h = await pumpDeals(tester, path: _new);
      expect(inDialog(find.text('Any 2 for EGP 0.00')), findsOneWidget);
      await typeInto(h, 'Price', '90');
      expect(inDialog(find.text('Any 2 for EGP 90.00')), findsOneWidget);
      await typeInto(h, 'How many', '');
      expect(inDialog(find.text('Any 0 for EGP 90.00')), findsOneWidget);
      await tapInDialog(h, 'Buy X get Y');
      expect(inDialog(find.text('Buy 0, get 1 free')), findsOneWidget);
      await typeInto(h, 'Buy', '2');
      await typeInto(h, 'Percent off', '50');
      expect(inDialog(find.text('Buy 2, get 1 at 50% off')), findsOneWidget);
      await typeInto(h, 'Percent off', '');
      expect(inDialog(find.text('Buy 2, get 1 free')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-032 "Items that count": an empty list is refused '
        'under it; the hint stays', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      expect(inDialog(find.text(h.t('deals.pool.hint'))), findsOneWidget);
      await typeInto(h, 'Name', 'Pair');
      await typeInto(h, 'Price', '90');
      await h.tap(inPool(find.bySemanticsLabel('Remove from the list')));
      await tapInDialog(h, 'Create deal');
      expect(
        inDialog(find.text('Add at least one item or category.')),
        findsOneWidget,
      );
      expect(callsTo(h, 'POST', listRoute), isEmpty);
    });

    testWidgets('OFFR-DEA-033 an entry picks a category, or an item by name '
        'or category with its cheapest price; no match reads "No results '
        'found"', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await tapInDialog(h, 'Category');
      expect(inPool(find.text('Choose a category')), findsOneWidget);
      await choose(h, 'Choose a category', 'Bakery');
      expect(inPool(find.text('Bakery')), findsOneWidget);

      await tapInDialog(h, 'Add an item');
      final trigger = labelledSelect('Choose an item');
      await h.tester.ensureVisible(trigger);
      await h.tap(trigger);
      await h.enterText(
        find.descendant(of: optionList, matching: find.byType(EditableText)),
        'Fresh Juice',
      );
      expect(
        find.descendant(of: optionList, matching: find.text('Orange Juice')),
        findsOneWidget,
      );
      await h.enterText(
        find.descendant(of: optionList, matching: find.byType(EditableText)),
        'zzz',
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
        'cookie',
      );
      // The cheapest size's price beside the item.
      expect(
        find.descendant(of: optionList, matching: find.text('EGP 55.00')),
        findsOneWidget,
      );
      await h.tap(
        find
            .descendant(
              of: optionList,
              matching: find.text('Chocolate Chip Cookie'),
            )
            .last,
      );
      expect(inPool(find.text('Chocolate Chip Cookie')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-034 a size select for an item with sizes: "Any '
        'size" by default; a new item clears it', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await choose(
        h,
        'Choose an item',
        'Chocolate Chip Cookie',
        search: 'Cookie',
      );
      expect(labelledSelect('Size'), findsNothing, reason: 'one size only');
      await choose(h, 'Choose an item', 'Iced Latte', search: 'Iced Latte');
      expect(
        find.descendant(
          of: labelledSelect('Size'),
          matching: find.text('Any size'),
        ),
        findsOneWidget,
      );
      await choose(h, 'Size', 'Large');
      expect(
        find.descendant(
          of: labelledSelect('Size'),
          matching: find.text('Large'),
        ),
        findsOneWidget,
      );
      await choose(h, 'Choose an item', 'Espresso', search: 'Espresso');
      expect(
        find.descendant(
          of: labelledSelect('Size'),
          matching: find.text('Any size'),
        ),
        findsOneWidget,
      );
      await choose(h, 'Size', 'Double');

      await typeInto(h, 'Name', 'Two doubles');
      await typeInto(h, 'Price', '150');
      await tapInDialog(h, 'Create deal');
      expect(bodiesTo(h, 'POST', listRoute).single['pool'], [
        {
          'menu_item_id': OffersSeed.item('espresso'),
          'category_id': null,
          'size_label': 'Double',
        },
      ]);
      await h.flushTimers();
    });

    testWidgets('OFFR-DEA-034 a category\'s sizes: every size its items '
        'have', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await tapInDialog(h, 'Category');
      await choose(h, 'Choose a category', 'Iced Coffee');
      await h.tap(labelledSelect('Size'));
      for (final s in ['Any size', 'Regular', 'Large']) {
        expect(
          find.descendant(of: optionList, matching: find.text(s)),
          findsOneWidget,
          reason: s,
        );
      }
      await h.tap(
        find.descendant(of: optionList, matching: find.text('Large')),
      );
      await choose(h, 'Choose a category', 'Bakery');
      expect(labelledSelect('Size'), findsNothing);
    });

    testWidgets('OFFR-DEA-035 an entry with nothing chosen is refused on '
        'the entry; the trash removes it', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await typeInto(h, 'Name', 'Any 2 bites for 90');
      await typeInto(h, 'Price', '90');
      await tapInDialog(h, 'Create deal');
      expect(
        inPool(find.text('Choose an item or a category.')),
        findsOneWidget,
      );
      expect(callsTo(h, 'POST', listRoute), isEmpty);
      await tapInDialog(h, 'Add a whole category');
      expect(
        inPool(find.text('Choose an item or a category.')),
        findsNWidgets(2),
      );
      await h.tap(inPool(find.bySemanticsLabel('Remove from the list')).first);
      expect(
        inPool(find.text('Choose an item or a category.')),
        findsOneWidget,
      );
      expect(inPool(find.text('Choose a category')), findsOneWidget);
      expect(inPool(find.text('Choose an item')), findsNothing);
    });

    testWidgets('OFFR-DEA-036 "Add an item" and "Add a whole category" add '
        'entries of their kind', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await tapInDialog(h, 'Add an item');
      await tapInDialog(h, 'Add a whole category');
      expect(inPool(find.text('Choose an item')), findsNWidgets(2));
      expect(inPool(find.text('Choose a category')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-037 buy X get Y: the reward list switch; on, its '
        'own list, refused empty; for N for a price it is hidden and sent as '
        '[]', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      expect(inDialog(find.text(h.t('deals.reward.hint'))), findsNothing);
      await typeInto(h, 'Name', 'Coffees and a cookie');
      await tapInDialog(h, 'Buy X get Y');
      expect(inDialog(find.text(h.t('deals.reward.hint'))), findsOneWidget);
      expect(pools, findsOneWidget);
      await tapInDialog(h, 'Category');
      await choose(h, 'Choose a category', 'Hot Coffee');
      await h.tap(switchOf('Reward items'));
      expect(pools, findsNWidgets(2));
      // On, it starts as an empty list of its own.
      await tapInDialog(h, 'Create deal');
      expect(
        inDialog(
          find.text('Add the reward items, or switch the separate list off.'),
        ),
        findsOneWidget,
      );
      await h.tap(inPool(find.text('Add an item'), 1));
      await tapInDialog(h, 'Create deal');
      expect(
        inPool(find.text('Choose an item or a category.'), 1),
        findsOneWidget,
      );
      await choose(
        h,
        'Choose an item',
        'Chocolate Chip Cookie',
        index: 0,
        search: 'Cookie',
      );
      // Back to N for a price: the leftover reward list is not sent.
      await tapInDialog(h, 'N for a price');
      expect(pools, findsOneWidget);
      await typeInto(h, 'Price', '120');
      await tapInDialog(h, 'Create deal');
      final body = bodiesTo(h, 'POST', listRoute).single;
      expect(body['reward_pool'], <Object?>[]);
      expect(body['kind'], 'n_for_price');
      await h.flushTimers();
    });

    testWidgets('OFFR-DEA-037 buy X get Y with its own reward list sends '
        'it', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await typeInto(h, 'Name', 'Coffees and a cookie');
      await tapInDialog(h, 'Buy X get Y');
      await tapInDialog(h, 'Category');
      await choose(h, 'Choose a category', 'Hot Coffee');
      await h.tap(switchOf('Reward items'));
      // The separate list starts empty.
      expect(inPool(find.byType(DashSelect<String>), 1), findsNothing);
      await h.tap(inPool(find.text('Add an item'), 1));
      await choose(
        h,
        'Choose an item',
        'Chocolate Chip Cookie',
        search: 'Cookie',
      );
      await tapInDialog(h, 'Create deal');
      final body = bodiesTo(h, 'POST', listRoute).single;
      expect(body['kind'], 'buy_get');
      expect(body['price'], isNull);
      expect(body['get_qty'], 1);
      expect(body['get_percent'], 100);
      expect(body['reward_pool'], [
        {
          'menu_item_id': OffersSeed.item('cookie'),
          'category_id': null,
          'size_label': null,
        },
      ]);
      await h.flushTimers();
    });

    testWidgets('OFFR-DEA-038 Most times per order: blank or 1 and more', (
      tester,
    ) async {
      final h = await pumpDeals(tester, path: _new);
      expect(inDialog(find.text('Blank = no limit')), findsOneWidget);
      await fillNew(h);
      await typeInto(h, 'Most times per order', '0');
      await tapInDialog(h, 'Create deal');
      expect(
        inDialog(
          find.text('Use a whole number of 1 or more, or leave it blank.'),
        ),
        findsOneWidget,
      );
      expect(callsTo(h, 'POST', listRoute), isEmpty);
      await typeInto(h, 'Most times per order', '3');
      await tapInDialog(h, 'Create deal');
      expect(bodiesTo(h, 'POST', listRoute).single['max_per_order'], 3);
      await h.flushTimers();
    });

    testWidgets('OFFR-DEA-039 Availability: the shared windows editor, its '
        'rules on Save, its windows sent', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await fillNew(h);
      expect(inDialog(find.text('Always available')), findsOneWidget);
      await tapInDialog(h, h.t('combos.windows.add'));
      await tapInDialog(h, h.t('combos.windows.clearDays'));
      await tapInDialog(h, 'Create deal');
      expect(inDialog(find.text(h.t('combos.errors.noDays'))), findsOneWidget);
      expect(callsTo(h, 'POST', listRoute), isEmpty);
      await h.tap(labelled(h.t('combos.windows.day.fri')));
      await h.tap(labelled(h.t('combos.windows.day.sat')));
      expect(inDialog(find.text(h.t('combos.errors.noDays'))), findsNothing);
      await tapInDialog(h, 'Create deal');
      expect(bodiesTo(h, 'POST', listRoute).single['windows'], [
        {
          'branch_id': null,
          'weekdays': 96,
          'starts_at': null,
          'ends_at': null,
          'valid_from': null,
          'valid_to': null,
        },
      ]);
      await h.flushTimers();
    });

    testWidgets('OFFR-DEA-040 Branches: one select per branch, named by it, '
        'opening on the deal\'s exceptions', (tester) async {
      final h = await pumpDeals(tester, path: _edit('juice-trio'));
      expect(inDialog(find.text('Branches')), findsOneWidget);
      expect(inDialog(find.text(h.t('deals.branchesHint'))), findsOneWidget);
      String state(String b) => (tester
          .widget<Text>(
            find
                .descendant(of: labelledSelect(b), matching: find.byType(Text))
                .first,
          )
          .data)!;
      expect(state('Heliopolis'), 'On here');
      expect(state('Maadi'), 'On here');
      expect(state('New Cairo'), 'Follow the deal');
      expect(state('Zamalek'), 'Follow the deal');
      await h.tap(labelledSelect('Zamalek'));
      for (final o in ['Follow the deal', 'On here', 'Off here']) {
        expect(
          find.descendant(of: optionList, matching: find.text(o)),
          findsOneWidget,
          reason: o,
        );
      }
      await h.tap(
        find.descendant(of: optionList, matching: find.text('Off here')),
      );
      expect(state('Zamalek'), 'Off here');
    });

    testWidgets('OFFR-DEA-040 no branches: no Branches section', (
      tester,
    ) async {
      final s = dealsServer();
      s.server.on('GET', '/branches', (req) => MockResponse.ok(<Object?>[]));
      await pumpDeals(tester, path: _new, server: s.server, db: s.db);
      expect(inDialog(find.text('Branches')), findsNothing);
      expect(inDialog(find.text('Follow the deal')), findsNothing);
    });

    testWidgets('OFFR-DEA-041 "Deal is on" (on by default) goes out as '
        'is_active', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await fillNew(h);
      await h.tap(switchOf('Deal is on'));
      await tapInDialog(h, 'Create deal');
      expect(bodiesTo(h, 'POST', listRoute).single['is_active'], isFalse);
      await h.flushTimers();
    });
  });

  group('save', () {
    testWidgets('OFFR-DEA-042 footer: Cancel and Create deal; Save on an '
        'existing deal; busy while saving', (tester) async {
      final s = dealsServer();
      final h = await pumpDeals(tester, path: _new, server: s.server, db: s.db);
      expect(inDialog(find.text('Cancel')), findsOneWidget);
      expect(inDialog(find.text('Create deal')), findsOneWidget);
      await fillNew(h);
      final gate = s.server.hold('POST', listRoute);
      await tapInDialog(h, 'Create deal');
      expect(submitButton(tester, 'Create deal').loading, isTrue);
      // A second press while it runs sends nothing more.
      await h.tap(inDialog(find.text('Create deal')));
      gate.release();
      await h.settle();
      expect(callsTo(h, 'POST', listRoute), hasLength(1));
      await h.expectToast('Deal created');
      await h.go(_edit('pastry-pair'));
      expect(inDialog(find.text('Save')), findsOneWidget);
      expect(inDialog(find.text('Create deal')), findsNothing);
    });

    testWidgets('OFFR-DEA-043 Save with errors: red lines on the fields, no '
        'request, no toast', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await typeInto(h, 'How many', '1');
      await tapInDialog(h, 'Create deal');
      expect(inDialog(find.text('This field is required.')), findsOneWidget);
      expect(
        inDialog(find.text('Use a whole number from 2 to 20.')),
        findsOneWidget,
      );
      expect(
        inDialog(find.text('Enter a price of 0 or more.')),
        findsOneWidget,
      );
      expect(
        inPool(find.text('Choose an item or a category.')),
        findsOneWidget,
      );
      expect(callsTo(h, 'POST', listRoute), isEmpty);
      expect(find.byType(DashToast), findsNothing);
      expect(dialog, findsOneWidget);
    });

    testWidgets('OFFR-DEA-044 create: POST the deal (sort = deals listed), '
        '"Deal created", the list refetches, the dialog closes', (
      tester,
    ) async {
      final h = await pumpDeals(tester, path: _new);
      final before = callsTo(h, 'GET', listRoute).length;
      await fillNew(h);
      expect(inDialog(find.text('Any 2 for EGP 90.00')), findsOneWidget);
      await tapInDialog(h, 'Create deal');
      expect(bodiesTo(h, 'POST', listRoute).single, {
        'name': 'Any 2 bites for 90',
        'name_translations': <String, Object?>{},
        'kind': 'n_for_price',
        'qty': 2,
        'price': 9000,
        'get_qty': null,
        'get_percent': null,
        'max_per_order': null,
        'sort': 5,
        'is_active': true,
        'pool': [
          {
            'menu_item_id': null,
            'category_id': OffersSeed.category('bakery'),
            'size_label': null,
          },
        ],
        'reward_pool': <Object?>[],
        'windows': <Object?>[],
      });
      expect(callsTo(h, 'PUT', branchRoute), isEmpty);
      expect(callsTo(h, 'DELETE', branchRoute), isEmpty);
      await h.expectToast('Deal created');
      expect(dialog, findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
      expect(callsTo(h, 'GET', listRoute).length, before + 1);
      expect(inTable(find.text('Any 2 bites for 90')), findsOneWidget);
    });

    testWidgets('OFFR-DEA-044 create with branches set: the branch calls '
        'follow, on the new deal', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await fillNew(h);
      await choose(h, 'Maadi', 'Off here');
      await tapInDialog(h, 'Create deal');
      final created = h.server.calls.firstWhere(
        (c) => c.method == 'POST' && c.template == listRoute,
      );
      final put = callsTo(h, 'PUT', branchRoute).single;
      expect(
        h.server.calls.indexOf(put),
        greaterThan(h.server.calls.indexOf(created)),
      );
      final newId = h.db!
          .table(OffersTables.deals)
          .rows
          .firstWhere((r) => r['name'] == 'Any 2 bites for 90')['id'];
      expect(put.path, '/deals/$newId/branches/${SeedIds.maadi}');
      expect(put.body, {'is_active': false});
      await h.expectToast('Deal created');
      expect(
        inRow('Any 2 bites for 90', find.text('1 branch exception')),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DEA-045 update: PUT the deal with its own sort, then a '
        'PUT per branch set on or off, then a DELETE per branch back to '
        'follow; "Changes saved"', (tester) async {
      final h = await pumpDeals(tester, path: _edit('coffee-cookie-free'));
      await typeInto(h, 'Name', 'Buy 2 coffees, get a free cookie');
      await choose(h, 'Zamalek', 'Follow the deal');
      await choose(h, 'New Cairo', 'On here');
      await choose(h, 'Heliopolis', 'Off here');
      await tapInDialog(h, 'Save');

      final id = dealId('coffee-cookie-free');
      final writes = [
        for (final c in h.server.calls)
          if (c.method != 'GET') '${c.method} ${c.path} ${c.body ?? ''}',
      ];
      expect(writes, [
        'PUT /deals/$id ${h.server.calls.firstWhere((c) => c.method == 'PUT').body}',
        'PUT /deals/$id/branches/${SeedIds.newCairo} {is_active: true}',
        'PUT /deals/$id/branches/${SeedIds.heliopolis} {is_active: false}',
        'DELETE /deals/$id/branches/${SeedIds.zamalek} ',
      ]);
      final body = bodiesTo(h, 'PUT', itemRoute).single;
      expect(body['name'], 'Buy 2 coffees, get a free cookie');
      expect(body['sort'], 1);
      expect(body['kind'], 'buy_get');
      expect(body['qty'], 2);
      expect(body['price'], isNull);
      expect(body['max_per_order'], 2);
      expect(body['pool'], [
        {
          'menu_item_id': null,
          'category_id': OffersSeed.category('hot'),
          'size_label': null,
        },
      ]);
      await h.expectToast('Changes saved');
      expect(dialog, findsNothing);
      expect(
        inRow(
          'Buy 2 coffees, get a free cookie',
          find.text('2 branch exceptions'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-DEA-045 nothing changed in the branches: the deal '
        'alone', (tester) async {
      final h = await pumpDeals(tester, path: _edit('juice-trio'));
      await tapInDialog(h, 'Save');
      expect(callsTo(h, 'PUT', itemRoute), hasLength(1));
      expect(callsTo(h, 'PUT', branchRoute), isEmpty);
      expect(callsTo(h, 'DELETE', branchRoute), isEmpty);
      await h.expectToast('Changes saved');
    });

    testWidgets('OFFR-DEA-046 a failed save toasts, keeps the dialog and '
        'what was typed, and sends no branch call', (tester) async {
      final s = dealsServer();
      final boom = MockResponse.error(500, 'boom');
      s.server.fail('PUT', itemRoute, boom);
      final h = await pumpDeals(
        tester,
        path: _edit('coffee-cookie-free'),
        server: s.server,
        db: s.db,
      );
      await typeInto(h, 'Name', 'Changed');
      await choose(h, 'Maadi', 'On here');
      await tapInDialog(h, 'Save');
      await h.expectToast(h.refusalWords(boom));
      expect(dialog, findsOneWidget);
      expect(field(tester, 'Name').value, 'Changed');
      expect(callsTo(h, 'PUT', branchRoute), isEmpty);
      expect(submitButton(tester, 'Save').loading, isFalse);
    });

    testWidgets('OFFR-DEA-046 DEAL_INVALID names the field in the dialog\'s '
        'words', (tester) async {
      final s = dealsServer();
      s.server.fail(
        'PUT',
        itemRoute,
        MockResponse.error(
          400,
          'Check the deal\'s "get_percent".',
          code: 'DEAL_INVALID',
          vars: {'field': 'get_percent'},
        ),
      );
      final h = await pumpDeals(
        tester,
        path: _edit('iced-latte-half'),
        server: s.server,
        db: s.db,
      );
      await tapInDialog(h, 'Save');
      await h.expectToast(
        h.t('errors.codes.DEAL_INVALID', args: {'field': 'Percent off'}),
      );
      expect(
        h.t('errors.codes.DEAL_INVALID', args: {'field': 'Percent off'}),
        'Check the deal\'s "Percent off".',
      );
      expect(dialog, findsOneWidget);
    });

    testWidgets('OFFR-DEA-046 the server refuses an item that is gone: '
        '"Check the deal\'s "Items that count"."', (tester) async {
      final s = dealsServer();
      final h = await pumpDeals(tester, path: _new, server: s.server, db: s.db);
      await typeInto(h, 'Name', 'Cookie pair');
      await typeInto(h, 'Price', '90');
      await choose(
        h,
        'Choose an item',
        'Chocolate Chip Cookie',
        search: 'Cookie',
      );
      s.db
              .table(OffersTables.menuItems)
              .find(OffersSeed.item('cookie'))!['deleted_at'] =
          s.db.nowIso;
      await tapInDialog(h, 'Create deal');
      expect(callsTo(h, 'POST', listRoute).single.status, 400);
      await h.expectToast('Check the deal\'s "Items that count".');
      expect(dialog, findsOneWidget);
    });

    testWidgets('OFFR-DEA-046 (divergence) the deal saved but a branch call '
        'failed: the list shows it, the dialog becomes "Edit deal" and the '
        'next Save updates it, never creating a second', (tester) async {
      final s = dealsServer();
      final refusal = MockResponse.denied('menu.deals.edit');
      s.server.fail('PUT', branchRoute, refusal);
      final h = await pumpDeals(tester, path: _new, server: s.server, db: s.db);
      final lists = callsTo(h, 'GET', listRoute).length;
      await fillNew(h);
      await choose(h, 'Maadi', 'Off here');
      await tapInDialog(h, 'Create deal');
      await h.expectToast(h.refusalWords(refusal));
      expect(dialog, findsOneWidget);
      expect(callsTo(h, 'POST', listRoute), hasLength(1));
      expect(callsTo(h, 'GET', listRoute).length, lists + 1);
      expect(inTable(find.text('Any 2 bites for 90')), findsOneWidget);
      expect(inDialog(find.text('Edit deal')), findsOneWidget);
      // What was typed stays (the refetch is what this save wrote).
      expect(
        find.descendant(
          of: labelledSelect('Maadi'),
          matching: find.text('Off here'),
        ),
        findsOneWidget,
      );
      // The second press: a PUT of the deal just created, then the branch.
      await tapInDialog(h, 'Save');
      expect(callsTo(h, 'POST', listRoute), hasLength(1));
      final created = callsTo(h, 'PUT', itemRoute).single;
      expect(created.path, startsWith('/deals/'));
      expect(callsTo(h, 'PUT', branchRoute).last.status, 204);
      await h.expectToast('Changes saved');
      expect(
        h.db!
            .table(OffersTables.deals)
            .rows
            .where((r) => r['name'] == 'Any 2 bites for 90'),
        hasLength(1),
      );
    });

    testWidgets('OFFR-DEA-047 read-only: every field disabled, no add or '
        'remove, no Add a window, "Close" only', (tester) async {
      final h = await pumpDeals(
        tester,
        path: _edit('weekend-breakfast'),
        persona: Persona.manager,
      );
      expect(field(tester, 'Name').enabled, isFalse);
      expect(field(tester, 'How many').enabled, isFalse);
      expect(field(tester, 'Price').enabled, isFalse);
      expect(
        tester
            .widget<DashSegmentedControl<String>>(
              inDialog(find.byType(DashSegmentedControl<String>)),
            )
            .enabled,
        isFalse,
      );
      expect(
        inDialog(find.bySemanticsLabel('Remove from the list')),
        findsNothing,
      );
      expect(inDialog(find.text('Add an item')), findsNothing);
      expect(inDialog(find.text('Add a whole category')), findsNothing);
      expect(inDialog(find.text(h.t('combos.windows.add'))), findsNothing);
      for (final s in tester.widgetList<DashSelect<Object?>>(
        inDialog(find.byWidgetPredicate((w) => w is DashSelect)),
      )) {
        expect(s.enabled, isFalse);
      }
      for (final w in tester.widgetList<DashSwitch>(
        inDialog(find.byType(DashSwitch)),
      )) {
        expect(w.enabled, isFalse);
      }
      expect(inDialog(find.text('Close')), findsOneWidget);
      expect(inDialog(find.text('Save')), findsNothing);
      expect(inDialog(find.text('Cancel')), findsNothing);
      // Enter in a field submits nothing.
      await tapInDialog(h, 'Close');
      expect(dialog, findsNothing);
      expect(h.server.calls.where((c) => c.method != 'GET'), isEmpty);
    });

    testWidgets('OFFR-DEA-048 entries are loose: the same category twice is '
        'sent; a switched-off item is offered; re-pressing the chosen '
        'segment clears the entry', (tester) async {
      final s = dealsServer();
      s.db
              .table(OffersTables.menuItems)
              .find(OffersSeed.item('cookie'))!['is_active'] =
          false;
      final h = await pumpDeals(tester, path: _new, server: s.server, db: s.db);
      await choose(
        h,
        'Choose an item',
        'Chocolate Chip Cookie',
        search: 'Cookie',
      );
      expect(inPool(find.text('Chocolate Chip Cookie')), findsOneWidget);
      expect(inPool(find.text('Inactive')), findsNothing);
      // The chosen segment again: the pick is cleared.
      await tapInDialog(h, 'Item');
      expect(inPool(find.text('Choose an item')), findsOneWidget);

      await tapInDialog(h, 'Category');
      await choose(h, 'Choose a category', 'Bakery');
      await tapInDialog(h, 'Add a whole category');
      await choose(h, 'Choose a category', 'Bakery', index: 1);
      await typeInto(h, 'Name', 'Bakery twice');
      await typeInto(h, 'Price', '100');
      await tapInDialog(h, 'Create deal');
      final bakery = {
        'menu_item_id': null,
        'category_id': OffersSeed.category('bakery'),
        'size_label': null,
      };
      expect(bodiesTo(h, 'POST', listRoute).single['pool'], [bakery, bakery]);
      await h.expectToast('Deal created');
    });

    testWidgets('OFFR-DEA-048 a pool item that is gone reads "Choose an '
        'item" and its id is sent back as it was', (tester) async {
      final s = dealsServer();
      final row = s.db.table(OffersTables.deals).find(dealId('pastry-pair'))!;
      row['pool'] = [
        {
          'menu_item_id': mockUuid('menu-item:gone'),
          'category_id': null,
          'size_label': null,
        },
      ];
      final h = await pumpDeals(
        tester,
        path: _edit('pastry-pair'),
        server: s.server,
        db: s.db,
      );
      expect(inPool(find.text('Choose an item')), findsOneWidget);
      await tapInDialog(h, 'Save');
      expect(bodiesTo(h, 'PUT', itemRoute).single['pool'], [
        {
          'menu_item_id': mockUuid('menu-item:gone'),
          'category_id': null,
          'size_label': null,
        },
      ]);
      // The server refuses it, in the dialog's words.
      await h.expectToast('Check the deal\'s "Items that count".');
    });

    testWidgets('OFFR-DEA-049 PUTs then DELETEs, one at a time; the first '
        'failure stops the rest and keeps the dialog; the saved deal is '
        'refetched (divergence)', (tester) async {
      final s = dealsServer();
      final boom = MockResponse.error(500, 'branch write failed');
      s.server.fail('PUT', branchRoute, boom);
      final h = await pumpDeals(
        tester,
        path: _edit('coffee-cookie-free'),
        server: s.server,
        db: s.db,
      );
      final lists = callsTo(h, 'GET', listRoute).length;
      await choose(h, 'Zamalek', 'Follow the deal');
      await choose(h, 'New Cairo', 'On here');
      await choose(h, 'Heliopolis', 'Off here');
      await tapInDialog(h, 'Save');
      expect(callsTo(h, 'PUT', itemRoute), hasLength(1));
      expect(callsTo(h, 'PUT', branchRoute), hasLength(1));
      expect(callsTo(h, 'DELETE', branchRoute), isEmpty);
      await h.expectToast(h.refusalWords(boom));
      expect(dialog, findsOneWidget);
      expect(callsTo(h, 'GET', listRoute).length, lists + 1);
      expect(
        find.descendant(
          of: labelledSelect('Heliopolis'),
          matching: find.text('Off here'),
        ),
        findsOneWidget,
        reason: 'what was typed stays',
      );
    });
  });

  group('area rules in the dialog', () {
    testWidgets('OFFR-ALL-017 a changed row re-seeds the open dialog', (
      tester,
    ) async {
      final h = await pumpDeals(tester, path: _edit('juice-trio'));
      await typeInto(h, 'Name', 'Half-typed');
      h.db!.table(OffersTables.deals).find(dealId('juice-trio'))!['name'] =
          'Juice trio for 250';
      h.container.read(realtimeBusProvider).invalidate(const ['/deals']);
      await h.settle();
      expect(field(tester, 'Name').value, 'Juice trio for 250');
    });

    testWidgets('OFFR-ALL-017 an unchanged refetch keeps what was typed', (
      tester,
    ) async {
      final h = await pumpDeals(tester, path: _edit('juice-trio'));
      await typeInto(h, 'Name', 'Half-typed');
      h.container.read(realtimeBusProvider).invalidate(const ['/deals']);
      await h.settle();
      expect(field(tester, 'Name').value, 'Half-typed');
    });

    testWidgets('OFFR-ALL-019 Enter in a text field submits', (tester) async {
      final h = await pumpDeals(tester, path: _new);
      await fillNew(h);
      await h.tester.showKeyboard(labelled('Name').first);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(callsTo(h, 'POST', listRoute), hasLength(1));
      await h.expectToast('Deal created');
    });

    testWidgets('OFFR-ALL-019 closing mid-save lets the save finish: toast, '
        'branch calls and the refresh still happen', (tester) async {
      final s = dealsServer();
      final h = await pumpDeals(tester, path: _new, server: s.server, db: s.db);
      await fillNew(h);
      await choose(h, 'Zamalek', 'On here');
      final gate = s.server.hold('POST', listRoute);
      final lists = callsTo(h, 'GET', listRoute).length;
      await tapInDialog(h, 'Create deal');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(dialog, findsNothing);
      gate.release();
      await h.settle();
      expect(callsTo(h, 'PUT', branchRoute), hasLength(1));
      await h.expectToast('Deal created');
      expect(callsTo(h, 'GET', listRoute).length, lists + 1);
      expect(inTable(find.text('Any 2 bites for 90')), findsOneWidget);
    });
  });
}
