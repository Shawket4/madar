// Ingredients: the page opens through the real shell (scaffold smoke test; the
// unit's builder adds the driven D-row tests beside it).
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Ingredients opens at /inventory/ingredients', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [inventoryArea],
      path: '/inventory/ingredients',
    );
    expect(h.location.path, '/inventory/ingredients');
    expect(find.text(h.t('inventory.catalog.title')), findsWidgets);
    await h.shot('smoke');
  });
}
