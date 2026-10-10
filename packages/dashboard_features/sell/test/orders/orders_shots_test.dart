// The Orders screenshot matrix: the default page at every size in EN light
// and AR dark; every other state at desktop EN light and phone AR light.
// Run with FDASH_SHOTS set; without it the tests still drive every state
// (and the harness still fails on overflow, missing words, English in AR).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/orders/order_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orders_support.dart';

/// Scrolls the page and shoots each screen of it.
Future<void> shootPage(DashHarness h, String name) async {
  await h.shot('orders/$name');
  final scroll = find
      .descendant(
        of: find.byType(DashPageScaffold),
        matching: find.byType(Scrollable),
      )
      .first;
  final state = h.tester.state<ScrollableState>(scroll);
  final pos = state.position;
  var i = 1;
  while (pos.pixels < pos.maxScrollExtent && i < 6) {
    pos.jumpTo(
      (pos.pixels + pos.viewportDimension * 0.85).clamp(0, pos.maxScrollExtent),
    );
    await h.settle(rounds: 2);
    await h.shot('orders/$name-${i++}');
  }
}

const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpOrders(
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

    testWidgets('loading, $tag', (tester) async {
      final s = ordersServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpOrders(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      await h.shot('orders/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('error, $tag', (tester) async {
      final s = ordersServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Database error: pool timed out'),
        times: null,
      );
      final h = await pumpOrders(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      await shootPage(h, 'error');
    });

    testWidgets('empty, $tag', (tester) async {
      final s = ordersServer();
      s.db['orders'].clear();
      final h = await pumpOrders(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      await shootPage(h, 'empty');
    });

    testWidgets('30 days with the delivery block, $tag', (tester) async {
      final h = await pumpOrders(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        preset: '30d',
      );
      await shootPage(h, 'month');
    });

    for (final key in ['combo', 'staff', 'reward', 'refused', 'voided']) {
      testWidgets('sheet $key, $tag', (tester) async {
        final h = await pumpOrders(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          query: '?order=${OrderSeedIds.showcase(key)}',
        );
        await h.shot('orders/sheet-$key');
      });
    }

    testWidgets('sheet delivery, $tag', (tester) async {
      final s = ordersServer();
      final date = MockClock.cairoDate(s.db.clock.now);
      final h = await pumpOrders(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
        query: '?order=${OrderSeedIds.deliverySale('heliopolis', date, 8)}',
      );
      await h.shot('orders/sheet-delivery');
      final sheet = h.tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(OrderSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      sheet.position.jumpTo(sheet.position.maxScrollExtent);
      await h.settle();
      await h.shot('orders/sheet-delivery-2');
    });

    testWidgets('sheet split, $tag', (tester) async {
      final h = await pumpOrders(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branchId: SeedIds.zamalek,
        query: '?order=${OrderSeedIds.showcase('split')}',
      );
      await h.shot('orders/sheet-split');
    });

    testWidgets('void dialog, $tag', (tester) async {
      final h = await pumpOrders(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        query: '?order=${OrderSeedIds.showcase('offline')}',
      );
      await h.tap(find.byKey(const ValueKey('order-sheet-void')));
      await h.shot('orders/void');
    });

    testWidgets('export sheet, $tag', (tester) async {
      final h = await pumpOrders(tester, size: size, locale: lang, dark: dark);
      await h.tap(find.byKey(const ValueKey('orders-export')));
      await h.tap(find.byKey(const ValueKey('export-customize')));
      await h.shot('orders/export');
    });

    testWidgets('exclude list and row menu, $tag', (tester) async {
      final h = await pumpOrders(tester, size: size, locale: lang, dark: dark);
      await h.tap(find.byKey(const ValueKey('orders-exclude-trigger')));
      await h.shot('orders/exclude');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      await h.tap(
        find.byKey(
          ValueKey('order-actions-${OrderSeedIds.showcase('offline')}'),
        ),
      );
      await h.shot('orders/row-menu');
    });
  }
}
