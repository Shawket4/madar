// The Operations screenshot matrix: the default (Tables) at {phone, tablet,
// desktop} x {en light, ar dark}, scrolled through the whole page; every
// other tab at {desktop, phone} x {en, ar}; the history panel, the exclude list, the export menu and the
// loading / failed / empty states at desktop-en-light and phone-ar-light.
// Written only with FDASH_SHOTS set; the pages still render (and must not
// overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/operations/ops_tables.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(
        of: opsPage,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('operations/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default (Tables), ${size.name} $lang', (tester) async {
        final h = await pumpOps(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  // Every tab in both languages at both ends of the width range.
  for (final size in [DashSize.desktop, DashSize.phone]) {
    for (final lang in ['en', 'ar']) {
      for (final tab in [
        'overview',
        'items',
        'tellers',
        'waiters',
        'branches',
      ]) {
        testWidgets('tab $tab, ${size.name} $lang', (tester) async {
          final h = await pumpOps(tester, size: size, locale: lang);
          await openTab(h, h.t('reports.operations.tabs.$tab'));
          await shootPage(h, tab);
        });
      }
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';

    testWidgets('a branch picked (sections), $tag', (tester) async {
      final h = await pumpOps(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branchId: SeedIds.newCairo,
      );
      await shootPage(h, 'branch');
    });

    testWidgets('the history panel, $tag', (tester) async {
      final h = await pumpOps(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branchId: SeedIds.heliopolis,
      );
      await h.tap(
        find
            .descendant(
              of: inPage(find.byKey(const ValueKey('ops-tables-table'))),
              matching: find.byKey(opsTableNameKey),
            )
            .first,
      );
      await h.shot('operations/history');
    });

    testWidgets('the exclude list, $tag', (tester) async {
      final h = await pumpOps(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        prefs: {
          'madar.excluded-line-items.${SeedIds.sabahOrg}':
              '["${MockSeed.menuItemId('latte')}"]',
        },
      );
      await openTab(h, h.t('reports.operations.tabs.overview'));
      await h.tap(inPage(find.byKey(const ValueKey('ops-exclude-trigger'))));
      await h.shot('operations/exclude-open');
    });

    testWidgets('the export menu, $tag', (tester) async {
      final h = await pumpOps(tester, size: size, locale: lang, dark: dark);
      await openTab(h, h.t('reports.operations.tabs.items'));
      await h.tap(inPage(find.byType(DashExportButton)));
      await h.shot('operations/export-open');
    });

    testWidgets('loading, $tag', (tester) async {
      final s = opsServer();
      final gate = s.server.hold('POST', metricsRoute);
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('operations/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = opsServer();
      s.server.fail(
        'POST',
        metricsRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('operations/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final h = await pumpOps(tester, size: size, locale: lang, dark: dark);
      await h.container
          .read(scopeProvider.notifier)
          .setCustomRange(
            '2026-01-01T00:00:00.000Z',
            '2026-01-02T00:00:00.000Z',
          );
      await h.settle();
      await shootPage(h, 'empty');
      await openTab(h, h.t('reports.operations.tabs.overview'));
      await shootPage(h, 'overview-empty');
    });
  }
}
