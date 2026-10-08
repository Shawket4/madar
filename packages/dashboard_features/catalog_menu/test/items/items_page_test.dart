// Smoke test of the `items` unit: the page opens through the real shell.
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('/menu/items opens', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [catalogMenuArea],
      path: '/menu/items',
    );
    expect(find.text(h.t('nav.menu')), findsWidgets);
  });
}
