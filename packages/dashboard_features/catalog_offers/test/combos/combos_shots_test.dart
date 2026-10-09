// The combos list's screenshot matrix: the default page at phone, tablet and
// desktop in English light and Arabic dark (one PNG per screen of scroll),
// then every other state at desktop-en-light and phone-ar-light.
// Run with FDASH_SHOTS=<dir> to write the PNGs.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/combos/combos_page.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];
const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

/// One PNG per screen of the page's scroll (at most three).
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: find.byType(CombosPage), matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var y = 0.0;
  for (var i = 1; i <= 3; i++) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('combos/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, $tag', (tester) async {
        final h = await pumpCombos(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    final delete = lang == 'ar' ? 'حذف' : 'Delete';

    testWidgets('loading, $tag', (tester) async {
      final s = combosServer();
      final gate = s.server.hold('GET', combosApi);
      final h = await pumpCombos(
        tester,
        seeded: s,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('combos/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = combosServer();
      s.server.fail(
        'GET',
        combosApi,
        MockResponse.error(500, 'Database error: pool timed out'),
      );
      final h = await pumpCombos(
        tester,
        seeded: s,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('combos/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final s = combosServer();
      clearCombos(s.db);
      final h = await pumpCombos(
        tester,
        seeded: s,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('combos/empty');
    });

    testWidgets('nothing matches, $tag', (tester) async {
      final h = await pumpCombos(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.enterText(searchBox(), 'falafel');
      await tester.pump(const Duration(milliseconds: 300));
      await h.settle();
      await h.shot('combos/empty-filtered');
    });

    testWidgets('restricted, $tag', (tester) async {
      final h = await pumpCombos(
        tester,
        seeded: serverWithCaps(['orders.read']),
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('combos/restricted');
    });

    testWidgets('reader (no actions), $tag', (tester) async {
      final h = await pumpCombos(
        tester,
        seeded: serverWithCaps(['menu.items.read', 'menu.categories.read']),
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('combos/reader');
    });

    testWidgets('delete confirm, $tag', (tester) async {
      final h = await pumpCombos(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(rowButton('Iced Afternoon', delete));
      await h.shot('combos/delete-confirm');
    });

    testWidgets('category select open, $tag', (tester) async {
      final h = await pumpCombos(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(filterSelect(lang == 'ar' ? 'الفئة' : 'Category'));
      await h.shot('combos/category-select');
    });

    testWidgets('two pages, $tag', (tester) async {
      final s = combosServer();
      addCombos(s.db, 30);
      final h = await pumpCombos(
        tester,
        seeded: s,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(inPage(find.bySemanticsLabel(lang == 'ar' ? 'التالي' : 'Next')));
      await shootPage(h, 'page-2');
    });
  }

  testWidgets('columns menu, desktop en', (tester) async {
    final h = await pumpCombos(tester);
    await h.tap(pageButton('Columns'));
    await h.shot('combos/columns-menu');
  });

  testWidgets('a 700 wide window (cards, a 240 search)', (tester) async {
    final h = await pumpCombos(tester, size: DashSize.tablet);
    tester.view.physicalSize = const Size(700, 900) * DashSize.pixelRatio;
    await h.settle();
    expect(tester.getSize(searchBox()).width, CombosMetrics.search);
    expect(inPage(find.byType(DashCard)), findsWidgets);
    await h.shot('combos/width-700');
  });
}
