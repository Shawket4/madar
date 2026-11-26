// The Items page's Export panel, shot in EN and AR at desktop and phone:
// the format, the file list and, for a PDF or CSV of a workbook of several,
// the sheet. Run with FDASH_SHOTS set; without it the tests still drive
// every state (and the harness still fails on overflow, missing words,
// English in AR).
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
  (DashSize.desktop, 'ar', true),
];

Future<void> _open(DashHarness h) => h.tap(
  inPage(
    find.descendant(
      of: find.byType(DashExportButton),
      matching: find.byType(DashButton),
    ),
  ),
);

void main() {
  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang${dark ? ' dark' : ''}';

    testWidgets('the panel as it opens, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      await _open(h);
      await h.shot('items/export-panel');
    });

    testWidgets('recipes as a PDF: the sheet, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      await _open(h);
      await h.tap(find.text(h.t('recipeBook.exportRecipes')).last);
      await h.tap(find.text(h.t('common.exportFormat.pdf')).last);
      expect(find.text(h.t('recipeBook.sheetTables')), findsOneWidget);
      await h.shot('items/export-panel-recipes-pdf');
    });

    testWidgets('the menu as a CSV: three sheets, $tag', (tester) async {
      final h = await pumpItems(tester, size: size, locale: lang, dark: dark);
      await _open(h);
      await h.tap(find.text(h.t('common.exportFormat.csv')).last);
      expect(find.text(h.t('menu.addons')), findsWidgets);
      await h.shot('items/export-panel-menu-csv');
    });
  }
}
