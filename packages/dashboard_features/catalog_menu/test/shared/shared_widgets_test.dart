// The area's shared widgets in the real shell: the category dialog's
// required name, the label grid and the floating save bar.
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show OrgIngredient;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/items/items_page.dart';
import 'package:dashboard_catalog_menu/src/shared/ingredient_options.dart';
import 'package:dashboard_catalog_menu/src/shared/label_grid_editor.dart';
import 'package:dashboard_catalog_menu/src/shared/label_model.dart';
import 'package:dashboard_catalog_menu/src/shared/unsaved_bar.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DashHarness> _pump(
  WidgetTester tester, {
  DashSize size = DashSize.desktop,
  String locale = 'en',
}) => DashHarness.pump(
  tester,
  areas: const [catalogMenuArea],
  path: '/menu/items',
  size: size,
  locale: locale,
);

BuildContext _ctx(WidgetTester tester) =>
    tester.element(find.byType(MenuItemsPage));

void main() {
  testWidgets('the category dialog requires a name and writes nothing', (
    tester,
  ) async {
    final h = await _pump(tester);
    unawaited(showCategoryDialog(_ctx(tester), orgId: SeedIds.sabahOrg));
    await h.settle();
    expect(find.text(h.t('menu.newCategory')), findsOneWidget);
    await h.tapText(h.t('common.save'));
    expect(find.text(h.t('common.requiredField')), findsOneWidget);
    expect(h.server.calls.where((c) => c.method == 'POST'), isEmpty);
    await h.shot('shared/category-dialog');
  });

  testWidgets('the category dialog on a phone in Arabic', (tester) async {
    final h = await _pump(tester, size: DashSize.phone, locale: 'ar');
    unawaited(showCategoryDialog(_ctx(tester), orgId: SeedIds.sabahOrg));
    await h.settle();
    expect(find.text(h.t('menu.newCategory')), findsOneWidget);
    await h.shot('shared/category-dialog');
  });

  for (final (size, locale) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    testWidgets('the label grid edits a cell and adds a column '
        '(${size.name} $locale)', (tester) async {
      final h = await _pump(tester, size: size, locale: locale);
      final catalog = [
        for (final r in h.db![MenuTables.ingredients].rows)
          OrgIngredient.fromJson(r),
      ];
      final byId = {for (final c in catalog) c.id: c};
      var blocks = toLabelBlocks(
        [
          (
            sizeLabel: null,
            ingredientId: MenuSeedIds.ingredient('house_blend'),
            quantity: '18',
            unit: 'g',
          ),
          (
            sizeLabel: 'Large',
            ingredientId: MenuSeedIds.ingredient('house_blend'),
            quantity: '27',
            unit: 'g',
          ),
        ],
        const [],
        h.t('modeling.grid.allSizes'),
      );
      unawaited(
        showDashDialog<void>(
          _ctx(tester),
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => DashSurface(
              title: h.t('modeling.bases.edit'),
              body: LabelGridEditor(
                blocks: blocks,
                catalogById: byId,
                ingredientOptions: ingredientOptions(
                  catalog,
                  context.translator,
                ),
                removableKeys: {
                  for (final b in blocks)
                    if (b.key != allSizes) b.key,
                },
                onChanged: (b) => setState(() => blocks = b),
                onAddColumn: (label) =>
                    setState(() => blocks = addLabelColumn(blocks, label)),
                onRemoveColumn: (key) =>
                    setState(() => blocks = removeLabelColumn(blocks, key)),
              ),
            ),
          ),
        ),
      );
      await h.settle();
      expect(find.text('House espresso blend'), findsOneWidget);
      final cell = find.bySemanticsLabel(
        h.t(
          'modeling.grid.cellAria',
          args: {'ingredient': 'House espresso blend', 'size': 'Large'},
        ),
      );
      await h.enterText(cell, '3o,5');
      expect(blocks.last.lines.single.quantity, '3.5');
      await h.enterText(
        find.bySemanticsLabel(h.t('modeling.grid.sizeLabelPh')),
        'Cup',
      );
      await h.tapText(h.t('modeling.grid.addLabel'));
      expect(blocks.map((b) => b.label), [
        h.t('modeling.grid.allSizes'),
        'Large',
        'Cup',
      ]);
      expect(fromLabelBlocks(blocks), hasLength(2));
      await h.shot('shared/label-grid');
    });
  }

  testWidgets('the floating save bar', (tester) async {
    final h = await _pump(tester);
    var discarded = false;
    unawaited(
      showDashDialog<void>(
        _ctx(tester),
        builder: (context) => DashSurface(
          title: h.t('menu.pricing.title'),
          body: SizedBox(
            height: 160,
            child: MenuUnsavedBarHost(
              bar: MenuUnsavedBar(
                countText: h.t('menu.pricing.unsavedN', count: 3),
                discardLabel: h.t('menu.pricing.discard'),
                saveLabel: h.t('common.save'),
                onDiscard: () => discarded = true,
                onSave: () {},
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await h.settle();
    expect(find.text(h.t('menu.pricing.unsavedN', count: 3)), findsOneWidget);
    await h.tapText(h.t('menu.pricing.discard'));
    expect(discarded, isTrue);
    await h.shot('shared/unsaved-bar');
  });
}
