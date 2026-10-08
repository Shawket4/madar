// Today's screenshot matrix: all branches and one branch at {phone, tablet,
// desktop} x {en light, ar dark}, scrolled through the whole page; and its
// other states (first run, loading, failed, quiet, the shortened figure) at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// the pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/today/today_page.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: find.byType(TodayPage), matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('today/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('all branches, $tag', (tester) async {
        final h = await pumpToday(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });

      testWidgets('Zamalek, $tag', (tester) async {
        final h = await pumpToday(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          branch: SeedIds.zamalek,
        );
        await shootPage(h, 'branch');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';

    testWidgets('first run, $tag', (tester) async {
      final h = await pumpToday(
        tester,
        size: size,
        locale: lang,
        branch: SeedIds.heliopolis,
      );
      await shootPage(h, 'first-run');
    });

    testWidgets('loading, $tag', (tester) async {
      final s = todayServer();
      final gates = [
        for (final r in [
          branchValuation,
          branchLow,
          orgOrders,
          stockRoute,
          wasteRoute,
        ])
          s.server.hold('GET', r),
      ];
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        branch: SeedIds.zamalek,
      );
      await shootPage(h, 'loading');
      for (final g in gates) {
        g.release();
      }
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = todayServer();
      for (final r in [branchValuation, branchLow, orgOrders, wasteRoute]) {
        s.server.fail(
          'GET',
          r,
          MockResponse.error(500, 'Database unavailable'),
          times: null,
        );
      }
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        branch: SeedIds.zamalek,
      );
      await shootPage(h, 'failed');
    });

    testWidgets('a quiet day, $tag', (tester) async {
      final s = todayServer();
      for (final bs in s.db[InvTables.branchStock].rows.toList()) {
        s.db[InvTables.branchStock].update(bs['id']! as String, {
          'par_min': null,
        });
      }
      for (final po in s.db[InvTables.purchaseOrders].rows.toList()) {
        s.db[InvTables.purchaseOrders].update(po['id']! as String, {
          'expected_at': '2026-10-20T20:59:59.999Z',
        });
      }
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        branch: SeedIds.maadi,
      );
      await shootPage(h, 'quiet');
    });

    testWidgets('the exact figure behind a shortened one, $tag', (
      tester,
    ) async {
      final s = todayServer();
      s.server.on('GET', branchValuation, (req) {
        return MockResponse.ok({
          'total_value': 123456789,
          'unknown_cost_count': 2,
          'items': <Object>[],
        });
      });
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        branch: SeedIds.zamalek,
      );
      final value = find.descendant(
        of: find.byType(DashStatCard).first,
        matching: find.byType(DashPressable),
      );
      if (value.evaluate().isNotEmpty) await h.tap(value.first);
      await h.shot('today/figure-popover');
    });
  }
}
