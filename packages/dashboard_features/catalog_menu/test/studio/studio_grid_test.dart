// The studio's Sizes, price & recipe section: the recipe grid, the base
// picker, the linked-copy bar and the "Set cost" popover
// (MENU-STUDIO-030..061, MENU-AREA-014). Figures from the area seed: Caffè
// Latte Regular = 180 ml full cream milk (EGP 0.042/ml) + 18 g house blend
// (EGP 0.95/g) + a 12oz cup (EGP 1.80) + a hot lid (EGP 0.60).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/studio/studio_widgets.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _latte = item('latte');
String _ing(String k) => MenuSeedIds.ingredient(k);

/// The quantity cell of [ingredient] in [size].
Finder cell(DashHarness h, String ingredient, String size) => studioLabel(
  h.t(
    'modeling.grid.cellAria',
    args: {'ingredient': ingredient, 'size': size},
  ),
);

/// The price box of [size].
Finder price(DashHarness h, String size) =>
    studioLabel(h.t('modeling.grid.priceAria', args: {'size': size}));

/// Every cell of the grid row [source]:[ingredientKey].
Finder row(String source, String ingredientKey) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(
        'studio-row-$source:${_ing(ingredientKey)}',
      ),
);

/// The ingredient cell of that row.
Finder rowHead(String source, String ingredientKey) =>
    find.byKey(ValueKey('studio-row-$source:${_ing(ingredientKey)}'));

/// The ⋯ menu of the [i]th size column.
Finder columnMenu(DashHarness h, int i) =>
    studioLabel(h.t('modeling.grid.columnActions')).at(i);

/// An option row's words in an open list (not the search box).
Finder option(Finder list, String name) => find.descendant(
  of: list,
  matching: find.byWidgetPredicate(
    (w) => w is Text && w.data == name,
  ),
);

/// [name] in an open dropdown menu.
Finder menuText(String name) => find.descendant(
  of: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuList'),
  matching: find.text(name),
);

/// The footer text containing [s].
Finder footerHas(String s) => studioHas(s);

void main() {
  group('MENU-STUDIO-030..036 the grid', () {
    testWidgets('MENU-STUDIO-030 rows: own, then base, then packaging rule', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final ys = [
        for (final r in [
          row('own', 'full_milk'),
          row('base', 'house_blend'),
          row('rule', 'cup_12oz'),
          row('rule', 'hot_lid'),
          row('rule', 'cup_16oz'),
          row('rule', 'sleeve'),
        ])
          tester.getTopLeft(inStudio(r).first).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      // Columns in size order, a Price row on top, the cost footer below.
      expect(
        tester.getTopLeft(fieldWithText('Regular')).dx,
        lessThan(tester.getTopLeft(fieldWithText('Large')).dx),
      );
      expect(
        tester.getTopLeft(price(h, 'Regular')).dy,
        lessThan(tester.getTopLeft(cell(h, 'Full cream milk', 'Regular')).dy),
      );
      expect(studioText(h.t('modeling.grid.cost')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-031 the catalog: active ingredients offered, '
        'with their unit; search matches the category', (tester) async {
      final h = await pumpStudio(tester);
      final call = lastCall(h, 'GET', catalogT);
      expect(call.path, '/inventory/orgs/${SeedIds.sabahOrg}/catalog');
      await h.tap(studioText(h.t('modeling.grid.addIngredient')));
      final list = find.byWidgetPredicate((w) => w is DashOptionList);
      final search = find.descendant(
        of: list,
        matching: find.byType(EditableText),
      );
      await h.enterText(search, 'Syrups');
      expect(option(list, 'Vanilla syrup'), findsOneWidget);
      // Inactive: not offered.
      await h.enterText(search, 'Vanilla powder');
      expect(option(list, 'Vanilla powder'), findsNothing);
      // Already an own row: not offered again.
      await h.enterText(search, 'Full cream');
      expect(option(list, 'Full cream milk'), findsNothing);
      await h.enterText(search, 'Oat');
      expect(find.descendant(of: list, matching: find.text('ml')), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
    });

    testWidgets('MENU-STUDIO-032 names, muted sources and their tags', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(
        find.descendant(
          of: inStudio(row('base', 'house_blend')),
          matching: find.text(
            h.t('modeling.grid.tagBase', args: {'name': 'Espresso shot'}),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: inStudio(row('rule', 'cup_12oz')),
          matching: find.text(h.t('modeling.grid.tagRule')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: inStudio(rowHead('own', 'full_milk')),
          matching: find.textContaining('Base:'),
        ),
        findsNothing,
      );
    });

    testWidgets('MENU-STUDIO-032/050 a linked row says "Follows …"', (
      tester,
    ) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final h = await pumpStudio(tester, key: 'iced_spanish', seeded: s);
      expect(
        find.descendant(
          of: inStudio(row('linked', 'full_milk')),
          matching: find.text(
            h.t('modeling.grid.tagLinked', args: {'name': 'Spanish Latte'}),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-AREA-014 until the catalog lands: "Unknown '
        'ingredient", no "+ ingredient" options, no "Set cost"', (
      tester,
    ) async {
      final s = studioServer();
      final gate = s.server.hold('GET', catalogT);
      final h = await pumpStudio(tester, key: 'pistachio_latte', seeded: s);
      expect(
        studioText(h.t('modeling.grid.unknownIngredient')),
        findsWidgets,
      );
      expect(studioText(h.t('menu.studio.recipe.setCost')), findsNothing);
      gate.release();
      await h.settle();
      expect(studioText(h.t('modeling.grid.unknownIngredient')), findsNothing);
      expect(studioText('Pistachio paste'), findsWidgets);
      expect(studioText(h.t('menu.studio.recipe.setCost')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-033 "swappable" on the milk row, never on a '
        'packaging rule', (tester) async {
      final h = await pumpStudio(tester);
      expect(
        find.descendant(
          of: inStudio(row('own', 'full_milk')),
          matching: find.text(
            h.t('modeling.grid.swappable', args: {'group': 'Milk'}),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: inStudio(row('rule', 'cup_12oz')),
          matching: find.textContaining('swappable'),
        ),
        findsNothing,
      );
    });

    testWidgets('MENU-STUDIO-034 "Set cost" on an ingredient with no cost', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'pistachio_latte');
      expect(
        find.descendant(
          of: inStudio(row('own', 'pistachio_paste')),
          matching: find.text(h.t('menu.studio.recipe.setCost')),
        ),
        findsOneWidget,
      );
      expect(studioText(h.t('menu.studio.recipe.setCost')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-035 an own cell keeps digits and one point', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      final c = cell(h, 'Full cream milk', 'Regular');
      expect(c, findsOneWidget);
      await h.enterText(c, '1,5a.2');
      expect(editableIn(tester, c).controller.text, '1.52');
      // The unit word after it; "—" placeholder on an empty cell.
      expect(
        find.descendant(
          of: inStudio(
            find.byKey(
              ValueKey(
                'studio-row-own:${_ing('full_milk')}|'
                '${MenuSeedIds.size('latte', 'Regular')}',
              ),
            ),
          ),
          matching: find.text('ml'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-035 focus selects the text', (tester) async {
      final h = await pumpStudio(tester);
      final c = cell(h, 'Full cream milk', 'Regular');
      await h.tap(c);
      final e = editableIn(tester, c);
      expect(e.controller.selection.start, 0);
      expect(e.controller.selection.end, e.controller.text.length);
    });

    testWidgets('MENU-STUDIO-036 a greyed cell reads "qty unit" or "—"', (
      tester,
    ) async {
      await pumpStudio(tester);
      final base = inStudio(row('base', 'house_blend'));
      expect(
        find.descendant(of: base, matching: find.textContaining('18')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: base, matching: find.textContaining('27')),
        findsOneWidget,
      );
      final cup = inStudio(row('rule', 'cup_16oz'));
      expect(find.descendant(of: cup, matching: find.text('—')), findsOneWidget);
    });
  });

  group('MENU-STUDIO-037..047 editing the grid', () {
    testWidgets('MENU-STUDIO-037 Enter / ↓ down a column, ↑ / Shift+Enter up; '
        'the hint', (tester) async {
      final h = await pumpStudio(tester);
      expect(studioText(h.t('modeling.grid.hint')), findsOneWidget);
      await h.tap(price(h, 'Large'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await h.settle(rounds: 2);
      expect(
        editableIn(tester, cell(h, 'Full cream milk', 'Large')).focusNode.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await h.settle(rounds: 2);
      expect(editableIn(tester, price(h, 'Large')).focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle(rounds: 2);
      expect(
        editableIn(tester, cell(h, 'Full cream milk', 'Large')).focusNode.hasFocus,
        isTrue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await h.settle(rounds: 2);
      expect(editableIn(tester, price(h, 'Large')).focusNode.hasFocus, isTrue);
      // A greyed row below stops the move.
      await h.tap(cell(h, 'Full cream milk', 'Large'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle(rounds: 2);
      expect(
        editableIn(tester, cell(h, 'Full cream milk', 'Large')).focusNode.hasFocus,
        isTrue,
      );
    });

    testWidgets('MENU-STUDIO-038 remove an own row from every size', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'spanish');
      expect(inStudio(rowHead('own', 'condensed_milk')), findsOneWidget);
      await h.tap(
        find.descendant(
          of: inStudio(row('own', 'condensed_milk')),
          matching: find.bySemanticsLabel(
            h.t('recipes.builder.removeIngredient'),
          ),
        ),
      );
      expect(inStudio(rowHead('own', 'condensed_milk')), findsNothing);
      await tapSave(h);
      final calls = h.server.callsTo(recipeT);
      expect(calls, hasLength(2));
      for (final c in calls) {
        final lines = ((c.body! as Map)['lines']! as List)
            .cast<Map<String, Object?>>();
        expect(lines.map((l) => l['ingredient_id']), [_ing('full_milk')]);
      }
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-039 "+ ingredient" adds a row to every size and '
        'focuses its first cell', (tester) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('modeling.grid.addIngredient')));
      await pickOption(h, 'Vanilla syrup');
      expect(inStudio(rowHead('own', 'vanilla_syrup')), findsOneWidget);
      final first = cell(h, 'Vanilla syrup', 'Regular');
      expect(editableIn(tester, first).controller.text, '');
      expect(editableIn(tester, cell(h, 'Vanilla syrup', 'Large')).controller.text, '');
      expect(editableIn(tester, first).focusNode.hasFocus, isTrue);
      // Blank cells send nothing: not dirty until a quantity is typed.
      expect(saveBar, findsNothing);
      await h.enterText(first, '10');
      expect(saveBar, findsOneWidget);
    });

    testWidgets('MENU-STUDIO-040 the Price row: "Price (EGP)", a box per size', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(studioText('${h.t('common.price')} (EGP)'), findsOneWidget);
      expect(editableIn(tester, price(h, 'Regular')).controller.text, '115');
      await h.enterText(price(h, 'Regular'), '12,5x');
      expect(editableIn(tester, price(h, 'Regular')).controller.text, '12.5');
      expect(
        inSection(
          h.t('menu.studio.sections.sizesTitle'),
          find.text(h.t('menu.studio.unsaved')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-040 Arabic: the currency label', (tester) async {
      final h = await pumpStudio(tester, locale: 'ar');
      expect(studioText('${h.t('common.price')} (ج.م)'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-041 a one-price item shows "Price", not a label '
        'box', (tester) async {
      final h = await pumpStudio(tester, key: 'cortado');
      expect(studioLabel(h.t('menu.sizeLabel')), findsNothing);
      expect(
        inSection(
          h.t('menu.studio.sections.sizesTitle'),
          find.text(h.t('menu.priceSection')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-041 label boxes: "e.g. Small", renamed = tinted', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(studioLabel(h.t('menu.sizeLabel')), findsNWidgets(2));
      await h.enterText(fieldWithText('Large'), '');
      expect(studioText(h.t('menu.studio.sizes.labelPh')), findsWidgets);
    });

    testWidgets('MENU-STUDIO-042 "+ Size": a blank column priced 0', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('modeling.grid.addSize')));
      expect(studioLabel(h.t('menu.sizeLabel')), findsNWidgets(3));
      expect(editableIn(tester, price(h, '')).controller.text, '0');
      expect(editableIn(tester, cell(h, 'Full cream milk', '')).controller.text, '');
    });

    testWidgets('MENU-STUDIO-042 on a one-price item both must be named', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'cortado');
      await h.tap(studioText(h.t('modeling.grid.addSize')));
      // The sentinel is blanked: two empty label boxes now.
      expect(studioLabel(h.t('menu.sizeLabel')), findsNWidgets(2));
      expect(
        inSection(
          h.t('menu.studio.sections.sizesTitle'),
          find.text(h.t('menu.priceSection')),
        ),
        findsNothing,
      );
      await tapSave(h);
      await h.expectToast(h.t('menu.studio.validate.sizeLabel'));
    });

    testWidgets('MENU-STUDIO-043 move a column earlier / later', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(columnMenu(h, 0));
      final earlier = find.bySemanticsLabel(h.t('modeling.grid.moveLeft'));
      expect(
        tester.widget<DashPressable>(
          find.ancestor(of: earlier, matching: find.byType(DashPressable)).first,
        ).enabled,
        isFalse,
      );
      await h.tap(find.bySemanticsLabel(h.t('modeling.grid.moveRight')));
      expect(
        tester.getTopLeft(fieldWithText('Large')).dx,
        lessThan(tester.getTopLeft(fieldWithText('Regular')).dx),
      );
      await tapSave(h);
      final sizes = (lastBody(h, 'PUT', sizesT)['sizes']! as List)
          .cast<Map<String, Object?>>();
      expect(sizes.map((s) => s['label']), ['Large', 'Regular']);
      await h.flushTimers();
    });

    testWidgets('MENU-STUDIO-044 "Copy from" replaces own lines only', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(columnMenu(h, 1));
      await h.tap(find.bySemanticsLabel(h.t('modeling.grid.copyFrom')));
      await h.shot('studio/copy-from');
      await h.tap(menuText('Regular'));
      expect(
        editableIn(tester, cell(h, 'Full cream milk', 'Large')).controller.text,
        '180',
      );
      // The base and rule lines stay.
      expect(inStudio(rowHead('rule', 'sleeve')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-045..047 Scale: start from, multiply by', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(columnMenu(h, 1));
      await h.tap(find.bySemanticsLabel(h.t('modeling.grid.scale')));
      expect(
        find.text(h.t('modeling.grid.scaleTitle', args: {'size': 'Large'})),
        findsOneWidget,
      );
      expect(find.text(h.t('modeling.grid.scaleDesc')), findsOneWidget);
      await h.shot('studio/scale-dialog');
      final factor = find.bySemanticsLabel(h.t('modeling.grid.factor'));
      expect(editableIn(tester, factor).controller.text, '1');
      await h.enterText(factor, '0');
      await h.tap(find.text(h.t('modeling.grid.apply')));
      expect(find.text(h.t('modeling.grid.factorInvalid')), findsOneWidget);
      await h.enterText(factor, '2');
      await h.tap(find.text(h.t('modeling.grid.apply')));
      expect(
        editableIn(tester, cell(h, 'Full cream milk', 'Large')).controller.text,
        '480',
      );
      // From another size: Large = Regular × 1.5.
      await h.tap(columnMenu(h, 1));
      await h.tap(find.bySemanticsLabel(h.t('modeling.grid.scale')));
      await h.tap(
        find.descendant(
          of: find.byType(DashSurface),
          matching: find.byType(DashSelect<String>),
        ),
      );
      await h.tap(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is DashOptionList),
          matching: find.text('Regular'),
        ),
      );
      await h.enterText(
        find.bySemanticsLabel(h.t('modeling.grid.factor')),
        '1.5',
      );
      await h.tap(find.text(h.t('modeling.grid.apply')));
      expect(
        editableIn(tester, cell(h, 'Full cream milk', 'Large')).controller.text,
        '270',
      );
    });

    testWidgets('MENU-STUDIO-047 Cancel leaves the column as it was', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(columnMenu(h, 1));
      await h.tap(find.bySemanticsLabel(h.t('modeling.grid.scale')));
      await h.enterText(
        find.bySemanticsLabel(h.t('modeling.grid.factor')),
        '3',
      );
      await h.tap(find.text(h.t('common.cancel')).last);
      expect(
        editableIn(tester, cell(h, 'Full cream milk', 'Large')).controller.text,
        '240',
      );
    });

    testWidgets('MENU-STUDIO-046 "Remove size" drops the column, no confirm', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(columnMenu(h, 0));
      await h.tap(find.bySemanticsLabel(h.t('menu.removeSize')));
      expect(fieldWithText('Regular'), findsNothing);
      expect(fieldWithText('Large'), findsOneWidget);
      await tapSave(h);
      final sizes = (lastBody(h, 'PUT', sizesT)['sizes']! as List);
      expect(sizes, hasLength(1));
      await h.flushTimers();
    });
  });

  group('MENU-STUDIO-048..049 cost and read-only', () {
    testWidgets('MENU-STUDIO-048 the server cost, then "≈" while edited', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      // Regular: 180×4.2 + 18×95 + 180 + 60 = 2,706 piastres; 1 − 27.06/115.
      expect(footerHas('EGP 27.06 · 76.5%'), findsOneWidget);
      await h.enterText(cell(h, 'Full cream milk', 'Regular'), '200');
      // 200×4.2 + 1,710 + 240 = 2,790.
      expect(footerHas('≈ EGP 27.90 · 75.7%'), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-048 an uncosted line: "Cost incomplete"; no '
        'line at all: "—"', (tester) async {
      final h = await pumpStudio(tester, key: 'pistachio_latte');
      expect(
        studioText(h.t('menu.studio.recipe.incomplete')),
        findsNWidgets(2),
      );
      await h.go(studioPath('cookie'));
      expect(
        inSection(
          h.t('menu.studio.sections.sizesTitle'),
          find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-049 refusal (manager): a read-only grid', (
      tester,
    ) async {
      final h = await pumpStudio(
        tester,
        key: 'pistachio_latte',
        persona: Persona.manager,
      );
      expect(cell(h, 'Full cream milk', 'Regular'), findsNothing);
      expect(
        tester.widget<TextField>(
          find.descendant(
            of: price(h, 'Regular'),
            matching: find.byType(TextField),
          ),
        ).enabled,
        isFalse,
      );
      expect(
        tester.widget<TextField>(
          find.descendant(
            of: studioLabel(h.t('menu.sizeLabel')).first,
            matching: find.byType(TextField),
          ),
        ).enabled,
        isFalse,
      );
      expect(studioLabel(h.t('modeling.grid.columnActions')), findsNothing);
      expect(
        inSection(
          h.t('menu.studio.sections.sizesTitle'),
          find.text(h.t('modeling.grid.addSize')),
        ),
        findsNothing,
      );
      expect(studioText(h.t('modeling.grid.addIngredient')), findsNothing);
      expect(
        studioLabel(h.t('recipes.builder.removeIngredient')),
        findsNothing,
      );
      expect(studioText(h.t('menu.studio.recipe.setCost')), findsNothing);
      await h.shot('studio/read-only');
    });
  });

  group('MENU-STUDIO-050..057 base and link', () {
    testWidgets('MENU-STUDIO-050 a linked copy: banner, text cells, a '
        'trimmed column menu, no base picker', (tester) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final h = await pumpStudio(tester, key: 'iced_spanish', seeded: s);
      expect(
        studioText(
          h.t('modeling.grid.followsReadOnly', args: {'name': 'Spanish Latte'}),
        ),
        findsOneWidget,
      );
      expect(cell(h, 'Full cream milk', 'Regular'), findsNothing);
      expect(studioText(h.t('modeling.grid.addIngredient')), findsNothing);
      expect(
        inSection(
          h.t('menu.studio.sections.sizesTitle'),
          find.text(h.t('modeling.grid.addSize')),
        ),
        findsNothing,
      );
      expect(
        studioLabel(h.t('recipes.builder.removeIngredient')),
        findsNothing,
      );
      expect(studioLabel(h.t('modeling.base.label')), findsNothing);
      // Labels and prices stay editable; the menu keeps move and remove.
      expect(
        tester.widget<TextField>(
          find.descendant(
            of: price(h, 'Regular'),
            matching: find.byType(TextField),
          ),
        ).enabled,
        isTrue,
      );
      await h.tap(columnMenu(h, 0));
      expect(find.bySemanticsLabel(h.t('modeling.grid.moveRight')), findsOneWidget);
      expect(find.bySemanticsLabel(h.t('menu.removeSize')), findsOneWidget);
      expect(find.bySemanticsLabel(h.t('modeling.grid.copyFrom')), findsNothing);
      expect(find.bySemanticsLabel(h.t('modeling.grid.scale')), findsNothing);
      await h.shot('studio/linked-copy');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
    });

    testWidgets('MENU-STUDIO-051 the base picker: label, value, options', (
      tester,
    ) async {
      final s = studioServer();
      s.db[MenuTables.sizes].update(MenuSeedIds.size('latte', 'Large'), {
        'base_id': MenuSeedIds.base('mocha_old'),
      });
      final h = await pumpStudio(tester, seeded: s);
      expect(studioText(h.t('modeling.base.label')), findsOneWidget);
      // Sizes disagree: "Different per size".
      expect(studioText(h.t('modeling.base.mixed')), findsOneWidget);
      await h.tap(find.byKey(const ValueKey('studio-base-picker')));
      final list = find.byWidgetPredicate((w) => w is DashOptionList);
      for (final name in [
        h.t('modeling.base.none'),
        'Espresso shot',
        'Iced build',
        // Inactive but in use here.
        'Mocha base (old)',
      ]) {
        expect(find.descendant(of: list, matching: find.text(name)), findsOneWidget);
      }
      await h.shot('studio/base-picker');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
    });

    testWidgets('MENU-STUDIO-051 an inactive base not in use is not offered', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      expect(studioText('Espresso shot'), findsOneWidget);
      await h.tap(find.byKey(const ValueKey('studio-base-picker')));
      final list = find.byWidgetPredicate((w) => w is DashOptionList);
      expect(
        find.descendant(of: list, matching: find.text('Mocha base (old)')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
    });

    testWidgets('MENU-STUDIO-051 disabled while sizes are dirty, with the note', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.enterText(price(h, 'Regular'), '116');
      expect(studioText(h.t('modeling.base.saveFirst')), findsOneWidget);
      final picker = tester.widget<DashSelect<String>>(
        find.byKey(const ValueKey('studio-base-picker')),
      );
      expect(picker.enabled, isFalse);
    });

    testWidgets('MENU-STUDIO-051 refusal (manager): the picker is disabled', (
      tester,
    ) async {
      await pumpStudio(tester, persona: Persona.manager);
      final picker = tester.widget<DashSelect<String>>(
        find.byKey(const ValueKey('studio-base-picker')),
      );
      expect(picker.enabled, isFalse);
    });

    testWidgets('MENU-STUDIO-052 apply a base to every saved size', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(find.byKey(const ValueKey('studio-base-picker')));
      await pickOption(h, 'Iced build');
      final calls = h.server.callsTo(baseT);
      expect(calls.map((c) => c.path), [
        '/menu-item-sizes/${MenuSeedIds.size('latte', 'Regular')}/base',
        '/menu-item-sizes/${MenuSeedIds.size('latte', 'Large')}/base',
      ]);
      for (final c in calls) {
        expect(c.body, {'base_id': MenuSeedIds.base('iced_build')});
      }
      await h.expectToast(h.t('modeling.base.applied', count: 2));
      expect(h.server.callsTo(studioT), hasLength(2));
      expect(inStudio(rowHead('base', 'ice')), findsOneWidget);
      expect(inStudio(rowHead('base', 'house_blend')), findsNothing);
      // Base lines never make the section dirty.
      expect(saveBar, findsNothing);
    });

    testWidgets('MENU-STUDIO-052 Arabic: the applied toast in Arabic', (
      tester,
    ) async {
      final h = await pumpStudio(tester, locale: 'ar');
      await h.tap(find.byKey(const ValueKey('studio-base-picker')));
      await pickOption(h, 'Iced build');
      await h.expectToast(h.t('modeling.base.applied', count: 2));
      expect(h.t('modeling.base.applied', count: 2), contains('القاعدة'));
    });

    testWidgets('MENU-STUDIO-052 None removes it; a refusal still refetches', (
      tester,
    ) async {
      final s = studioServer();
      final h = await pumpStudio(tester, seeded: s);
      await h.tap(find.byKey(const ValueKey('studio-base-picker')));
      await pickOption(h, h.t('modeling.base.none'));
      expect(lastBody(h, 'PUT', baseT), {'base_id': null});
      await h.expectToast(h.t('modeling.base.cleared'));
      expect(inStudio(rowHead('base', 'house_blend')), findsNothing);
      final refusal = MockResponse.badRequest(
        'Recipe base not found in this organization',
      );
      s.server.fail('PUT', baseT, refusal);
      final before = h.server.callsTo(studioT).length;
      await h.tap(find.byKey(const ValueKey('studio-base-picker')));
      await pickOption(h, 'Espresso shot');
      await h.expectToast(h.refusalWords(refusal));
      expect(h.server.callsTo(studioT).length, before + 1);
    });

    testWidgets('MENU-STUDIO-053 "Manage bases" opens /menu/bases', (
      tester,
    ) async {
      final h = await pumpStudio(tester);
      await h.tap(studioText(h.t('modeling.base.manage')));
      expect(h.location.path, '/menu/bases');
    });

    testWidgets('MENU-STUDIO-054 "Recipe follows" + the source link; "Out of '
        'sync" when it drifted', (tester) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      // Drift: the copy's stored line no longer matches its source.
      final line = s.db[MenuTables.recipeLines].firstWhere(
        (l) => l['menu_item_id'] == item('iced_spanish'),
      )!;
      line['quantity'] = '999';
      final h = await pumpStudio(tester, key: 'iced_spanish', seeded: s);
      expect(lastCall(h, 'GET', linkT).path, '/menu-items/${item('iced_spanish')}/recipe-link');
      expect(studioText(h.t('modeling.linked.follows')), findsOneWidget);
      expect(studioText(h.t('modeling.linked.outOfSync')), findsOneWidget);
      // The web's neutral outline badge, not a warning wash.
      expect(
        find.ancestor(
          of: studioText(h.t('modeling.linked.outOfSync')),
          matching: find.byType(StudioOutlineBadge),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: studioText(h.t('modeling.linked.outOfSync')),
          matching: find.byType(DashBadge),
        ),
        findsNothing,
      );
      await h.shot('studio/out-of-sync');
      await h.tap(studioText('Spanish Latte').last);
      expect(h.location.path, '/menu/items/${item('spanish')}');
    });

    testWidgets('MENU-STUDIO-054 in sync: no badge', (tester) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final h = await pumpStudio(tester, key: 'iced_spanish', seeded: s);
      expect(studioText(h.t('modeling.linked.outOfSync')), findsNothing);
    });

    testWidgets('MENU-STUDIO-055 Unlink: confirm, DELETE, toast, own lines', (
      tester,
    ) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final h = await pumpStudio(tester, key: 'iced_spanish', seeded: s);
      await h.tap(studioText(h.t('modeling.linked.unlink')));
      expect(find.text(h.t('modeling.linked.unlinkTitle')), findsOneWidget);
      expect(
        find.text(
          h.t('modeling.linked.unlinkDesc', args: {'name': 'Spanish Latte'}),
        ),
        findsOneWidget,
      );
      await h.tap(find.text(h.t('modeling.linked.unlink')).last);
      expect(lastCall(h, 'DELETE', linkT).path, '/menu-items/${item('iced_spanish')}/recipe-link');
      await h.expectToast(h.t('modeling.linked.unlinked'));
      expect(cell(h, 'Full cream milk', 'Regular'), findsOneWidget);
      expect(studioText(h.t('modeling.linked.follows')), findsNothing);
    });

    testWidgets('MENU-STUDIO-055 a refused unlink toasts the server', (
      tester,
    ) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final refusal = MockResponse.denied('menu.items.edit');
      s.server.fail('DELETE', linkT, refusal);
      final h = await pumpStudio(tester, key: 'iced_spanish', seeded: s);
      await h.tap(studioText(h.t('modeling.linked.unlink')));
      await h.tap(find.text(h.t('modeling.linked.unlink')).last);
      await h.expectToast(h.refusalWords(refusal));
      expect(studioText(h.t('modeling.linked.follows')), findsOneWidget);
    });

    testWidgets('MENU-STUDIO-056 a source lists its copies by name', (
      tester,
    ) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final h = await pumpStudio(tester, key: 'spanish', seeded: s);
      expect(studioText(h.t('modeling.linked.copies')), findsOneWidget);
      expect(
        h.server.callsTo(itemT, method: 'GET').map((c) => c.path),
        contains('/menu-items/${item('iced_spanish')}'),
      );
      await h.tap(studioText('Iced Spanish Latte'));
      expect(h.location.path, '/menu/items/${item('iced_spanish')}');
    });

    testWidgets('MENU-STUDIO-056 a copy whose read fails reads "Copy 1"', (
      tester,
    ) async {
      final s = studioServer();
      linkCopy(s.db, 'iced_spanish', 'spanish');
      s.server.fail(
        'GET',
        itemT,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpStudio(tester, key: 'spanish', seeded: s);
      expect(
        studioText(h.t('modeling.linked.copyN', args: {'n': 1})),
        findsOneWidget,
      );
    });

    testWidgets('MENU-STUDIO-057 refusal (manager): no Unlink', (
      tester,
    ) async {
      final s = studioServer(persona: Persona.manager);
      linkCopy(s.db, 'iced_spanish', 'spanish');
      final h = await pumpStudio(
        tester,
        key: 'iced_spanish',
        persona: Persona.manager,
        seeded: s,
      );
      expect(studioText(h.t('modeling.linked.follows')), findsOneWidget);
      expect(studioText(h.t('modeling.linked.unlink')), findsNothing);
    });
  });

  group('MENU-STUDIO-058..061', () {
    testWidgets('MENU-STUDIO-058 dirty = sizes or own lines; typing it back '
        'is clean again', (tester) async {
      final h = await pumpStudio(tester);
      await h.enterText(cell(h, 'Full cream milk', 'Regular'), '181');
      expect(saveBar, findsOneWidget);
      await h.enterText(cell(h, 'Full cream milk', 'Regular'), '180');
      expect(saveBar, findsNothing);
      await h.enterText(price(h, 'Large'), '135.0');
      expect(saveBar, findsOneWidget);
    });

    testWidgets('MENU-STUDIO-059 seeding: active sizes by sort, plain figures', (
      tester,
    ) async {
      final s = studioServer();
      s.db[MenuTables.sizes].update(MenuSeedIds.size('latte', 'Regular'), {
        'sort': 5,
      });
      s.db[MenuTables.sizes].insert({
        'menu_item_id': _latte,
        'label': 'Kids',
        'price_override': 9000,
        'is_active': false,
        'sort': 0,
        'base_id': null,
      }, timestamps: false);
      final h = await pumpStudio(tester, seeded: s);
      expect(fieldWithText('Kids'), findsNothing);
      expect(
        tester.getTopLeft(fieldWithText('Large')).dx,
        lessThan(tester.getTopLeft(fieldWithText('Regular')).dx),
      );
      expect(editableIn(tester, cell(h, 'Full cream milk', 'Regular')).controller.text, '180');
      expect(editableIn(tester, price(h, 'Large')).controller.text, '135');
    });

    testWidgets('MENU-STUDIO-060 phone: the grid scrolls sideways', (
      tester,
    ) async {
      final h = await pumpStudio(tester, size: DashSize.phone);
      final grid = inSection(
        h.t('menu.studio.sections.sizesTitle'),
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      expect(grid, findsWidgets);
      final pos = tester.state<ScrollableState>(grid.first).position;
      expect(pos.maxScrollExtent, greaterThan(0));
      await h.shot('studio/grid-phone');
    });

    testWidgets('MENU-STUDIO-061 "Set cost": validate, PATCH, toast, refresh', (
      tester,
    ) async {
      final h = await pumpStudio(tester, key: 'pistachio_latte');
      await h.tap(studioText(h.t('menu.studio.recipe.setCost')));
      // The hint above the box carries the same words: the box is last.
      final box = find
          .bySemanticsLabel(
            h.t('menu.studio.recipe.costPerUnit', args: {'unit': 'g'}),
          )
          .last;
      expect(find.text('Pistachio paste'), findsWidgets);
      await h.shot('studio/set-cost');
      await h.enterText(box, '-1');
      await h.tap(find.text(h.t('common.save')).last);
      await h.expectToast(h.t('menu.studio.recipe.invalidCost'));
      expect(h.server.callsTo(catalogItemT), isEmpty);
      final catalogReads = h.server.callsTo(catalogT).length;
      await h.enterText(box, '1.25');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      final call = lastCall(h, 'PATCH', catalogItemT);
      expect(
        call.path,
        '/inventory/orgs/${SeedIds.sabahOrg}/catalog/${_ing('pistachio_paste')}',
      );
      expect(call.body, {'cost_per_unit': 125.0});
      await h.expectToast(h.t('menu.studio.recipe.costSet'));
      expect(h.server.callsTo(catalogT).length, catalogReads + 1);
      expect(h.server.callsTo(studioT), hasLength(2));
      expect(studioText(h.t('menu.studio.recipe.setCost')), findsNothing);
    });

    testWidgets('MENU-STUDIO-061 a refused cost toasts the server', (
      tester,
    ) async {
      final s = studioServer();
      final refusal = MockResponse.denied('inventory.adjust');
      s.server.fail('PATCH', catalogItemT, refusal);
      final h = await pumpStudio(tester, key: 'pistachio_latte', seeded: s);
      await h.tap(studioText(h.t('menu.studio.recipe.setCost')));
      await h.enterText(
        find
            .bySemanticsLabel(
              h.t('menu.studio.recipe.costPerUnit', args: {'unit': 'g'}),
            )
            .last,
        '2',
      );
      await h.tap(find.text(h.t('common.save')).last);
      await h.expectToast(h.refusalWords(refusal));
    });
  });
}
