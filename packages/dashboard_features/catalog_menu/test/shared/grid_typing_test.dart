// Typing into the label grid a key at a time (the web's e4170ce: its grids
// remounted the cell on every keystroke, so "18" could not be typed). Each
// keystroke rebuilds the grid from the host's new blocks; the box being typed
// in must keep its value and its focus, also when a cell is cleared and when
// an edit changes the rows' order (`buildGridRows` orders rows by the first
// column that carries them).
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show OrgIngredient;
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/items/items_page.dart';
import 'package:dashboard_catalog_menu/src/shared/grid_model.dart';
import 'package:dashboard_catalog_menu/src/shared/ingredient_options.dart';
import 'package:dashboard_catalog_menu/src/shared/label_grid_editor.dart';
import 'package:dashboard_catalog_menu/src/shared/label_model.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'typing.dart';

String get _blendId => MenuSeedIds.ingredient('house_blend');
String get _milkId => MenuSeedIds.ingredient('full_milk');
const String _blend = 'House espresso blend';
const String _milk = 'Full cream milk';

/// Opens the label grid over the items page with [lines]; returns the harness
/// and a reader of the host's current blocks.
Future<(DashHarness, List<GridBlock> Function())> _open(
  WidgetTester tester,
  List<LabelledLine> lines,
) async {
  final h = await DashHarness.pump(
    tester,
    areas: const [catalogMenuArea],
    path: '/menu/items',
  );
  final catalog = [
    for (final r in h.db![MenuTables.ingredients].rows)
      OrgIngredient.fromJson(r),
  ];
  final byId = {for (final c in catalog) c.id: c};
  var blocks = toLabelBlocks(lines, const [], h.t('modeling.grid.allSizes'));
  unawaited(
    showDashDialog<void>(
      tester.element(find.byType(MenuItemsPage)),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => DashSurface(
          title: h.t('modeling.bases.edit'),
          body: LabelGridEditor(
            blocks: blocks,
            catalogById: byId,
            ingredientOptions: ingredientOptions(catalog, context.translator),
            onChanged: (b) => setState(() => blocks = b),
          ),
        ),
      ),
    ),
  );
  await h.settle();
  return (h, () => blocks);
}

Finder _cell(DashHarness h, String ingredient, String size) =>
    find.bySemanticsLabel(
      h.t(
        'modeling.grid.cellAria',
        args: {'ingredient': ingredient, 'size': size},
      ),
    );

String? _qty(List<GridBlock> blocks, String key, String ingredientId) => blocks
    .firstWhere((b) => b.key == key)
    .lines
    .where((l) => l.ingredientId == ingredientId)
    .firstOrNull
    ?.quantity;

void main() {
  testWidgets('typing "18" a key at a time keeps the value and the focus', (
    tester,
  ) async {
    final (h, blocks) = await _open(tester, [
      (sizeLabel: null, ingredientId: _blendId, quantity: '', unit: 'g'),
      (sizeLabel: null, ingredientId: _milkId, quantity: '', unit: 'ml'),
    ]);
    final all = h.t('modeling.grid.allSizes');
    final typing = await TypingSession.start(h, _cell(h, _blend, all));
    // A blank line reads 0 when loaded; the person deletes it first.
    await typing.clear();
    await typing.type('18');
    expect(typing.text, '18');
    expect(_qty(blocks(), allSizes, _blendId), '18');
    expect(_qty(blocks(), allSizes, _milkId), '0');
    typing.expectFocusHeld();
  });

  testWidgets('clearing a cell and typing on stays in the same row', (
    tester,
  ) async {
    final (h, blocks) = await _open(tester, [
      (sizeLabel: null, ingredientId: _blendId, quantity: '18', unit: 'g'),
      (sizeLabel: null, ingredientId: _milkId, quantity: '180', unit: 'ml'),
    ]);
    final all = h.t('modeling.grid.allSizes');
    final typing = await TypingSession.start(h, _cell(h, _milk, all));
    await typing.clear();
    expect(_qty(blocks(), allSizes, _milkId), '');
    typing.expectFocusHeld();
    await typing.type('24');
    expect(typing.text, '24');
    expect(_qty(blocks(), allSizes, _milkId), '24');
    expect(_qty(blocks(), allSizes, _blendId), '18');
    typing.expectFocusHeld();
  });

  testWidgets('an edit that moves the row up keeps typing in that row', (
    tester,
  ) async {
    // Only "Large" carries lines: milk first, then the blend. The first key
    // in the blend's All sizes cell gives All sizes its first line, so the
    // blend becomes the first row (rows follow the first column).
    final (h, blocks) = await _open(tester, [
      (sizeLabel: 'Large', ingredientId: _milkId, quantity: '240', unit: 'ml'),
      (sizeLabel: 'Large', ingredientId: _blendId, quantity: '27', unit: 'g'),
    ]);
    final all = h.t('modeling.grid.allSizes');
    final typing = await TypingSession.start(h, _cell(h, _blend, all));
    await typing.type('18');
    expect(_qty(blocks(), allSizes, _blendId), '18');
    expect(_qty(blocks(), allSizes, _milkId), isNull);
    expect(typing.focusedLabel, _cellLabel(h, _blend, all));
    expect(typing.text, '18');
    // The other cells kept their own values.
    expect(fieldText(tester, _cell(h, _milk, all)), '');
    expect(fieldText(tester, _cell(h, _blend, 'Large')), '27');
    expect(fieldText(tester, _cell(h, _milk, 'Large')), '240');
    // Enter moves down a row from where the person is.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await h.settle(rounds: 2);
    expect(typing.focusedLabel, _cellLabel(h, _milk, all));
  });
}

String _cellLabel(DashHarness h, String ingredient, String size) => h.t(
  'modeling.grid.cellAria',
  args: {'ingredient': ingredient, 'size': size},
);
