// The web's `recipe/label-model.test.ts`, ported.
import 'package:dashboard_catalog_menu/src/shared/label_model.dart';
import 'package:flutter_test/flutter_test.dart';

const List<LabelledLine> lines = [
  (sizeLabel: null, ingredientId: 'honey', quantity: '10.000', unit: 'g'),
  (sizeLabel: 'Cup', ingredientId: 'milk', quantity: '90', unit: 'g'),
  (sizeLabel: 'Can', ingredientId: 'milk', quantity: 110, unit: 'g'),
];

void main() {
  test('round-trips lines through columns', () {
    final blocks = toLabelBlocks(lines, const [], 'All sizes');
    expect(blocks.map((b) => b.key), [allSizes, 'L:Cup', 'L:Can']);
    expect(blocks[0].lines[0].quantity, '10');
    expect(fromLabelBlocks(blocks), [
      (sizeLabel: null, ingredientId: 'honey', quantity: 10.0, unit: 'g'),
      (sizeLabel: 'Cup', ingredientId: 'milk', quantity: 90.0, unit: 'g'),
      (sizeLabel: 'Can', ingredientId: 'milk', quantity: 110.0, unit: 'g'),
    ]);
  });

  test('adds known size labels as empty columns and drops blank cells', () {
    final blocks = addLabelColumn(
      toLabelBlocks(lines.sublist(0, 1), const ['Cup'], 'All'),
      'Can',
    );
    expect(blocks.map((b) => b.label), ['All', 'Cup', 'Can']);
    expect(blocks[2].lines, hasLength(1));
    expect(fromLabelBlocks(blocks), hasLength(1));
  });

  test('never removes the every-size column', () {
    final blocks = toLabelBlocks(lines, const [], 'All');
    expect(removeLabelColumn(blocks, allSizes), hasLength(3));
    expect(removeLabelColumn(blocks, 'L:Cup').map((b) => b.label), [
      'All',
      'Can',
    ]);
  });
}
