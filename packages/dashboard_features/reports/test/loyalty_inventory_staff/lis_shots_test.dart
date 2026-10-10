// The screenshot matrix of Loyalty, Inventory reports and Staff
// discipline: each page's default at {phone, tablet, desktop} x {en light,
// ar dark}, scrolled through; every tab and state at desktop-en-light and
// phone-ar-light. Written only with FDASH_SHOTS set; the pages still render
// (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Shoots the page top to bottom: `<page>/<name>-1`, `-2`, …
Future<void> shootPage(DashHarness h, String page, String name) async {
  final scroll = find
      .descendant(
        of: find.byType(DashPageScaffold),
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
    await h.shot('$page/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

const _pages = [
  ('loyalty', loyaltyPath),
  ('inventory', inventoryPath),
  ('staff', staffPath),
];

const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

void main() {
  for (final (page, path) in _pages) {
    for (final size in DashSize.values) {
      for (final (lang, dark) in [('en', false), ('ar', true)]) {
        testWidgets('$page default, ${size.name} $lang', (tester) async {
          final h = await pumpUnit(
            tester,
            path: path,
            size: size,
            locale: lang,
            dark: dark,
          );
          await shootPage(h, page, 'default');
        });
      }
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    final ar = lang == 'ar';

    for (final (tab, en, arLabel) in [
      ('campaigns', 'Campaigns', 'الحملات'),
      ('liability', 'Liability', 'الالتزامات'),
    ]) {
      testWidgets('loyalty $tab, $tag', (tester) async {
        final h = await pumpUnit(
          tester,
          path: loyaltyPath,
          size: size,
          locale: lang,
          dark: dark,
        );
        await openTab(h, ar ? arLabel : en);
        await shootPage(h, 'loyalty', tab);
      });
    }

    for (final (tab, en, arLabel) in [
      ('shrinkage', 'Shrinkage', 'العجز'),
      ('waste', 'Waste', 'التالف'),
      ('lead-time', 'PO lead time', 'مدة توريد الطلبات'),
      ('low-stock', 'Low stock', 'مخزون منخفض'),
    ]) {
      testWidgets('inventory $tab, $tag', (tester) async {
        final h = await pumpUnit(
          tester,
          path: inventoryPath,
          size: size,
          locale: lang,
          dark: dark,
        );
        await openTab(h, ar ? arLabel : en);
        await shootPage(h, 'inventory', tab);
      });
    }

    testWidgets('inventory branch picked, $tag', (tester) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        size: size,
        locale: lang,
        dark: dark,
        branchId: SeedIds.maadi,
      );
      await shootPage(h, 'inventory', 'branch');
      await openTab(h, ar ? 'مخزون منخفض' : 'Low stock');
      await shootPage(h, 'inventory', 'branch-low-stock');
    });

    testWidgets('inventory export menu, $tag', (tester) async {
      final h = await pumpUnit(
        tester,
        path: inventoryPath,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(find.byKey(const ValueKey('inv-export')));
      await h.shot('inventory/export-menu');
      await h.tap(find.text(ar ? 'تصدير Excel' : 'Export Excel').last);
      await h.settle();
      await h.flushTimers();
    });

    testWidgets('failed reads, $tag', (tester) async {
      final s = unitServer();
      for (final t in [behaviorTpl, orgTpl('consumption'), disciplineTpl]) {
        s.server.fail(
          'GET',
          t,
          MockResponse.error(500, 'Service busy'),
          times: null,
        );
      }
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      await h.shot('loyalty/overview-failed');
      await h.go(inventoryPath);
      await h.shot('inventory/failed');
      await h.go(staffPath);
      await h.shot('staff/failed');
    });

    testWidgets('loading, $tag', (tester) async {
      final s = unitServer();
      final gates = [
        for (final t in [behaviorTpl, orgTpl('consumption'), disciplineTpl])
          s.server.hold('GET', t),
      ];
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      await h.shot('loyalty/overview-loading');
      await h.go(inventoryPath);
      await h.shot('inventory/loading');
      await h.go(staffPath);
      await h.shot('staff/loading');
      for (final g in gates) {
        g.release();
      }
      await h.settle();
    });

    testWidgets('empty, $tag', (tester) async {
      final s = unitServer();
      s.server
        ..on('GET', orgTpl('consumption'), (req) => MockResponse.ok([]))
        ..on(
          'GET',
          disciplineTpl,
          (req) => MockResponse.ok({
            'from': req.q('from'),
            'to': req.q('to'),
            'rows': <Object>[],
          }),
        )
        ..on(
          'GET',
          campaignsTpl,
          (req) => MockResponse.ok({
            'from': defaultFrom,
            'to': defaultTo,
            'campaigns': <Object>[],
          }),
        );
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      await openTab(h, ar ? 'الحملات' : 'Campaigns');
      await h.shot('loyalty/campaigns-empty');
      await h.go(inventoryPath);
      await h.shot('inventory/empty');
      await h.go(staffPath);
      await h.shot('staff/empty');
    });

    testWidgets('restricted, $tag', (tester) async {
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        persona: Persona.limited,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('loyalty/restricted');
      await h.go(inventoryPath);
      await h.shot('inventory/restricted');
      await h.go(staffPath);
      await h.shot('staff/restricted');
    });
  }
}
