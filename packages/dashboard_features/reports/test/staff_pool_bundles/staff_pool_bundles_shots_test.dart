// The screenshot matrix for Staff drinks and Bundles: each page's default
// state at {phone, tablet, desktop} × {en light, ar dark}, and every dialog
// and side panel at desktop-en-light and phone-ar-light. Writes PNGs only
// with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/bundles_mix_dialog.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/bundles_report_page.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drinks_table.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_pool_report_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];
const _overlays = [(DashSize.desktop, 'en'), (DashSize.phone, 'ar')];

final String _helio = '$staffPoolPath?branchId=${SeedIds.heliopolis}';
final String _zamalekBundles = '$bundlesPath?branchId=${SeedIds.zamalek}';

/// One PNG per screen of [page]'s own scroll, top to bottom.
Future<void> shootPage(DashHarness h, Type page, String name) async {
  final scroll = find
      .descendant(of: find.byType(page), matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('$name-$i');
    if (y >= position.maxScrollExtent || i >= 6) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
  position.jumpTo(0);
  await h.settle(rounds: 2);
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('staff drinks default, $tag', (tester) async {
        final h = await pumpReports(
          tester,
          path: _helio,
          size: size,
          locale: lang,
          dark: dark,
        );
        expect(find.byType(StaffDrinksTable), findsOneWidget);
        await shootPage(h, StaffPoolReportPage, 'default');
      });

      testWidgets('bundles default, $tag', (tester) async {
        final h = await pumpReports(
          tester,
          path: _zamalekBundles,
          size: size,
          locale: lang,
          dark: dark,
        );
        expect(find.text(h.t('reports.bundles.title')), findsWidgets);
        await shootPage(h, BundlesReportPage, 'default');
      });
    }
  }

  for (final (size, lang) in _overlays) {
    final tag = '${size.name} $lang light';

    testWidgets('staff drinks order sheet, $tag', (tester) async {
      final h = await pumpReports(
        tester,
        path: '$_helio&preset=today',
        size: size,
        locale: lang,
      );
      await h.tap(
        find.descendant(
          of: find.byType(StaffDrinksTable),
          matching: find.text(h.t('staffPool.viewOrder')),
        ),
      );
      await h.shot('order-sheet');
    });

    testWidgets('staff drinks pool off, $tag', (tester) async {
      final h = await pumpReports(
        tester,
        path: '$staffPoolPath?branchId=${SeedIds.newCairo}',
        size: size,
        locale: lang,
      );
      await h.shot('pool-off');
    });

    testWidgets('staff drinks pick a branch, $tag', (tester) async {
      final h = await pumpReports(
        tester,
        path: staffPoolPath,
        size: size,
        locale: lang,
      );
      await h.shot('pick-branch');
    });

    testWidgets('bundles mix dialog and deals, $tag', (tester) async {
      final h = await pumpReports(
        tester,
        path: _zamalekBundles,
        size: size,
        locale: lang,
      );
      await h.tapText(lang == 'en' ? 'Brunch for Two' : 'برانش لشخصين');
      await h.shot('mix-dialog');
      await h.tap(
        find.descendant(
          of: find.byType(BundlesMixDialog),
          matching: find.bySemanticsLabel(h.t('common.close')),
        ),
      );
      await h.tapText(h.t('reports.bundles.deals'));
      await h.shot('deals');
    });
  }
}
