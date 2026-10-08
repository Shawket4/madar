// Purchasing: the page opens through the real shell (scaffold smoke test; the
// unit's builder adds the driven D-row tests beside it).
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Purchasing opens at /inventory/purchasing', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [inventoryArea],
      path: '/inventory/purchasing',
    );
    expect(h.location.path, '/inventory/purchasing');
    expect(find.text(h.t('inventory.purchasing.title')), findsWidgets);
    await h.shot('smoke');
  });
}
