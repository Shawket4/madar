// Inventory settings: the page opens through the real shell (scaffold smoke test; the
// unit's builder adds the driven D-row tests beside it).
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Inventory settings opens at /inventory/settings', (
    tester,
  ) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [inventoryArea],
      path: '/inventory/settings',
    );
    expect(h.location.path, '/inventory/settings');
    expect(find.text(h.t('inventory.settings.title')), findsWidgets);
    await h.shot('smoke');
  });
}
