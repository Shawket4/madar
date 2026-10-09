// The count editor on New Cairo's open count (started 08:15 by Dina, 9 of 25
// rows counted, House Blend flagged with a reason, Croissant Dough flagged
// without one, Dried Hibiscus new here): the poll, hydration, autosave,
// search and filters, the figures, the flag rule, found items, cancel and
// finalize (INV-CNT-024…048, -055, -057, -059, -060, -063…065).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _minus = '−';
String _id(String key) => InvIds.ingredient(key);

/// New Cairo with its open count, the hydration's own save already out.
Future<DashHarness> pumpOpen(
  WidgetTester tester, {
  ({MockServer server, MockDb db})? s,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool settleSave = true,
}) async {
  final h = await pumpCounts(
    tester,
    server: s?.server,
    db: s?.db,
    size: size,
    locale: locale,
    branch: SeedIds.newCairo,
  );
  if (settleSave) await waitAutosave(h);
  return h;
}

Finder get _finalize => inEditor(byKey('count-finalize'));

/// Every toast on screen.
Finder get _toasts => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_ToastCard',
);
bool _canFinalize(WidgetTester t) =>
    t.widget<DashButton>(_finalize).onPressed != null;

/// The names of the rows shown, top to bottom.
List<String> shownRows(WidgetTester tester) {
  final rows = find.descendant(
    of: inEditor(byKey('count-table')),
    matching: find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('count-row-'),
    ),
  );
  final items = tester.widgetList(rows).toList();
  final byId = {
    for (final i in invIngredients) InvIds.ingredient(i.key): i.name,
  };
  return [
    for (final w in items)
      byId[(w.key! as ValueKey<String>).value.substring('count-row-'.length)] ??
          '?',
  ];
}

Future<void> _filter(DashHarness h, String label) => h.tap(
  find.descendant(
    of: inEditor(byKey('count-filter')),
    matching: find.text(label),
  ),
);

void main() {
  group('header, chrome and states', () {
    testWidgets('INV-CNT-025 Open count, In progress, the start time, '
        'progress; "Saving…" while a save is out', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      expect(inEditor(find.text('Open count')), findsOneWidget);
      final pill = tester.widget<DashStatusPill>(
        inEditor(find.byType(DashStatusPill)).first,
      );
      expect(pill.label, 'In progress');
      expect(pill.tone, DashTone.accent);
      expect(inEditor(find.text('08:15 AM')), findsOneWidget);
      expect(inEditor(find.text('9/25 done')), findsOneWidget);
      final gate = s.server.hold('PUT', itemsRoute);
      await typeCount(h, 'sugar', '1700');
      expect(inEditor(find.text('Saving…')), findsNothing);
      await h.tester.pump(const Duration(milliseconds: 1300));
      await h.settle();
      expect(inEditor(find.text('Saving…')), findsOneWidget);
      gate.release();
      await h.settle();
      expect(inEditor(find.text('Saving…')), findsNothing);
      // Typing into an uncounted row moves the progress.
      await typeCount(h, 'decaf', '470');
      expect(inEditor(find.text('10/25 done')), findsOneWidget);
      await waitAutosave(h);
    });

    testWidgets('INV-CNT-032/063 loading: six skeleton rows inside the '
        'whole chrome; Cancel live, Finalize off', (tester) async {
      final s = countsServer();
      final gate = s.server.hold('GET', getRoute);
      final h = await pumpOpen(tester, s: s, settleSave: false);
      final skeleton = inEditor(byKey('count-loading'));
      expect(
        find.descendant(of: skeleton, matching: find.byType(LayoutBuilder)),
        findsNWidgets(6),
      );
      expect(inEditor(find.text('Open count')), findsOneWidget);
      expect(inEditor(find.text('In progress')), findsOneWidget);
      expect(inEditor(find.text('0/0 done')), findsOneWidget);
      expect(inEditor(find.text('08:15 AM')), findsNothing);
      expect(inEditor(byKey('count-search')), findsOneWidget);
      expect(inEditor(byKey('count-filter')), findsOneWidget);
      expect(inEditor(byKey('count-category')), findsNothing);
      expect(inEditor(byKey('count-add')), findsNothing);
      expect(inEditor(textHas('Book stock keeps moving')), findsOneWidget);
      expect(inEditor(textHas('Net difference EGP 0.00')), findsOneWidget);
      expect(
        tester.widget<DashButton>(inEditor(byKey('count-cancel'))).onPressed,
        isNotNull,
      );
      expect(_canFinalize(tester), isFalse);
      gate.release();
      await h.settle();
      expect(inEditor(byKey('count-table')), findsOneWidget);
      await waitAutosave(h);
    });

    testWidgets('INV-CNT-033/063 error: "Couldn\'t load the open count", no '
        'server words; Retry reads only the count', (tester) async {
      final s = countsServer();
      final boom = MockResponse.error(500, 'Count is resting');
      s.server.fail('GET', getRoute, boom, times: null);
      final h = await pumpOpen(tester, s: s, settleSave: false);
      expect(
        inEditor(find.text("Couldn't load the open count")),
        findsOneWidget,
      );
      expect(inEditor(find.text(h.refusalWords(boom))), findsNothing);
      expect(inEditor(find.text('0/0 done')), findsOneWidget);
      expect(inEditor(textHas('Net difference EGP 0.00')), findsOneWidget);
      expect(_canFinalize(tester), isFalse);
      s.server.clearFailures();
      final before = h.server.calls.length;
      await h.tap(inEditor(find.text('Retry')));
      expect(h.server.calls.sublist(before).map((c) => c.template), [getRoute]);
      expect(inEditor(byKey('count-table')), findsOneWidget);
      await waitAutosave(h);
    });

    testWidgets('INV-CNT-033 a failed poll keeps the rows', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      s.server.fail('GET', getRoute, MockResponse.error(500, 'blip'));
      await h.tester.pump(const Duration(seconds: 30));
      await h.settle();
      expect(h.server.callsTo(getRoute), hasLength(2));
      expect(inEditor(byKey('count-table')), findsOneWidget);
      expect(inEditor(find.text("Couldn't load the open count")), findsNothing);
    });

    testWidgets('INV-CNT-034/063 nothing to count: the empty state and "New '
        'ingredient" to Ingredients; the chrome stays', (tester) async {
      final s = countsServer();
      s.db[InvTables.stocktakeItems].removeWhere(
        (i) => i['stocktake_id'] == openNewCairo,
      );
      final h = await pumpOpen(tester, s: s);
      expect(inEditor(find.text('Nothing to count yet')), findsOneWidget);
      expect(
        inEditor(
          find.text(
            'This organization has no ingredients in its catalog. Add '
            'ingredients first, then count them here.',
          ),
        ),
        findsOneWidget,
      );
      expect(inEditor(find.text('0/0 done')), findsOneWidget);
      expect(_canFinalize(tester), isFalse);
      expect(h.server.callsTo(itemsRoute), isEmpty, reason: 'nothing counted');
      await h.tap(inEditor(find.text('New ingredient')));
      expect(h.location.path, '/inventory/ingredients');
    });

    testWidgets('INV-CNT-043 the sales footnote', (tester) async {
      await pumpOpen(tester);
      expect(
        inEditor(
          find.text(
            'Book stock keeps moving while you count. Finalizing compares '
            'your counts with book stock at that moment, so sales during the '
            'count are not treated as shrinkage.',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('rows and figures', () {
    testWidgets('INV-CNT-035/055 the columns, the server\'s order, the pills, '
        'book stock and "was … at start"', (tester) async {
      await pumpOpen(tester);
      for (final c in [
        'INGREDIENT',
        'BOOK STOCK',
        'COUNTED',
        'DIFFERENCE',
        'VALUE',
        'REASON',
      ]) {
        expect(inEditor(find.text(c)), findsOneWidget, reason: c);
      }
      final names = shownRows(tester);
      expect(names, hasLength(25));
      expect(names.take(5), [
        'Ice Cubes',
        'Decaf Beans',
        'Ethiopia Single Origin Beans',
        'House Blend Beans',
        'Turkish Coffee Ground',
      ]);
      expect(names.last, 'Paper Cup 12oz');
      expect(inRow('croissant', find.text('Flagged')), findsOneWidget);
      expect(inRow('croissant', find.text('Bakery')), findsOneWidget);
      expect(inRow('croissant', find.text('48 pcs')), findsOneWidget);
      expect(
        inRow('croissant', textHas('was ${ltr('54')} at start')),
        findsOneWidget,
      );
      expect(inRow('hibiscus', find.text('New here')), findsOneWidget);
      expect(inRow('hibiscus', find.text('0 g')), findsOneWidget);
      expect(inRow('hibiscus', textHas('at start')), findsNothing);
      expect(inRow('oat', find.text('Flagged')), findsNothing);
    });

    testWidgets('INV-CNT-026 hydration: the saved figures and reasons, once; '
        'a later poll never overwrites what is typed', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      expect(inputOf(tester, countInput('house-blend')).value, '2100');
      expect(inputOf(tester, countInput('croissant')).value, '37');
      expect(inputOf(tester, countInput('decaf')).value, '');
      final reason = tester.widget<DashSelect<String>>(
        inEditor(byKey('count-reason-${_id('house-blend')}')),
      );
      expect(reason.value, 'miscount');
      await typeCount(h, 'oat', '6300');
      // Meanwhile the server's figures change (another device).
      itemRow(s.db, openNewCairo, 'oat')['counted_qty'] = 1.0;
      itemRow(s.db, openNewCairo, 'decaf')['counted_qty'] = 2.0;
      await h.tester.pump(const Duration(seconds: 30));
      await h.settle();
      expect(inputOf(tester, countInput('oat')).value, '6300');
      expect(inputOf(tester, countInput('decaf')).value, '');
    });

    testWidgets('INV-CNT-026 (divergence) until the first edit here, a poll '
        'brings in figures saved elsewhere, without saving', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      final saves = h.server.callsTo(itemsRoute).length;
      itemRow(s.db, openNewCairo, 'decaf')['counted_qty'] = 465.0;
      await h.tester.pump(const Duration(seconds: 30));
      await h.settle();
      expect(inputOf(tester, countInput('decaf')).value, '465');
      await waitAutosave(h);
      expect(h.server.callsTo(itemsRoute), hasLength(saves));
      // Once something is typed here, polls leave the figures alone.
      await typeCount(h, 'oat', '6300');
      itemRow(s.db, openNewCairo, 'turkish')['counted_qty'] = 1.0;
      await h.tester.pump(const Duration(seconds: 30));
      await h.settle();
      expect(inputOf(tester, countInput('turkish')).value, '');
    });

    testWidgets('INV-CNT-024 the open count is read again every 30 s: book '
        'stock and the flags follow', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      expect(h.server.callsTo(getRoute), hasLength(1));
      expect(_canFinalize(tester), isFalse);
      // A delivery lands: Croissant's book drops to 38, so 37 is within 5%.
      stockRow(s.db, SeedIds.newCairo, 'croissant')!['on_hand'] = 38.0;
      await h.tester.pump(const Duration(seconds: 25));
      await h.settle();
      expect(h.server.callsTo(getRoute), hasLength(1));
      await h.tester.pump(const Duration(seconds: 5));
      await h.settle();
      expect(h.server.callsTo(getRoute), hasLength(2));
      expect(inRow('croissant', find.text('38 pcs')), findsOneWidget);
      expect(inRow('croissant', find.text('Flagged')), findsNothing);
      expect(inEditor(textHas('need a reason')), findsNothing);
      expect(_canFinalize(tester), isTrue);
      // The poll alone never saves.
      expect(h.server.callsTo(itemsRoute), hasLength(1));
    });

    testWidgets('INV-CNT-036/037/038 typing a figure: the difference, signed '
        'and coloured, and its value; blank or "." is not counted', (
      tester,
    ) async {
      final h = await pumpOpen(tester);
      await typeCount(h, 'decaf', '480');
      final up = tester.widget<Text>(inRow('decaf', find.text('+10')));
      expect(
        up.style!.color,
        DashTone.success.foreground(tester.element(editor).madarColors),
      );
      expect(inRow('decaf', find.text('EGP 11.00')), findsOneWidget);
      await typeCount(h, 'decaf', '450');
      expect(inRow('decaf', find.text('${_minus}20')), findsOneWidget);
      expect(inRow('decaf', find.text('${_minus}EGP 22.00')), findsOneWidget);
      await typeCount(h, 'decaf', '470');
      expect(inRow('decaf', find.text('0')), findsOneWidget);
      await typeCount(h, 'decaf', '');
      expect(inRow('decaf', find.text('not counted')), findsOneWidget);
      expect(inRow('decaf', find.text('—')), findsNWidgets(2));
      await typeCount(h, 'decaf', '.');
      expect(inRow('decaf', find.text('not counted')), findsOneWidget);
      // Letters never get in (a number input).
      await typeCount(h, 'decaf', '4a8');
      expect(inputOf(tester, countInput('decaf')).value, '48');
      await waitAutosave(h);
    });

    testWidgets('INV-CNT-036 the input names its ingredient', (tester) async {
      await pumpOpen(tester);
      expect(
        inputOf(tester, countInput('oat')).semanticLabel,
        'Counted Oat Milk',
      );
    });

    testWidgets('INV-CNT-038 no cost: the value is "—"', (tester) async {
      final h = await pumpOpen(tester);
      await typeCount(h, 'hibiscus', '5');
      expect(inRow('hibiscus', find.text('+5')), findsOneWidget);
      expect(inRow('hibiscus', find.text('—')), findsOneWidget);
      await waitAutosave(h);
    });

    testWidgets('INV-CNT-039/040 the flag rule: 5% of book (the count\'s '
        'threshold), or stock out of nothing; a warning wash and a reason '
        'list, red while empty', (tester) async {
      final h = await pumpOpen(tester);
      // Decaf: book 470. 446 is over 5% under: flagged; 447 is not.
      await typeCount(h, 'decaf', '447');
      expect(inRow('decaf', find.text('Flagged')), findsNothing);
      expect(inEditor(byKey('count-reason-${_id('decaf')}')), findsNothing);
      await typeCount(h, 'decaf', '446');
      expect(inRow('decaf', find.text('Flagged')), findsOneWidget);
      // Book 0: any figure is flagged.
      await typeCount(h, 'hibiscus', '1');
      expect(inRow('hibiscus', find.text('Flagged')), findsOneWidget);
      final select = tester.widget<DashSelect<String>>(
        inEditor(byKey('count-reason-${_id('hibiscus')}')),
      );
      expect(select.invalid, isTrue);
      expect(select.placeholder, 'Reason');
      expect(select.options.map((o) => o.label), [
        'Theft',
        'Spoilage',
        'Breakage',
        'Miscount',
        'Supplier short',
        'Transfer error',
        'Other',
      ]);
      final row = tester.widget<Container>(editorRow('hibiscus'));
      expect((row.decoration! as BoxDecoration).color, isNotNull);
      final plain = tester.widget<Container>(editorRow('oat'));
      expect((plain.decoration! as BoxDecoration).color, isNull);
      await pick(
        h,
        inEditor(byKey('count-reason-${_id('hibiscus')}')),
        'Other',
      );
      expect(
        tester
            .widget<DashSelect<String>>(
              inEditor(byKey('count-reason-${_id('hibiscus')}')),
            )
            .invalid,
        isFalse,
      );
      await waitAutosave(h);
    });

    testWidgets('INV-CNT-044 the net difference and the reasons still due', (
      tester,
    ) async {
      final h = await pumpOpen(tester);
      // House Blend −300 × 90, Croissant −11 × 900, Oat +130 × 12, Cup Lid
      // +6 × 60: −34,980 piastres.
      expect(
        inEditor(textHas('Net difference ${_minus}EGP 349.80')),
        findsOneWidget,
      );
      expect(inEditor(textHas('1 need a reason')), findsOneWidget);
      await typeCount(h, 'oat', '7000');
      // Oat now +740 × 12 = 8,880: −27,660; and Oat is flagged too.
      expect(
        inEditor(textHas('Net difference ${_minus}EGP 276.60')),
        findsOneWidget,
      );
      expect(inEditor(textHas('2 need a reason')), findsOneWidget);
      await typeCount(h, 'house-blend', '3000');
      await typeCount(h, 'croissant', '48');
      await typeCount(h, 'oat', '6260');
      // +600 × 90 + 360 = +54,360.
      expect(inEditor(textHas('Net difference +EGP 543.60')), findsOneWidget);
      expect(inEditor(textHas('need a reason')), findsNothing);
      await waitAutosave(h);
    });
  });

  group('search and filters', () {
    testWidgets('INV-CNT-028 search: any case, part of the name', (
      tester,
    ) async {
      final h = await pumpOpen(tester);
      await h.enterText(inEditor(byKey('count-search')), 'MILK');
      expect(shownRows(tester), [
        'Almond Milk',
        'Full Cream Milk',
        'Oat Milk',
        'Skimmed Milk',
      ]);
      await h.enterText(inEditor(byKey('count-search')), '   ');
      expect(shownRows(tester), hasLength(25));
    });

    testWidgets('INV-CNT-042 nothing matches: "No results found"', (
      tester,
    ) async {
      final h = await pumpOpen(tester);
      await h.enterText(inEditor(byKey('count-search')), 'zzz');
      expect(inEditor(find.text('No results found')), findsOneWidget);
      expect(shownRows(tester), isEmpty);
    });

    testWidgets('INV-CNT-029 the category list: All categories and each '
        'category the rows span', (tester) async {
      final h = await pumpOpen(tester);
      final select = tester.widget<DashSelect<String?>>(
        inEditor(byKey('count-category')),
      );
      expect(select.options.map((o) => o.label), [
        'All categories',
        'General',
        'Coffee Beans',
        'Milk',
        'Dairy & Eggs',
        'Syrups & Sauces',
        'Dry Goods',
        'Bakery',
        'Packaging',
      ]);
      await pick(h, inEditor(byKey('count-category')), 'Milk');
      expect(shownRows(tester), [
        'Almond Milk',
        'Full Cream Milk',
        'Oat Milk',
        'Skimmed Milk',
      ]);
      await pick(h, inEditor(byKey('count-category')), 'All categories');
      expect(shownRows(tester), hasLength(25));
    });

    testWidgets('INV-CNT-029 one category only: no list', (tester) async {
      final s = countsServer();
      s.db[InvTables.stocktakeItems].removeWhere(
        (i) =>
            i['stocktake_id'] == openNewCairo &&
            i['category_id'] != InvIds.category('milk'),
      );
      await pumpOpen(tester, s: s);
      expect(inEditor(byKey('count-category')), findsNothing);
      expect(shownRows(tester), hasLength(4));
    });

    testWidgets('INV-CNT-030/055 To count, Counted, Flagged — in the '
        'server\'s order', (tester) async {
      final h = await pumpOpen(tester);
      await _filter(h, 'To count');
      expect(shownRows(tester), hasLength(16));
      await _filter(h, 'Counted');
      expect(shownRows(tester), [
        'House Blend Beans',
        'Full Cream Milk',
        'Oat Milk',
        'Skimmed Milk',
        'Vanilla Syrup',
        'Sugar',
        'Croissant Dough',
        'Cup Lid',
        'Paper Cup 12oz',
      ]);
      await _filter(h, 'Flagged');
      expect(shownRows(tester), ['House Blend Beans', 'Croissant Dough']);
      await _filter(h, 'All');
      expect(shownRows(tester), hasLength(25));
    });
  });

  group('autosave', () {
    testWidgets('INV-CNT-064 hydration sends the saved figures back once, '
        '1.2 s after the load; polls never save', (tester) async {
      final h = await pumpOpen(tester, settleSave: false);
      expect(h.server.callsTo(itemsRoute), isEmpty);
      await waitAutosave(h);
      final put = h.server.callsTo(itemsRoute, method: 'PUT').single;
      expect(put.path, '/stocktakes/$openNewCairo/items');
      final items = (put.body! as Map)['items']! as List;
      expect(items, hasLength(9));
      expect(items.first, {
        'counted_qty': 2100,
        'org_ingredient_id': _id('house-blend'),
        'variance_reason': 'miscount',
      });
      expect(
        items.firstWhere(
          (i) => (i as Map)['org_ingredient_id'] == _id('croissant'),
        ),
        {
          'counted_qty': 37,
          'org_ingredient_id': _id('croissant'),
          'variance_reason': null,
        },
      );
      await h.tester.pump(const Duration(seconds: 61));
      await h.settle();
      expect(h.server.callsTo(itemsRoute), hasLength(1));
    });

    testWidgets('INV-CNT-064 nothing counted yet: no hydration save', (
      tester,
    ) async {
      final s = countsServer();
      for (final i in s.db[InvTables.stocktakeItems].where(
        (i) => i['stocktake_id'] == openNewCairo,
      )) {
        i['counted_qty'] = null;
        i['variance_reason'] = null;
      }
      final h = await pumpOpen(tester, s: s);
      expect(h.server.callsTo(itemsRoute), isEmpty);
      expect(inEditor(find.text('0/25 done')), findsOneWidget);
    });

    testWidgets('INV-CNT-041 1.2 s after the last change, every counted row '
        'with its reason; one save at a time', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      await typeCount(h, 'decaf', '46');
      await h.tester.pump(const Duration(milliseconds: 800));
      await typeCount(h, 'decaf', '460');
      await h.tester.pump(const Duration(milliseconds: 800));
      expect(h.server.callsTo(itemsRoute), hasLength(1), reason: 'debounced');
      final gate = s.server.hold('PUT', itemsRoute);
      await h.tester.pump(const Duration(milliseconds: 500));
      await h.settle();
      expect(h.server.callsTo(itemsRoute), hasLength(2));
      final items = (lastBody(h, itemsRoute, 'PUT')! as Map)['items']! as List;
      expect(items, hasLength(10));
      expect(
        items.firstWhere(
          (i) => (i as Map)['org_ingredient_id'] == _id('decaf'),
        ),
        {
          'counted_qty': 460,
          'org_ingredient_id': _id('decaf'),
          'variance_reason': null,
        },
      );
      // A change while that save is out waits for it.
      await typeCount(h, 'turkish', '990');
      await waitAutosave(h);
      expect(h.server.callsTo(itemsRoute), hasLength(2));
      gate.release();
      await h.settle();
      expect(h.server.callsTo(itemsRoute), hasLength(3));
      expect(
        ((lastBody(h, itemsRoute, 'PUT')! as Map)['items']! as List),
        hasLength(11),
      );
      expect(itemRow(s.db, openNewCairo, 'turkish')['counted_qty'], 990);
    });

    testWidgets('INV-CNT-041/036/060 a refused save toasts the server\'s '
        'words and stays due: a negative figure, a closed count', (
      tester,
    ) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      await typeCount(h, 'decaf', '-5');
      expect(inRow('decaf', find.text('${_minus}475')), findsOneWidget);
      expect(inRow('decaf', find.text('Flagged')), findsOneWidget);
      await waitAutosave(h);
      await h.expectToast(
        h.refusalWords(MockResponse.badRequest('counted_qty cannot be negative')),
      );
      // Still due: the next edit sends it again (fixed now).
      await typeCount(h, 'decaf', '470');
      await waitAutosave(h);
      expect(itemRow(s.db, openNewCairo, 'decaf')['counted_qty'], 470);
      // Finalized elsewhere meanwhile.
      s.db[InvTables.stocktakes].find(openNewCairo)!['status'] = 'finalized';
      await typeCount(h, 'decaf', '471');
      await waitAutosave(h);
      await h.expectToast(
        h.refusalWords(
          MockResponse.conflict(
            'Cannot edit counts on a finalized or cancelled stocktake',
          ),
        ),
      );
    });

    testWidgets('INV-CNT-059 a save refused for the capability is the '
        'server\'s words; nothing is hidden', (tester) async {
      final s = countsServer();
      final denied = MockResponse.denied('inventory.counts.edit');
      final h = await pumpOpen(tester, s: s);
      s.server.fail('PUT', itemsRoute, denied);
      await typeCount(h, 'decaf', '470');
      await waitAutosave(h);
      await h.expectToast(h.refusalWords(denied));
      expect(inEditor(byKey('count-cancel')), findsOneWidget);
      expect(inEditor(byKey('count-finalize')), findsOneWidget);
    });

    testWidgets('INV-CNT-041 (divergence) leaving the page with a save due '
        'still sends it', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      await typeCount(h, 'decaf', '455');
      await h.go('/inventory/today');
      h.allowUnmatched = true;
      await h.settle();
      expect(itemRow(s.db, openNewCairo, 'decaf')['counted_qty'], 455);
    });
  });

  group('divergences', () {
    testWidgets('INV-CNT-007 (divergence) another branch\'s open count gets '
        'its own editor: its own figures, never this one\'s', (tester) async {
      final s = countsServer();
      final api = DashboardApi(s.server);
      final other = await api.stocktakes.createStocktake(
        branchId: SeedIds.zamalek,
        body: CreateStocktakeRequest(orgIngredientIds: [_id('oat')]),
      );
      await api.stocktakes.upsertItems(
        id: other.id,
        body: UpsertItemsRequest(
          items: [ItemCountInput(orgIngredientId: _id('oat'), countedQty: 11)],
        ),
      );
      s.server.calls.clear();
      final h = await pumpOpen(tester, s: s);
      await typeCount(h, 'decaf', '460');
      await h.container.read(scopeProvider.notifier).setBranch(SeedIds.zamalek);
      await h.settle();
      expect(inputOf(tester, countInput('oat')).value, '11');
      await waitAutosave(h);
      final toOther = [
        for (final c in h.server.callsTo(itemsRoute))
          if (c.path == '/stocktakes/${other.id}/items') c,
      ];
      for (final c in toOther) {
        final ids = [
          for (final i in (c.body! as Map)['items']! as List)
            (i as Map)['org_ingredient_id'],
        ];
        expect(ids, [_id('oat')], reason: 'only its own rows');
      }
      // New Cairo's due figure went to New Cairo's count.
      expect(itemRow(s.db, openNewCairo, 'decaf')['counted_qty'], 460);
    });

    testWidgets('INV-CNT-041 (divergence) Finalize waits for every save in '
        'flight, also one that started while it was waiting', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      await pick(
        h,
        inEditor(byKey('count-reason-${_id('croissant')}')),
        'Spoilage',
      );
      await waitAutosave(h);
      final first = s.server.hold('PUT', itemsRoute);
      await typeCount(h, 'decaf', '460');
      await waitAutosave(h); // a save goes out and hangs
      await typeCount(h, 'decaf', '461');
      await waitAutosave(h); // the next one waits behind it
      await h.tap(_finalize); // so does Finalize
      final second = s.server.hold('PUT', itemsRoute);
      first.release();
      await h.settle();
      expect(h.server.callsTo(finalizeRoute), isEmpty);
      second.release();
      await h.settle();
      expect(h.server.callsTo(finalizeRoute), hasLength(1));
      expect(itemRow(s.db, openNewCairo, 'decaf')['counted_qty'], 461);
    });

    testWidgets('INV-CNT-045 (divergence) a confirmed cancel drops the save '
        'still due (no 409 toast after it)', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      await typeCount(h, 'decaf', '460');
      await h.tap(inEditor(byKey('count-cancel')));
      await h.tap(find.text('Cancel stocktake').last);
      await waitAutosave(h);
      expect(
        [
          for (final c in h.server.callsTo(itemsRoute))
            if (c.status != 200) c,
        ],
        isEmpty,
      );
      expect(_toasts, findsNothing);
    });
  });

  group('found items', () {
    testWidgets('INV-CNT-031 a cycle count offers the rest of the catalog; a '
        'pick joins the end of the list as new here and saves with the next '
        'figure', (tester) async {
      final s = countsServer();
      final st = s.db[InvTables.stocktakes].find(openNewCairo)!;
      st['scope'] = {'kind': 'category', 'category_id': InvIds.category('milk')};
      s.db[InvTables.stocktakeItems].removeWhere(
        (i) =>
            i['stocktake_id'] == openNewCairo &&
            i['category_id'] != InvIds.category('milk'),
      );
      final h = await pumpOpen(tester, s: s);
      expect(h.server.callsTo(catalogRoute), hasLength(1));
      final picker = tester.widget<DashSelect<String>>(
        inEditor(byKey('count-add')),
      );
      expect(picker.placeholder, 'Add an item…');
      expect(picker.options.map((o) => o.label), isNot(contains('Oat Milk')));
      expect(
        picker.options.firstWhere((o) => o.label == 'Sugar').hint,
        'Dry Goods',
      );
      await pickSearch(h, inEditor(byKey('count-add')), 'Sugar');
      expect(shownRows(tester).last, 'Sugar');
      expect(inRow('sugar', find.text('New here')), findsOneWidget);
      expect(inRow('sugar', find.text('0 g')), findsOneWidget);
      expect(inEditor(find.text('3/5 done')), findsOneWidget);
      expect(h.server.callsTo(itemsRoute), hasLength(1), reason: 'not yet');
      // Book 0: counting it flags it; its value uses the catalog's cost.
      await typeCount(h, 'sugar', '100');
      expect(inRow('sugar', find.text('EGP 3.50')), findsOneWidget);
      await pick(h, inEditor(byKey('count-reason-${_id('sugar')}')), 'Other');
      await waitAutosave(h);
      final items = (lastBody(h, itemsRoute, 'PUT')! as Map)['items']! as List;
      expect(items.last, {
        'counted_qty': 100,
        'org_ingredient_id': _id('sugar'),
        'variance_reason': 'other',
      });
      // The next read holds it: still one row.
      await h.tester.pump(const Duration(seconds: 30));
      await h.settle();
      expect(
        shownRows(tester).where((n) => n == 'Sugar'),
        hasLength(1),
      );
      expect(
        tester
            .widget<DashSelect<String>>(inEditor(byKey('count-add')))
            .options
            .map((o) => o.label),
        isNot(contains('Sugar')),
      );
    });

    testWidgets('INV-CNT-031 a whole-branch count: no picker, no catalog '
        'read', (tester) async {
      final h = await pumpOpen(tester);
      expect(inEditor(byKey('count-add')), findsNothing);
      expect(h.server.callsTo(catalogRoute), isEmpty);
    });

    testWidgets('INV-CNT-027 the new-here banner counts the new rows; none '
        'new, no banner', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      expect(
        inEditor(
          find.text(
            '1 ingredients have never been counted or moved at this branch. '
            'Counting them is what starts tracking them here.',
          ),
        ),
        findsOneWidget,
      );
      itemRow(s.db, openNewCairo, 'hibiscus')['is_new'] = false;
      await h.tester.pump(const Duration(seconds: 30));
      await h.settle();
      expect(inEditor(byKey('count-new-here')), findsNothing);
    });
  });

  group('cancel', () {
    testWidgets('INV-CNT-045 confirm, then the count is cancelled and the '
        'editor goes, with no toast', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      await h.tap(inEditor(byKey('count-cancel')));
      expect(find.text('Discard this count?'), findsOneWidget);
      expect(
        find.text(
          'Every figure entered in this open count is thrown away. Book '
          'stock stays as it is.',
        ),
        findsOneWidget,
      );
      final dialog = tester.widget<DashConfirmDialog>(
        find.byType(DashConfirmDialog),
      );
      expect(dialog.destructive, isTrue);
      // Cancel: nothing happens.
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Cancel'),
        ),
      );
      expect(h.server.callsTo(cancelRoute), isEmpty);
      expect(editor, findsOneWidget);
      // Confirm.
      final lists = h.server.callsTo(listRoute).length;
      await h.tap(inEditor(byKey('count-cancel')));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Cancel stocktake'),
        ),
      );
      expect(
        h.server.callsTo(cancelRoute).single.path,
        '/stocktakes/$openNewCairo/cancel',
      );
      expect(h.server.callsTo(listRoute).length, greaterThan(lists));
      expect(editor, findsNothing);
      expect(inPage(find.text('Start a count')), findsOneWidget);
      expect(_toasts, findsNothing);
      expect(s.db[InvTables.stocktakes].find(openNewCairo)!['status'], 'cancelled');
    });

    testWidgets('INV-CNT-045 a refused cancel is a toast; the editor stays', (
      tester,
    ) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      final denied = MockResponse.denied('inventory.counts.edit');
      s.server.fail('POST', cancelRoute, denied);
      await h.tap(inEditor(byKey('count-cancel')));
      await h.tap(find.text('Cancel stocktake').last);
      await h.expectToast(h.refusalWords(denied));
      expect(editor, findsOneWidget);
    });
  });

  group('finalize', () {
    testWidgets('INV-CNT-046/047 off while a flagged row has no reason; with '
        'one: the figures are saved first, then finalized; the report '
        'opens and the editor goes, no toast', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      expect(_canFinalize(tester), isFalse);
      await pick(
        h,
        inEditor(byKey('count-reason-${_id('croissant')}')),
        'Spoilage',
      );
      expect(_canFinalize(tester), isTrue);
      final before = h.server.calls.length;
      await h.tap(_finalize);
      final after = [
        for (final c in h.server.calls.sublist(before))
          if (c.method != 'GET') '${c.method} ${c.template}',
      ];
      expect(after, ['PUT $itemsRoute', 'POST $finalizeRoute']);
      expect(
        ((lastBody(h, itemsRoute, 'PUT')! as Map)['items']! as List)
            .firstWhere(
              (i) => (i as Map)['org_ingredient_id'] == _id('croissant'),
            ),
        {
          'counted_qty': 37,
          'org_ingredient_id': _id('croissant'),
          'variance_reason': 'spoilage',
        },
      );
      expect(report, findsOneWidget);
      expect(
        h.server.callsTo(reportRoute).single.path,
        '/stocktakes/$openNewCairo/variance-report',
      );
      expect(editor, findsNothing);
      expect(_toasts, findsNothing);
      expect(
        s.db[InvTables.stocktakes].find(openNewCairo)!['status'],
        'finalized',
      );
    });

    testWidgets('INV-CNT-048 the server\'s 409 (the book moved since the '
        'last read) is the toast; the editor stays', (tester) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      await pick(
        h,
        inEditor(byKey('count-reason-${_id('croissant')}')),
        'Spoilage',
      );
      stockRow(s.db, SeedIds.newCairo, 'oat')!['on_hand'] = 5000.0;
      await h.tap(_finalize);
      await h.expectToast(
        h.refusalWords(
          MockResponse.conflict(
            'These items have a large difference and need a reason before '
            'finalizing: Oat Milk',
          ),
        ),
      );
      expect(editor, findsOneWidget);
      expect(report, findsNothing);
    });

    testWidgets('INV-CNT-048 a failed pre-save: finalize is not sent', (
      tester,
    ) async {
      final s = countsServer();
      final h = await pumpOpen(tester, s: s);
      await pick(
        h,
        inEditor(byKey('count-reason-${_id('croissant')}')),
        'Spoilage',
      );
      s.server.fail('PUT', itemsRoute, MockResponse.error(500, 'nope'));
      await h.tester.pump(const Duration(milliseconds: 100));
      await h.tap(_finalize);
      expect(h.server.callsTo(finalizeRoute), isEmpty);
      await h.flushTimers();
      expect(editor, findsOneWidget);
      expect(tester.widget<DashButton>(_finalize).loading, isFalse);
    });

    testWidgets('INV-CNT-065 nothing counted: no save, straight to finalize', (
      tester,
    ) async {
      final h = await pumpCounts(tester, branch: SeedIds.heliopolis);
      await h.tap(inPage(byKey('counts-first-run')));
      await h.tap(inScope(byKey('count-scope-start')));
      await h.flushTimers();
      expect(editor, findsOneWidget);
      expect(_canFinalize(tester), isTrue);
      await h.tap(_finalize);
      expect(h.server.callsTo(itemsRoute), isEmpty);
      expect(h.server.callsTo(finalizeRoute), hasLength(1));
      expect(report, findsOneWidget);
    });
  });

  testWidgets('INV-CNT-057 phone: the toolbar wraps with a full-width search, '
      'the table scrolls sideways, the footer wraps', (tester) async {
    final h = await pumpOpen(tester, size: DashSize.phone, locale: 'ar');
    final search = tester.getSize(inEditor(byKey('count-search')));
    final toolbar = tester.getSize(inEditor(byKey('count-toolbar')));
    expect(search.width, closeTo(toolbar.width, 1));
    expect(
      find.descendant(
        of: inEditor(byKey('count-table')),
        matching: find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
    final cancel = tester.getTopLeft(inEditor(byKey('count-cancel')));
    final net = tester.getTopLeft(inEditor(byKey('count-net')));
    expect(cancel.dy, greaterThan(net.dy));
    await typeCount(h, 'decaf', '470');
    expect(inEditor(find.text('10/25 تم')), findsOneWidget);
    await waitAutosave(h);
  });
}
