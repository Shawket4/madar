// Ingredients: the ingredient drawer (INV-ING-033…053, -056, INV-ALL-024,
// -026), driven through the real shell.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/waste/waste_dialog.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

DashButton drawerButton(WidgetTester tester, String key) =>
    tester.widget<DashButton>(inDrawer(byKey(key)));

/// The newest movements of [key] at [branchId], as the server orders them.
List<MockRow> movementsOf(MockDb db, String branchId, String key) {
  final rows = db[InvTables.movements].where(
    (m) =>
        m['branch_id'] == branchId &&
        m['org_ingredient_id'] == InvIds.ingredient(key),
  );
  rows.sort((a, b) {
    final c = DateTime.parse(
      b['created_at']! as String,
    ).compareTo(DateTime.parse(a['created_at']! as String));
    return c != 0 ? c : compareJson(b['id'], a['id']);
  });
  return rows;
}

void main() {
  testWidgets('INV-ING-033 header: name, category badge, "Branch cost" from '
      'the branch row, the supplier', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final f = h.container.read(formatProvider);
    final rec = stockRow(s.db, SeedIds.zamalek, 'house-blend')!;
    final cost = rec['cost_per_unit'] as num?;
    await openDrawer(h, 'House Blend Beans');
    expect(inDrawer(find.text('House Blend Beans')), findsOneWidget);
    expect(inDrawer(find.text('Coffee Beans')), findsOneWidget);
    final label = cost != null ? 'Branch cost' : 'Standard cost';
    final figure = f.fmtMoney(cost ?? 90);
    expect(
      inDrawer(textHas('$label: ${dashFigure(figure)} · Nile Roasters')),
      findsOneWidget,
    );
  });

  testWidgets('INV-ING-033 a branch that never stocked it: "Standard cost" '
      'and the catalog figure', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.heliopolis);
    await openDrawer(h, 'Full Cream Milk');
    expect(
      inDrawer(
        textHas('Standard cost: ${dashFigure('EGP 0.05')} · Delta Dairy'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-ING-034 / INV-ING-048 All branches: "Select a branch to '
      'manage its stock", Edit and View recipes only, no history read', (
    tester,
  ) async {
    final h = await pumpIngredients(tester);
    await openDrawer(h, 'Oat Milk');
    expect(
      inDrawer(find.text('Select a branch to manage its stock')),
      findsOneWidget,
    );
    expect(inDrawer(byKey('ingredient-drawer-edit')), findsOneWidget);
    expect(inDrawer(byKey('ingredient-drawer-recipes')), findsOneWidget);
    expect(inDrawer(byKey('ingredient-drawer-waste')), findsNothing);
    expect(inDrawer(byKey('ingredient-drawer-count')), findsNothing);
    expect(h.server.callsTo(movementsRoute), isEmpty);
  });

  testWidgets('INV-ING-047 unknown cost reads "—" in the drawer', (
    tester,
  ) async {
    final h = await pumpIngredients(tester);
    await openDrawer(h, 'Dried Hibiscus');
    expect(
      inDrawer(
        textHas('Standard cost: ${dashFigure('—')} · Cairo Fresh Produce'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-ING-035 On hand below zero: tinted figure, "Below zero", '
      'when it was last counted', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final f = h.container.read(formatProvider);
    final rec = stockRow(s.db, SeedIds.zamalek, 'oat')!;
    await openDrawer(h, 'Oat Milk');
    final box = byKey('ingredient-drawer-on-hand');
    expect(
      find.descendant(of: box, matching: find.text('On hand')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: box,
        matching: textHas(dashFigure(f.fmtNumber(rec['on_hand']! as num))),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: box, matching: find.text('Below zero')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: box,
        matching: find.text(
          'Last counted ${dashFigure(f.fmtDateTime(rec['last_counted_at']))}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-ING-035 never counted at this branch', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    await openDrawer(h, 'Hazelnut Syrup');
    expect(
      inDrawer(
        find.text(
          'Never counted at this branch. Count it to set the real figure.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-ING-036 / INV-ALL-024 (divergence) Count this item with no '
      'open count starts a one-item count, then Stock counts on the same '
      'branch', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await openDrawer(h, 'Oat Milk');
    await h.tap(inDrawer(byKey('ingredient-drawer-count')));
    final post = h.server.callsTo(stocktakesRoute, method: 'POST').single;
    expect(post.path, '/stocktakes/branches/${SeedIds.zamalek}');
    expect(post.body, {
      'category_id': null,
      'note': null,
      'org_ingredient_ids': [InvIds.ingredient('oat')],
    });
    expect(drawer, findsNothing);
    expect(h.location.path, '/inventory/counts');
    expect(h.container.read(currentScopeProvider).branchId, SeedIds.zamalek);
    final open = s.db[InvTables.stocktakes].firstWhere(
      (st) =>
          st['branch_id'] == SeedIds.zamalek && st['status'] == 'in_progress',
    );
    expect(open, isNotNull);
  });

  testWidgets('INV-ING-036 with a count open it just goes there', (
    tester,
  ) async {
    final h = await pumpIngredients(tester, branch: SeedIds.newCairo);
    await openDrawer(h, 'Sugar');
    await h.tap(inDrawer(byKey('ingredient-drawer-count')));
    expect(h.server.callsTo(stocktakesRoute, method: 'POST'), isEmpty);
    expect(h.location.path, '/inventory/counts');
  });

  testWidgets('INV-ING-036 a refused count toasts and keeps the drawer', (
    tester,
  ) async {
    final s = ingredientsServer();
    s.server.fail(
      'POST',
      stocktakesRoute,
      MockResponse.denied('inventory.counts.create'),
    );
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await openDrawer(h, 'Oat Milk');
    await h.tap(inDrawer(byKey('ingredient-drawer-count')));
    expect(
      textHas(h.refusalWords(MockResponse.denied('inventory.counts.create'))),
      findsOneWidget,
    );
    expect(drawer, findsOneWidget);
    expect(h.location.path, ingredientsPath);
    await h.flushTimers();
  });

  testWidgets('INV-ING-056 counts list failed: Count this item posts and the '
      'server\'s 409 is the toast', (tester) async {
    final s = ingredientsServer();
    s.server.fail(
      'GET',
      stocktakesRoute,
      MockResponse.error(500, 'down'),
      times: null,
    );
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.newCairo,
    );
    await openDrawer(h, 'Sugar');
    await h.tap(inDrawer(byKey('ingredient-drawer-count')));
    expect(h.server.callsTo(stocktakesRoute, method: 'POST'), hasLength(1));
    expect(
      textHas('An open stocktake already exists for this branch'),
      findsOneWidget,
    );
    expect(drawer, findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('INV-ING-037 reorder levels: prefilled, saved, toast; the '
      'server\'s refusal is a toast', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final rec = stockRow(s.db, SeedIds.zamalek, 'almond')!;
    await openDrawer(h, 'Almond Milk');
    String field(String key) => tester
        .widget<EditableText>(
          find.descendant(
            of: inDrawer(byKey(key)),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;
    expect(inDrawer(find.text('Reorder levels')), findsOneWidget);
    expect(inDrawer(find.text('Reorder point (ml)')), findsOneWidget);
    expect(
      field('ingredient-drawer-par-min'),
      '${(rec['par_min']! as num).toInt()}',
    );
    await h.enterText(inDrawer(byKey('ingredient-drawer-par-min')), '2500');
    await h.enterText(inDrawer(byKey('ingredient-drawer-par-max')), '');
    await h.tap(inDrawer(byKey('ingredient-drawer-par-save')));
    await h.expectToast('Changes saved');
    final put = h.server.callsTo(parRoute, method: 'PUT').single;
    expect(
      put.path,
      '/inventory/branches/${SeedIds.zamalek}/stock/${InvIds.ingredient('almond')}/par',
    );
    expect(put.body, {'par_max': null, 'par_min': 2500});
    expect(stockRow(s.db, SeedIds.zamalek, 'almond')!['par_min'], 2500);
    expect(drawer, findsOneWidget);

    await h.enterText(inDrawer(byKey('ingredient-drawer-par-max')), '100');
    await h.tap(inDrawer(byKey('ingredient-drawer-par-save')));
    expect(textHas('Max par must be at least the min par'), findsOneWidget);
    await h.flushTimers();

    await h.enterText(inDrawer(byKey('ingredient-drawer-par-min')), '-5');
    await h.enterText(inDrawer(byKey('ingredient-drawer-par-max')), '');
    await h.tap(inDrawer(byKey('ingredient-drawer-par-save')));
    expect(textHas('Par levels cannot be negative'), findsOneWidget);
    expect(h.server.callsTo(parRoute, method: 'PUT').last.body, {
      'par_max': null,
      'par_min': -5,
    });
    await h.flushTimers();
  });

  testWidgets('INV-ING-037 / INV-ING-052 Save par refused by the server '
      '(inventory.adjust)', (tester) async {
    final s = ingredientsServer();
    s.server.fail('PUT', parRoute, MockResponse.denied('inventory.adjust'));
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await openDrawer(h, 'Almond Milk');
    await h.tap(inDrawer(byKey('ingredient-drawer-par-save')));
    expect(
      textHas(h.refusalWords(MockResponse.denied('inventory.adjust'))),
      findsOneWidget,
    );
    expect(drawerButton(tester, 'ingredient-drawer-par-save').loading, isFalse);
    await h.flushTimers();
  });

  testWidgets('INV-ING-038 / INV-ING-048 stock history: the latest 50, '
      'signed and tinted, with the balance', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    expect(h.server.callsTo(movementsRoute), isEmpty);
    final f = h.container.read(formatProvider);
    await openDrawer(h, 'Oat Milk');
    final call = h.server.callsTo(movementsRoute).single;
    expect(call.path, '/inventory/branches/${SeedIds.zamalek}/movements');
    expect(call.query, {
      'org_ingredient_id': [InvIds.ingredient('oat')],
      'per_page': ['50'],
    });
    expect(inDrawer(find.text('Stock history')), findsOneWidget);
    final rows = movementsOf(s.db, SeedIds.zamalek, 'oat');
    final first = rows.first;
    final list = byKey('ingredient-history');
    // Every one of the latest 50, no more.
    final shown = find.descendant(
      of: list,
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('movement-') &&
            !(w.key! as ValueKey<String>).value.startsWith('movement-qty-'),
      ),
    );
    expect(shown, findsNWidgets(rows.length < 50 ? rows.length : 50));
    final row = byKey('movement-${first['id']}');
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          h.t('inventory.movements.types.${first['movement_type']}'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text(dashFigure(f.fmtDateTime(first['created_at']))),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          dashFigure(f.fmtNumber(first['balance_after']! as num)),
        ),
      ),
      findsOneWidget,
    );
    // Signed quantity + unit, red below zero and green otherwise.
    final colors = tester.element(drawer).madarColors;
    for (final m in rows.take(rows.length < 50 ? rows.length : 50)) {
      final qty = tester.widget<Text>(byKey('movement-qty-${m['id']}'));
      final q = m['quantity']! as num;
      expect(
        qty.data,
        dashFigure(
          '${f.fmtNumber(q, const NumberOptions(signDisplay: SignDisplay.exceptZero))} ml',
        ),
      );
      expect(
        qty.style!.color,
        (q < 0 ? DashTone.danger : DashTone.success).foreground(colors),
        reason: '$q',
      );
    }
  });

  testWidgets('INV-ING-039 stock history loading: four skeleton rows', (
    tester,
  ) async {
    final s = ingredientsServer();
    final gate = s.server.hold('GET', movementsRoute);
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await openDrawer(h, 'Oat Milk');
    expect(
      find.descendant(
        of: byKey('ingredient-history-loading'),
        matching: find.byType(DashSkeleton),
      ),
      findsNWidgets(12),
    );
    gate.release();
    await h.settle();
    expect(inDrawer(byKey('ingredient-history')), findsOneWidget);
  });

  testWidgets('INV-ING-040 / INV-ALL-026 stock history error: its title and '
      'Retry, no server words; Retry asks again', (tester) async {
    final s = ingredientsServer();
    s.server.fail(
      'GET',
      movementsRoute,
      MockResponse.error(500, 'ledger offline'),
      times: null,
    );
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await openDrawer(h, 'Oat Milk');
    expect(inDrawer(find.text("Couldn't load stock history")), findsOneWidget);
    expect(inDrawer(textHas('ledger offline')), findsNothing);
    final n = h.server.callsTo(movementsRoute).length;
    final stock = h.server.callsTo(stockRoute).length;
    s.server.clearFailures();
    await h.tap(inDrawer(find.text('Retry')));
    expect(h.server.callsTo(movementsRoute).length, n + 1);
    expect(h.server.callsTo(stockRoute).length, stock);
    expect(inDrawer(byKey('ingredient-history')), findsOneWidget);
  });

  testWidgets('INV-ING-041 / INV-ING-049 no movements and no branch row: '
      '"No movements yet", on hand 0', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.heliopolis);
    await openDrawer(h, 'Sugar');
    expect(inDrawer(find.text('No movements yet')), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('ingredient-drawer-on-hand'),
        matching: textHas('${dashFigure('0')} g'),
      ),
      findsOneWidget,
    );
    // Nothing on hand: nothing to waste.
    expect(drawerButton(tester, 'ingredient-drawer-waste').onPressed, isNull);
  });

  testWidgets('INV-ING-053 a movement type with no word reads its code', (
    tester,
  ) async {
    final s = ingredientsServer();
    final rows = movementsOf(s.db, SeedIds.zamalek, 'oat');
    s.db[InvTables.movements].update(rows.first['id']! as String, {
      'movement_type': 'barter_in',
    });
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    h.allowMissingKeys = true;
    await openDrawer(h, 'Oat Milk');
    expect(inDrawer(find.text('barter_in')), findsOneWidget);
  });

  testWidgets('INV-ING-042 Edit closes the drawer and opens Edit ingredient', (
    tester,
  ) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    await openDrawer(h, 'Oat Milk');
    await h.tap(inDrawer(byKey('ingredient-drawer-edit')));
    expect(drawer, findsNothing);
    expect(inDialog(find.text('Edit ingredient')), findsOneWidget);
  });

  testWidgets('INV-ING-043 / INV-ING-046 Record waste: off at or under zero; '
      'otherwise the waste dialog with this ingredient', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    await openDrawer(h, 'Croissant Dough');
    expect(drawerButton(tester, 'ingredient-drawer-waste').onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    await openDrawer(h, 'Oat Milk');
    expect(drawerButton(tester, 'ingredient-drawer-waste').onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    await openDrawer(h, 'Almond Milk');
    await h.tap(inDrawer(byKey('ingredient-drawer-waste')));
    expect(drawer, findsNothing);
    final w = tester.widget<RecordWasteDialog>(find.byType(RecordWasteDialog));
    expect(w.branchId, SeedIds.zamalek);
    expect(w.presetIngredientId, InvIds.ingredient('almond'));
  });

  testWidgets('INV-ING-044 View recipes goes to the menu items', (
    tester,
  ) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    h.allowUnmatched = true;
    await openDrawer(h, 'Oat Milk');
    await h.tap(inDrawer(byKey('ingredient-drawer-recipes')));
    expect(drawer, findsNothing);
    expect(h.location.path, '/menu/items');
  });

  testWidgets('INV-ING-045 the drawer closes with ×, Escape and a tap '
      'outside', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    await openDrawer(h, 'Oat Milk');
    await h.tap(inDrawer(find.bySemanticsLabel('Close')));
    expect(drawer, findsNothing);
    await openDrawer(h, 'Oat Milk');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(drawer, findsNothing);
    await openDrawer(h, 'Oat Milk');
    await tester.tapAt(const Offset(20, 450));
    await h.settle();
    expect(drawer, findsNothing);
  });

  testWidgets('INV-ING-051 phone: the drawer is the whole screen', (
    tester,
  ) async {
    final h = await pumpIngredients(
      tester,
      size: DashSize.phone,
      branch: SeedIds.zamalek,
    );
    await openDrawer(h, 'Oat Milk');
    expect(
      tester
          .widget<DashSurfaceScope>(
            find.ancestor(of: drawer, matching: find.byType(DashSurfaceScope)),
          )
          .mode,
      DashSurfaceMode.fullScreen,
    );
    expect(tester.getSize(drawer).width, DashSize.phone.size.width);
  });
}
