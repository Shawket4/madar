// Operations › Items, Tellers, Waiters, Branches (REP-OPS-047…055, 063,
// 064, 065, 066) and the table kit's states there (REP-ALL-018, 019).
import 'package:dashboard_api/dashboard_api.dart'
    show AddonSalesRow, BranchComparison, TellerStats, WaiterStats;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/area_seed.dart';
import 'package:dashboard_reports/src/mock/operations_mock.dart';
import 'package:dashboard_reports/src/operations/ops_analytics.dart';
import 'package:dashboard_reports/src/operations/ops_charts.dart';
import 'package:dashboard_reports/src/operations/ops_rank_table.dart';
import 'package:dashboard_reports/src/operations/ops_report_kit.dart';
import 'package:dashboard_reports/src/operations/ops_support.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<MockRow> _orders(DashHarness h, List<String> branchIds) {
  final s = h.container.read(currentScopeProvider);
  return reportOrders(
    h.db!,
    branchIds: branchIds,
    from: DateTime.parse(s.from),
    to: DateTime.parse(s.to),
  );
}

Finder get _rankFinder => inPage(find.byKey(const ValueKey('ops-items-table')));

OpsRankTable<OpsItemRow> _rankTable(WidgetTester tester) =>
    tester.widget<OpsRankTable<OpsItemRow>>(_rankFinder);

DashDataTable<T> _table<T>(WidgetTester tester, String key) =>
    tester.widget<DashDataTable<T>>(inPage(find.byKey(ValueKey(key))));

List<String> _headers<T>(WidgetTester tester, String key) => [
  for (final c in _table<T>(tester, key).columns) c.label,
];

void _expectRange(DashHarness h, MockCall call) {
  final s = h.container.read(currentScopeProvider);
  expect(DateTime.parse(call.query['from']!.single), DateTime.parse(s.from));
  expect(DateTime.parse(call.query['to']!.single), DateTime.parse(s.to));
}

/// The titled table card [title] (the report kit's `OpsTableCard`).
Finder _tableCard(String title) => inPage(
  find.ancestor(of: find.text(title), matching: find.byType(OpsTableCard)),
);

void main() {
  group('Items', () {
    testWidgets('REP-OPS-047 / item 7 the ranked Items table: combined item '
        'sales, top 50, joined with the period\'s sales (revenue, category) '
        'and the menu (pictures)', (tester) async {
      final h = await pumpOps(tester);
      await openTab(h, 'Items');
      final call = h.server.callsTo(itemsRoute).single;
      expect(call.path, '/reports/branches/$allBranchesId/items-combined');
      expect(call.query['limit'], ['50']);
      _expectRange(h, call);
      // The Overview's read, the same key: one cache for both tabs.
      expect(h.server.callsTo(salesRoute), hasLength(1));
      final t = _rankTable(tester);
      expect(
        [t.lead.label, for (final c in t.columns) c.label],
        ['Item', 'Sold', 'Revenue', 'Share', 'Avg price'],
      );
      expect(t.initialSort, (columnId: 'quantity', descending: true));
      final want = opsCombinedItems(_orders(h, SeedIds.sabahBranches));
      expect([for (final r in t.rows) r.id], [for (final r in want) r.itemId]);
      expect(
        [for (final r in t.rows) r.rank],
        [for (var i = 1; i <= want.length; i++) i],
      );
      expect(t.rows.first.quantity, want.first.totalQty);
      // Revenue, share and average price are the sales report's figures.
      final sales = opsBranchSales(
        branchId: allBranchesId,
        branchName: 'x',
        orders: _orders(h, SeedIds.sabahBranches),
      );
      final sold = {
        for (final c in sales.byCategory)
          for (final i in c.items) i.menuItemId: (i, c.categoryName),
      };
      final total = t.rows.fold<int>(0, (a, r) => a + r.revenue);
      expect(total, greaterThan(0));
      for (final r in t.rows) {
        final s = sold[r.id];
        expect(r.revenue, s?.$1.revenue ?? 0);
        expect(r.category, s?.$2);
        expect(r.share, closeTo(r.revenue / total, 1e-9));
        if (s != null && s.$1.quantitySold > 0) {
          expect(r.avgPrice, (s.$1.revenue / s.$1.quantitySold).round());
        }
      }
      expect(t.rows.fold<double>(0, (a, r) => a + r.share), closeTo(1, 1e-9));
      expect(inPage(find.text(t.rows.first.name)), findsOneWidget);
      // The figures read end-aligned, in the app's money format.
      final f = h.container.read(formatProvider);
      expect(
        inPage(find.text(dashFigure(f.fmtMoney(t.rows.first.revenue)))),
        findsWidgets,
      );
      expect(pageText(h.t('analytics.tabs.items')), findsWidgets);
      await h.shot('operations/items');
    });

    testWidgets('REP-OPS-048 add-on sales, top 20: Name, sold, Revenue; 10 '
        'a page so rows 11–20 are on page 2', (tester) async {
      final h = await pumpOps(tester);
      await openTab(h, 'Items');
      final call = h.server.callsTo(addonsRoute).single;
      expect(call.query['limit'], ['20']);
      _expectRange(h, call);
      expect(_headers<AddonSalesRow>(tester, 'ops-addons-table'), [
        'Name',
        'sold',
        'Revenue',
      ]);
      final t = _table<AddonSalesRow>(tester, 'ops-addons-table');
      expect(t.pageSize, 10);
      final want = opsAddonSales(h.db!, _orders(h, SeedIds.sabahBranches));
      expect(t.rows.length, want.length.clamp(0, 20));
      final f = h.container.read(formatProvider);
      final table = inPage(find.byKey(const ValueKey('ops-addons-table')));
      expect(
        find.descendant(
          of: table,
          matching: find.text(dashFigure(f.fmtMoney(want.first.revenue))),
        ),
        findsOneWidget,
      );
      if (t.rows.length > 10) {
        expect(
          find.descendant(of: table, matching: textHas('Page 1 of 2')),
          findsOneWidget,
        );
      }
    });

    testWidgets('REP-OPS-047 / 048 errors: each table card its own card '
        'error and Retry (the charts\' look, web b448fd9), asking only its '
        'read again', (tester) async {
      final s = opsServer();
      final refusal = MockResponse.error(500, 'The items read failed');
      s.server.fail('GET', itemsRoute, refusal, times: null);
      final h = await pumpOps(tester, server: s.server, db: s.db);
      await openTab(h, 'Items');
      final items = _tableCard('Items');
      expect(
        find.descendant(of: items, matching: find.text("Couldn't load this")),
        findsOneWidget,
      );
      expect(
        find.descendant(of: items, matching: find.byType(DashDataTable)),
        findsNothing,
      );
      // The add-ons card is untouched.
      expect(
        find.descendant(
          of: _tableCard('Addon Sales'),
          matching: find.text("Couldn't load this"),
        ),
        findsNothing,
      );
      await h.shot('operations/items-failed');
      s.server.clearFailures();
      // The tab press's warm-up failed too (dropped, read again): count from
      // here.
      final asked = h.server.callsTo(itemsRoute).length;
      final addons = h.server.callsTo(addonsRoute).length;
      // While the retry runs: still the error, never the empty words.
      final gate = s.server.hold('GET', itemsRoute);
      await h.tap(find.descendant(of: items, matching: find.text('Retry')));
      expect(
        find.descendant(of: items, matching: find.text("Couldn't load this")),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: items,
          matching: find.text('No data for this period'),
        ),
        findsNothing,
      );
      gate.release();
      await h.settle();
      expect(h.server.callsTo(itemsRoute), hasLength(asked + 1));
      expect(h.server.callsTo(addonsRoute), hasLength(addons));
      expect(
        find.descendant(of: items, matching: find.text("Couldn't load this")),
        findsNothing,
      );
    });

    testWidgets('REP-OPS-047 / 048 empty: "No data for this period"; '
        'loading: skeleton rows', (tester) async {
      final s = opsServer();
      final h = await pumpOps(tester, server: s.server, db: s.db);
      final gate = s.server.hold('GET', itemsRoute);
      await openTab(h, 'Items');
      expect(_rankTable(tester).loading, isTrue);
      expect(
        find.descendant(of: _rankFinder, matching: find.byType(DashSkeleton)),
        findsWidgets,
      );
      gate.release();
      await h.settle();
      await h.container
          .read(scopeProvider.notifier)
          .setCustomRange(
            '2026-01-01T00:00:00.000Z',
            '2026-01-02T00:00:00.000Z',
          );
      await h.settle();
      expect(pageText('No data for this period'), findsNWidgets(2));
    });

    testWidgets('REP-OPS-064 Arabic names on the Items tab', (tester) async {
      final h = await pumpOps(tester, locale: 'ar', size: DashSize.phone);
      await openTab(h, h.t('reports.operations.tabs.items'));
      final want = opsCombinedItems(_orders(h, SeedIds.sabahBranches));
      final first = seedMenu.firstWhere(
        (m) => MockSeed.menuItemId(m.key) == want.first.itemId,
      );
      expect(pageText(first.ar), findsWidgets);
      await h.shot('operations/items');
    });
  });

  group('Tellers', () {
    testWidgets('REP-OPS-049 Revenue by Teller: the ten biggest, names on a '
        '110 px axis, compact money', (tester) async {
      final h = await pumpOps(tester);
      await openTab(h, 'Tellers');
      final call = h.server.callsTo(tellersRoute).single;
      expect(call.query['limit'], ['50']);
      _expectRange(h, call);
      final want = opsTellerStats(_orders(h, SeedIds.sabahBranches));
      final chart = tester.widget<OpsHBarChart>(
        inPage(find.byKey(const ValueKey('ops-tellers-chart'))),
      );
      final top = ([
        ...want,
      ]..sort((a, b) => b.revenue.compareTo(a.revenue))).take(10).toList();
      expect(chart.labels, [for (final r in top) r.tellerName]);
      expect(chart.values, [for (final r in top) r.revenue.toDouble()]);
      expect(OpsHBarChart.nameAxis, 110);
      final f = h.container.read(formatProvider);
      expect(chart.formatAxis(250000), f.fmtMoneyCompact(250000));
      expect(chart.tooltip(0), 'Revenue: ${f.fmtMoney(top.first.revenue)}');
      await h.shot('operations/tellers');
    });

    testWidgets('REP-OPS-050 Teller Details: Teller, Orders, Revenue, AOV, '
        '"Order voided", Tills; 50 a page', (tester) async {
      final h = await pumpOps(tester);
      await openTab(h, 'Tellers');
      expect(_headers<TellerStats>(tester, 'ops-tellers-table'), [
        'Teller',
        'Orders',
        'Revenue',
        'AOV',
        'Order voided',
        'Tills',
      ]);
      final t = _table<TellerStats>(tester, 'ops-tellers-table');
      expect(t.pageSize, 50);
      final want = opsTellerStats(_orders(h, SeedIds.sabahBranches));
      expect(t.rows, hasLength(want.length));
      final r = want.first;
      final f = h.container.read(formatProvider);
      final table = inPage(find.byKey(const ValueKey('ops-tellers-table')));
      expect(
        find.descendant(of: table, matching: find.text(r.tellerName)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: table,
          matching: find.text(dashFigure(f.fmtMoney(r.avgOrderValue))),
        ),
        findsWidgets,
      );
      expect(
        want.fold<int>(0, (s, x) => s + x.revenue),
        summarizeSales(_orders(h, SeedIds.sabahBranches)).revenue,
      );
    });

    testWidgets('REP-OPS-049 / 050 failed: the chart\'s error and the '
        'table\'s, both Retry the one read', (tester) async {
      final s = opsServer();
      s.server.fail(
        'GET',
        tellersRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpOps(tester, server: s.server, db: s.db);
      await openTab(h, 'Tellers');
      expect(pageText("Couldn't load this"), findsNWidgets(2));
      s.server.clearFailures();
      // The tab press's warm-up failed too (dropped, read again).
      final asked = h.server.callsTo(tellersRoute).length;
      await h.tap(pageText('Retry').first);
      expect(h.server.callsTo(tellersRoute), hasLength(asked + 1));
      expect(pageText("Couldn't load this"), findsNothing);
    });

    testWidgets('REP-OPS-049 / 050 loading and empty', (tester) async {
      final s = opsServer();
      final h = await pumpOps(tester, server: s.server, db: s.db);
      final gate = s.server.hold('GET', tellersRoute);
      await openTab(h, 'Tellers');
      expect(
        find.descendant(
          of: chartCard('Revenue by Teller'),
          matching: find.byType(DashSkeleton),
        ),
        findsOneWidget,
      );
      expect(_table<TellerStats>(tester, 'ops-tellers-table').loading, isTrue);
      gate.release();
      await h.settle();
      await h.container
          .read(scopeProvider.notifier)
          .setCustomRange(
            '2026-01-01T00:00:00.000Z',
            '2026-01-02T00:00:00.000Z',
          );
      await h.settle();
      expect(pageText('No data for this period'), findsNWidgets(2));
    });
  });

  group('Waiters', () {
    testWidgets('REP-OPS-051 Revenue by Waiter: the top ten', (tester) async {
      final h = await pumpOps(tester);
      await openTab(h, 'Waiters');
      final call = h.server.callsTo(waitersRoute).single;
      expect(call.query.containsKey('limit'), isFalse);
      _expectRange(h, call);
      final want = opsWaiterStats(_orders(h, SeedIds.sabahBranches));
      final chart = tester.widget<OpsHBarChart>(
        inPage(find.byKey(const ValueKey('ops-waiters-chart'))),
      );
      expect(chart.labels, [
        for (final r in want.waiters.take(10)) r.waiterName,
      ]);
      await h.shot('operations/waiters');
    });

    testWidgets('REP-OPS-052 / 053 Waiter Details and the coverage caption', (
      tester,
    ) async {
      final h = await pumpOps(tester);
      await openTab(h, 'Waiters');
      expect(_headers<WaiterStats>(tester, 'ops-waiters-table'), [
        'Waiter',
        'Orders',
        'Revenue',
        'AOV',
        'Items Sold',
        'Items / Order',
        'Order voided',
      ]);
      expect(_table<WaiterStats>(tester, 'ops-waiters-table').pageSize, 50);
      final want = opsWaiterStats(_orders(h, SeedIds.sabahBranches));
      final f = h.container.read(formatProvider);
      expect(
        pageText(
          '${fmtNum(f, want.attributedOrders)} of '
          '${fmtNum(f, want.totalOrders)} orders came through waiters',
        ),
        findsOneWidget,
      );
      final table = inPage(find.byKey(const ValueKey('ops-waiters-table')));
      // Items / Order at most 1 decimal.
      expect(
        find.descendant(
          of: table,
          matching: figure(
            fmtNum(f, want.waiters.first.avgItemsPerOrder, maxDp: 1),
          ),
        ),
        findsWidgets,
      );
      expect(want.attributedOrders, lessThan(want.totalOrders));
    });

    testWidgets('REP-OPS-053 a background refresh keeps the caption (only '
        'the first load hides it)', (tester) async {
      final s = opsServer();
      final h = await pumpOps(
        tester,
        server: s.server,
        db: s.db,
        branchId: SeedIds.zamalek,
      );
      await openTab(h, 'Waiters');
      expect(inPage(textHas('orders came through waiters')), findsOneWidget);
      final gate = s.server.hold('GET', waitersRoute);
      h.realtime.current!.emit('till.closed', data: '{}');
      await h.settle();
      expect(h.server.callsTo(waitersRoute), hasLength(2));
      expect(inPage(textHas('orders came through waiters')), findsOneWidget);
      gate.release();
      await h.settle();
    });

    testWidgets('REP-OPS-053 no caption while loading, on error, or with no '
        'orders', (tester) async {
      final s = opsServer();
      final h = await pumpOps(tester, server: s.server, db: s.db);
      final gate = s.server.hold('GET', waitersRoute);
      await openTab(h, 'Waiters');
      expect(inPage(textHas('orders came through waiters')), findsNothing);
      gate.release();
      await h.settle();
      expect(inPage(textHas('orders came through waiters')), findsOneWidget);
      s.server.fail(
        'GET',
        waitersRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      await h.container
          .read(scopeProvider.notifier)
          .setPreset(ScopePreset.last7Days);
      await h.settle();
      expect(inPage(textHas('orders came through waiters')), findsNothing);
      s.server.clearFailures();
      await h.container
          .read(scopeProvider.notifier)
          .setCustomRange(
            '2026-01-01T00:00:00.000Z',
            '2026-01-02T00:00:00.000Z',
          );
      await h.settle();
      expect(inPage(textHas('orders came through waiters')), findsNothing);
      expect(pageText('No data for this period'), findsNWidgets(2));
    });
  });

  group('Branches', () {
    testWidgets('REP-OPS-054 Revenue by Branch: every branch, largest first', (
      tester,
    ) async {
      final h = await pumpOps(tester);
      await openTab(h, 'Branches');
      final call = h.server.callsTo(comparisonRoute).single;
      expect(call.path, '/reports/orgs/${SeedIds.sabahOrg}/comparison');
      _expectRange(h, call);
      final chart = tester.widget<OpsBarChart>(
        inPage(find.byKey(const ValueKey('ops-branches-chart'))),
      );
      expect(chart.labels, hasLength(4));
      final sorted = [...chart.values]..sort((a, b) => b.compareTo(a));
      expect(chart.values, sorted);
      // The four branches add up to the org's revenue.
      expect(
        chart.values.fold<double>(0, (a, b) => a + b),
        summarizeSales(_orders(h, SeedIds.sabahBranches)).revenue,
      );
      await h.shot('operations/branches');
    });

    testWidgets('REP-OPS-055 Branch Details: Branch, Orders, Revenue, AOV, '
        'Void Rate (1 dp percent)', (tester) async {
      final h = await pumpOps(tester);
      await openTab(h, 'Branches');
      expect(_headers<BranchComparison>(tester, 'ops-branches-table'), [
        'Branch',
        'Orders',
        'Revenue',
        'AOV',
        'Void Rate',
      ]);
      final t = _table<BranchComparison>(tester, 'ops-branches-table');
      expect(t.pageSize, 50);
      final f = h.container.read(formatProvider);
      final r = t.rows.first;
      expect(
        find.descendant(
          of: inPage(find.byKey(const ValueKey('ops-branches-table'))),
          matching: figure(f.fmtPercent(r.voidRatePct / 100)),
        ),
        findsWidgets,
      );
      expect(f.fmtPercent(0.0345), '3.5%');
    });

    testWidgets('REP-OPS-066 a manager in All branches: their branch in the '
        'analytics, every org branch in the comparison', (tester) async {
      final h = await pumpOps(tester, persona: Persona.manager);
      await openTab(h, 'Tellers');
      final tellers = _table<TellerStats>(tester, 'ops-tellers-table').rows;
      expect(
        tellers.length,
        opsTellerStats(_orders(h, [SeedIds.zamalek])).length,
      );
      await openTab(h, 'Branches');
      expect(
        _table<BranchComparison>(tester, 'ops-branches-table').rows,
        hasLength(4),
      );
    });

    testWidgets('REP-OPS-054 refused (another org): the error and Retry', (
      tester,
    ) async {
      final s = opsServer();
      final refusal = MockResponse.forbidden('Not your org');
      s.server.fail('GET', comparisonRoute, refusal, times: null);
      final h = await pumpOps(tester, server: s.server, db: s.db);
      await openTab(h, 'Branches');
      expect(pageText("Couldn't load this"), findsNWidgets(2));
      expect(pageText('Retry'), findsNWidgets(2));
    });
  });

  testWidgets('REP-OPS-063 / REP-ALL-019 phone: the tables are cards titled '
      'by name, cells labelled', (tester) async {
    final h = await pumpOps(tester, size: DashSize.phone);
    await openTab(h, 'Tellers');
    final table = inPage(find.byKey(const ValueKey('ops-tellers-table')));
    expect(
      find.descendant(of: table, matching: find.text('AOV')),
      findsWidgets,
    );
    final t = _table<TellerStats>(tester, 'ops-tellers-table');
    expect(t.columns.first.phone, DashPhoneRole.title);
    await h.shot('operations/tellers');
  });

  testWidgets('REP-OPS-065 / REP-ALL-009 a till event refetches the open '
      'analytics tab while a branch is picked; a floor event does not', (
    tester,
  ) async {
    final h = await pumpOps(tester, branchId: SeedIds.zamalek);
    await openTab(h, 'Items');
    expect(h.server.callsTo(itemsRoute), hasLength(1));
    h.realtime.current!.emit('till.opened', data: '{}');
    await h.settle();
    expect(h.server.callsTo(itemsRoute), hasLength(2));
    expect(h.server.callsTo(addonsRoute), hasLength(2));
    h.realtime.current!.emit('table.updated', data: '{}');
    await h.settle();
    expect(h.server.callsTo(itemsRoute), hasLength(2));
    await openTab(h, 'Branches');
    expect(h.server.callsTo(comparisonRoute), hasLength(1));
    h.realtime.current!.emit('till.closed', data: '{}');
    await h.settle();
    expect(h.server.callsTo(comparisonRoute), hasLength(2));
  });
}
