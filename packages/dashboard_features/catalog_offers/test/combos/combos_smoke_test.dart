// The combos list mounts in the shell at /menu/combos.
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/combos/combos_page.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('/menu/combos opens the combos page', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [catalogOffersArea],
      path: '/menu/combos',
    );
    expect(find.byType(CombosPage), findsOneWidget);
    expect(find.text(h.t('combos.subtitle')), findsOneWidget);
    await h.shot('combos/scaffold');
  });

  testWidgets('/menu/combos in Arabic on a phone', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [catalogOffersArea],
      path: '/menu/combos',
      size: DashSize.phone,
      locale: 'ar',
      dark: true,
    );
    expect(find.byType(CombosPage), findsOneWidget);
    expect(find.text('الكومبو'), findsWidgets);
    await h.shot('combos/scaffold');
  });
}
