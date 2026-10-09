// Ingredients: the page, its table, filter, search and export, driven through
// the real shell (INV-ING-001…013, -047, -049, -054 and the INV-ALL rows
// that live on this page).
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/rendering.dart' show SemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The Sabah catalog's names, as the server orders them.
List<String> catalogNames(MockDb db) {
  final names = [
    for (final r in db[InvTables.ingredients].rows)
      if (r['org_id'] == SeedIds.sabahOrg) r['name']! as String,
  ]..sort();
  return names;
}

/// Names of the catalog rows [branchId] has below par / never counted.
List<String> lowAt(MockDb db, String branchId) => [
  for (final n in catalogNames(db))
    if (_rec(db, branchId, n) case final s?
        when ((s['par_min'] as num?) ?? 0) > 0 &&
            (s['on_hand']! as num) <= (s['par_min']! as num))
      n,
];

List<String> uncountedAt(MockDb db, String branchId) => [
  for (final n in catalogNames(db))
    if (_rec(db, branchId, n)?['last_counted_at'] == null) n,
];

MockRow? _rec(MockDb db, String branchId, String name) {
  final ing = db[InvTables.ingredients].firstWhere((r) => r['name'] == name)!;
  return db[InvTables.branchStock].firstWhere(
    (s) => s['branch_id'] == branchId && s['org_ingredient_id'] == ing['id'],
  );
}

/// The names the table shows on its current page.
List<String> shownNames(MockDb db) => [
  for (final n in catalogNames(db))
    if (inTable(find.text(n)).evaluate().isNotEmpty) n,
];

Future<void> openPalette(DashHarness h, String query) async {
  await h.tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await h.tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await h.tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await h.settle();
  await h.enterText(find.byType(DashCommandPalette), query);
}

void main() {
  testWidgets('INV-ING-001 header: title, subtitle, Export Excel and New '
      'ingredient', (tester) async {
    final h = await pumpIngredients(tester);
    expect(h.location.path, ingredientsPath);
    expect(inPage(find.text('Ingredients')), findsOneWidget);
    expect(
      inPage(
        find.text(
          "The organization's catalog. Every branch counts from this list.",
        ),
      ),
      findsOneWidget,
    );
    expect(inPage(find.text('Export Excel')), findsOneWidget);
    expect(inPage(find.text('New ingredient')), findsOneWidget);
  });

  testWidgets('INV-ING-002 / INV-ALL-009 no organization in scope: the title '
      'and "Select an organization to manage inventory" only', (tester) async {
    final h = await pumpIngredients(tester, persona: Persona.platform);
    expect(
      inPage(find.text('Select an organization to manage inventory')),
      findsOneWidget,
    );
    expect(inPage(find.text('Ingredients')), findsOneWidget);
    expect(find.text('New ingredient'), findsNothing);
    expect(h.server.callsTo(catalogRoute), isEmpty);
  });

  testWidgets('INV-ING-002 a platform admin with Sabah picked sees the '
      'catalog', (tester) async {
    final h = await pumpIngredients(
      tester,
      persona: Persona.platform,
      prefs: sabahPicked(),
    );
    expect(inTable(find.text('Almond Milk')), findsOneWidget);
    expect(h.server.callsTo(catalogRoute).single.path,
        '/inventory/orgs/${SeedIds.sabahOrg}/catalog');
  });

  testWidgets('INV-ING-003 reads with All branches: catalog and branches, no '
      'stock and no counts', (tester) async {
    final h = await pumpIngredients(tester);
    expect(h.server.callsTo(catalogRoute).single.path,
        '/inventory/orgs/${SeedIds.sabahOrg}/catalog');
    expect(
      h.server.callsTo(branchesRoute).last.query['org_id'],
      [SeedIds.sabahOrg],
    );
    expect(h.server.callsTo(stockRoute), isEmpty);
    expect(h.server.callsTo(stocktakesRoute), isEmpty);
    expect(h.server.callsTo(suppliersRoute), isEmpty);
    expect(h.server.callsTo(categoriesRoute), isEmpty);
  });

  testWidgets('INV-ING-003 with Zamalek picked: its stock and its counts, '
      'once each', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    expect(h.server.callsTo(stockRoute).single.path,
        '/inventory/branches/${SeedIds.zamalek}/stock');
    expect(h.server.callsTo(stocktakesRoute).single.path,
        '/stocktakes/branches/${SeedIds.zamalek}');
  });

  testWidgets('INV-ALL-008 a ?branchId= deep link reads that branch',
      (tester) async {
    final h = await pumpIngredients(
      tester,
      path: '$ingredientsPath?branchId=${SeedIds.maadi}',
    );
    expect(h.server.callsTo(stockRoute).last.path,
        '/inventory/branches/${SeedIds.maadi}/stock');
    expect(inPage(byKey('ingredients-filter')), findsOneWidget);
  });

  testWidgets('INV-ALL-007 /inventory/items opens Ingredients', (tester) async {
    final h = await pumpIngredients(tester, path: '/inventory/items');
    expect(h.location.path, ingredientsPath);
    expect(inTable(find.text('Almond Milk')), findsOneWidget);
  });

  testWidgets('INV-ING-008 columns without a branch; unknown cost and no '
      'supplier read "—"', (tester) async {
    final h = await pumpIngredients(tester);
    for (final head in ['NAME', 'CATEGORY', 'STANDARD COST', 'SUPPLIER']) {
      expect(inTable(find.text(head)), findsOneWidget, reason: head);
    }
    for (final head in ['ON HAND', 'REORDER POINT', 'STATUS']) {
      expect(inTable(find.text(head)), findsNothing, reason: head);
    }
    // Dried Hibiscus: no cost (never "free"), an inactive supplier still set.
    await search(h, 'Dried Hibiscus');
    expect(inTable(find.text('Dry Goods')), findsOneWidget);
    expect(inTable(textHas('—')), findsOneWidget);
    expect(inTable(find.text('Cairo Fresh Produce')), findsOneWidget);
    // Ice Cubes: no supplier; a 0.1-piastre gram shows as EGP 0.00.
    await search(h, 'Ice Cubes');
    expect(inTable(textHas('EGP 0.00')), findsOneWidget);
    expect(inTable(find.text('—')), findsOneWidget);
  });

  testWidgets('INV-ING-009 with a branch: On hand (Below zero pill), '
      'Reorder point and Status', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    for (final head in ['ON HAND', 'REORDER POINT', 'STATUS']) {
      expect(inTable(find.text(head)), findsOneWidget, reason: head);
    }
    final oat = stockRow(s.db, SeedIds.zamalek, 'oat')!;
    expect((oat['on_hand']! as num) < 0, isTrue, reason: 'seed: below zero');
    await search(h, 'Oat Milk');
    expect(inTable(find.text('Below zero')), findsOneWidget);
    expect(inTable(find.text('Low')), findsOneWidget);
    // Hazelnut Syrup joined after the full count: never counted at Zamalek.
    await search(h, 'Hazelnut Syrup');
    expect(inTable(find.text('Never counted')), findsOneWidget);
    // House Blend: counted, above par.
    await search(h, 'House Blend');
    final hb = stockRow(s.db, SeedIds.zamalek, 'house-blend')!;
    expect(
      inTable(find.text(hb['on_hand']! as num > (hb['par_min']! as num)
          ? 'OK'
          : 'Low')),
      findsOneWidget,
    );
    final par = h.container.read(formatProvider).fmtNumber(
      hb['par_min']! as num,
    );
    expect(inTable(textHas('$par g')), findsWidgets);
  });

  testWidgets('INV-ING-049 a branch row missing from the stock answer reads '
      '"—" and no status', (tester) async {
    final s = ingredientsServer();
    s.server.on('GET', stockRoute, (req) => MockResponse.ok(const []));
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await search(h, 'Almond Milk');
    // Cost, on hand and reorder point fall back to "—" / no pill.
    expect(inTable(find.text('—')), findsNWidgets(2));
    expect(inTable(find.byType(DashStatusPill)), findsNothing);
  });

  testWidgets('INV-ING-006 filter Low stock / Never counted (branch only)',
      (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final low = lowAt(s.db, SeedIds.zamalek);
    final never = uncountedAt(s.db, SeedIds.zamalek);
    expect(low, isNotEmpty);
    expect(never, containsAll(['Chai Spice Mix', 'Hazelnut Syrup']));

    await h.tap(inPage(find.text('Low stock')));
    expect(shownNames(s.db), low);
    await h.tap(inPage(find.text('Never counted')));
    expect(shownNames(s.db), never);
    await h.tap(inPage(find.text('All')));
    expect(find.text('Page 1 of 3'), findsOneWidget);
  });

  testWidgets('INV-ING-006 the filter is not offered with All branches',
      (tester) async {
    await pumpIngredients(tester);
    expect(inPage(byKey('ingredients-filter')), findsNothing);
    expect(inPage(find.text('Low stock')), findsNothing);
  });

  testWidgets('INV-ING-054 a filter that matches nothing shows "No '
      'ingredients yet" and turns Export off; it is kept across All branches',
      (tester) async {
    final s = ingredientsServer();
    // Nothing low at Zamalek.
    for (final r in s.db[InvTables.branchStock].where(
      (r) => r['branch_id'] == SeedIds.zamalek,
    )) {
      s.db[InvTables.branchStock].update(r['id']! as String, {'par_min': null});
    }
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await h.tap(inPage(find.text('Low stock')));
    expect(inPage(find.text('No ingredients yet')), findsOneWidget);
    expect(inPage(find.text('No results found')), findsNothing);
    final export = tester.widget<DashExportButton>(
      inPage(find.byType(DashExportButton)),
    );
    expect(export.enabled, isFalse);

    await h.container.read(scopeProvider.notifier).setBranch(null);
    await h.settle();
    expect(inPage(byKey('ingredients-filter')), findsNothing);
    expect(inTable(find.text('Almond Milk')), findsOneWidget);

    await h.container.read(scopeProvider.notifier).setBranch(SeedIds.zamalek);
    await h.settle();
    expect(inPage(find.text('No ingredients yet')), findsOneWidget);
  });

  testWidgets('INV-ING-007 / INV-ALL-021 / INV-ALL-025 search: name, '
      'category, supplier and the raw cost; never the rendered words',
      (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    expect(
      inPage(find.widgetWithText(DashSearchInput, 'Search ingredients')),
      findsOneWidget,
    );
    await search(h, 'nile roasters');
    expect(shownNames(s.db), [
      'Decaf Beans',
      'Ethiopia Single Origin Beans',
      'House Blend Beans',
      'Turkish Coffee Ground',
    ]);
    await search(h, 'sauces'); // the category "Syrups & Sauces"
    expect(shownNames(s.db), contains('Chocolate Sauce'));
    expect(shownNames(s.db), contains('Vanilla Syrup'));
    await search(h, '4.5'); // Full Cream Milk's raw cost
    expect(shownNames(s.db), ['Full Cream Milk']);
    await search(h, 'EGP');
    expect(inPage(find.text('No ingredients yet')), findsOneWidget);
  });

  testWidgets('INV-ALL-016 ten rows a page, Previous/Next, back to page 1 on '
      'a search', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    final names = catalogNames(s.db);
    expect(names.length, greaterThan(20));
    expect(shownNames(s.db), names.take(10).toList());
    expect(find.text('Page 1 of 3'), findsOneWidget);
    await h.tap(find.bySemanticsLabel('Next'));
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(shownNames(s.db), names.skip(10).take(10).toList());
    await search(h, 'milk');
    expect(find.textContaining('Page '), findsNothing);
    expect(shownNames(s.db), contains('Almond Milk'));
  });

  testWidgets('INV-ALL-016 (divergence) a filter switch keeps the kit '
      'table on its page (the web goes back to page 1)', (tester) async {
    final s = ingredientsServer();
    // Fifteen never counted at Zamalek: two pages of them.
    var n = 0;
    for (final r in s.db[InvTables.branchStock].where(
      (r) => r['branch_id'] == SeedIds.zamalek,
    )) {
      if (n++ >= 15) break;
      s.db[InvTables.branchStock].update(r['id']! as String, {
        'last_counted_at': null,
      });
    }
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final never = uncountedAt(s.db, SeedIds.zamalek);
    expect(never.length, inInclusiveRange(11, 20));
    await h.tap(find.bySemanticsLabel('Next'));
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await h.tap(inPage(find.text('Never counted')));
    // Kit gap: still page 2 (the web shows "Page 1 of 2").
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(shownNames(s.db), never.skip(10).toList());
  });

  testWidgets('INV-ING-012 / INV-ALL-017 Columns menu hides a column',
      (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(find.text('Columns')));
    for (final c in [
      'Name',
      'Category',
      'Standard cost',
      'Supplier',
      'On hand',
      'Reorder point',
      'Status',
    ]) {
      expect(find.text(c), findsWidgets, reason: c);
    }
    await h.tap(find.text('Supplier').last);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(inTable(find.text('SUPPLIER')), findsNothing);
    expect(inTable(find.text('STANDARD COST')), findsOneWidget);
  });

  testWidgets('INV-ING-010 / INV-ALL-020 a row opens the drawer; rows are '
      'focusable buttons', (tester) async {
    final sem = tester.ensureSemantics();
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    final row = find.bySemanticsLabel(RegExp('^Almond Milk'));
    expect(row, findsWidgets);
    final data = tester.getSemantics(row.first).getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    await h.tap(inTable(find.text('Almond Milk')));
    expect(drawer, findsOneWidget);
    expect(inDrawer(find.text('Almond Milk')), findsOneWidget);
    sem.dispose();
  });

  testWidgets('INV-ALL-020 Tab reaches a row; Enter opens it', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(find.byType(DashSearchInput)));
    final cell = tester.getCenter(cellText('Almond Milk'));
    var reached = false;
    for (var i = 0; i < 12 && !reached; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await h.settle(rounds: 1);
      final focus = FocusManager.instance.primaryFocus;
      reached = focus != null && focus.rect.contains(cell);
    }
    expect(reached, isTrue, reason: 'Tab reaches the Almond Milk row');
    expect(drawer, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await h.settle();
    expect(inDrawer(find.text('Almond Milk')), findsOneWidget);
  });

  testWidgets('INV-ING-011 / INV-ALL-018 loading: skeleton rows, then the '
      'catalog', (tester) async {
    final s = ingredientsServer();
    final gate = s.server.hold('GET', catalogRoute);
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    expect(inTable(find.byType(DashSkeleton)), findsWidgets);
    expect(inTable(find.text('Almond Milk')), findsNothing);
    gate.release();
    await h.settle();
    expect(inTable(find.byType(DashSkeleton)), findsNothing);
    expect(inTable(find.text('Almond Milk')), findsOneWidget);
  });

  testWidgets('INV-ING-011 / INV-ALL-018 / INV-ALL-026 error: "Couldn\'t load '
      'this", the server\'s words, Retry refetches the catalog only',
      (tester) async {
    final s = ingredientsServer();
    s.server.fail(
      'GET',
      catalogRoute,
      MockResponse.error(500, 'The catalog is resting'),
      times: null,
    );
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    expect(inPage(find.text("Couldn't load this")), findsOneWidget);
    expect(inPage(find.text('The catalog is resting')), findsOneWidget);
    expect(inPage(find.textContaining('Page ')), findsNothing);
    final stockCalls = h.server.callsTo(stockRoute).length;
    s.server.clearFailures();
    await h.tap(inPage(find.text('Retry')));
    expect(inTable(find.text('Almond Milk')), findsOneWidget);
    expect(h.server.callsTo(stockRoute).length, stockCalls);
  });

  testWidgets('INV-ING-011 / INV-ALL-018 empty catalog: "No ingredients '
      'yet", Export off', (tester) async {
    final s = ingredientsServer();
    s.db[InvTables.ingredients].removeWhere(
      (r) => r['org_id'] == SeedIds.sabahOrg,
    );
    await pumpIngredients(tester, server: s.server, db: s.db);
    expect(inPage(find.text('No ingredients yet')), findsOneWidget);
    expect(
      tester
          .widget<DashExportButton>(inPage(find.byType(DashExportButton)))
          .enabled,
      isFalse,
    );
  });

  testWidgets('INV-ALL-006 (divergence) without inventory.read the shell '
      'shows Restricted and nothing is read', (tester) async {
    final h = await pumpIngredients(tester, persona: Persona.limited);
    expect(find.byType(Restricted), findsOneWidget);
    expect(page, findsNothing);
    expect(h.server.callsTo(catalogRoute), isEmpty);
  });

  testWidgets('INV-ALL-006 a read the server refuses shows its words in the '
      'table (the persona holds the leaf, the server says no)', (tester) async {
    final s = ingredientsServer();
    s.server.fail(
      'GET',
      catalogRoute,
      MockResponse.denied('inventory.read'),
      times: null,
    );
    await pumpIngredients(tester, server: s.server, db: s.db);
    expect(inPage(find.text("Couldn't load this")), findsOneWidget);
    expect(inPage(textHas('(inventory.read)')), findsOneWidget);
    expect(inPage(find.text('New ingredient')), findsOneWidget);
  });

  testWidgets('INV-ALL-001 / INV-ALL-002 the sidebar leaf: shown with '
      'inventory.read, hidden without', (tester) async {
    await pumpIngredients(tester, persona: Persona.manager);
    expect(
      find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Ingredients'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-ALL-003 / INV-ALL-004 the Inventory parent is open on an '
      'inventory page; the palette lists Ingredients', (tester) async {
    final h = await pumpIngredients(tester, persona: Persona.manager);
    final leaf = find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text('Ingredients'),
    );
    expect(leaf.hitTestable(), findsOneWidget);
    await openPalette(h, 'Ingred');
    final hit = find.descendant(
      of: find.byType(DashCommandPalette),
      matching: find.text('Ingredients'),
    );
    expect(hit, findsOneWidget);
  });

  testWidgets('INV-ALL-004 no palette entry without inventory.read',
      (tester) async {
    final h = await pumpIngredients(tester, persona: Persona.limited);
    await openPalette(h, 'Ingred');
    expect(
      find.descendant(
        of: find.byType(DashCommandPalette),
        matching: find.text('Ingredients'),
      ),
      findsNothing,
    );
  });

  testWidgets('INV-ALL-002 no leaf without inventory.read', (tester) async {
    await pumpIngredients(tester, persona: Persona.limited);
    expect(
      find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Ingredients'),
      ),
      findsNothing,
    );
  });

  testWidgets('INV-ALL-005 module gate: a Dawam-only business sees "Not part '
      'of this business\'s plan"', (tester) async {
    final h = await pumpIngredients(tester, persona: Persona.dawamOnly);
    expect(page, findsNothing);
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(h.server.callsTo(catalogRoute), isEmpty);
  });

  testWidgets('INV-ALL-015 a realtime resync refetches the catalog and the '
      'branch stock', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    final c = h.server.callsTo(catalogRoute).length;
    final st = h.server.callsTo(stockRoute).length;
    h.realtime.current!.emit('resync');
    await h.settle();
    expect(h.server.callsTo(catalogRoute).length, c + 1);
    expect(h.server.callsTo(stockRoute).length, st + 1);
  });

  testWidgets('INV-ING-013 / INV-ALL-019 phone: each row is a card with its '
      'labelled grid; no Columns menu; the filter scrolls', (tester) async {
    final h = await pumpIngredients(
      tester,
      size: DashSize.phone,
      branch: SeedIds.zamalek,
    );
    expect(inPage(find.text('Columns')), findsNothing);
    expect(inPage(byKey('ingredients-filter')), findsOneWidget);
    expect(
      find.ancestor(
        of: inPage(byKey('ingredients-filter')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsWidgets,
    );
    expect(inTable(find.text('Almond Milk')), findsOneWidget);
    for (final label in [
      'Category',
      'Standard cost',
      'Supplier',
      'On hand',
      'Reorder point',
      'Status',
    ]) {
      expect(inTable(find.text(label)), findsWidgets, reason: label);
    }
    await h.tap(inTable(find.text('Almond Milk')));
    expect(drawer, findsOneWidget);
  });

  group('INV-ING-005 / INV-ALL-012 / INV-ALL-013 export', () {
    testWidgets('with a branch: 8 columns, every filtered row, the file '
        'name, the toasts', (tester) async {
      final s = ingredientsServer();
      final h = await pumpIngredients(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      await h.tap(inPage(find.text('Low stock')));
      final low = lowAt(s.db, SeedIds.zamalek);
      await h.tap(inPage(byKey('ingredients-export')));
      await h.expectToast('Exported ${low.length} rows');
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.title, 'Ingredients');
      expect(sheet.name, 'Ingredients');
      expect([for (final c in sheet.columns) c.header], [
        'Name',
        'Category',
        'Cost / unit (EGP)',
        'Unit',
        'Supplier',
        'On hand',
        'Reorder point',
        'Status',
      ]);
      expect([for (final r in sheet.rows) r.first], low);
      final oat = sheet.rows.firstWhere((r) => r.first == 'Oat Milk');
      final rec = stockRow(s.db, SeedIds.zamalek, 'oat')!;
      expect(oat[2], 0.12); // 12 piastres per ml
      expect(oat[3], 'ml');
      expect(oat[5], rec['on_hand']);
      expect(oat[6], rec['par_min']);
      expect(oat[7], 'Low');
      expect(h.files.saved.single.filename, 'Madar-Ingredients-2026-10-08.xlsx');
    });

    testWidgets('All branches: 5 columns; unknown cost blank, no supplier '
        '"—"', (tester) async {
      final s = ingredientsServer();
      final h = await pumpIngredients(tester, server: s.server, db: s.db);
      await h.tap(inPage(byKey('ingredients-export')));
      await h.expectToast('Exported ${catalogNames(s.db).length} rows');
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.columns.length, 5);
      final hibiscus = sheet.rows.firstWhere(
        (r) => r.first == 'Dried Hibiscus',
      );
      expect(hibiscus[2], isNull); // INV-ING-047
      final ice = sheet.rows.firstWhere((r) => r.first == 'Ice Cubes');
      expect(ice[4], '—');
      expect(ice[3], 'g');
      final litre = sheet.rows.where((r) => r[3] == 'L');
      expect(litre, isEmpty, reason: 'no litre item in the seed');
    });

    testWidgets('spinner while exporting; "Export failed" on a failure',
        (tester) async {
      final h = await pumpIngredients(tester);
      final hold = Completer<void>();
      h.exports.hold = hold.future;
      await h.tap(inPage(byKey('ingredients-export')));
      expect(find.text('Gathering data…'), findsOneWidget);
      expect(
        tester
            .widget<DashExportButton>(inPage(find.byType(DashExportButton)))
            .loading,
        isTrue,
      );
      hold.complete();
      h.exports.hold = null;
      await h.settle();
      await h.flushTimers();
      h.exports.failNext = StateError('disk full');
      await h.tap(inPage(byKey('ingredients-export')));
      await h.expectToast('Export failed');
    });
  });
}
