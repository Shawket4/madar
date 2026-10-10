// madar-shared's catalog_vectors.json (the web's `src/lib`, pinned to its tag;
// tool/sync_web_vectors.py): each case's unit price is [unitPrice] over its
// item view, as the web's `pricing/unit-price.test.ts` checks it.
import 'package:dashboard_catalog_menu/src/pricing/pricing_model.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final v = sharedVectors('catalog')! as Map<String, Object?>;
  final views = {
    for (final i in (v['items']! as List).cast<Map<String, Object?>>())
      i['key']! as String: i['view']! as Map<String, Object?>,
  };
  // Skipped: unknown_option, an option error (the size price is not in it).
  final cases = [
    for (final c in (v['cases']! as List).cast<Map<String, Object?>>())
      if ((c['expected']! as Map)['error']?['error'] != 'unknown_option') c,
  ];

  test(
    'covers the cases',
    () => expect(cases.length, greaterThanOrEqualTo(45)),
  );

  for (final c in cases) {
    test('${c['name']}', () {
      final view = views[c['item']]!;
      final sizes = [
        for (final s in (view['sizes']! as List).cast<Map<String, Object?>>())
          (
            label: s['label']! as String,
            price: s['price'] as int?,
            isActive: s['is_active']! as bool,
            branchPrice: s['branch_price'] as int?,
          ),
      ];
      final line = (c['expected']! as Map)['line'] as Map?;
      expect(
        unitPrice(
          sizes,
          (c['selection']! as Map)['size_label'] as String?,
          view['branch_price'] as int?,
        ),
        line?['unit_price'], // no_priced_size → null
      );
    });
  }
}
