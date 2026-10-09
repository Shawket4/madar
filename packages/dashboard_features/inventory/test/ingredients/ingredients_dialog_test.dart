// Ingredients: the New / Edit ingredient dialog (INV-ING-004, -014…032,
// -050…052, -055, INV-ALL-010, -011, -023), driven through the real shell.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show realtimeBusProvider;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Opens the Edit dialog of [name] (from its drawer).
Future<void> openEdit(DashHarness h, String name) async {
  await openDrawer(h, name);
  await h.tap(inDrawer(byKey('ingredient-drawer-edit')));
  expect(drawer, findsNothing);
  expect(dialog, findsOneWidget);
}

DashButton saveButton(WidgetTester tester) =>
    tester.widget<DashButton>(inDialog(byKey('ingredient-save')));

String fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: inDialog(byKey(key)),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

void main() {
  testWidgets('INV-ING-004 / INV-ING-014 New ingredient: empty, unit g, '
      'General, Advanced closed; suppliers and categories read while open',
      (tester) async {
    final h = await pumpIngredients(tester);
    expect(h.server.callsTo(suppliersRoute), isEmpty);
    expect(h.server.callsTo(categoriesRoute), isEmpty);
    await openCreate(h);
    expect(inDialog(find.text('New ingredient')), findsOneWidget);
    expect(inDialog(find.text('Ingredients')), findsOneWidget);
    expect(fieldText(tester, 'ingredient-name'), '');
    expect(inDialog(find.text('General')), findsOneWidget);
    expect(inDialog(find.text('g')), findsWidgets);
    expect(inDialog(find.text('No supplier')), findsOneWidget);
    expect(fieldText(tester, 'ingredient-cost'), '');
    expect(inDialog(byKey('ingredient-description')), findsNothing);
    expect(h.server.callsTo(suppliersRoute), hasLength(1));
    expect(h.server.callsTo(categoriesRoute), hasLength(1));
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('INV-ING-015 Edit ingredient is prefilled', (tester) async {
    final h = await pumpIngredients(tester);
    await openEdit(h, 'Full Cream Milk');
    expect(inDialog(find.text('Edit ingredient')), findsOneWidget);
    expect(fieldText(tester, 'ingredient-name'), 'Full Cream Milk');
    expect(inDialog(find.text('Milk')), findsOneWidget);
    expect(inDialog(find.text('ml')), findsWidgets);
    expect(fieldText(tester, 'ingredient-cost'), '0.045');
    expect(inDialog(find.text('Delta Dairy')), findsOneWidget);
    await h.tap(inDialog(byKey('ingredient-advanced')));
    expect(fieldText(tester, 'ingredient-description'), '3% fat');
    expect(fieldText(tester, 'ingredient-pack-unit'), 'carton');
    expect(fieldText(tester, 'ingredient-pack-size'), '1000');
    expect(fieldText(tester, 'ingredient-density'), '1.03');
    expect(fieldText(tester, 'ingredient-yield'), '');
    // No per-branch levels when editing.
    expect(inDialog(byKey('ingredient-pars')), findsNothing);
  });

  testWidgets('INV-ING-016 / INV-ING-032 Save is off while the name is '
      'blank; a duplicate name is the server\'s 409', (tester) async {
    final h = await pumpIngredients(tester);
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), '   ');
    expect(saveButton(tester).onPressed, isNull);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Oat Milk');
    expect(saveButton(tester).onPressed, isNotNull);
    await h.tap(inDialog(byKey('ingredient-save')));
    expect(
      textHas('An ingredient with this name already exists in the catalog'),
      findsOneWidget,
    );
    expect(dialog, findsOneWidget);
    expect(fieldText(tester, 'ingredient-name'), 'Oat Milk');
    await h.flushTimers();
  });

  testWidgets('INV-ING-017 / INV-ING-027 "New category…" needs a name; Save '
      'creates the category, then the ingredient in it', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Pistachio Paste');
    await pick(h, 'ingredient-category', 'New category…');
    expect(inDialog(byKey('ingredient-new-category')), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
    await h.enterText(inDialog(byKey('ingredient-new-category')), 'Nut Pastes');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    expect(dialog, findsNothing);
    final cat = s.db[InvTables.categories].firstWhere(
      (c) => c['name'] == 'Nut Pastes',
    )!;
    expect(cat['slug'], 'nut_pastes');
    expect(lastBody(h, categoriesRoute, 'POST'), {'name': 'Nut Pastes'});
    final body = lastBody(h, catalogRoute, 'POST');
    expect(body['category_id'], cat['id']);
    expect(body['name'], 'Pistachio Paste');
    expect(body['unit'], 'g');
    expect(body['cost_per_unit'], isNull);
    expect(body.containsKey('supplier_id'), isFalse);
    await search(h, 'Pistachio');
    expect(inTable(find.text('Nut Pastes')), findsOneWidget);
  });

  testWidgets('INV-ING-018 units: every unit on create; the same measure on '
      'edit; locked for pcs', (tester) async {
    final h = await pumpIngredients(tester);
    await openCreate(h);
    await h.tap(inDialog(byKey('ingredient-unit')));
    for (final u in ['kg', 'ml', 'L', 'pcs']) {
      expect(find.text(u), findsWidgets, reason: u);
    }
    await h.tap(find.text('kg').last);
    expect(
      tester
          .widget<DashSelectField<String>>(inDialog(byKey('ingredient-unit')))
          .value,
      'kg',
    );
    await h.tap(inDialog(find.text('Cancel')));

    await openEdit(h, 'Croissant Dough');
    final unit = tester.widget<DashSelectField<String>>(
      inDialog(byKey('ingredient-unit')),
    );
    expect(unit.enabled, isFalse);
    expect([for (final o in unit.options) o.value], ['pcs']);
    await h.tap(inDialog(find.text('Cancel')));

    await openEdit(h, 'Oat Milk');
    final ml = tester.widget<DashSelectField<String>>(
      inDialog(byKey('ingredient-unit')),
    );
    expect([for (final o in ml.options) o.value], ['ml', 'l']);
    expect([for (final o in ml.options) o.label], ['ml', 'L']);
  });

  testWidgets('INV-ING-019 / INV-ING-029 changing the unit warns, then saves '
      'the unit and the cost in two requests; the server converts',
      (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final before = stockRow(s.db, SeedIds.zamalek, 'house-blend')!;
    final onHand = (before['on_hand']! as num).toDouble();
    await openEdit(h, 'House Blend Beans');
    expect(inDialog(byKey('ingredient-unit-notice')), findsNothing);
    await pick(h, 'ingredient-unit', 'kg');
    expect(
      inDialog(
        find.text(
          "Changing the unit will convert this ingredient's recipes, stock "
          'and cost to the new unit.',
        ),
      ),
      findsOneWidget,
    );
    // The cost untouched: one PATCH, no cost in it.
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    final patches = h.server.callsTo(catalogItemRoute, method: 'PATCH');
    expect(patches, hasLength(1));
    final body = patches.single.body! as Map<String, Object?>;
    expect(body['unit'], 'kg');
    expect(body.containsKey('cost_per_unit'), isFalse);
    final ing = ingredientRow(s.db, 'house-blend');
    expect(ing['unit'], 'kg');
    expect(ing['cost_per_unit'], 90000); // 90 piastres a gram → per kg
    final after = stockRow(s.db, SeedIds.zamalek, 'house-blend')!;
    expect(after['on_hand'], closeTo(onHand / 1000, 0.0005));
  });

  testWidgets('INV-ING-029 an edited cost with a new unit is a second PATCH '
      'of the cost alone', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openEdit(h, 'Oat Milk');
    await pick(h, 'ingredient-unit', 'L');
    await h.enterText(inDialog(byKey('ingredient-cost')), '130');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    final patches = h.server.callsTo(catalogItemRoute, method: 'PATCH');
    expect(patches, hasLength(2));
    expect((patches.first.body! as Map)['unit'], 'l');
    expect((patches.first.body! as Map).containsKey('cost_per_unit'), isFalse);
    expect(patches.last.body, {'cost_per_unit': 13000});
    expect(ingredientRow(s.db, 'oat')['cost_per_unit'], 13000);
  });

  testWidgets('INV-ING-028 edit with the unit unchanged is one PATCH of '
      'every field', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openEdit(h, 'Cocoa Powder');
    await h.enterText(inDialog(byKey('ingredient-name')), 'Cocoa Powder 22%');
    await h.enterText(inDialog(byKey('ingredient-cost')), '0.3');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    final patch = h.server.callsTo(catalogItemRoute, method: 'PATCH').single;
    expect(patch.path,
        '/inventory/orgs/${SeedIds.sabahOrg}/catalog/${InvIds.ingredient('cocoa')}');
    final body = patch.body! as Map<String, Object?>;
    expect(body['name'], 'Cocoa Powder 22%');
    expect(body['unit'], 'g');
    expect(body['cost_per_unit'], 30);
    expect(body['category_id'], InvIds.category('dry_goods'));
    expect(body['supplier_id'], InvIds.supplier('metro'));
    expect(body.containsKey('description'), isTrue);
    await search(h, 'Cocoa Powder 22%');
    expect(cellText('Cocoa Powder 22%'), findsOneWidget);
  });

  testWidgets('INV-ING-020 (divergence) the cost keeps the hundredth of a '
      'piastre; blank is unknown', (tester) async {
    final h = await pumpIngredients(tester);
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Sea Salt');
    await h.enterText(inDialog(byKey('ingredient-cost')), '0.0045');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    expect(lastBody(h, catalogRoute, 'POST')['cost_per_unit'], 0.45);

    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Rock Salt');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    final body = lastBody(h, catalogRoute, 'POST');
    expect(body.containsKey('cost_per_unit'), isTrue);
    expect(body['cost_per_unit'], isNull);
  });

  testWidgets('INV-ING-020 (divergence) saving an untouched 0.1-piastre cost '
      'leaves it as it is', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openEdit(h, 'Ice Cubes');
    expect(fieldText(tester, 'ingredient-cost'), '0.001');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    expect(lastBody(h, catalogItemRoute, 'PATCH')['cost_per_unit'], 0.1);
    expect(ingredientRow(s.db, 'ice')['cost_per_unit'], 0.1);
  });

  testWidgets('INV-ING-021 / INV-ALL-023 supplier: active ones only, '
      'searchable; picked once it cannot be cleared', (tester) async {
    final h = await pumpIngredients(tester);
    await openCreate(h);
    final sup = tester.widget<DashSelectField<String>>(
      inDialog(byKey('ingredient-supplier')),
    );
    expect(sup.searchable, isTrue);
    expect(sup.placeholder, 'No supplier');
    expect([for (final o in sup.options) o.label], [
      'Delta Dairy',
      'Golden Bakery Supply',
      'Metro Wholesale',
      'Nile Roasters',
      'PackRight Egypt',
    ]);
    await h.tap(inDialog(byKey('ingredient-supplier')));
    expect(find.text('Search'), findsWidgets);
    await h.tap(find.text('Nile Roasters').last);
    expect(inDialog(find.text('Nile Roasters')), findsOneWidget);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Brazil Beans');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    expect(lastBody(h, catalogRoute, 'POST')['supplier_id'],
        InvIds.supplier('nile-roasters'));
  });

  testWidgets('INV-ALL-023 an inactive supplier still set shows the '
      'placeholder and is sent back unchanged', (tester) async {
    final h = await pumpIngredients(tester);
    await openEdit(h, 'Dried Hibiscus');
    expect(inDialog(find.text('No supplier')), findsOneWidget);
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    expect(lastBody(h, catalogItemRoute, 'PATCH')['supplier_id'],
        InvIds.supplier('cairo-fresh'));
  });

  testWidgets('INV-ING-022 / INV-ING-030 Advanced opens and closes; Cancel '
      'closes; reopening resets every field', (tester) async {
    final h = await pumpIngredients(tester);
    await openCreate(h);
    await h.tap(inDialog(byKey('ingredient-advanced')));
    expect(inDialog(byKey('ingredient-description')), findsOneWidget);
    await h.tap(inDialog(byKey('ingredient-advanced')));
    expect(inDialog(byKey('ingredient-description')), findsNothing);
    await h.tap(inDialog(byKey('ingredient-advanced')));
    await h.enterText(inDialog(byKey('ingredient-name')), 'Draft name');
    await h.tap(inDialog(find.text('Cancel')));
    expect(dialog, findsNothing);
    await openCreate(h);
    expect(fieldText(tester, 'ingredient-name'), '');
    expect(inDialog(byKey('ingredient-description')), findsNothing);
  });

  testWidgets('INV-ING-023 / INV-ING-024 / INV-ING-025 the advanced fields: '
      'trimmed text, numbers, blanks as null', (tester) async {
    final h = await pumpIngredients(tester);
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), '  Rose Water  ');
    await pick(h, 'ingredient-unit', 'ml');
    await h.tap(inDialog(byKey('ingredient-advanced')));
    await h.enterText(
      inDialog(byKey('ingredient-description')),
      '  Lebanese, food grade ',
    );
    await h.enterText(inDialog(byKey('ingredient-pack-unit')), ' bottle ');
    await h.enterText(inDialog(byKey('ingredient-pack-size')), '250');
    await h.enterText(inDialog(byKey('ingredient-yield')), '97.5');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    final body = lastBody(h, catalogRoute, 'POST');
    expect(body['name'], 'Rose Water');
    expect(body['unit'], 'ml');
    expect(body['description'], 'Lebanese, food grade');
    expect(body['pack_unit'], 'bottle');
    expect(body['pack_size'], 250);
    expect(body['yield_pct'], 97.5);
    expect(body.containsKey('density_g_per_ml'), isTrue);
    expect(body['density_g_per_ml'], isNull);
  });

  testWidgets('INV-ING-026 / INV-ING-027 / INV-ING-050 reorder levels per '
      'ACTIVE branch; only filled rows are saved, after the ingredient',
      (tester) async {
    final s = ingredientsServer();
    s.db['branches'].update(SeedIds.heliopolis, {'is_active': false});
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openCreate(h);
    expect(inDialog(find.text('Reorder levels per branch')), findsOneWidget);
    expect(
      inDialog(
        find.text(
          'Optional. Opening stock is not typed here — count it on the branch '
          'and the ledger takes it from there.',
        ),
      ),
      findsOneWidget,
    );
    for (final b in [SeedIds.maadi, SeedIds.newCairo, SeedIds.zamalek]) {
      expect(inDialog(byKey('ingredient-par-min-$b')), findsOneWidget);
    }
    expect(inDialog(byKey('ingredient-par-min-${SeedIds.heliopolis}')),
        findsNothing);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Pistachio Paste');
    await h.enterText(
      inDialog(byKey('ingredient-par-min-${SeedIds.zamalek}')),
      '500',
    );
    await h.enterText(
      inDialog(byKey('ingredient-par-max-${SeedIds.maadi}')),
      '1200',
    );
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    final created = s.db[InvTables.ingredients].firstWhere(
      (r) => r['name'] == 'Pistachio Paste',
    )!;
    final puts = h.server.callsTo(parRoute, method: 'PUT');
    expect([for (final p in puts) p.path], [
      '/inventory/branches/${SeedIds.maadi}/stock/${created['id']}/par',
      '/inventory/branches/${SeedIds.zamalek}/stock/${created['id']}/par',
    ]);
    expect(puts.first.body, {'par_min': null, 'par_max': 1200});
    expect(puts.last.body, {'par_min': 500, 'par_max': null});
    final calls = h.server.calls.map((c) => c.template).toList();
    expect(calls.indexOf(catalogRoute) < calls.indexOf(parRoute), isTrue);
  });

  testWidgets('INV-ING-030 Save spins while the request runs', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Saffron');
    final gate = s.server.hold('POST', catalogRoute);
    await h.tap(inDialog(byKey('ingredient-save')));
    expect(saveButton(tester).loading, isTrue);
    gate.release();
    await h.settle();
    await h.expectToast('Changes saved');
    expect(dialog, findsNothing);
  });

  testWidgets('INV-ING-031 / INV-ALL-011 a failed save toasts the server\'s '
      'words and keeps the dialog; a new category made first stays',
      (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Pistachio Paste');
    await pick(h, 'ingredient-category', 'New category…');
    await h.enterText(inDialog(byKey('ingredient-new-category')), 'Nut Pastes');
    s.server.fail(
      'POST',
      catalogRoute,
      MockResponse.badRequest('Unit must be one of: g, kg, ml, l, pcs'),
    );
    await h.tap(inDialog(byKey('ingredient-save')));
    expect(textHas('Unit must be one of: g, kg, ml, l, pcs'), findsOneWidget);
    expect(dialog, findsOneWidget);
    expect(saveButton(tester).loading, isFalse);
    expect(fieldText(tester, 'ingredient-name'), 'Pistachio Paste');
    expect(
      s.db[InvTables.categories].firstWhere((c) => c['name'] == 'Nut Pastes'),
      isNotNull,
    );
    await h.flushTimers();
  });

  testWidgets('INV-ING-031 the server refuses a unit change across measures',
      (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openEdit(h, 'Sugar');
    s.server.fail(
      'PATCH',
      catalogItemRoute,
      MockResponse.badRequest(
        'A unit can only change within the same measure: g ↔ kg or ml ↔ l.',
      ),
    );
    await pick(h, 'ingredient-unit', 'kg');
    await h.tap(inDialog(byKey('ingredient-save')));
    expect(
      textHas('A unit can only change within the same measure'),
      findsOneWidget,
    );
    expect(dialog, findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('INV-ING-055 (divergence) a reorder level the server refuses: '
      'Save again finishes without a second ingredient', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Pistachio Paste');
    await h.enterText(
      inDialog(byKey('ingredient-par-min-${SeedIds.zamalek}')),
      '500',
    );
    s.server.fail(
      'PUT',
      parRoute,
      MockResponse.badRequest('Par levels cannot be negative'),
    );
    final lists = h.server.callsTo(catalogRoute, method: 'GET').length;
    await h.tap(inDialog(byKey('ingredient-save')));
    expect(textHas('Par levels cannot be negative'), findsOneWidget);
    expect(dialog, findsOneWidget);
    // The ingredient exists now: the list shows it.
    expect(h.server.callsTo(catalogRoute, method: 'GET').length, lists + 1);
    await h.flushTimers();
    // Edited after the failure: the new words reach the created ingredient.
    await h.enterText(inDialog(byKey('ingredient-name')), 'Pistachio Cream');
    await h.enterText(inDialog(byKey('ingredient-cost')), '1.5');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    expect(h.server.callsTo(catalogRoute, method: 'POST'), hasLength(1));
    final patch = h.server.callsTo(catalogItemRoute, method: 'PATCH').single;
    final created = s.db[InvTables.ingredients].firstWhere(
      (r) => r['name'] == 'Pistachio Cream',
    )!;
    expect(patch.path,
        '/inventory/orgs/${SeedIds.sabahOrg}/catalog/${created['id']}');
    expect(created['cost_per_unit'], 150);
    expect(h.server.callsTo(parRoute, method: 'PUT'), hasLength(2));
    expect(
      s.db[InvTables.ingredients].where((r) => r['name'] == 'Pistachio Paste'),
      isEmpty,
    );
  });

  testWidgets('INV-ING-055 (divergence) a new category renamed after a '
      'failure is created under its new name', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Pistachio Paste');
    await pick(h, 'ingredient-category', 'New category…');
    await h.enterText(inDialog(byKey('ingredient-new-category')), 'Nut Paste');
    s.server.fail(
      'POST',
      catalogRoute,
      MockResponse.badRequest('Supplier does not belong to this organization'),
    );
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.flushTimers();
    await h.enterText(inDialog(byKey('ingredient-new-category')), 'Nut Pastes');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    final posts = h.server.callsTo(categoriesRoute, method: 'POST');
    expect([for (final p in posts) (p.body! as Map)['name']],
        ['Nut Paste', 'Nut Pastes']);
    final cat = s.db[InvTables.categories].firstWhere(
      (c) => c['name'] == 'Nut Pastes',
    )!;
    expect(lastBody(h, catalogRoute, 'POST')['category_id'], cat['id']);
  });

  testWidgets('INV-ING-020 (divergence) an untouched cost finer than a '
      'hundredth of a piastre is sent back as stored', (tester) async {
    final s = ingredientsServer();
    s.db[InvTables.ingredients].update(InvIds.ingredient('sugar'), {
      'cost_per_unit': 3.4567,
    });
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openEdit(h, 'Sugar');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    expect(lastBody(h, catalogItemRoute, 'PATCH')['cost_per_unit'], 3.4567);
    expect(ingredientRow(s.db, 'sugar')['cost_per_unit'], 3.4567);
  });

  testWidgets('INV-ING-029 an untouched cost with a new unit is never sent '
      '(the server converts it)', (tester) async {
    final s = ingredientsServer();
    s.db[InvTables.ingredients].update(InvIds.ingredient('oat'), {
      'cost_per_unit': 12.345,
    });
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openEdit(h, 'Oat Milk');
    await pick(h, 'ingredient-unit', 'L');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    expect(h.server.callsTo(catalogItemRoute, method: 'PATCH'), hasLength(1));
    expect(ingredientRow(s.db, 'oat')['cost_per_unit'], 12345);
  });

  testWidgets('INV-ING-052 the manager is offered New ingredient; the server '
      'refuses it (inventory.items.create)', (tester) async {
    final h = await pumpIngredients(tester, persona: Persona.manager);
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Pistachio Paste');
    await h.tap(inDialog(byKey('ingredient-save')));
    expect(textHas('Add stock items (inventory.items.create)'), findsOneWidget);
    expect(dialog, findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('INV-ALL-010 a save refreshes the inventory reads (catalog, '
      'stock, counts)', (tester) async {
    final h = await pumpIngredients(tester, branch: SeedIds.zamalek);
    int n(String r) => h.server.callsTo(r, method: 'GET').length;
    final before = [n(catalogRoute), n(stockRoute), n(stocktakesRoute)];
    await openCreate(h);
    await h.enterText(inDialog(byKey('ingredient-name')), 'Pistachio Paste');
    await h.tap(inDialog(byKey('ingredient-save')));
    await h.expectToast('Changes saved');
    expect(
      [n(catalogRoute), n(stockRoute), n(stocktakesRoute)],
      [for (final b in before) b + 1],
    );
    expect(n(branchesRoute), greaterThan(0));
  });

  testWidgets('INV-ING-051 phone: the dialog is a full-screen sheet with its '
      'field pairs side by side', (tester) async {
    final h = await pumpIngredients(tester, size: DashSize.phone, locale: 'ar');
    await openCreate(h);
    expect(
      tester
          .widget<DashSurfaceScope>(
            find.ancestor(of: dialog, matching: find.byType(DashSurfaceScope)),
          )
          .mode,
      DashSurfaceMode.fullScreen,
    );
    final cat = tester.getRect(inDialog(byKey('ingredient-category')));
    final unit = tester.getRect(inDialog(byKey('ingredient-unit')));
    expect(cat.top, unit.top);
  });

  testWidgets('INV-ING-015 (re-seed) the edit dialog takes a fresher row '
      'until the person types; then their words stay', (tester) async {
    final s = ingredientsServer();
    final h = await pumpIngredients(tester, server: s.server, db: s.db);
    await openEdit(h, 'Full Cream Milk');
    Future<void> rename(String name) async {
      ingredientRow(s.db, 'full-cream')['name'] = name;
      h.container.read(realtimeBusProvider).invalidate(const ['/inventory']);
      await h.settle();
    }

    await rename('Whole Milk');
    expect(fieldText(tester, 'ingredient-name'), 'Whole Milk');
    await h.enterText(inDialog(byKey('ingredient-name')), 'My Milk');
    await rename('Barista Milk');
    expect(fieldText(tester, 'ingredient-name'), 'My Milk');
  });
}
