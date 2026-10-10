// The web's `recipe/grid-model.test.ts`, ported.
import 'package:dashboard_catalog_menu/src/shared/grid_model.dart';
import 'package:flutter_test/flutter_test.dart';

GridBlock cup() => const GridBlock(
  key: 'cup',
  id: 'cup',
  label: 'Cup',
  lines: [
    GridLine(ingredientId: 'milk', quantity: '180', unit: 'g'),
    GridLine(ingredientId: 'beans', quantity: '18', unit: 'g'),
    GridLine(
      ingredientId: 'honey',
      quantity: '10',
      unit: 'g',
      source: LineSource.base,
    ),
    GridLine(
      ingredientId: 'cup16',
      quantity: '1',
      unit: 'pcs',
      source: LineSource.rule,
    ),
  ],
);

GridBlock can() => const GridBlock(
  key: 'can',
  id: 'can',
  label: 'Can',
  lines: [
    GridLine(ingredientId: 'milk', quantity: '250', unit: 'g'),
    GridLine(
      ingredientId: 'honey',
      quantity: '12',
      unit: 'g',
      source: LineSource.base,
    ),
  ],
);

Map<String, String> pristineOf(List<GridBlock> blocks) => {
  for (final b in blocks) b.key: ownRecipeSig(b.lines),
};

void main() {
  group('save diffing', () {
    test('excludes base/rule/linked lines from the payload', () {
      expect(ownPayload(cup().lines), [
        (ingredientId: 'milk', quantity: 180.0, unit: 'g'),
        (ingredientId: 'beans', quantity: 18.0, unit: 'g'),
      ]);
      expect(
        ownPayload(const [
          GridLine(
            ingredientId: 'x',
            quantity: '5',
            unit: 'g',
            source: LineSource.linked,
          ),
        ]),
        isEmpty,
      );
    });

    test('drops blank cells from the payload', () {
      expect(
        ownPayload(const [
          GridLine(ingredientId: 'x', quantity: '', unit: 'g'),
        ]),
        isEmpty,
      );
    });

    test('reports only sizes whose own lines changed', () {
      final blocks = [cup(), can()];
      final pristine = pristineOf(blocks);
      expect(changedSizeKeys(blocks, pristine), isEmpty);
      final edited = setCell(blocks, 'can', 'milk', '260', 'g');
      expect(changedSizeKeys(edited, pristine), {'can'});
    });

    test('ignores changes to non-own lines', () {
      final blocks = [cup(), can()];
      final pristine = pristineOf(blocks);
      final refreshed = [
        for (final b in blocks)
          b.withLines([
            for (final l in b.lines)
              l.source == LineSource.base ? l.withQuantity('99') : l,
          ]),
      ];
      expect(changedSizeKeys(refreshed, pristine), isEmpty);
    });

    test('an added empty row is no change; a new size is', () {
      final blocks = [cup(), can()];
      final pristine = pristineOf(blocks);
      expect(changedSizeKeys(addRow(blocks, 'sugar', 'g'), pristine), isEmpty);
      final withNew = [...blocks, const GridBlock(key: 'new-1', label: 'Big')];
      expect(changedSizeKeys(withNew, pristine), {'new-1'});
    });
  });

  group('grid pivot and edits', () {
    test('pivots rows own first, then base, then rule', () {
      final rows = buildGridRows([cup(), can()]);
      expect(rows.map((r) => r.key), [
        'own:milk',
        'own:beans',
        'base:honey',
        'rule:cup16',
      ]);
      expect(rows[0].cells, {'cup': '180', 'can': '250'});
      expect(rows[1].cells['can'], isNull);
    });

    test('setCell adds a missing own line beside a same-ingredient base '
        'line', () {
      final next = setCell([cup(), can()], 'can', 'honey', '5', 'g');
      final canLines = next[1].lines;
      expect(canLines.where((l) => l.ingredientId == 'honey'), hasLength(2));
      expect(
        ownPayload(canLines),
        contains((ingredientId: 'honey', quantity: 5.0, unit: 'g')),
      );
    });

    test('removeRow removes only own lines', () {
      expect(
        removeRow([
          cup(),
        ], 'honey')[0].lines.any((l) => l.ingredientId == 'honey'),
        isTrue,
      );
      expect(
        removeRow([
          cup(),
        ], 'milk')[0].lines.any((l) => l.ingredientId == 'milk'),
        isFalse,
      );
    });
  });

  group('copy and scale', () {
    test('copies own lines, keeping the target\'s base lines', () {
      final canLines = copyColumn([cup(), can()], 'cup', 'can')[1].lines;
      expect(ownPayload(canLines), [
        (ingredientId: 'milk', quantity: 180.0, unit: 'g'),
        (ingredientId: 'beans', quantity: 18.0, unit: 'g'),
      ]);
      expect(
        canLines.firstWhere((l) => l.source == LineSource.base).quantity,
        '12',
      );
      expect(canLines.any((l) => l.source == LineSource.rule), isFalse);
    });

    test('copies scaled', () {
      final next = copyColumn([cup(), can()], 'cup', 'can', 2);
      expect(ownPayload(next[1].lines).map((l) => l.quantity), [360, 36]);
    });

    test('scales own quantities in place, rounded to 3 decimals', () {
      final next = scaleColumn([cup()], 'cup', 1 / 3);
      expect(next[0].lines.map((l) => l.quantity), ['60', '6', '10', '1']);
      const blank = GridBlock(
        key: 'k',
        label: 'K',
        lines: [GridLine(ingredientId: 'a', quantity: '', unit: 'g')],
      );
      expect(scaleColumn([blank], 'k', 2)[0].lines[0].quantity, '');
      const one = GridBlock(
        key: 'k',
        label: 'K',
        lines: [GridLine(ingredientId: 'a', quantity: '1', unit: 'g')],
      );
      expect(scaleColumn([one], 'k', 0.3333)[0].lines[0].quantity, '0.333');
    });

    test('copy onto itself with a factor scales', () {
      expect(copyColumn([cup()], 'cup', 'cup', 2)[0].lines[0].quantity, '360');
    });
  });

  test('the swappable badge matches a group offering the same family', () {
    const slugs = {
      'milk': 'milk',
      'oat': 'milk',
      'beans': 'coffee_bean',
      'syrup': 'syrup',
    };
    const groups = <SwapGroupInfo>[
      (name: 'Extras', ingredientIds: ['syrup']),
      (name: 'Milk', ingredientIds: ['oat', 'milk']),
    ];
    String? slugOf(String id) => slugs[id];
    expect(swapGroupFor('milk', groups, slugOf), 'Milk');
    expect(swapGroupFor('coffee_bean', groups, slugOf), isNull);
    expect(swapGroupFor('syrup', groups, slugOf), isNull);
  });
}
