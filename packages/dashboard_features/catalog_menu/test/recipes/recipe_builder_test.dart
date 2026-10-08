// Smoke test of the `recipes` unit: the studio page that hosts its pieces
// opens through the real shell (the builder itself lives in the item and
// add-on recipe dialogs).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the recipes host page opens', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [catalogMenuArea],
      path: '/menu/items/${MockSeed.menuItemId('latte')}',
    );
    expect(find.text(h.t('menu.studio.itemTitle')), findsWidgets);
  });
}
