// The owner's rule (2026-10-11): a filter carries through navigation. The
// combos filtered, a combo opened and Back; the discounts searched and paged,
// another page and back — the same list (`DashRememberedState`).
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/combo_editor/combo_editor_page.dart';
import 'package:dashboard_catalog_offers/src/combos/combos_page.dart';
import 'package:dashboard_catalog_offers/src/discounts/discounts_page.dart';
import 'package:dashboard_catalog_offers/src/shared/menu_options.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'combos/support.dart' as combos;
import 'discounts/support.dart' as discounts;

Map<String, List<String>> lastCombosQuery(DashHarness h) =>
    h.server.callsTo(combos.combosApi).last.query;

Finder option(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.text(label),
);

void expectCombosFiltered(DashHarness h, WidgetTester tester) {
  expect(h.location.path, combos.combosPath);
  expect(find.byType(CombosPage), findsOneWidget);
  expect(find.bySemanticsLabel('Category: Breakfast'), findsWidgets);
  expect(find.bySemanticsLabel('Status: Active'), findsWidgets);
  final q = lastCombosQuery(h);
  expect(q['category_id'], [OffersSeed.category('breakfast')]);
  expect(q['is_active'], ['true']);
  expect(combos.shownNames(tester), ['Brunch for Two']);
}

Future<void> filterCombos(DashHarness h) async {
  await h.tap(combos.filterSelect('Category'));
  await h.tap(option('Breakfast'));
  await h.tap(combos.filterSelect('Status'));
  await h.tap(option('Active'));
}

void main() {
  testWidgets('combos filtered → open a combo → Back keeps the filters', (
    tester,
  ) async {
    final h = await combos.pumpCombos(tester);
    await filterCombos(h);
    expectCombosFiltered(h, tester);
    await h.tap(combos.rowOf('Brunch for Two'));
    expect(find.byType(ComboEditorPage), findsOneWidget);
    await h.tap(find.bySemanticsLabel(h.t('common.back')).first);
    expectCombosFiltered(h, tester);
  });

  testWidgets('combos filtered → open a combo → system back keeps them', (
    tester,
  ) async {
    final h = await combos.pumpCombos(tester);
    await filterCombos(h);
    await h.tap(combos.rowOf('Brunch for Two'));
    expect(await tester.binding.handlePopRoute(), isTrue);
    await h.settle();
    expectCombosFiltered(h, tester);
  });

  testWidgets('combos: a remembered category that was deleted is dropped', (
    tester,
  ) async {
    final s = combos.combosServer();
    final h = await combos.pumpCombos(tester, seeded: s);
    await filterCombos(h);
    await h.go('/menu/deals');
    final cat = s.db
        .table(OffersTables.categories)
        .rows
        .firstWhere((r) => r['id'] == OffersSeed.category('breakfast'));
    cat['deleted_at'] = '2026-10-11T00:00:00Z';
    h.container.invalidate(offersCategoriesProvider);
    await h.go(combos.combosPath);
    expect(find.bySemanticsLabel('Category: All categories'), findsWidgets);
    expect(lastCombosQuery(h).containsKey('category_id'), isFalse);
    expect(find.bySemanticsLabel('Status: Active'), findsWidgets);
  });

  testWidgets('discounts: the search and the page come back', (tester) async {
    final s = combos.combosServer();
    discounts.addPromos(s.db, 6);
    final h = await DashHarness.pump(
      tester,
      areas: const [catalogOffersArea],
      path: discounts.discountsPath,
      server: s.server,
      db: s.db,
    );
    await h.tap(discounts.inPage(find.bySemanticsLabel('Next')));
    expect(discounts.inTable(find.text('Staff Meal')), findsOneWidget);
    await h.go('/menu/deals');
    await h.go(discounts.discountsPath);
    expect(find.byType(DiscountsPage), findsOneWidget);
    expect(discounts.inTable(find.text('Staff Meal')), findsOneWidget);

    await h.enterText(discounts.inPage(find.byType(DashSearchInput)), 'FIXED');
    expect(discounts.inTable(find.text('Staff Meal')), findsNothing);
    await h.go('/menu/combos');
    await h.go(discounts.discountsPath);
    final box = tester.widget<DashSearchInput>(
      discounts.inPage(find.byType(DashSearchInput)),
    );
    expect(box.value, 'FIXED');
    expect(discounts.inTable(find.text('Late Order Apology')), findsOneWidget);
    expect(discounts.inTable(find.text('Staff Meal')), findsNothing);
    // The `?edit` dialog is not a filter: it never comes back by itself.
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
  });
}
