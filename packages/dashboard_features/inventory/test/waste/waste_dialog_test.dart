// The Record waste dialog (INV-WST-014…023, -031), from the Waste log, from
// Today's "Log waste" (INV-TOD-030) and from the ingredient drawer
// (INV-ING-046), each driven end to end against the mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/ingredients/ingredient_drawer.dart';
import 'package:dashboard_inventory/src/today/today_parts.dart';
import 'package:dashboard_inventory/src/waste/waste_dialog.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String createRoute = '/inventory/branches/{branch_id}/waste';

Finder get ingredientPicker => inDialog(
  find.descendant(
    of: byKey('waste-ingredient'),
    matching: find.byType(DashSelectTrigger),
  ),
);
Finder get reasonPicker => inDialog(
  find.descendant(
    of: byKey('waste-reason'),
    matching: find.byType(DashSelectTrigger),
  ),
);
Finder get qtyField => inDialog(byKey('waste-quantity'));
Finder get noteField => inDialog(byKey('waste-note'));

/// Opens the dialog from the Waste log at [branch].
Future<DashHarness> openFromLog(
  WidgetTester tester, {
  String branch = 'zamalek',
  MockServer? server,
  MockDb? db,
  DashSize size = DashSize.desktop,
}) async {
  final id = switch (branch) {
    'heliopolis' => SeedIds.heliopolis,
    _ => SeedIds.zamalek,
  };
  final h = await pumpWaste(
    tester,
    branch: id,
    server: server,
    db: db,
    size: size,
  );
  await h.tap(inPage(byKey('waste-record')));
  expect(dialog, findsOneWidget);
  return h;
}

/// The POST bodies sent so far.
List<Object?> posted(DashHarness h) => [
  for (final c in h.server.callsTo(createRoute, method: 'POST')) c.body,
];

void main() {
  testWidgets('INV-TOD-030 / INV-WST-014…021 from Today: pick, type, record; '
      'the waste lands in the log and Today shows it', (tester) async {
    final h = await pumpWaste(
      tester,
      path: '/inventory/today',
      branch: SeedIds.zamalek,
    );
    final stockReads = h.server.callsTo(stockRoute).length;
    await h.tap(byKey('today-log-waste'));
    expect(dialog, findsOneWidget);
    // INV-WST-014: the title, the reset fields, the default reason.
    expect(inDialog(find.text('Record waste')), findsNWidgets(2));
    expect(inDialog(find.text('Waste log')), findsOneWidget);
    expect(inDialog(find.text('Pick an ingredient')), findsOneWidget);
    expect(inDialog(find.text('Expired')), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
    // The stock is Today's own read of the branch (one cache).
    expect(h.server.callsTo(stockRoute).length, stockReads);

    await pickSearch(h, ingredientPicker, 'Matcha Powder');
    // INV-WST-017
    expect(inDialog(find.text('80 g on hand')), findsOneWidget);
    // INV-WST-018: more than on hand.
    await h.enterText(qtyField, '100');
    expect(inDialog(find.text('More than on hand')), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
    await h.enterText(qtyField, '20');
    expect(inDialog(find.text('More than on hand')), findsNothing);
    // INV-WST-019 / -020
    await pick(h, reasonPicker, 'Spoiled');
    await h.enterText(noteField, '  Dropped the tin  ');
    expect(submitButton(tester).onPressed, isNotNull);

    final logReads = h.server.callsTo(logRoute).length;
    await h.tap(inDialog(byKey('waste-submit')));
    // INV-WST-021
    expect(posted(h), [
      {
        'note': 'Dropped the tin',
        'org_ingredient_id': InvIds.ingredient('matcha'),
        'quantity': 20,
        'reason': 'spoiled',
      },
    ]);
    expect(
      h.server.callsTo(createRoute, method: 'POST').single.path,
      '/inventory/branches/${SeedIds.zamalek}/waste',
    );
    await h.expectToast('Waste recorded');
    expect(dialog, findsNothing);
    expect(stockRow(h.db!, SeedIds.zamalek, 'matcha')!['on_hand'], 60);
    // Inventory invalidated: Today's reads ask again and show it.
    expect(h.server.callsTo(logRoute).length, greaterThan(logReads));
    expect(h.server.callsTo(stockRoute).length, greaterThan(stockReads));
    final todays = find.descendant(
      of: find.byType(TodayWasteSection),
      matching: find.text('Matcha Powder'),
    );
    expect(todays, findsOneWidget);
    final line = tester
        .widgetList<DashListRow>(
          find.descendant(
            of: find.byType(TodayWasteSection),
            matching: find.byType(DashListRow),
          ),
        )
        .firstWhere((r) => r.title == 'Matcha Powder');
    expect(line.value, '20 g');
    expect(line.meta, 'Spoiled');

    // The Waste log has it too, first, as typed here.
    await h.go(wastePath);
    expect(inTable(find.text('Matcha Powder')), findsNWidgets(2));
    expect(inTable(find.text('Nour El-Sayed')), findsOneWidget);
  });

  testWidgets('INV-ING-046 from the ingredient drawer: the ingredient '
      'preset; recorded end to end', (tester) async {
    final h = await pumpWaste(
      tester,
      path: '/inventory/ingredients',
      branch: SeedIds.zamalek,
    );
    final onHand =
        (stockRow(h.db!, SeedIds.zamalek, 'almond')!['on_hand']! as num)
            .toDouble();
    final ingredients = find.byKey(const ValueKey('ingredients-table'));
    await h.enterText(
      find.descendant(of: ingredients, matching: find.byType(DashSearchInput)),
      'Almond Milk',
    );
    await h.tap(
      find.descendant(
        of: ingredients,
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Almond Milk',
        ),
      ),
    );
    await h.tap(
      find.descendant(
        of: find.byType(IngredientDrawer),
        matching: byKey('ingredient-drawer-waste'),
      ),
    );
    expect(dialog, findsOneWidget);
    expect(inDialog(find.text('Almond Milk')), findsOneWidget);
    final figure = h.container.read(formatProvider).fmtNumber(onHand);
    expect(inDialog(find.text('$figure ml on hand')), findsOneWidget);
    await h.enterText(qtyField, '100');
    await h.tap(inDialog(byKey('waste-submit')));
    expect(posted(h), [
      {
        'note': null,
        'org_ingredient_id': InvIds.ingredient('almond'),
        'quantity': 100,
        'reason': 'expired',
      },
    ]);
    await h.expectToast('Waste recorded');
    expect(
      stockRow(h.db!, SeedIds.zamalek, 'almond')!['on_hand'],
      onHand - 100,
    );
  });

  testWidgets('INV-WST-014 each opening starts blank', (tester) async {
    final h = await openFromLog(tester);
    await pickSearch(h, ingredientPicker, 'Matcha Powder');
    await h.enterText(qtyField, '5');
    await pick(h, reasonPicker, 'Theft');
    await h.tap(inDialog(byKey('waste-cancel')));
    await h.tap(inPage(byKey('waste-record')));
    expect(inDialog(find.text('Pick an ingredient')), findsOneWidget);
    expect(inDialog(find.text('Expired')), findsOneWidget);
    expect(
      tester.widget<DashTextInput>(
        find.descendant(of: qtyField, matching: find.byType(DashTextInput)),
      ).value,
      '',
    );
    expect(posted(h), isEmpty);
  });

  testWidgets('INV-WST-015 nothing on record: count it first (Stock '
      'counts, the branch kept)', (tester) async {
    final h = await openFromLog(tester, branch: 'heliopolis');
    expect(
      inDialog(find.text('This branch has no stock on record yet.')),
      findsOneWidget,
    );
    await h.tap(inDialog(byKey('waste-count-first')));
    expect(dialog, findsNothing);
    expect(h.location.path, '/inventory/counts');
    expect(h.container.read(currentScopeProvider).branchId, SeedIds.heliopolis);
  });

  testWidgets('INV-WST-015 a branch with stock: no banner', (tester) async {
    await openFromLog(tester);
    expect(inDialog(byKey('waste-count-first')), findsNothing);
  });

  testWidgets('INV-WST-015 / INV-WST-031 (divergence) a failed stock read '
      'says so with Retry, not "no stock on record"', (tester) async {
    final s = wasteServer();
    final boom = MockResponse.error(500, 'Stock is unavailable');
    // Every try fails (the button's intent warm included).
    s.server.fail('GET', stockRoute, boom, times: null);
    final h = await openFromLog(tester, server: s.server, db: s.db);
    expect(inDialog(find.text(h.refusalWords(boom))), findsOneWidget);
    expect(
      inDialog(find.text('This branch has no stock on record yet.')),
      findsNothing,
    );
    s.server.clearFailures();
    await h.tap(inDialog(byKey('waste-stock-retry')));
    expect(inDialog(find.text(h.refusalWords(boom))), findsNothing);
    await pickSearch(h, ingredientPicker, 'Matcha Powder');
    expect(inDialog(find.text('80 g on hand')), findsOneWidget);
  });

  testWidgets('INV-WST-016 every catalog row, its category searchable, its '
      'on-hand hint', (tester) async {
    final h = await openFromLog(tester);
    await h.tap(ingredientPicker);
    final list = tester.widget<DashOptionList<String>>(
      find.byType(DashOptionList<String>),
    );
    final catalog = h.db![InvTables.ingredients].rows.where(
      (i) => i['org_id'] == SeedIds.sabahOrg,
    );
    expect(list.options.length, catalog.length);
    String? hint(String label) =>
        list.options.firstWhere((o) => o.label == label).hint;
    expect(hint('Matcha Powder'), '80 g');
    expect(hint('Croissant Dough'), 'nothing on hand');
    expect(hint('Oat Milk'), '−350 ml (below zero)');
    expect(
      list.options.firstWhere((o) => o.label == 'Croissant Dough').keywords,
      'Bakery',
    );
    await h.enterText(find.byType(DashOptionList<String>), 'Bakery');
    expect(option('Croissant Dough'), findsOneWidget);
    expect(option('Matcha Powder'), findsNothing);
  });

  testWidgets('INV-WST-018 / INV-WST-021 Record waste stays off for blank, '
      'zero or unreadable quantities and without an ingredient', (
    tester,
  ) async {
    final h = await openFromLog(tester);
    await h.enterText(qtyField, '5');
    expect(submitButton(tester).onPressed, isNull, reason: 'no ingredient');
    await pickSearch(h, ingredientPicker, 'Matcha Powder');
    expect(submitButton(tester).onPressed, isNotNull);
    for (final q in ['', '0', '.']) {
      await h.enterText(qtyField, q);
      expect(submitButton(tester).onPressed, isNull, reason: '"$q"');
    }
    await h.enterText(qtyField, '80');
    expect(submitButton(tester).onPressed, isNotNull, reason: 'all of it');
    await h.enterText(qtyField, '0.0001');
    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('INV-WST-019 the six reasons a person may pick, in order', (
    tester,
  ) async {
    final h = await openFromLog(tester);
    await h.tap(reasonPicker);
    final list = tester.widget<DashOptionList<String>>(
      find.byType(DashOptionList<String>),
    );
    expect([for (final o in list.options) o.label], [
      'Expired',
      'Spoiled',
      'Damaged',
      'Overproduction',
      'Theft',
      'Other',
    ]);
    expect([for (final o in list.options) o.value], [
      'expired',
      'spoiled',
      'damaged',
      'overproduction',
      'theft',
      'other',
    ]);
  });

  testWidgets('INV-WST-020 the note is optional; blank goes as null', (
    tester,
  ) async {
    final h = await openFromLog(tester);
    expect(inDialog(find.text('(Optional)')), findsOneWidget);
    await pickSearch(h, ingredientPicker, 'Matcha Powder');
    await h.enterText(qtyField, '2.5');
    await h.enterText(noteField, '   ');
    await h.tap(inDialog(byKey('waste-submit')));
    expect(posted(h), [
      {
        'note': null,
        'org_ingredient_id': InvIds.ingredient('matcha'),
        'quantity': 2.5,
        'reason': 'expired',
      },
    ]);
    await h.expectToast('Waste recorded');
  });

  testWidgets('INV-WST-021 a spinner while saving; inventory and reports '
      'refresh even when the dialog closed first', (tester) async {
    final s = wasteServer();
    final gate = s.server.hold('POST', createRoute);
    final h = await openFromLog(tester, server: s.server, db: s.db);
    await pickSearch(h, ingredientPicker, 'Matcha Powder');
    await h.enterText(qtyField, '10');
    await h.tap(inDialog(byKey('waste-submit')));
    expect(submitButton(tester).loading, isTrue);
    final logs = h.server.callsTo(logRoute).length;
    final reports = h.server.callsTo(reportRoute).length;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(dialog, findsNothing);
    gate.release();
    await h.settle();
    expect(h.server.callsTo(logRoute).length, logs + 1);
    expect(h.server.callsTo(reportRoute).length, reports + 1);
    expect(inTable(find.text('Matcha Powder')), findsNWidgets(2));
    // Expired: 162.50 + the new 10 g × 250 = 187.50, still the largest.
    expect(
      find.descendant(of: reasons, matching: find.byType(DashSummaryLine)),
      findsNWidgets(6),
    );
    expect(
      tester
          .widgetList<DashSummaryLine>(
            find.descendant(of: reasons, matching: find.byType(DashSummaryLine)),
          )
          .first
          .value,
      'EGP 187.50',
    );
  });

  testWidgets('INV-WST-022 over on hand at the server: its words; the '
      'dialog stays open with the input', (tester) async {
    final h = await openFromLog(tester);
    await pickSearch(h, ingredientPicker, 'Matcha Powder');
    await h.enterText(qtyField, '20');
    // Another till wasted most of it meanwhile.
    stockRow(h.db!, SeedIds.zamalek, 'matcha')!['on_hand'] = 5.0;
    await h.tap(inDialog(byKey('waste-submit')));
    await h.expectToast(
      h.refusalWords(
        MockResponse.badRequest('Only 5.000 on hand — cannot waste 20.000.'),
      ),
    );
    expect(dialog, findsOneWidget);
    expect(submitButton(tester).loading, isFalse);
    expect(
      tester.widget<DashTextInput>(
        find.descendant(of: qtyField, matching: find.byType(DashTextInput)),
      ).value,
      '20',
    );
    expect(stockRow(h.db!, SeedIds.zamalek, 'matcha')!['on_hand'], 5.0);
  });

  testWidgets('INV-WST-022 over the person\'s limit, or no capability: the '
      'server\'s words each time', (tester) async {
    final s = wasteServer();
    final h = await openFromLog(tester, server: s.server, db: s.db);
    await pickSearch(h, ingredientPicker, 'Matcha Powder');
    await h.enterText(qtyField, '1');
    for (final refusal in [
      MockResponse.forbidden(
        'This waste is over your limit or outside your branches.',
      ),
      MockResponse.denied('inventory.waste.record'),
    ]) {
      s.server.fail('POST', createRoute, refusal);
      await h.tap(inDialog(byKey('waste-submit')));
      await h.expectToast(h.refusalWords(refusal));
      expect(dialog, findsOneWidget);
    }
    expect(stockRow(h.db!, SeedIds.zamalek, 'matcha')!['on_hand'], 80);
  });

  testWidgets('INV-WST-023 Cancel and Escape close without posting', (
    tester,
  ) async {
    final h = await openFromLog(tester);
    await h.tap(inDialog(byKey('waste-cancel')));
    expect(dialog, findsNothing);
    await h.tap(inPage(byKey('waste-record')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(dialog, findsNothing);
    expect(posted(h), isEmpty);
  });

  testWidgets('INV-WST-031 a preset ingredient before the stock arrives: '
      'Record waste is on once a quantity is typed; the check follows the '
      'stock', (tester) async {
    final s = wasteServer();
    final h = await pumpWaste(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final gate = s.server.hold('GET', stockRoute);
    final ctx = tester.element(page);
    final done = showRecordWasteDialog(
      ctx,
      branchId: SeedIds.zamalek,
      presetIngredientId: InvIds.ingredient('matcha'),
    );
    await h.settle();
    expect(inDialog(find.text('Pick an ingredient')), findsOneWidget);
    expect(inDialog(byKey('waste-count-first')), findsNothing);
    await h.enterText(qtyField, '100');
    expect(submitButton(tester).onPressed, isNotNull);
    gate.release();
    await h.settle();
    expect(inDialog(find.text('Matcha Powder')), findsOneWidget);
    expect(inDialog(find.text('More than on hand')), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
    await h.enterText(qtyField, '30');
    await h.tap(inDialog(byKey('waste-submit')));
    expect(await done, isTrue);
    await h.flushTimers();
  });

  testWidgets('phone: the dialog is a full-screen sheet; Arabic words', (
    tester,
  ) async {
    final h = await pumpWaste(
      tester,
      branch: SeedIds.zamalek,
      size: DashSize.phone,
      locale: 'ar',
    );
    await h.tap(inPage(byKey('waste-record')));
    expect(dialog, findsOneWidget);
    expect(inDialog(find.text(h.t('inventory.waste.recordTitle'))), findsWidgets);
    expect(inDialog(find.text(h.t('inventory.waste.reasons.expired'))),
        findsOneWidget);
  });
}
