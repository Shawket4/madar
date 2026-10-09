// Orders: the list, filters, KPIs, delivery block, paging, states, refusals
// and the area-wide rows (SELL-ORD-001 … 034, 081, 086, 091; SELL-ALL-*).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/customers/customer_sheet.dart';
import 'package:dashboard_sell/src/orders/order_sheet.dart';
import 'package:dashboard_sell/src/orders/orders_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';
import 'orders_support.dart';

String _ref(Map<String, Object?> o) =>
    (o['order_ref'] as String?) ??
    '#${o['display_number'] ?? o['order_number']}';

/// An option in the open select's list.
Finder option(String text) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('DashOptionList'),
  ),
  matching: find.text(text),
);

Future<void> _pickFilter(DashHarness h, String key, String text) async {
  await h.tap(find.byKey(ValueKey(key)));
  await h.tap(option(text));
}

/// A table header (the kit shows them in capitals).
Finder header(String label) => inTable(
  find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').toLowerCase() == label.toLowerCase(),
  ),
);

void main() {
  testWidgets('SELL-ORD-001/002 header, filters and the first page', (
    tester,
  ) async {
    final h = await pumpOrders(tester);
    expect(inPage(find.text('Orders')), findsWidgets);
    expect(find.text(h.t('orders.subtitle')), findsOneWidget);
    expect(inPage(find.text('Export Excel')), findsOneWidget);
    final call = h.server.callsTo(listRoute).single;
    final scope = h.container.read(currentScopeProvider);
    expect(call.query['branch_id'], [SeedIds.heliopolis]);
    expect(call.query['from'], [scope.from]);
    expect(call.query['to'], [scope.to]);
    expect(call.query['page'], ['1']);
    expect(call.query['per_page'], ['20']);
    for (final k in [
      'status',
      'payment_method',
      'teller_name',
      'order_type',
      'channel',
      'exclude_items',
      'till_id',
    ]) {
      expect(call.query.containsKey(k), isFalse, reason: k);
    }
    // The first twenty of today's Heliopolis orders, newest first.
    final today = todaysOrders(h.db!, SeedIds.heliopolis);
    expect(inTable(find.text(_ref(today.first))), findsOneWidget);
    expect(inTable(find.text(_ref(today[19]))), findsOneWidget);
    expect(inTable(find.text(_ref(today[20]))), findsNothing);
    await h.shot('orders/default');
  });

  testWidgets('SELL-ORD-002 All branches sends no branch_id', (tester) async {
    final h = await pumpOrders(tester, branchId: null);
    final call = h.server.callsTo(listRoute).single;
    expect(call.query.containsKey('branch_id'), isFalse);
    // The delivery block reads the all-branches sentinel.
    expect(
      h.server.callsTo(deliverySalesRoute).single.path,
      '/reports/branches/00000000-0000-0000-0000-000000000000/delivery-sales',
    );
  });

  testWidgets('SELL-ORD-002 a platform admin with no org asks nothing', (
    tester,
  ) async {
    final h = await pumpOrders(
      tester,
      persona: Persona.platform,
      branchId: null,
    );
    expect(h.server.callsTo(listRoute), isEmpty);
    expect(h.server.callsTo(deliverySalesRoute), isEmpty);
  });

  testWidgets('SELL-ORD-004/005 teller and waiter searches, debounced 350 ms', (
    tester,
  ) async {
    final h = await pumpOrders(tester, branchId: SeedIds.zamalek);
    expect(find.text(h.t('orders.searchTeller')), findsOneWidget);
    await h.enterText(find.byKey(const ValueKey('orders-teller')), 'Yous');
    expect(h.server.callsTo(listRoute).length, 1, reason: 'still typing');
    await tester.pump(const Duration(milliseconds: 250));
    await h.settle();
    expect(h.server.callsTo(listRoute).last.query['teller_name'], ['Yous']);
    await h.enterText(find.byKey(const ValueKey('orders-waiter')), 'Adham');
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    final last = h.server.callsTo(listRoute).last;
    expect(last.query['waiter_name'], ['Adham']);
    expect(last.query['teller_name'], ['Yous']);
    expect(inTable(find.text('Adham Reda')), findsWidgets);
  });

  testWidgets('SELL-ORD-006 Status filter', (tester) async {
    final h = await pumpOrders(tester);
    await _pickFilter(h, 'orders-status', 'Voided');
    final call = h.server.callsTo(listRoute).last;
    expect(call.query['status'], ['voided']);
    expect(
      inTable(
        find.text(_ref(h.db!['orders'].find(OrderSeedIds.showcase('voided'))!)),
      ),
      findsOneWidget,
    );
    await _pickFilter(h, 'orders-status', 'All statuses');
    // Back to the first key: the cached unfiltered page again.
    expect(
      inTable(find.text(_ref(todaysOrders(h.db!, SeedIds.heliopolis).first))),
      findsOneWidget,
    );
  });

  testWidgets('SELL-ORD-007 Payment filter lists the six methods', (
    tester,
  ) async {
    final h = await pumpOrders(tester);
    await h.tap(find.byKey(const ValueKey('orders-payment')));
    for (final m in [
      'All payments',
      'Cash',
      'Card',
      'Digital Wallet',
      'Mixed',
      'Talabat Online',
      'Talabat Cash',
    ]) {
      expect(option(m), findsOneWidget, reason: m);
    }
    await h.tap(option('Card'));
    expect(h.server.callsTo(listRoute).last.query['payment_method'], ['card']);
  });

  testWidgets('SELL-ORD-008/009 Type filter; Channel only with Delivery', (
    tester,
  ) async {
    final h = await pumpOrders(tester);
    expect(find.byKey(const ValueKey('orders-channel')), findsNothing);
    await _pickFilter(h, 'orders-type', 'Delivery');
    expect(h.server.callsTo(listRoute).last.query['order_type'], ['delivery']);
    expect(find.byKey(const ValueKey('orders-channel')), findsOneWidget);
    await _pickFilter(h, 'orders-channel', 'In-mall');
    final call = h.server.callsTo(listRoute).last;
    expect(call.query['channel'], ['in_mall']);
    expect(call.query['order_type'], ['delivery']);
    // Anything but Delivery resets the channel.
    await _pickFilter(h, 'orders-type', 'Dine-in');
    final after = h.server.callsTo(listRoute).last;
    expect(after.query['order_type'], ['dine_in']);
    expect(after.query.containsKey('channel'), isFalse);
    expect(find.byKey(const ValueKey('orders-channel')), findsNothing);
  });

  testWidgets(
    'SELL-ORD-010 ?till= (and the legacy ?shift_id=) narrows to a till',
    (tester) async {
      final till = h0TillId();
      final h = await pumpOrders(tester, query: '?till=$till');
      expect(h.server.callsTo(listRoute).last.query['till_id'], [till]);
      // The export reads the same till (no chip or label says so).
      await h.tap(find.byKey(const ValueKey('orders-export')));
      await h.tap(find.byKey(const ValueKey('export-run')));
      expect(h.server.callsTo(exportRoute).single.query['till_id'], [till]);
      await h.flushTimers();
      // The legacy alias, on another till (Counter 2's).
      final counter2 = MockSeed.tillId(
        'heliopolis',
        MockClock.cairoDate(MockSeed.now),
        'counter2',
      );
      await h.go('/orders?shift_id=$counter2');
      expect(h.server.callsTo(listRoute).last.query['till_id'], [counter2]);
      expect(inTable(find.textContaining('-T2-')), findsWidgets);
      expect(inTable(find.textContaining('-T1-')), findsNothing);
    },
  );

  testWidgets(
    'SELL-ORD-003/029/SELL-ALL-011 paging; a filter returns to page 1, '
    'the exclusions do not',
    (tester) async {
      final h = await pumpOrders(tester);
      final total = todaysOrders(h.db!, SeedIds.heliopolis).length;
      final pages = (total / 20).ceil();
      expect(
        find.text(h.t('common.page', args: {'current': 1, 'total': pages})),
        findsOneWidget,
      );
      await h.tapLabel(h.t('common.next'));
      expect(h.server.callsTo(listRoute).last.query['page'], ['2']);
      expect(
        find.text(h.t('common.page', args: {'current': 2, 'total': pages})),
        findsOneWidget,
      );
      // Excluding an item keeps the page.
      await h.tap(find.byKey(const ValueKey('orders-exclude-trigger')));
      await h.enterText(
        find.byKey(const ValueKey('orders-exclude-search')),
        'Caffè',
      );
      await h.tap(
        find.byKey(ValueKey('orders-exclude-${MockSeed.menuItemId('latte')}')),
      );
      final excludedCall = h.server.callsTo(listRoute).last;
      expect(excludedCall.query['page'], ['2']);
      expect(excludedCall.query['exclude_items'], [
        MockSeed.menuItemId('latte'),
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      // A status filter goes back to page 1 …
      await _pickFilter(h, 'orders-status', 'Completed');
      expect(h.server.callsTo(listRoute).last.query['page'], ['1']);
      // … and changing it back does not bring page 2 back.
      await _pickFilter(h, 'orders-status', 'All statuses');
      expect(
        find.text(h.t('common.page', args: {'current': 1, 'total': pages})),
        findsOneWidget,
      );
      expect(
        find.text(h.t('common.page', args: {'current': 2, 'total': pages})),
        findsNothing,
      );
      final first = todaysOrders(h.db!, SeedIds.heliopolis).first;
      expect(inTable(find.text(_ref(first))), findsOneWidget);
    },
  );

  testWidgets('SELL-ORD-012 the KPI strip reads the list summary', (
    tester,
  ) async {
    final h = await pumpOrders(tester);
    final fmt = h.container.read(formatProvider);
    final rows = todaysOrders(h.db!, SeedIds.heliopolis);
    final sold = rows.where((o) => o['status'] != 'voided');
    final revenue = sold.fold<int>(
      0,
      (s, o) => s + (o['total_amount']! as int),
    );
    final discounts = sold.fold<int>(
      0,
      (s, o) => s + (o['discount_amount']! as int),
    );
    for (final label in [
      'Revenue',
      'Completed',
      'Items Sold',
      'Voided',
      'Discounts',
    ]) {
      expect(inPage(find.text(label)), findsWidgets, reason: label);
    }
    expect(inPage(find.text(fmt.fmtMoney(revenue))), findsWidgets);
    expect(inPage(find.text(fmt.fmtMoney(discounts))), findsWidgets);
    expect(inPage(find.text(fmt.fmtNumber(sold.length))), findsWidgets);
    // Items Sold: every unit sold, combo headers left out.
    final items = sold.fold<int>(
      0,
      (n, o) => n + soldUnits(h.db!, o['id']! as String),
    );
    final itemsTile = find.byKey(const ValueKey('line_items'));
    expect(
      find.descendant(of: itemsTile, matching: find.text(fmt.fmtNumber(items))),
      findsOneWidget,
    );
    // Voided: one today, so the tile turns red.
    final voided = rows.length - sold.length;
    expect(voided, greaterThan(0));
    final voidedTile = find.byKey(const ValueKey('voided'));
    expect(
      find.descendant(
        of: voidedTile,
        matching: find.text(fmt.fmtNumber(voided)),
      ),
      findsOneWidget,
    );
    expect(tester.widget<DashStatCard>(voidedTile).tone, DashTone.danger);
  });

  testWidgets('SELL-ORD-012 no voided order: the Voided tile stays neutral', (
    tester,
  ) async {
    final s = ordersServer();
    s.db['orders'].removeWhere(
      (o) => o['branch_id'] == SeedIds.newCairo && o['status'] == 'voided',
    );
    await pumpOrders(
      tester,
      branchId: SeedIds.newCairo,
      server: s.server,
      db: s.db,
    );
    expect(
      tester.widget<DashStatCard>(find.byKey(const ValueKey('voided'))).tone,
      DashTone.neutral,
    );
  });

  testWidgets('SELL-ORD-013/014/015 the exclude control: lazy menu, search, '
      'toggle, hint, kept per org, Clear', (tester) async {
    final h = await pumpOrders(tester);
    expect(h.server.callsTo(menuItemsRoute), isEmpty, reason: 'lazy');
    expect(
      find.bySemanticsLabel(h.t('analytics.excludeItems')),
      findsOneWidget,
    );
    await h.tap(find.byKey(const ValueKey('orders-exclude-trigger')));
    expect(h.server.callsTo(menuItemsRoute).single.query['org_id'], [
      SeedIds.sabahOrg,
    ]);
    expect(find.text(h.t('analytics.excludeScopeNote')), findsOneWidget);
    expect(find.text('Excluded from Items Sold'), findsOneWidget);
    await h.enterText(
      find.byKey(const ValueKey('orders-exclude-search')),
      'spanish',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    expect(find.text('Spanish Latte'), findsOneWidget);
    expect(find.text('Caffè Latte'), findsNothing);
    await h.tap(
      find.byKey(ValueKey('orders-exclude-${MockSeed.menuItemId('spanish')}')),
    );
    expect(h.server.callsTo(listRoute).last.query['exclude_items'], [
      MockSeed.menuItemId('spanish'),
    ]);
    expect(find.byKey(const ValueKey('orders-exclude-count')), findsOneWidget);
    expect(find.text('1 item excluded'), findsOneWidget);
    expect(h.prefs.getJson('madar.excluded-line-items.${SeedIds.sabahOrg}'), [
      MockSeed.menuItemId('spanish'),
    ]);
    await h.enterText(
      find.byKey(const ValueKey('orders-exclude-search')),
      'zzzz',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    expect(find.text('No results found'), findsOneWidget);
    await h.tap(find.byKey(const ValueKey('orders-exclude-clear')));
    // Back to the first key: served from the cache, nothing excluded.
    expect(find.byKey(const ValueKey('orders-exclude-count')), findsNothing);
    expect(find.text('1 item excluded'), findsNothing);
    expect(
      h.prefs.getJson('madar.excluded-line-items.${SeedIds.sabahOrg}'),
      isEmpty,
    );
  });

  testWidgets('SELL-ORD-015 stored exclusions are sent from the first request', (
    tester,
  ) async {
    final h = await pumpOrders(
      tester,
      prefs: {
        'madar.excluded-line-items.${SeedIds.sabahOrg}':
            '["${MockSeed.menuItemId('latte')}","${MockSeed.menuItemId('mocha')}"]',
      },
    );
    expect(h.server.callsTo(listRoute).single.query['exclude_items'], [
      '${MockSeed.menuItemId('latte')},${MockSeed.menuItemId('mocha')}',
    ]);
    expect(find.text('2 items excluded'), findsOneWidget);
  });

  testWidgets(
    'SELL-ORD-016/017 the delivery block: totals and a card per channel',
    (tester) async {
      final h = await pumpOrders(tester, preset: '30d');
      final fmt = h.container.read(formatProvider);
      final call = h.server.callsTo(deliverySalesRoute).single;
      expect(
        call.path,
        '/reports/branches/${SeedIds.heliopolis}/delivery-sales',
      );
      final scope = h.container.read(currentScopeProvider);
      expect(call.query['from'], [scope.from]);
      expect(find.text('By channel'), findsOneWidget);
      for (final w in [
        'Delivery revenue',
        'Delivered orders',
        'Avg ticket',
        'Delivery fees',
      ]) {
        expect(inPage(find.text(w)), findsWidgets, reason: w);
      }
      final mall = find.byKey(const ValueKey('delivery-channel-in_mall'));
      final out = find.byKey(const ValueKey('delivery-channel-outside'));
      expect(
        find.descendant(of: mall, matching: find.text('In-mall delivery')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: out, matching: find.text('Outside delivery')),
        findsOneWidget,
      );
      // Every sixth day an outside run was cancelled.
      final cancelled = h.db!['delivery_orders']
          .where(
            (r) =>
                r['branch_id'] == SeedIds.heliopolis &&
                r['status'] == 'cancelled' &&
                !DateTime.parse(
                  r['created_at']! as String,
                ).isBefore(DateTime.parse(scope.from)),
          )
          .length;
      expect(cancelled, greaterThan(0));
      expect(
        find.descendant(
          of: out,
          matching: find.text('${ltr(fmt.fmtNumber(cancelled))} cancelled'),
        ),
        findsOneWidget,
      );
      final delivered = h.db!['delivery_orders'].where(
        (r) =>
            r['branch_id'] == SeedIds.heliopolis &&
            r['channel'] == 'in_mall' &&
            r['status'] == 'delivered' &&
            !DateTime.parse(
              r['created_at']! as String,
            ).isBefore(DateTime.parse(scope.from)),
      );
      final mallRevenue = delivered.fold<int>(
        0,
        (s, r) => s + (r['total']! as int),
      );
      expect(
        find.descendant(
          of: mall,
          matching: find.text(fmt.fmtMoney(mallRevenue)),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Revenue share')), findsWidgets);
      // The totals: revenue, delivered orders, average ticket, fees.
      final all = h.db!['delivery_orders'].where(
        (r) =>
            r['branch_id'] == SeedIds.heliopolis &&
            r['status'] == 'delivered' &&
            !DateTime.parse(
              r['created_at']! as String,
            ).isBefore(DateTime.parse(scope.from)),
      );
      final revenue = all.fold<int>(0, (s, r) => s + (r['total']! as int));
      final fees = all.fold<int>(0, (s, r) => s + (r['delivery_fee']! as int));
      Finder tile(String key) => find.descendant(
        of: find.byKey(const ValueKey('orders-delivery')),
        matching: find.byKey(ValueKey(key)),
      );
      expect(
        find.descendant(
          of: tile('rev'),
          matching: find.text(fmt.fmtMoney(revenue)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('orders'),
          matching: find.text(fmt.fmtNumber(all.length)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('avg'),
          matching: find.text(fmt.fmtMoney(revenue ~/ all.length)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('fees'),
          matching: find.text(fmt.fmtMoney(fees)),
        ),
        findsOneWidget,
      );
      // Each card's own fees.
      final mallFees = delivered.fold<int>(
        0,
        (s, r) => s + (r['delivery_fee']! as int),
      );
      expect(
        find.descendant(
          of: mall,
          matching: find.textContaining(
            fmt.fmtMoney(mallFees),
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('SELL-ORD-016 no delivered order: no delivery block', (
    tester,
  ) async {
    final h = await pumpOrders(tester, branchId: SeedIds.maadi);
    expect(h.server.callsTo(deliverySalesRoute), hasLength(1));
    expect(find.byKey(const ValueKey('orders-delivery')), findsNothing);
  });

  testWidgets('SELL-ORD-018/019/021/025 the row: ref + delivery badge, date, '
      'teller, waiter, tax, total', (tester) async {
    final h = await pumpOrders(tester);
    final fmt = h.container.read(formatProvider);
    final date = MockClock.cairoDate(h.db!.clock.now);
    final sale = h.db!['orders'].find(
      OrderSeedIds.deliverySale('heliopolis', date, 8),
    )!;
    final row = find
        .ancestor(
          of: inTable(find.text(_ref(sale))),
          matching: find.byType(DashPressable),
        )
        .first;
    Finder inRow(Finder f) => find.descendant(of: row, matching: f);
    expect(inRow(find.text('Outside')), findsOneWidget);
    expect(
      inRow(find.text(fmt.fmtDateTime(sale['created_at']))),
      findsOneWidget,
    );
    expect(inRow(find.text(sale['teller_name']! as String)), findsOneWidget);
    expect(inRow(find.text('—')), findsOneWidget, reason: 'no waiter');
    expect(
      inRow(find.text(fmt.fmtMoney(sale['tax_amount']! as int))),
      findsOneWidget,
    );
    expect(
      inRow(find.text(fmt.fmtMoney(sale['total_amount']! as int))),
      findsOneWidget,
    );
    final mall = h.db!['orders'].find(
      OrderSeedIds.deliverySale('heliopolis', date, 7),
    )!;
    final mallRow = find
        .ancestor(
          of: inTable(find.text(_ref(mall))),
          matching: find.byType(DashPressable),
        )
        .first;
    expect(
      find.descendant(of: mallRow, matching: find.text('In-mall')),
      findsOneWidget,
    );
    for (final label in [
      '#',
      'Date',
      'Customer',
      'Teller',
      'Waiter',
      'Status',
      'Payment',
      'Tax',
      'Total',
    ]) {
      expect(header(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('SELL-ORD-020/SELL-ALL-015 the customer name opens the customer, '
      'not the row', (tester) async {
    final h = await pumpOrders(tester);
    final reward = h.db!['orders'].find(OrderSeedIds.showcase('reward'))!;
    await h.tap(inTable(find.text(reward['customer_name']! as String)));
    expect(find.byType(CustomerSheet), findsOneWidget);
    expect(
      h.server.callsTo('/customers/{id}').last.path,
      '/customers/${reward['customer_id']}',
    );
    expect(find.byType(OrderSheet), findsNothing);
    expect(h.location.queryParameters.containsKey('order'), isFalse);
  });

  testWidgets(
    'SELL-ORD-020/SELL-ALL-015 without customers.view the name is text',
    (tester) async {
      final s = ordersServer();
      dropCaps(s.server, {'customers.view'});
      final h = await pumpOrders(tester, server: s.server, db: s.db);
      final reward = s.db['orders'].find(OrderSeedIds.showcase('reward'))!;
      await h.tap(inTable(find.text(reward['customer_name']! as String)));
      // The tap reached the row: the order opens, no customer.
      expect(find.byType(CustomerSheet), findsNothing);
      expect(find.byType(OrderSheet), findsOneWidget);
      expect(h.server.callsTo('/customers/{id}'), isEmpty);
    },
  );

  testWidgets('SELL-ORD-022/023 status pill and the Offline price badge', (
    tester,
  ) async {
    final h = await pumpOrders(tester);
    final fmt = h.container.read(formatProvider);
    final id = OrderSeedIds.showcase('offline');
    final badge = find.byKey(ValueKey('price-flag-$id'));
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('Offline price')),
      findsOneWidget,
    );
    final hint =
        '${h.t('orders.offlinePriceHint')} '
        '${h.t('orders.offlinePriceExpected', args: {'amount': fmt.fmtMoney(27000)})}';
    expect(find.bySemanticsLabel('Offline price. $hint'), findsOneWidget);
    expect(inTable(find.text('Voided')), findsWidgets);
    expect(inTable(find.text('Completed')), findsWidgets);
  });

  testWidgets('SELL-ORD-024 a split sale lists each leg with its amount', (
    tester,
  ) async {
    final h = await pumpOrders(tester, branchId: SeedIds.zamalek);
    final fmt = h.container.read(formatProvider);
    final split = h.db!['orders'].find(OrderSeedIds.showcase('split'))!;
    final legs = (split['payment_legs']! as List).cast<Map<String, Object?>>();
    final row = find
        .ancestor(
          of: inTable(find.text(_ref(split))),
          matching: find.byType(DashPressable),
        )
        .first;
    expect(
      find.descendant(of: row, matching: find.text('Mixed')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining(
          fmt.fmtMoney(legs[1]['amount']! as int),
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'SELL-ORD-026/SELL-ALL-008 a row opens its sheet; the row is selected',
    (tester) async {
      final h = await pumpOrders(tester);
      final first = todaysOrders(h.db!, SeedIds.heliopolis).first;
      await h.tap(inTable(find.text(_ref(first))));
      expect(find.byType(OrderSheet), findsOneWidget);
      expect(h.location.queryParameters['order'], first['id']);
      expect(h.server.callsTo(orderRoute).last.path, '/orders/${first['id']}');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DashPressable &&
              w.selected == true &&
              w.semanticLabel == _ref(first),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SELL-ORD-027 no predictive loading (port choice): one read per page',
    (tester) async {
      final h = await pumpOrders(tester);
      expect(h.server.callsTo(listRoute), hasLength(1));
      expect(h.server.callsTo(orderRoute), isEmpty);
    },
  );

  testWidgets(
    'SELL-ORD-028 row actions: Details, and Void order on a completed order',
    (tester) async {
      final h = await pumpOrders(tester);
      final voided = OrderSeedIds.showcase('voided');
      await h.tap(find.byKey(ValueKey('order-actions-$voided')));
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Void order'), findsNothing);
      await h.tap(find.text('Details'));
      expect(find.byType(OrderSheet), findsOneWidget);
      expect(h.location.queryParameters['order'], voided);
      await h.tapLabel('Close');
      expect(find.byType(OrderSheet), findsNothing);
      final offline = OrderSeedIds.showcase('offline');
      await h.tap(find.byKey(ValueKey('order-actions-$offline')));
      await h.tap(find.text('Void order'));
      expect(find.byKey(const ValueKey('void-submit')), findsOneWidget);
      expect(
        find.byType(OrderSheet),
        findsNothing,
        reason: 'actions never open the row',
      );
    },
  );

  for (final (lang, dark) in [('en', false), ('ar', true)]) {
    testWidgets('SELL-ORD-018..028 at 1440 ($lang) every column and the row '
        'actions fit: no sideways scroll', (tester) async {
      final h = await pumpOrders(tester, locale: lang, dark: dark);
      final table = find.byKey(const ValueKey('orders-table'));
      final sideways = find.descendant(
        of: table,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.horizontal,
        ),
      );
      // The kit wraps the grid in a sideways scroller only when it overflows.
      expect(sideways, findsNothing);
      final box = tester.getRect(table);
      final actions = tester.getRect(
        find.byKey(
          ValueKey('order-actions-${OrderSeedIds.showcase('voided')}'),
        ),
      );
      expect(box.contains(actions.center), isTrue);
      expect(h.tester.takeException(), isNull);
    });
  }

  testWidgets(
    'SELL-ORD-030/SELL-ALL-010 loading: skeleton rows, then the data',
    (tester) async {
      final s = ordersServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpOrders(tester, server: s.server, db: s.db);
      expect(inTable(find.byType(DashSkeleton)), findsWidgets);
      expect(find.text('No orders in this range'), findsNothing);
      gate.release();
      await h.settle();
      expect(inTable(find.byType(DashSkeleton)), findsNothing);
      expect(
        inTable(find.text(_ref(todaysOrders(s.db, SeedIds.heliopolis).first))),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SELL-ORD-031/SELL-ALL-010 error with the server words and Retry',
    (tester) async {
      final s = ordersServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Database error: pool timed out'),
        times: null,
      );
      final h = await pumpOrders(tester, server: s.server, db: s.db);
      expect(find.text("Couldn't load this"), findsOneWidget);
      expect(
        find.text(
          h.refusalWords(
            MockResponse.error(500, 'Database error: pool timed out'),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('No orders in this range'), findsNothing);
      s.server.clearFailures();
      final before = h.server.callsTo(listRoute).length;
      await h.tapText('Retry');
      expect(h.server.callsTo(listRoute).length, before + 1);
      expect(find.text("Couldn't load this"), findsNothing);
    },
  );

  testWidgets('SELL-ORD-031/SELL-ALL-004/017 a capability refusal shows the '
      'refusal words', (tester) async {
    final s = ordersServer();
    s.server.fail(
      'GET',
      listRoute,
      MockResponse.denied('orders.read'),
      times: null,
    );
    final h = await pumpOrders(tester, server: s.server, db: s.db);
    expect(
      find.text(h.refusalWords(MockResponse.denied('orders.read'))),
      findsOneWidget,
    );
  });

  testWidgets('SELL-ORD-032/SELL-ALL-010 empty state', (tester) async {
    final s = ordersServer();
    s.db['orders'].clear();
    final h = await pumpOrders(tester, server: s.server, db: s.db);
    expect(find.text('No orders in this range'), findsOneWidget);
    expect(find.text(h.t('orders.emptyBody')), findsOneWidget);
    expect(find.textContaining('Page '), findsNothing);
  });

  testWidgets(
    'SELL-ORD-033/091 Columns hides a column until the page remounts',
    (tester) async {
      final h = await pumpOrders(tester);
      expect(header('Waiter'), findsOneWidget);
      await h.tap(inPage(find.text('Columns')));
      final menuWaiter = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_MenuList',
        ),
        matching: find.text('Waiter'),
      );
      await h.tap(menuWaiter);
      // The menu stays open while toggling.
      expect(menuWaiter, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(menuWaiter, findsNothing);
      expect(header('Waiter'), findsNothing);
      await h.go('/tills');
      await h.go('/orders');
      expect(header('Waiter'), findsOneWidget);
    },
  );

  testWidgets(
    'SELL-ORD-034/SELL-ALL-009 phone: cards, no Columns menu, tap opens',
    (tester) async {
      final h = await pumpOrders(tester, size: DashSize.phone);
      final first = todaysOrders(h.db!, SeedIds.heliopolis).first;
      expect(inPage(find.text('Columns')), findsNothing);
      expect(inTable(find.text(_ref(first))), findsOneWidget);
      expect(inTable(find.text('Teller')), findsWidgets);
      expect(
        find.byKey(ValueKey('order-actions-${first['id']}')),
        findsOneWidget,
      );
      await h.tap(inTable(find.text(_ref(first))));
      expect(find.byType(OrderSheet), findsOneWidget);
    },
  );

  testWidgets('SELL-ORD-081/SELL-ALL-014 Export Excel opens the sheet with the '
      'page\'s filters', (tester) async {
    final h = await pumpOrders(tester);
    await h.enterText(find.byKey(const ValueKey('orders-teller')), 'Far');
    await tester.pump(const Duration(milliseconds: 400));
    await h.settle();
    await _pickFilter(h, 'orders-payment', 'Card');
    final button = find.byKey(const ValueKey('orders-export'));
    expect(tester.widget<DashExportButton>(button).enabled, isTrue);
    await h.tap(inPage(find.text('Export Excel')));
    expect(find.text('Export Orders'), findsOneWidget);
    // Custom forces nothing: the snapshot and the call carry the page's.
    await h.tap(find.byKey(const ValueKey('preset-custom')));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('export-snapshot')),
        matching: find.text('Card'),
      ),
      findsOneWidget,
    );
    await h.tap(find.byKey(const ValueKey('export-run')));
    final call = h.server.callsTo(exportRoute).single;
    expect(call.query['teller_name'], ['Far']);
    expect(call.query['payment_method'], ['card']);
    expect(call.query['branch_id'], [SeedIds.heliopolis]);
    await h.flushTimers();
    expect(h.files.saved, hasLength(1));
  });

  testWidgets('SELL-ORD-086/SELL-ALL-006 till.* refetches the delivery block, '
      'not the list', (tester) async {
    final h = await pumpOrders(tester);
    final lists = h.server.callsTo(listRoute).length;
    final blocks = h.server.callsTo(deliverySalesRoute).length;
    expect(h.realtime.current, isNotNull);
    expect(h.realtime.current!.branchId, SeedIds.heliopolis);
    h.realtime.current!.emit('till.closed', data: '{}');
    await h.settle();
    expect(h.server.callsTo(deliverySalesRoute).length, blocks + 1);
    expect(h.server.callsTo(listRoute).length, lists);
    h.realtime.current!.emit('ticket.created', data: '{}');
    await h.settle();
    expect(h.server.callsTo(listRoute).length, lists);
  });

  testWidgets('SELL-ALL-006 no stream while All branches is selected', (
    tester,
  ) async {
    final h = await pumpOrders(tester, branchId: null);
    expect(h.realtime.current, isNull);
  });

  testWidgets('SELL-ALL-005 the period comes from the scope (7 days)', (
    tester,
  ) async {
    final h = await pumpOrders(tester, preset: '7d');
    final scope = h.container.read(currentScopeProvider);
    final call = h.server.callsTo(listRoute).single;
    expect(call.query['from'], [scope.from]);
    final today = MockClock.startOfCairoDay(h.db!.clock.now);
    expect(DateTime.parse(scope.from), today.subtract(const Duration(days: 6)));
  });

  testWidgets('SELL-ALL-001 the Sell group, its five leaves, by capability', (
    tester,
  ) async {
    final h = await pumpOrders(tester);
    Finder side(String text) => find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text(text),
    );
    expect(side('Sell'), findsOneWidget);
    // The group folds what does not fit under "1 more".
    if (side('Customers').evaluate().isEmpty) await h.tap(side('1 more'));
    final ys = [
      for (final w in ['Orders', 'Floor', 'Bookings', 'Tills', 'Customers'])
        tester.getTopLeft(side(w)).dy,
    ];
    expect(ys, [...ys]..sort());
  });

  testWidgets('SELL-ALL-001 a teller sees only the leaves they hold', (
    tester,
  ) async {
    final h = await pumpOrders(
      tester,
      persona: Persona.limited,
      branchId: SeedIds.maadi,
    );
    Finder side(String text) => find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text(text),
    );
    expect(side('Orders'), findsOneWidget);
    expect(side('Tills'), findsOneWidget);
    if (side('Customers').evaluate().isEmpty) await h.tap(side('1 more'));
    expect(side('Customers'), findsOneWidget);
    expect(side('Floor'), findsNothing);
    expect(side('Bookings'), findsNothing);
    expect(h.server.callsTo(listRoute).single.query['branch_id'], [
      SeedIds.maadi,
    ]);
  });

  testWidgets('SELL-ALL-002 POS switched off: the module gate', (tester) async {
    final h = await pumpOrders(
      tester,
      persona: Persona.dawamOnly,
      branchId: null,
    );
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(find.text(h.t('dawam.modulePosOff')), findsOneWidget);
    expect(h.server.callsTo(listRoute), isEmpty);
  });

  testWidgets('SELL-ALL-003 the modules read failed: error and Retry', (
    tester,
  ) async {
    final s = ordersServer();
    s.server.fail(
      'GET',
      '/orgs/{id}/modules',
      MockResponse.error(500, 'Database error: boom'),
      times: null,
    );
    final h = await pumpOrders(tester, server: s.server, db: s.db);
    expect(find.textContaining(h.t('dawam.modulesLoadError')), findsOneWidget);
    expect(h.server.callsTo(listRoute), isEmpty);
    s.server.clearFailures();
    await h.tapText('Retry');
    expect(find.textContaining(h.t('dawam.modulesLoadError')), findsNothing);
    expect(h.server.callsTo(listRoute), hasLength(1));
  });

  testWidgets('SELL-ALL-007 /shifts goes to /tills with its params', (
    tester,
  ) async {
    final h = await pumpSellAt(tester, '/shifts?report=abc');
    expect(h.location.path, '/tills');
    expect(h.location.queryParameters['report'], 'abc');
  });

  testWidgets('SELL-ALL-012 the shared confirm dialog', (tester) async {
    final h = await pumpOrders(tester);
    final ctx = tester.element(find.byType(OrdersPage));
    final answer = showDashConfirm(
      ctx,
      title: 'Close the till?',
      description: 'The drawer is counted.',
      destructive: true,
    );
    await h.settle();
    expect(find.text('Close the till?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    await h.tapText('Confirm');
    expect(await answer, isTrue);
  });

  testWidgets('prefetch: pointing at Orders warms the list; opening it asks '
      'nothing more', (tester) async {
    final h = await pumpSellAt(tester, '/tills', branchId: SeedIds.heliopolis);
    expect(h.server.callsTo(listRoute), isEmpty);
    final row = find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text('Orders'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row));
    await h.settle();
    expect(
      h.server.callsTo(listRoute),
      hasLength(1),
      reason: 'warmed on hover',
    );
    await h.tap(row);
    expect(h.location.path, '/orders');
    expect(
      h.server.callsTo(listRoute),
      hasLength(1),
      reason: 'served from the cache',
    );
    expect(inTable(find.byType(DashSkeleton)), findsNothing);
  });
}

/// A till of Heliopolis today (the morning one).
String h0TillId() =>
    MockSeed.tillId('heliopolis', MockClock.cairoDate(MockSeed.now), 'morning');

/// The sell area at [path] (another page), today, [branchId] picked.
Future<DashHarness> pumpSellAt(
  WidgetTester tester,
  String path, {
  String? branchId,
}) {
  final s = ordersServer();
  return pumpSell(
    tester,
    path,
    branchId: branchId,
    server: s.server,
    db: s.db,
    prefs: {ScopePrefKeys.preset: 'today'},
  );
}
