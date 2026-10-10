// The editor's browser-side rules (`counts_data.dart`; the web's
// `count-editor.tsx` and `lib.ts`): the rows, the filters, the stats.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_inventory/src/counts/counts_data.dart';
import 'package:flutter_test/flutter_test.dart';

CountRow row(
  String id, {
  String name = 'x',
  String cat = 'c1',
  double book = 10,
  double opening = 10,
  num? cost = 100,
  bool isNew = false,
}) => CountRow(
  orgIngredientId: id,
  ingredientName: name,
  unit: 'g',
  categoryId: cat,
  categoryName: 'Cat $cat',
  openingQty: opening,
  bookQty: book,
  unitCost: cost,
  isNew: isNew,
);

StocktakeItem item(String id) => StocktakeItem(
  bookQty: 5,
  categoryId: 'c1',
  categoryName: 'Cat c1',
  createdAt: DateTime.utc(2026),
  id: 'i$id',
  ingredientName: 'Item $id',
  isNew: false,
  openingQty: 5,
  orgIngredientId: id,
  stocktakeId: 's',
  unit: 'g',
);

void main() {
  test('scope kind: full when missing', () {
    expect(stocktakeScopeKind(null), 'full');
    expect(stocktakeScopeKind(const {}), 'full');
    expect(stocktakeScopeKind(const {'kind': 'items'}), 'items');
  });

  test('rows: the snapshot in order, then found items it does not hold', () {
    final rows = countEditorRows([item('a'), item('b')], [row('b'), row('z')]);
    expect(rows.map((r) => r.orgIngredientId), ['a', 'b', 'z']);
    expect(rows[1].ingredientName, 'Item b', reason: 'the server wins');
  });

  test('categories in first-seen order', () {
    expect(
      countRowCategories([
        row('a', cat: 'm'),
        row('b', cat: 'k'),
        row('c', cat: 'm'),
      ]),
      [('m', 'Cat m'), ('k', 'Cat k')],
    );
  });

  test('search: case-insensitive, trimmed (W1), only with a visible '
      'character', () {
    final rows = [row('a', name: 'Oat Milk'), row('b', name: 'Sugar')];
    List<String> v(String q) => [
      for (final r in visibleCountRows(
        rows,
        search: q,
        category: null,
        filter: CountFilter.all,
        counts: const {},
        threshold: 5,
      ))
        r.orgIngredientId,
    ];
    expect(v('MILK'), ['a']);
    expect(v('  '), ['a', 'b']);
    expect(v(' oat '), ['a'], reason: 'outer spaces are ignored');
  });

  test('filters: to count, counted, flagged (at the threshold)', () {
    final rows = [row('a'), row('b'), row('c'), row('d', book: 0)];
    const counts = {'a': '10', 'b': '9.5', 'c': '', 'd': '1'};
    List<String> v(CountFilter f, {String? cat}) => [
      for (final r in visibleCountRows(
        rows,
        search: '',
        category: cat,
        filter: f,
        counts: counts,
        threshold: 5,
      ))
        r.orgIngredientId,
    ];
    expect(v(CountFilter.uncounted), ['c']);
    expect(v(CountFilter.counted), ['a', 'b', 'd']);
    expect(v(CountFilter.flagged), ['b', 'd']);
    expect(v(CountFilter.all, cat: 'zz'), isEmpty);
  });

  test('stats: net over counted rows with a cost; progress', () {
    final rows = [
      row('a', book: 10, cost: 100),
      row('b', book: 10, cost: null),
      row('c', book: 4, cost: 50),
      row('d'),
    ];
    final s = countStats(rows, const {'a': '8', 'b': '20', 'c': '5'});
    expect(s.net, -200 + 50);
    expect(s.counted, 3);
    expect(s.total, 4);
  });

  test('moved since start; the hydrated text', () {
    expect(movedSinceStart(10, 10), isFalse);
    expect(movedSinceStart(10, 10.0000000001), isFalse);
    expect(movedSinceStart(10, 9), isTrue);
    expect(countInputText(2100), '2100');
    expect(countInputText(2.5), '2.5');
  });

  test('a found item: nothing on the books, the catalog cost, new', () {
    final ing = OrgIngredient.fromJson({
      'id': 'x',
      'org_id': 'o',
      'name': 'Sugar',
      'unit': 'g',
      'category_id': 'c',
      'category_slug': 'dry',
      'category_name': 'Dry Goods',
      'cost_per_unit': 3.5,
      'is_active': true,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    final r = CountRow.found(ing);
    expect(r.bookQty, 0);
    expect(r.openingQty, 0);
    expect(r.unitCost, 3.5);
    expect(r.isNew, isTrue);
  });
}
