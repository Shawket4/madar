// Waste log: the page opens through the real shell (scaffold smoke test; the
// unit's builder adds the driven D-row tests beside it).
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Waste log opens at /inventory/waste', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [inventoryArea],
      path: '/inventory/waste',
    );
    expect(h.location.path, '/inventory/waste');
    expect(find.text(h.t('inventory.waste.title')), findsWidgets);
    await h.shot('smoke');
  });
}
