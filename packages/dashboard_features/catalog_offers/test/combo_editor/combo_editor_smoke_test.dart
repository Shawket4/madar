// The combo editor mounts in the shell at /menu/combos/:comboId, on its own
// route (the list is not built under it).
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/combo_editor/combo_editor_page.dart';
import 'package:dashboard_catalog_offers/src/combos/combos_page.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('/menu/combos/new opens the editor in create mode', (
    tester,
  ) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [catalogOffersArea],
      path: '/menu/combos/new',
    );
    final page = tester.widget<ComboEditorPage>(find.byType(ComboEditorPage));
    expect(page.isNew, isTrue);
    expect(find.byType(CombosPage), findsNothing);
    expect(find.text(h.t('combos.new')), findsWidgets);
    await h.shot('combo-editor/scaffold');
  });

  testWidgets('/menu/combos/<id> opens that combo; Back returns to the list', (
    tester,
  ) async {
    final id = OffersSeed.comboId('morning-croissant');
    final h = await DashHarness.pump(
      tester,
      areas: const [catalogOffersArea],
      path: '/menu/combos/$id',
    );
    final page = tester.widget<ComboEditorPage>(find.byType(ComboEditorPage));
    expect(page.comboId, id);
    await h.tapLabel(h.t('common.back'));
    expect(h.location.path, '/menu/combos');
    expect(find.byType(CombosPage), findsOneWidget);
  });
}
