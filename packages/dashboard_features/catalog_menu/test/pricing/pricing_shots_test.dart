// The screenshot matrix of `/menu/pricing`: the default state at every size
// in English light and Arabic dark, then each other state (an item expanded
// with staged edits and the save bar, the add-ons tab, loading, error, empty,
// pick a branch, no org, the refused save) at desktop-en-light and
// phone-ar-light.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/shared/unsaved_bar.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _iced = sizeId('iced_latte', 'Regular');
final String _icedL = sizeId('iced_latte', 'Large');
final String _oat = optionId('milk', 'oat');

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpPricing(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.shot('pricing/default');
      });
    }
  }

  testWidgets('edits, desktop en dark: the unsaved tint and a red hide', (
    tester,
  ) async {
    final h = await pumpPricing(tester, dark: true);
    await expand(h, 'Iced Latte');
    await typePrice(h, _iced, 'in_store', '135');
    await toggle(h, _icedL, 'in_mall');
    await reveal(h, cellOf(_iced, 'in_store'));
    await h.shot('pricing/edits');
  });

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final name = lang == 'en' ? 'Iced Latte' : 'آيس لاتيه';
    final addons = lang == 'en' ? 'Add-ons' : 'الإضافات';

    testWidgets('edits and the save bar, ${size.name} $lang', (tester) async {
      final h = await pumpPricing(tester, size: size, locale: lang);
      await expand(h, name);
      await typePrice(h, _iced, 'in_store', '135');
      await toggle(h, _icedL, 'in_mall');
      await reveal(h, cellOf(_iced, 'in_store'));
      await h.shot('pricing/edits');
    });

    testWidgets('add-ons, ${size.name} $lang', (tester) async {
      final h = await pumpPricing(tester, size: size, locale: lang);
      await h.tap(pageText(addons));
      await reveal(h, cellOf(_oat, 'in_store'));
      await h.shot('pricing/addons');
    });

    testWidgets('loading, ${size.name} $lang', (tester) async {
      final s = pricingServer();
      final gate = s.server.hold('GET', catalogT);
      final h = await pumpPricing(tester, size: size, locale: lang, seeded: s);
      await h.shot('pricing/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('error, ${size.name} $lang', (tester) async {
      final s = pricingServer();
      s.server.fail('GET', catalogT, MockResponse.error(500, 'Database down'));
      final h = await pumpPricing(tester, size: size, locale: lang, seeded: s);
      await h.shot('pricing/error');
    });

    testWidgets('empty, ${size.name} $lang', (tester) async {
      final s = pricingServer();
      s.db['menu_items'].removeWhere((_) => true);
      final h = await pumpPricing(tester, size: size, locale: lang, seeded: s);
      await h.shot('pricing/empty');
    });

    testWidgets('pick a branch, ${size.name} $lang', (tester) async {
      final h = await pumpPricing(
        tester,
        size: size,
        locale: lang,
        allBranches: true,
      );
      await h.shot('pricing/pick-branch');
    });

    testWidgets('no org, ${size.name} $lang', (tester) async {
      final h = await pumpPricing(
        tester,
        size: size,
        locale: lang,
        persona: Persona.platform,
      );
      await h.shot('pricing/no-org');
    });

    testWidgets('a refused save, ${size.name} $lang', (tester) async {
      final s = pricingServer();
      final h = await pumpPricing(tester, size: size, locale: lang, seeded: s);
      await expand(h, name);
      await typePrice(h, _iced, 'in_store', '135');
      s.server.fail('PUT', overrideT, MockResponse.denied('menu.items.edit'));
      await h.tap(
        find.descendant(
          of: find.byType(MenuUnsavedBar),
          matching: find.text(h.t('common.save')),
        ),
      );
      await h.shot('pricing/refused');
      await h.flushTimers();
    });
  }
}
