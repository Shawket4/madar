// The recipe builder and the create-ingredient dialog (MENU-RCP-001..023),
// driven through the real shell inside the two hosts the web gives them (see
// `recipe_host.dart`): the add-on recipe dialog (standalone, one size, "New
// ingredient", its own Save) and the item dialog's recipe section (deferred,
// the item's sizes).
//
// Figures, from the area seed (piastres per unit): house blend 95/g, full
// cream milk 4.2/ml, oat milk 14/ml, pistachio paste unknown.
// Latte Regular 18 g + 180 ml = 1710 + 756 = 2466 (EGP 24.66), sold at
// 11500 → margin 78.6 %; Large 27 g + 240 ml = 2565 + 1008 = 3573
// (EGP 35.73), sold at 13500 → 73.5 %. Extra shot 18 g = 1710 (EGP 17.10),
// sold at 3000 → 43 %.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/shared/menu_text.dart' show oneSize;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_host.dart';

const String _catalog = '/inventory/orgs/{org_id}/catalog';
const String _categories = '/inventory/orgs/{org_id}/categories';
const String _addonLines = '/recipes/addons/{addon_item_id}';
const String _optionRecipe = '/modifier-options/{oid}/recipe';

Finder _inBuilder(Finder f) =>
    find.descendant(of: find.byType(RecipeBuilder), matching: f);

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(CreateIngredientDialog), matching: f);

DashButton _button(WidgetTester tester, Finder scope, String label) =>
    tester.widget<DashButton>(
      find.ancestor(
        of: find.descendant(of: scope, matching: find.text(label)),
        matching: find.byType(DashButton),
      ),
    );

/// Opens [picker] and picks [name], searched for first (a person types).
Future<void> _pick(DashHarness h, Finder picker, String name) async {
  await h.tap(picker);
  await _search(h, name);
  final list = find.byWidgetPredicate((w) => w is DashOptionList);
  await h.tap(find.descendant(of: list, matching: find.text(name)).last);
}

/// Types [text] into the open option list's search box.
Future<void> _search(DashHarness h, String text) async {
  final list = find.byWidgetPredicate((w) => w is DashOptionList);
  await h.enterText(
    find.descendant(of: list, matching: find.byType(EditableText)),
    text,
  );
}

Finder _optionList(Finder f) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: f,
);

Color? _color(WidgetTester tester, Finder text) =>
    tester.widget<Text>(text).style?.color;

String get _blend => 'House espresso blend';
String get _milk => 'Full cream milk';

void main() {
  group('the builder in the add-on recipe dialog (standalone)', () {
    testWidgets("MENU-RCP-001 seeds the rows from the host's lines", (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      expect(
        h.server.callsTo(_addonLines).single.path,
        '/recipes/addons/${extrasOption('shot')}',
      );
      expect(ingredientPicker(h, _blend), findsOneWidget);
      expect(qtyText(tester, qtyBox(h, _blend, 'One size')), '18');
      expect(_inBuilder(find.text('g')), findsOneWidget);
    });

    testWidgets('MENU-RCP-002 no "Copy from…" (no host passes copy sources)', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      expect(find.text(h.t('recipes.builder.copyFrom')), findsNothing);
    });

    testWidgets('MENU-RCP-003 "New ingredient" in the toolbar', (tester) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      expect(_inBuilder(find.text('New ingredient')), findsOneWidget);
      await h.tap(_inBuilder(find.text('New ingredient')));
      expect(find.byType(CreateIngredientDialog), findsOneWidget);
    });

    testWidgets('MENU-RCP-004 one size: no scale switch', (tester) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      expect(_inBuilder(find.textContaining('Scale from')), findsNothing);
      expect(_inBuilder(find.byType(DashSwitch)), findsNothing);
    });

    testWidgets('MENU-RCP-006 the one_size section reads "One size"', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      expect(inSection(0, find.text('One size')), findsOneWidget);
      expect(_inBuilder(find.text('one_size')), findsNothing);
    });

    testWidgets('MENU-RCP-007/008/011 cost, line cost and margin (43 %, '
        'plain) against the default price', (tester) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      // The line and the section total.
      expect(inSection(0, find.text('EGP 17.10')), findsNWidgets(2));
      expect(inSection(0, find.text('COST')), findsOneWidget);
      expect(inSection(0, find.text('MARGIN')), findsOneWidget);
      final margin = inSection(0, find.text('43%'));
      expect(margin, findsOneWidget);
      final c = tester.element(find.byType(RecipeBuilder)).madarColors;
      expect(_color(tester, margin), c.textPrimary);
    });

    testWidgets('MENU-RCP-009 the ingredient picker: active ingredients, the '
        'unit as a hint, the category searchable; picking sets name and unit', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      await h.tap(ingredientPicker(h, _blend));
      // The search box says "Search".
      expect(_optionList(find.text('Search')), findsOneWidget);
      // Inactive Vanilla powder is not offered.
      await _search(h, 'Vanilla');
      expect(_optionList(find.text('Vanilla syrup')), findsOneWidget);
      expect(_optionList(find.text('Vanilla powder')), findsNothing);
      // A category name finds its members.
      await _search(h, 'botanicals');
      expect(_optionList(find.text('Matcha powder')), findsOneWidget);
      expect(_optionList(find.text('Fresh mint')), findsOneWidget);
      expect(_optionList(find.text('Vanilla syrup')), findsNothing);
      await _search(h, 'zzz');
      expect(_optionList(find.text('No results found')), findsOneWidget);
      await _search(h, 'Oat milk');
      // The hint is the unit word.
      expect(_optionList(find.text('ml')), findsOneWidget);
      await h.tap(_optionList(find.text('Oat milk')).last);
      expect(ingredientPicker(h, 'Oat milk'), findsOneWidget);
      // 18 ml × 14 = 252.
      expect(_inBuilder(find.text('ml')), findsOneWidget);
      expect(inSection(0, find.text('EGP 2.52')), findsNWidgets(2));
      expect(qtyText(tester, qtyBox(h, 'Oat milk', 'One size')), '18');
    });

    testWidgets('MENU-RCP-010 quantity: digits and one dot, Arabic digits '
        'read as Latin, placeholder 0.000', (tester) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      final box = qtyBox(h, _blend, 'One size');
      await h.enterText(box, '2a7,5.1');
      expect(qtyText(tester, box), '27.51');
      await h.enterText(box, '٢٠');
      expect(qtyText(tester, box), '20');
      // 20 × 95.
      expect(inSection(0, find.text('EGP 19.00')), findsNWidgets(2));
      await h.tap(_inBuilder(find.text('Add ingredient')));
      expect(
        find.descendant(
          of: qtyBox(h, 'Ingredient', 'One size'),
          matching: find.text('0.000'),
        ),
        findsWidgets,
      );
    });

    testWidgets('MENU-RCP-007/011 "—" for a row without a unit cost or a '
        'numeric quantity, and with no rows', (tester) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      final box = qtyBox(h, _blend, 'One size');
      await h.enterText(box, '');
      // The line and the total are unknown; no margin.
      expect(inSection(0, find.text('—')), findsNWidgets(2));
      expect(inSection(0, find.text('MARGIN')), findsNothing);
      await h.enterText(box, '18');
      await h.tap(_inBuilder(find.text('Add ingredient')));
      await _pick(h, ingredientPicker(h, 'Ingredient'), 'Pistachio paste');
      await h.enterText(qtyBox(h, 'Pistachio paste', 'One size'), '10');
      // The blend line still costs; the paste has no unit cost, so the total
      // is unknown.
      expect(inSection(0, find.text('EGP 17.10')), findsOneWidget);
      expect(inSection(0, find.text('—')), findsNWidgets(2));
      await h.tap(
        find.bySemanticsLabel(h.t('recipes.builder.removeIngredient')).first,
      );
      await h.tap(
        find.bySemanticsLabel(h.t('recipes.builder.removeIngredient')).first,
      );
      // No rows: the cost is "—" and only "Add ingredient" is left.
      expect(inSection(0, find.text('—')), findsOneWidget);
      expect(_inBuilder(find.byType(DashSelect<String>)), findsNothing);
    });

    testWidgets('MENU-RCP-012 the trash removes its row and recosts', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      await h.tap(_inBuilder(find.text('Add ingredient')));
      await _pick(h, ingredientPicker(h, 'Ingredient'), 'Sugar');
      await h.enterText(qtyBox(h, 'Sugar', 'One size'), '10');
      // 1710 + 30.
      expect(inSection(0, find.text('EGP 17.40')), findsOneWidget);
      final trash = find.bySemanticsLabel('Remove ingredient');
      expect(trash, findsNWidgets(2));
      await h.tap(trash.first);
      expect(ingredientPicker(h, _blend), findsNothing);
      expect(ingredientPicker(h, 'Sugar'), findsOneWidget);
      expect(inSection(0, find.text('EGP 0.30')), findsNWidgets(2));
    });

    testWidgets('MENU-RCP-013 "Add ingredient" adds an empty row (unit g)', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      await h.tap(_inBuilder(find.text('Add ingredient')));
      expect(ingredientPicker(h, 'Ingredient'), findsOneWidget);
      expect(qtyText(tester, qtyBox(h, 'Ingredient', 'One size')), '');
      expect(_inBuilder(find.text('g')), findsNWidgets(2));
      // An empty row has no cost: the total is unknown.
      expect(inSection(0, find.text('—')), findsNWidgets(2));
    });

    testWidgets('MENU-RCP-016 the footer: Save disabled until a change, '
        '"Unsaved changes", a spinner while saving, then the new baseline', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      final log = SaveLog()..hold = Completer<void>();
      await openExtraShot(h, log: log, closeOnSave: false);
      final builder = find.byType(RecipeBuilder);
      DashButton save() => _button(tester, builder, 'Save recipe');
      expect(save().onPressed, isNull);
      expect(find.text('Unsaved changes'), findsNothing);

      final box = qtyBox(h, _blend, 'One size');
      await h.enterText(box, '20');
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(save().onPressed, isNotNull);
      // Back to the saved quantity: nothing to save.
      await h.enterText(box, '18');
      expect(find.text('Unsaved changes'), findsNothing);
      expect(save().onPressed, isNull);

      await h.enterText(box, '20');
      await h.tap(_inBuilder(find.text('Save recipe')));
      expect(save().loading, isTrue);
      expect(log.calls.single.$1.single.quantityUsed, 20);
      expect(log.calls.single.$2, isEmpty);
      log.hold!.complete();
      await h.settle();
      final put = h.server.callsTo(_optionRecipe, method: 'PUT').single;
      expect(put.path, '/modifier-options/${extrasOption('shot')}/recipe');
      expect(put.body, [
        {
          'ingredient_id': MenuSeedIds.ingredient('house_blend'),
          'quantity': 20,
          'unit': 'g',
        },
      ]);
      await h.expectToast('Recipe saved');
      expect(save().loading, isFalse);
      expect(find.text('Unsaved changes'), findsNothing);
      expect(save().onPressed, isNull);
      expect(qtyText(tester, box), '20');
    });

    testWidgets('MENU-RCP-016 a removed row is reported to the host; the '
        'host closes after a save (the web)', (tester) async {
      final h = await pumpRecipeHost(tester);
      final log = await openExtraShot(h);
      await h.tap(find.bySemanticsLabel('Remove ingredient'));
      await h.tap(_inBuilder(find.text('Save recipe')));
      expect(log.calls.single.$1, isEmpty);
      expect(log.calls.single.$2, [
        (sizeLabel: oneSize, ingredientName: _blend),
      ]);
      expect(h.server.callsTo(_optionRecipe).single.body, isEmpty);
      await h.expectToast('Recipe saved');
      expect(find.byType(RecipeBuilder), findsNothing);
    });

    testWidgets('MENU-RCP-016 a failed save: the server\'s words, still '
        'unsaved', (tester) async {
      final s = recipeServer();
      final refusal = MockResponse.unprocessable('Quantity must be positive');
      s.server.fail('PUT', _optionRecipe, refusal);
      final h = await pumpRecipeHost(tester, seeded: s);
      await openExtraShot(h);
      await h.enterText(qtyBox(h, _blend, 'One size'), '20');
      await h.tap(_inBuilder(find.text('Save recipe')));
      await h.expectToast(h.refusalWords(refusal));
      expect(find.byType(RecipeBuilder), findsOneWidget);
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(
        _button(tester, find.byType(RecipeBuilder), 'Save recipe').onPressed,
        isNotNull,
      );
    });

    testWidgets('MENU-RCP-023 closing with unsaved edits drops them (no '
        'guard, as on the web)', (tester) async {
      final h = await pumpRecipeHost(tester);
      await openExtraShot(h);
      await h.enterText(qtyBox(h, _blend, 'One size'), '25');
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.byType(RecipeBuilder), findsNothing);
      expect(h.server.callsTo(_optionRecipe), isEmpty);
      await openExtraShot(h);
      expect(qtyText(tester, qtyBox(h, _blend, 'One size')), '18');
      expect(find.text('Unsaved changes'), findsNothing);
    });
  });

  group("the builder in the item dialog's recipe section (deferred)", () {
    testWidgets("MENU-RCP-001 re-seeds only when the rows' content changes", (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      final (_, initial) = await openLatte(h);
      final box = qtyBox(h, _blend, 'Regular');
      await h.enterText(box, '20');
      // The host rebuilds with equal rows: the edit stays.
      initial.value = latteRows();
      await h.settle();
      expect(qtyText(tester, box), '20');
      // A saved quantity changed: the rows are replaced.
      initial.value = [
        for (final r in latteRows())
          if (r.sizeLabel == 'Regular' && r.ingredientName == _blend)
            RecipeRowInit(
              sizeLabel: r.sizeLabel,
              orgIngredientId: r.orgIngredientId,
              ingredientName: r.ingredientName,
              ingredientUnit: r.ingredientUnit,
              quantityUsed: 19,
            )
          else
            r,
      ];
      await h.settle();
      expect(qtyText(tester, box), '19');
      expect(qtyText(tester, qtyBox(h, _blend, 'Large')), '27');
    });

    testWidgets('MENU-RCP-003 no "New ingredient" in the item dialog', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      await openLatte(h);
      expect(_inBuilder(find.text('New ingredient')), findsNothing);
      expect(find.text(h.t('recipes.builder.copyFrom')), findsNothing);
    });

    testWidgets('MENU-RCP-004/006 a section per size, in order, and the '
        '"Scale from <base>" switch', (tester) async {
      final h = await pumpRecipeHost(tester);
      await openLatte(h);
      expect(inSection(0, find.text('Regular')), findsOneWidget);
      expect(inSection(1, find.text('Large')), findsOneWidget);
      expect(sizeSection(2), findsNothing);
      expect(_inBuilder(find.text('Scale from Regular')), findsOneWidget);
      expect(_inBuilder(find.byType(DashSwitch)), findsOneWidget);
    });

    testWidgets('MENU-RCP-005 scaling: the base rows × the factor, rounded '
        'to 3 decimals, replace the size; the switch hides the panel', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      final (log, _) = await openLatte(h);
      await h.tap(_inBuilder(find.text('Scale from Regular')));
      expect(
        _inBuilder(find.text('Multiply Regular quantities by:')),
        findsOneWidget,
      );
      final factor = find.byKey(const ValueKey('recipe-factor-Large'));
      expect(
        find.descendant(of: factor, matching: find.text('1.5')),
        findsWidgets,
      );
      await h.enterText(factor, '1,33a3');
      expect(qtyText(tester, factor), '1.333');
      // The factor sits by its ×; a quantity by its unit.
      TextAlign align(Finder f) => tester
          .widget<EditableText>(
            find.descendant(of: f, matching: find.byType(EditableText)),
          )
          .textAlign;
      expect(align(factor), TextAlign.left);
      expect(align(qtyBox(h, _blend, 'Large')), TextAlign.right);
      await h.tap(_inBuilder(find.text('Apply scaling')));
      expect(qtyText(tester, qtyBox(h, _blend, 'Large')), '23.994');
      expect(qtyText(tester, qtyBox(h, _milk, 'Large')), '239.94');
      expect(qtyText(tester, qtyBox(h, _blend, 'Regular')), '18');
      expect(
        [
          for (final r in log.last)
            if (r.sizeLabel == 'Large') r.quantityUsed,
        ],
        [23.994, 239.94],
      );
      // 23.994 × 95 + 239.94 × 4.2 = 2279.43 + 1007.748.
      expect(inSection(1, find.text('EGP 32.87')), findsOneWidget);
      await h.tap(_inBuilder(find.text('Scale from Regular')));
      expect(_inBuilder(find.text('Apply scaling')), findsNothing);
    });

    testWidgets('MENU-RCP-005 an untouched factor counts as × 1', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      await openLatte(h);
      await h.tap(_inBuilder(find.text('Scale from Regular')));
      await h.tap(_inBuilder(find.text('Apply scaling')));
      expect(qtyText(tester, qtyBox(h, _blend, 'Large')), '18');
      expect(qtyText(tester, qtyBox(h, _milk, 'Large')), '180');
    });

    testWidgets('MENU-RCP-005 (divergence) a cleared or zero factor leaves '
        "that size's rows alone", (tester) async {
      final h = await pumpRecipeHost(tester);
      await openLatte(h, sizes: const ['Regular', 'Large', 'Double']);
      await h.tap(_inBuilder(find.text('Scale from Regular')));
      await h.enterText(find.byKey(const ValueKey('recipe-factor-Large')), '2');
      await h.enterText(find.byKey(const ValueKey('recipe-factor-Large')), '');
      await h.enterText(
        find.byKey(const ValueKey('recipe-factor-Double')),
        '0',
      );
      await h.tap(_inBuilder(find.text('Apply scaling')));
      // The web drops every Large row here; Flutter keeps them.
      expect(qtyText(tester, qtyBox(h, _blend, 'Large')), '27');
      expect(qtyText(tester, qtyBox(h, _milk, 'Large')), '240');
      expect(inSection(2, find.byType(DashSelect<String>)), findsNothing);
    });

    testWidgets('MENU-RCP-007/008/011 each size: line costs, the total and '
        'a green margin against its price', (tester) async {
      final h = await pumpRecipeHost(tester);
      await openLatte(h);
      final c = tester.element(find.byType(RecipeBuilder)).madarColors;
      for (final (i, line1, line2, total, margin) in [
        (0, 'EGP 17.10', 'EGP 7.56', 'EGP 24.66', '78.6%'),
        (1, 'EGP 25.65', 'EGP 10.08', 'EGP 35.73', '73.5%'),
      ]) {
        expect(inSection(i, find.text(line1)), findsOneWidget);
        expect(inSection(i, find.text(line2)), findsOneWidget);
        expect(inSection(i, find.text(total)), findsOneWidget);
        final m = inSection(i, find.text(margin));
        expect(m, findsOneWidget);
        expect(_color(tester, m), DashTone.success.foreground(c));
      }
    });

    testWidgets('MENU-RCP-008 plain from 30 %, amber below; a size without a '
        'price uses the lowest', (tester) async {
      final h = await pumpRecipeHost(tester);
      // Regular 5000: (5000 − 2466) / 5000 = 50.7 %. Large has no price of
      // its own: the lowest (5000) gives (5000 − 3573) / 5000 = 28.5 %.
      await openLatte(h, prices: const {'Regular': 5000});
      final c = tester.element(find.byType(RecipeBuilder)).madarColors;
      final fair = inSection(0, find.text('50.7%'));
      expect(_color(tester, fair), c.textPrimary);
      final low = inSection(1, find.text('28.5%'));
      expect(_color(tester, low), DashTone.warning.foreground(c));
    });

    testWidgets('MENU-RCP-008 no price (or 0): no margin', (tester) async {
      final h = await pumpRecipeHost(tester);
      await openLatte(h, prices: const {'Regular': 0, 'Large': 0});
      expect(_inBuilder(find.text('MARGIN')), findsNothing);
      expect(inSection(0, find.text('EGP 24.66')), findsOneWidget);
    });

    testWidgets('MENU-RCP-013 "Add ingredient" adds the row to its own size', (
      tester,
    ) async {
      final h = await pumpRecipeHost(tester);
      await openLatte(h);
      await h.tap(inSection(1, find.text('Add ingredient')));
      expect(inSection(1, ingredientPicker(h, 'Ingredient')), findsOneWidget);
      expect(inSection(0, ingredientPicker(h, 'Ingredient')), findsNothing);
      expect(qtyBox(h, 'Ingredient', 'Large'), findsOneWidget);
    });

    testWidgets('MENU-RCP-014/015 deferred: no footer; only the rows that '
        'count reach the host, on every edit', (tester) async {
      final h = await pumpRecipeHost(tester);
      final (log, _) = await openLatte(h);
      expect(_inBuilder(find.text('Save recipe')), findsNothing);
      expect(log.last, hasLength(4));
      expect(
        log.last.first,
        CleanRow(
          sizeLabel: 'Regular',
          orgIngredientId: MenuSeedIds.ingredient('house_blend'),
          ingredientName: _blend,
          ingredientUnit: 'g',
          quantityUsed: 18,
        ),
      );
      await h.tap(inSection(0, find.text('Add ingredient')));
      expect(log.last, hasLength(4), reason: 'no name, no quantity');
      await _pick(h, inSection(0, ingredientPicker(h, 'Ingredient')), 'Sugar');
      expect(log.last, hasLength(4), reason: 'no quantity');
      final sugar = qtyBox(h, 'Sugar', 'Regular');
      await h.enterText(sugar, '0');
      expect(log.last, hasLength(4), reason: 'zero');
      await h.enterText(sugar, '5');
      expect(log.last, hasLength(5));
      expect(
        log.last.last,
        CleanRow(
          sizeLabel: 'Regular',
          orgIngredientId: MenuSeedIds.ingredient('sugar'),
          ingredientName: 'Sugar',
          ingredientUnit: 'g',
          quantityUsed: 5,
        ),
      );
      await h.enterText(qtyBox(h, _milk, 'Large'), '.');
      expect(log.last, hasLength(4), reason: 'not a number');
      expect(find.text('Unsaved changes'), findsNothing);
    });
  });

  group('the create-ingredient dialog', () {
    Future<DashHarness> open(
      WidgetTester tester, {
      Persona persona = Persona.owner,
      ({MockServer server, MockDb db})? seeded,
    }) async {
      final h = await pumpRecipeHost(tester, persona: persona, seeded: seeded);
      await openExtraShot(h);
      await h.tap(_inBuilder(find.text('New ingredient')));
      return h;
    }

    Finder name() => _inDialog(find.bySemanticsLabel('Name'));
    DashButton save(WidgetTester tester) =>
        _button(tester, find.byType(CreateIngredientDialog), 'Save');

    testWidgets('MENU-RCP-017 title and description', (tester) async {
      await open(tester);
      expect(_inDialog(find.text('Create ingredient')), findsOneWidget);
      expect(
        _inDialog(find.text('Define what each item and add-on consumes')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-RCP-018 Name has the focus; Save waits for a name', (
      tester,
    ) async {
      await open(tester);
      final editable = tester.widget<EditableText>(
        find.descendant(of: name(), matching: find.byType(EditableText)).first,
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(save(tester).onPressed, isNull);
      await tester.enterText(
        find.descendant(of: name(), matching: find.byType(EditableText)).first,
        '   ',
      );
      await tester.pump();
      expect(save(tester).onPressed, isNull);
      await tester.enterText(
        find.descendant(of: name(), matching: find.byType(EditableText)).first,
        'Rose syrup',
      );
      await tester.pump();
      expect(save(tester).onPressed, isNotNull);
    });

    testWidgets('MENU-RCP-019 the category: the org\'s ingredient '
        'categories, General first chosen', (tester) async {
      final h = await open(tester);
      expect(
        h.server.callsTo(_categories).single.path,
        '/inventory/orgs/$sabahOrg/categories',
      );
      expect(_inDialog(find.text('General')), findsOneWidget);
      await h.tap(_inDialog(find.text('General')));
      for (final c in ['Coffee beans', 'Milk', 'Syrups & sauces']) {
        expect(_optionList(find.text(c)), findsOneWidget);
      }
    });

    testWidgets('MENU-RCP-020 the unit: g (default), kg, ml, L, pcs', (
      tester,
    ) async {
      final h = await open(tester);
      expect(_inDialog(find.text('Unit')), findsOneWidget);
      await h.tap(_inDialog(find.text('g')));
      for (final u in ['g', 'kg', 'ml', 'L', 'pcs']) {
        expect(_optionList(find.text(u)), findsOneWidget);
      }
    });

    testWidgets(
      'MENU-RCP-021 the cost: optional, "—" when blank, digits only',
      (tester) async {
        final h = await open(tester);
        final cost = _inDialog(find.bySemanticsLabel('Cost / unit (EGP)'));
        expect(
          find.descendant(of: cost, matching: find.text('—')),
          findsWidgets,
        );
        await h.enterText(cost, '0,3x5');
        expect(qtyText(tester, cost), '0.35');
      },
    );

    testWidgets('MENU-RCP-022 Save creates the ingredient, refreshes the '
        'recipe reads, adds it to the first size, toasts and closes', (
      tester,
    ) async {
      final h = await open(tester);
      final catalogReads = h.server.callsTo(_catalog, method: 'GET').length;
      final lineReads = h.server.callsTo(_addonLines).length;
      await h.enterText(name(), '  Rose syrup ');
      await h.tap(_inDialog(find.text('General')));
      await h.tap(_optionList(find.text('Syrups & sauces')).last);
      await h.tap(_inDialog(find.text('g')));
      await h.tap(_optionList(find.text('ml')).last);
      await h.enterText(
        _inDialog(find.bySemanticsLabel('Cost / unit (EGP)')),
        '0.35',
      );
      await h.tap(_inDialog(find.text('Save')));

      final post = h.server.callsTo(_catalog, method: 'POST').single;
      expect(post.path, '/inventory/orgs/$sabahOrg/catalog');
      expect(post.body, {
        'name': 'Rose syrup',
        'category_id': MenuSeedIds.ingredientCategory('syrup'),
        'unit': 'ml',
        'cost_per_unit': 35,
      });
      await h.expectToast('Changes saved');
      expect(find.byType(CreateIngredientDialog), findsNothing);
      // invalidateRecipes: the ingredient catalog and the add-on's lines.
      expect(
        h.server.callsTo(_catalog, method: 'GET').length,
        catalogReads + 1,
      );
      expect(h.server.callsTo(_addonLines).length, lineReads + 1);
      // A new row in the first size, without a quantity.
      expect(ingredientPicker(h, 'Rose syrup'), findsOneWidget);
      expect(qtyText(tester, qtyBox(h, 'Rose syrup', 'One size')), '');
      expect(_inBuilder(find.text('ml')), findsOneWidget);
      expect(find.text('Unsaved changes'), findsOneWidget);
      final row = h.db![MenuTables.ingredients].firstWhere(
        (i) => i['name'] == 'Rose syrup',
      );
      expect(row?['cost_per_unit'], 35);
      expect(row?['category_slug'], 'syrup');
    });

    testWidgets('MENU-RCP-021/022 a blank cost and no category go as null '
        '(the categories read failed: the server files it under General)', (
      tester,
    ) async {
      final s = recipeServer();
      s.server.fail(
        'GET',
        _categories,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await open(tester, seeded: s);
      // Nothing to choose: the select shows its placeholder; the failure
      // says so (the web shows an empty select).
      expect(_inDialog(find.text('General')), findsNothing);
      expect(_inDialog(find.text('Category')), findsWidgets);
      expect(
        _inDialog(find.text("Couldn't load ingredient categories")),
        findsOneWidget,
      );
      expect(_inDialog(find.text('Retry')), findsOneWidget);
      await h.enterText(name(), 'Rose water');
      await h.tap(_inDialog(find.text('Save')));
      expect(h.server.callsTo(_catalog, method: 'POST').single.body, {
        'name': 'Rose water',
        'category_id': null,
        'unit': 'g',
        'cost_per_unit': null,
      });
      await h.expectToast('Changes saved');
      final row = s.db[MenuTables.ingredients].firstWhere(
        (i) => i['name'] == 'Rose water',
      );
      expect(row?['category_slug'], 'general');
      expect(row?['cost_per_unit'], isNull);
    });

    testWidgets('MENU-RCP-022 closed (Esc) while saving: the ingredient '
        'still joins the first size and "Changes saved" still shows', (
      tester,
    ) async {
      final s = recipeServer();
      final gate = s.server.hold('POST', _catalog);
      final h = await open(tester, seeded: s);
      await h.enterText(name(), 'Rose syrup');
      await h.tap(_inDialog(find.text('Save')));
      expect(save(tester).loading, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.byType(CreateIngredientDialog), findsNothing);
      expect(ingredientPicker(h, 'Rose syrup'), findsNothing);
      gate.release();
      await h.settle();
      expect(ingredientPicker(h, 'Rose syrup'), findsOneWidget);
      expect(qtyText(tester, qtyBox(h, 'Rose syrup', 'One size')), '');
      expect(find.text('Unsaved changes'), findsOneWidget);
      await h.expectToast('Changes saved');
    });

    testWidgets('MENU-RCP-022 Cancel closes without writing', (tester) async {
      final h = await open(tester);
      await h.enterText(name(), 'Rose syrup');
      await h.tap(_inDialog(find.text('Cancel')));
      expect(find.byType(CreateIngredientDialog), findsNothing);
      expect(h.server.callsTo(_catalog, method: 'POST'), isEmpty);
      expect(ingredientPicker(h, 'Rose syrup'), findsNothing);
      expect(find.text('Unsaved changes'), findsNothing);
    });

    testWidgets("MENU-RCP-022 a refused name: the server's words, the dialog "
        'stays open', (tester) async {
      final h = await open(tester);
      await h.enterText(name(), 'Oat milk');
      await h.tap(_inDialog(find.text('Save')));
      await h.expectToast(
        h.refusalWords(
          MockResponse.conflict(
            'An ingredient with this name already exists in the catalog',
          ),
        ),
      );
      expect(find.byType(CreateIngredientDialog), findsOneWidget);
      expect(save(tester).loading, isFalse);
      expect(save(tester).onPressed, isNotNull);
    });

    for (final p in [Persona.manager, Persona.limited]) {
      testWidgets('MENU-RCP-022 refusal: ${p.name} may not create '
          'ingredients (inventory.items.create)', (tester) async {
        final h = await open(tester, persona: p);
        await h.enterText(name(), 'Rose syrup');
        await h.tap(_inDialog(find.text('Save')));
        await h.expectToast(
          h.refusalWords(MockResponse.denied('inventory.items.create')),
        );
        expect(find.byType(CreateIngredientDialog), findsOneWidget);
        expect(h.server.callsTo(_catalog, method: 'POST').single.status, 403);
        expect(
          h.db![MenuTables.ingredients].firstWhere(
            (i) => i['name'] == 'Rose syrup',
          ),
          isNull,
        );
      });
    }
  });

  group('states', () {
    testWidgets('loading (MENU-AREA-014): until the catalog lands, rows show '
        'their saved names and costs read "—"', (tester) async {
      final s = recipeServer();
      final gate = s.server.hold('GET', _catalog);
      final h = await pumpRecipeHost(tester, seeded: s);
      await openExtraShot(h);
      expect(ingredientPicker(h, _blend), findsOneWidget);
      expect(inSection(0, find.text('—')), findsNWidgets(2));
      expect(inSection(0, find.text('MARGIN')), findsNothing);
      // The picker says it is loading, never "No results found".
      await h.tap(ingredientPicker(h, _blend));
      expect(_optionList(find.text('Loading…')), findsOneWidget);
      expect(_optionList(find.text('No results found')), findsNothing);
      gate.release();
      await h.settle();
      expect(_optionList(find.text('Loading…')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(inSection(0, find.text('EGP 17.10')), findsNWidgets(2));
      expect(inSection(0, find.text('43%')), findsOneWidget);
    });

    testWidgets('error (divergence): a failed catalog read says so with '
        'Retry; the rows stay, costs unknown; Retry asks only that read', (
      tester,
    ) async {
      final s = recipeServer();
      final boom = MockResponse.error(500, 'Catalog unavailable');
      s.server.fail('GET', _catalog, boom, times: null);
      final h = await pumpRecipeHost(tester, seeded: s);
      await openExtraShot(h);
      final failed = _inBuilder(find.text("Couldn't load the ingredients"));
      expect(failed, findsOneWidget);
      expect(_inBuilder(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(ingredientPicker(h, _blend), findsOneWidget);
      expect(inSection(0, find.text('—')), findsNWidgets(2));
      // The picker repeats the failure instead of "No results found".
      await h.tap(ingredientPicker(h, _blend));
      expect(
        _optionList(find.text("Couldn't load the ingredients")),
        findsOneWidget,
      );
      expect(_optionList(find.text('No results found')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();

      // Retry: the error stays, spinning, while the read runs again.
      s.server.clearFailures();
      final gate = s.server.hold('GET', _catalog);
      final lines = h.server.callsTo(_addonLines).length;
      await h.tap(_inBuilder(find.text('Retry')));
      expect(failed, findsOneWidget);
      expect(
        _button(tester, find.byType(RecipeBuilder), 'Retry').loading,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(failed, findsNothing);
      expect(inSection(0, find.text('EGP 17.10')), findsNWidgets(2));
      expect(h.server.callsTo(_addonLines).length, lines);
    });

    testWidgets('empty: an add-on without lines: one empty size, cost "—", '
        'nothing to save', (tester) async {
      final s = recipeServer();
      for (final g in s.db[MenuTables.groups].rows) {
        for (final o in (g['options'] as List).cast<Map<String, Object?>>()) {
          if (o['id'] == extrasOption('shot')) o['recipe'] = <Object?>[];
        }
      }
      final h = await pumpRecipeHost(tester, seeded: s);
      await openExtraShot(h);
      expect(_inBuilder(find.byType(DashSelect<String>)), findsNothing);
      expect(inSection(0, find.text('—')), findsOneWidget);
      expect(_inBuilder(find.text('Add ingredient')), findsOneWidget);
      expect(
        _button(tester, find.byType(RecipeBuilder), 'Save recipe').onPressed,
        isNull,
      );
    });
  });

  testWidgets('/menu/recipes (retired) lands on /menu/items, search dropped', (
    tester,
  ) async {
    final h = await pumpRecipeHost(tester);
    h.allowUnmatched = true; // the items page is another unit's
    await h.go('/menu/recipes?item=${MockSeed.menuItemId('latte')}');
    expect(h.location.path, '/menu/items');
    expect(h.location.queryParameters, isEmpty);
  });

  group('the create-ingredient dialog: categories states', () {
    testWidgets('loading: the category select says "Loading…" and offers '
        'nothing', (tester) async {
      final s = recipeServer();
      final gate = s.server.hold('GET', _categories);
      final h = await pumpRecipeHost(tester, seeded: s);
      await openExtraShot(h);
      await h.tap(_inBuilder(find.text('New ingredient')));
      expect(_inDialog(find.text('Loading…')), findsOneWidget);
      final select = tester.widget<DashSelectField<String>>(
        _inDialog(find.byType(DashSelectField<String>)).first,
      );
      expect(select.enabled, isFalse);
      gate.release();
      await h.settle();
      expect(_inDialog(find.text('Loading…')), findsNothing);
      expect(_inDialog(find.text('General')), findsOneWidget);
    });

    testWidgets('error: Retry reads the categories again and General is '
        'chosen', (tester) async {
      final s = recipeServer();
      s.server.fail(
        'GET',
        _categories,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpRecipeHost(tester, seeded: s);
      await openExtraShot(h);
      await h.tap(_inBuilder(find.text('New ingredient')));
      final failed = _inDialog(
        find.text("Couldn't load ingredient categories"),
      );
      expect(failed, findsOneWidget);
      s.server.clearFailures();
      final gate = s.server.hold('GET', _categories);
      await h.tap(_inDialog(find.text('Retry')));
      expect(failed, findsOneWidget);
      expect(
        _button(tester, find.byType(CreateIngredientDialog), 'Retry').loading,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(failed, findsNothing);
      expect(_inDialog(find.text('General')), findsOneWidget);
    });
  });
}
