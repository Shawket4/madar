// The Financial screenshot matrix: the default (Menu profitability, Ledger)
// at {phone, tablet, desktop} x {en light, ar dark}, scrolled through; every
// other tab and view, the popovers and the loading / failed / empty states
// at desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// the pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default (ledger), ${size.name} $lang', (tester) async {
        final h = await pumpFin(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(WidgetTester tester, {String? branchId}) =>
        pumpFin(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          branchId: branchId,
        );

    testWidgets('quadrant, $tag', (tester) async {
      final h = await open(tester);
      await pickSegment(
        h,
        'fin-view',
        h.t('insights.profitability.viewQuadrant'),
      );
      await shootPage(h, 'quadrant');
    });

    testWidgets('repricing, $tag', (tester) async {
      final h = await open(tester);
      await openInner(h, h.t('insights.profitability.repricingTab'));
      await shootPage(h, 'repricing');
    });

    testWidgets('decisions, $tag', (tester) async {
      final h = await open(tester);
      await openInner(h, h.t('insights.profitability.decisionsTab'));
      await shootPage(h, 'decisions');
    });

    testWidgets('target editor (a branch), $tag', (tester) async {
      final h = await open(tester, branchId: SeedIds.zamalek);
      await h.tap(find.byKey(const ValueKey('fin-target-trigger')));
      await h.shot('financial/target-editor');
    });

    testWidgets('flag popover, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('flag-'),
            )
            .first,
      );
      await h.shot('financial/flag-popover');
    });

    for (final (tab, key) in [
      ('revenue', 'reports.financial.tabs.revenue'),
      ('channel', 'reports.financial.tabs.channel'),
      ('valuation', 'reports.financial.tabs.valuation'),
      ('spend', 'reports.financial.tabs.supplierSpend'),
      ('trend', 'reports.financial.tabs.materialCostTrend'),
    ]) {
      testWidgets('tab $tab, $tag', (tester) async {
        final h = await open(tester);
        await openTab(h, h.t(key));
        await shootPage(h, tab);
      });
    }

    for (final g in ['peak_hours', 'peak_days', 'monthly']) {
      testWidgets('revenue $g, $tag', (tester) async {
        final h = await open(tester);
        await openTab(h, h.t('reports.financial.tabs.revenue'));
        await pickSegment(
          h,
          'fin-granularity',
          h.t('analytics.granularity.$g'),
        );
        await shootPage(h, 'revenue-$g');
      });
    }

    testWidgets('ledger failed, $tag', (tester) async {
      final s = finServer();
      s.server.fail(
        'GET',
        ledgerRoute,
        MockResponse.error(500, 'The report is unavailable.'),
        times: null,
      );
      final h = await pumpFin(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await h.shot('financial/ledger-failed');
    });

    testWidgets('ledger loading, $tag', (tester) async {
      final s = finServer();
      final gate = s.server.hold('GET', ledgerRoute);
      final h = await pumpFin(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await h.shot('financial/ledger-loading');
      gate.release();
      await h.settle();
    });
  }
}
