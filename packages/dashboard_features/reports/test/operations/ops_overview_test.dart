// Operations › Overview (REP-OPS-034…046, 064, 065, 068, 069) and the
// chart / KPI rules it shows (REP-ALL-020, 023, 024).
import 'package:dashboard_api/dashboard_api.dart' show BranchSalesReport;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/area_seed.dart';
import 'package:dashboard_reports/src/mock/operations_mock.dart';
import 'package:dashboard_reports/src/operations/ops_charts.dart';
import 'package:dashboard_reports/src/operations/ops_support.dart';
import 'package:design_system/design_system.dart';
import 'package:dashboard_core/mock.dart' show MemoryPreferences;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The branch-sales report the page should show, from the seed.
BranchSalesReport _expected(
  DashHarness h,
  List<String> branchIds, {
  Set<String>? exclude,
}) {
  final s = h.container.read(currentScopeProvider);
  final from = DateTime.parse(s.from);
  final to = DateTime.parse(s.to);
  return opsBranchSales(
    branchId: s.scopeBranchId,
    branchName: 'x',
    orders: reportOrders(h.db!, branchIds: branchIds, from: from, to: to),
    exclude: exclude,
  );
}

num _kpi(WidgetTester tester, String key) => tester
    .widget<DashStatValue>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(DashStatValue),
      ),
    )
    .value;

Finder get _trigger =>
    inPage(find.byKey(const ValueKey('ops-exclude-trigger')));

Future<DashHarness> _overview(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  String locale = 'en',
  DashSize size = DashSize.desktop,
  bool dark = false,
  MockServer? server,
  MockDb? db,
  String? branchId,
  Map<String, String>? prefs,
}) async {
  final h = await pumpOps(
    tester,
    persona: persona,
    locale: locale,
    size: size,
    dark: dark,
    server: server,
    db: db,
    branchId: branchId,
    prefs: prefs,
  );
  await openTab(h, h.t('reports.operations.tabs.overview'));
  return h;
}

/// The exclude list's row for menu item [key], brought into view by a search
/// for its name (the list is lazy).
Future<Finder> _excludeRow(DashHarness h, String key, {String? name}) async {
  await h.enterText(
    find.byKey(const ValueKey('ops-exclude-search')),
    name ?? seedMenuItem(key)!.name,
  );
  return find.byKey(ValueKey('ops-exclude-${MockSeed.menuItemId(key)}'));
}

String _excludedPref(List<String> ids) =>
    '[${ids.map((i) => '"$i"').join(',')}]';

void main() {
  testWidgets('REP-OPS-034 branch sales for the period: the sentinel with '
      'All branches, no exclude_items', (tester) async {
    final h = await _overview(tester);
    final call = h.server.callsTo(salesRoute).single;
    expect(call.path, '/reports/branches/$allBranchesId/sales');
    final s = h.container.read(currentScopeProvider);
    expect(DateTime.parse(call.query['from']!.single), DateTime.parse(s.from));
    expect(DateTime.parse(call.query['to']!.single), DateTime.parse(s.to));
    expect(call.query.containsKey('exclude_items'), isFalse);
  });

  testWidgets('REP-OPS-035…038 / 041 / 042 / 069 the six KPIs, their icons '
      'and accents', (tester) async {
    final h = await _overview(tester);
    final d = _expected(h, SeedIds.sabahBranches);
    expect(d.totalOrders, greaterThan(0));
    expect(_kpi(tester, 'revenue'), d.totalRevenue);
    expect(_kpi(tester, 'tax'), d.totalTax);
    expect(_kpi(tester, 'orders'), d.totalOrders);
    expect(_kpi(tester, 'line_items'), d.totalLineItems);
    // REP-OPS-041: computed here, rounded.
    expect(_kpi(tester, 'aov'), (d.totalRevenue / d.totalOrders).round());
    expect(_kpi(tester, 'voided'), d.voidedOrders);
    final cards = tester.widgetList<DashStatCard>(
      inPage(find.byType(DashStatCard)),
    );
    expect(
      [for (final c in cards) c.label],
      ['Revenue', 'Tax', 'Orders', 'Items Sold', 'Avg Order', 'Order voided'],
    );
    expect(
      [for (final c in cards) c.icon],
      ['coins', 'percent', 'receipt', 'shopping-basket', 'trending-up', 'ban'],
    );
    expect(
      [for (final c in cards) c.tone],
      [
        DashTone.neutral,
        DashTone.info,
        DashTone.accent,
        DashTone.info,
        DashTone.info,
        DashTone.warning,
      ],
    );
    // REP-ALL-023: six cards are dense.
    expect(cards.every((c) => c.dense), isTrue);
    // Items Sold carries the exclude control; no hint while none excluded.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('line_items')),
        matching: _trigger,
      ),
      findsOneWidget,
    );
    expect(pageText('1 item excluded'), findsNothing);
  });

  testWidgets('REP-OPS-041 no orders: Avg Order is 0', (tester) async {
    final h = await _overview(tester);
    await h.container
        .read(scopeProvider.notifier)
        .setCustomRange('2026-01-01T00:00:00.000Z', '2026-01-02T00:00:00.000Z');
    await h.settle();
    expect(_kpi(tester, 'orders'), 0);
    expect(_kpi(tester, 'aov'), 0);
    // REP-OPS-043…045 empty.
    expect(pageText('No data for this period'), findsNWidgets(3));
    await h.shot('operations/overview-empty');
  });

  group('REP-OPS-039 / 040 / 068 the exclude control', () {
    testWidgets('the menu loads only once the list opens; it shows the note, '
        'a search, the group and every item', (tester) async {
      final h = await _overview(tester);
      expect(h.server.callsTo(menuRoute), isEmpty);
      final trigger = tester.widget<DashPressable>(_trigger);
      expect(trigger.semanticLabel, 'Exclude items from this count');
      await h.tap(_trigger);
      final menu = h.server.callsTo(menuRoute).single;
      expect(menu.query['org_id'], [SeedIds.sabahOrg]);
      expect(find.text(h.t('analytics.excludeScopeNote')), findsOneWidget);
      expect(find.text('Excluded from Items Sold'), findsOneWidget);
      expect(find.byKey(const ValueKey('ops-exclude-search')), findsOneWidget);
      // The first items of the menu, by name.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('ops-exclude-') &&
              (w.key! as ValueKey<String>).value.length > 40,
        ),
        findsWidgets,
      );
      await h.shot('operations/exclude');
      expect(await _excludeRow(h, 'latte'), findsOneWidget);
    });

    testWidgets('a tap excludes an item: the badge counts it, the hint says '
        'so, the read carries exclude_items, it is saved for the org', (
      tester,
    ) async {
      final h = await _overview(tester);
      final latte = MockSeed.menuItemId('latte');
      final mocha = MockSeed.menuItemId('mocha');
      await h.tap(_trigger);
      await h.tap(await _excludeRow(h, 'latte'));
      var call = h.server.callsTo(salesRoute).last;
      expect(call.query['exclude_items'], [latte]);
      expect(pageText('1 item excluded'), findsOneWidget);
      await h.tap(await _excludeRow(h, 'mocha'));
      call = h.server.callsTo(salesRoute).last;
      expect(call.query['exclude_items'], ['$latte,$mocha']);
      expect(pageText('2 items excluded'), findsOneWidget);
      // The badge.
      expect(
        find.descendant(of: _trigger, matching: find.text('2')),
        findsOneWidget,
      );
      expect(h.prefs.getJson(excludedItemsPrefKey(SeedIds.sabahOrg)), [
        latte,
        mocha,
      ]);
      // Only Items Sold moves (REP-OPS-039's note).
      final d = _expected(h, SeedIds.sabahBranches, exclude: {latte, mocha});
      expect(_kpi(tester, 'line_items'), d.totalLineItems);
      expect(_kpi(tester, 'revenue'), d.totalRevenue);
      expect(
        d.totalLineItems,
        lessThan(_expected(h, SeedIds.sabahBranches).totalLineItems!),
      );
      // A second tap puts it back: the latte-only answer is still cached.
      final calls = h.server.callsTo(salesRoute).length;
      await h.tap(await _excludeRow(h, 'mocha'));
      expect(h.server.callsTo(salesRoute), hasLength(calls));
      expect(pageText('1 item excluded'), findsOneWidget);
      expect(
        _kpi(tester, 'line_items'),
        _expected(h, SeedIds.sabahBranches, exclude: {latte}).totalLineItems,
      );
    });

    testWidgets('Clear empties the list; the read drops exclude_items', (
      tester,
    ) async {
      final latte = MockSeed.menuItemId('latte');
      final h = await _overview(
        tester,
        prefs: {
          excludedItemsPrefKey(SeedIds.sabahOrg): _excludedPref([latte]),
        },
      );
      expect(h.server.callsTo(salesRoute).single.query['exclude_items'], [
        latte,
      ]);
      await h.tap(_trigger);
      await h.tap(find.byKey(const ValueKey('ops-exclude-clear')));
      expect(
        h.server.callsTo(salesRoute).last.query.containsKey('exclude_items'),
        isFalse,
      );
      expect(find.byKey(const ValueKey('ops-exclude-clear')), findsNothing);
      expect(h.prefs.getJson(excludedItemsPrefKey(SeedIds.sabahOrg)), isEmpty);
    });

    testWidgets('the search matches the shown name; nothing → "No results '
        'found"', (tester) async {
      final h = await _overview(tester);
      await h.tap(_trigger);
      final search = find.byKey(const ValueKey('ops-exclude-search'));
      await h.enterText(search, 'LAT');
      final latte = MockSeed.menuItemId('latte');
      expect(find.byKey(ValueKey('ops-exclude-$latte')), findsOneWidget);
      expect(
        find.byKey(ValueKey('ops-exclude-${MockSeed.menuItemId('mocha')}')),
        findsNothing,
      );
      await h.enterText(search, 'zzzz');
      expect(find.text('No results found'), findsOneWidget);
    });

    testWidgets('REP-OPS-040 "Loading…" while the menu loads', (tester) async {
      final s = opsServer();
      final gate = s.server.hold('GET', menuRoute);
      final h = await _overview(tester, server: s.server, db: s.db);
      await h.tap(_trigger);
      expect(find.text('Loading…'), findsOneWidget);
      gate.release();
      await h.settle();
      expect(find.text('Loading…'), findsNothing);
    });

    testWidgets('REP-OPS-064 Arabic names in Arabic; the search matches them', (
      tester,
    ) async {
      final h = await _overview(tester, locale: 'ar', size: DashSize.phone);
      await h.tap(_trigger);
      final latte = seedMenuItem('latte')!;
      // Searching the Arabic name finds it, and it reads in Arabic.
      final row = await _excludeRow(h, 'latte', name: latte.ar);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(latte.ar)),
        findsOneWidget,
      );
      // The English name is not what is shown, so it does not match.
      expect(await _excludeRow(h, 'latte', name: latte.name), findsNothing);
      await h.enterText(find.byKey(const ValueKey('ops-exclude-search')), '');
      await h.shot('operations/exclude');
    });

    testWidgets('REP-OPS-068 the same per-org device list the Orders page '
        'reads; another org keeps its own', (tester) async {
      final latte = MockSeed.menuItemId('latte');
      final h = await _overview(
        tester,
        prefs: {
          excludedItemsPrefKey(SeedIds.sabahOrg): _excludedPref([latte]),
          excludedItemsPrefKey('another-org'): _excludedPref(['x', 'y']),
        },
      );
      expect(
        excludedItemsPrefKey(SeedIds.sabahOrg),
        'madar.excluded-line-items.${SeedIds.sabahOrg}',
      );
      expect(pageText('1 item excluded'), findsOneWidget);
      final icon = tester.widget<DashIcon>(
        find.descendant(of: _trigger, matching: find.byType(DashIcon)),
      );
      expect(icon.name, 'list-filter');
      expect(icon.color, h.tester.element(_trigger).madarColors.info);
    });

    testWidgets('REP-OPS-068 with no org nothing is saved', (tester) async {
      final c = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(MemoryPreferences({})),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(excludedItemsProvider(null), (_, _) {});
      c.read(excludedItemsProvider(null).notifier).toggle('a');
      expect(sub.read(), ['a']);
      final prefs = c.read(preferencesProvider) as MemoryPreferences;
      expect(prefs.getJson(excludedItemsPrefKey('null')), isNull);
      expect(excludeItemsParam(const []), isNull);
      expect(excludeItemsParam(const ['a', 'b']), 'a,b');
    });
  });

  testWidgets('REP-OPS-043 Revenue by Payment Method: slices > 0, largest '
      'first, payment colours, a legend with words and money', (tester) async {
    final h = await _overview(tester);
    final d = _expected(h, SeedIds.sabahBranches);
    final methods =
        (d.revenueByMethod as Map).entries
            .where((e) => (e.value as num) > 0)
            .toList()
          ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    final donut = tester.widget<DashDonutChart>(
      inPage(find.byKey(const ValueKey('ops-payment-donut'))),
    );
    expect(
      [for (final s in donut.slices) s.value],
      [for (final e in methods) (e.value as num).toDouble()],
    );
    expect(
      [for (final s in donut.slices) s.label],
      [for (final e in methods) h.t('payments.${e.key}')],
    );
    final f = h.container.read(formatProvider);
    final card = chartCard('Revenue by Payment Method');
    for (final e in methods) {
      expect(
        find.descendant(
          of: card,
          matching: find.text(h.t('payments.${e.key}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text(dashFigure(f.fmtMoney(e.value as num))),
        ),
        findsOneWidget,
      );
    }
    // Colour is never the only signal; and slices sum to Revenue.
    expect(donut.slices.fold<double>(0, (a, s) => a + s.value), d.totalRevenue);
    expect(donut.formatValue!(1250), f.fmtMoney(1250));
  });

  testWidgets('REP-OPS-044 By Category: the 10 biggest by revenue, every '
      'label, compact money axis', (tester) async {
    final h = await _overview(tester);
    final d = _expected(h, SeedIds.sabahBranches);
    final cats = [...d.byCategory]
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final chart = tester.widget<OpsBarChart>(
      inPage(find.byKey(const ValueKey('ops-by-category'))),
    );
    expect(chart.labels, [for (final c in cats.take(10)) c.categoryName]);
    expect(chart.values, [for (final c in cats.take(10)) c.revenue.toDouble()]);
    final f = h.container.read(formatProvider);
    expect(chart.formatAxis(150000), f.fmtMoneyCompact(150000));
    expect(chart.tooltip(0), 'Revenue: ${f.fmtMoney(cats.first.revenue)}');
  });

  testWidgets('REP-OPS-045 Top Items by Quantity Sold: ten rows with rank, '
      'name, "n sold" and revenue', (tester) async {
    final h = await _overview(tester);
    final d = _expected(h, SeedIds.sabahBranches);
    final card = chartCard('Top Items by Quantity Sold');
    final f = h.container.read(formatProvider);
    final top = d.topItems.take(10).toList();
    expect(top, hasLength(10));
    for (final (i, it) in top.indexed) {
      expect(
        find.descendant(of: card, matching: find.text(dashFigure('${i + 1}'))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text(it.itemName)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: card,
        matching: find.text(
          '${dashFigure(fmtNum(f, top.first.quantitySold))} sold',
        ),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(of: card, matching: find.text(dashFigure('11'))),
      findsNothing,
    );
  });

  testWidgets('REP-OPS-064 Arabic: item and category names in Arabic, '
      'payment words translated, figures LTR', (tester) async {
    final h = await _overview(tester, locale: 'ar', size: DashSize.tablet);
    final latte = seedMenuItem('latte')!;
    expect(pageText(latte.ar), findsWidgets);
    expect(pageText(h.t('payments.cash')), findsWidgets);
    final chart = tester.widget<OpsBarChart>(
      inPage(find.byKey(const ValueKey('ops-by-category'))),
    );
    expect(chart.labels.first, matches(RegExp(r'[؀-ۿ]')));
    // REP-ALL-020: the plot reads left to right in Arabic.
    expect(
      tester
          .widget<Directionality>(
            find
                .descendant(
                  of: inPage(find.byType(OpsBarChart)),
                  matching: find.byType(Directionality),
                )
                .first,
          )
          .textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('REP-OPS-046 a failed read: each card its own frameless error '
      'with Retry; Retry asks for branch sales again', (tester) async {
    final s = opsServer();
    s.server.fail(
      'GET',
      salesRoute,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await _overview(tester, server: s.server, db: s.db);
    expect(pageText("Couldn't load this"), findsNWidgets(3));
    for (final e in tester.widgetList<DashErrorState>(
      inPage(find.byType(DashErrorState)),
    )) {
      expect(e.framed, isFalse);
    }
    await h.shot('operations/overview-failed');
    s.server.clearFailures();
    final before = h.server.callsTo(salesRoute).length;
    await h.tap(pageText('Retry').first);
    expect(h.server.callsTo(salesRoute).length, before + 1);
    expect(pageText("Couldn't load this"), findsNothing);
    expect(
      inPage(find.byKey(const ValueKey('ops-payment-donut'))),
      findsOneWidget,
    );
  });

  testWidgets('REP-OPS-043…045 loading: chart skeletons and five top-item '
      'rows; KPI skeletons', (tester) async {
    final s = opsServer();
    final h = await pumpOps(tester, server: s.server, db: s.db);
    final gate = s.server.hold('GET', salesRoute);
    await openTab(h, 'Overview');
    for (final c in tester.widgetList<DashStatCard>(
      inPage(find.byType(DashStatCard)),
    )) {
      expect(c.loading, isTrue);
    }
    expect(
      find.descendant(
        of: chartCard('Top Items by Quantity Sold'),
        matching: find.byType(DashSkeleton),
      ),
      findsNWidgets(5),
    );
    expect(
      find.descendant(
        of: chartCard('By Category'),
        matching: find.byType(DashSkeleton),
      ),
      findsOneWidget,
    );
    await h.shot('operations/overview-loading');
    gate.release();
    await h.settle();
  });

  testWidgets('REP-OPS-034 a manager: their branch only, through the '
      'sentinel', (tester) async {
    final h = await _overview(tester, persona: Persona.manager);
    final d = _expected(h, [SeedIds.zamalek]);
    expect(_kpi(tester, 'revenue'), d.totalRevenue);
  });

  testWidgets('REP-OPS-065 / REP-ALL-009 a till event refetches the '
      'Overview while a branch is picked', (tester) async {
    final h = await _overview(tester, branchId: SeedIds.zamalek);
    expect(h.server.callsTo(salesRoute), hasLength(1));
    h.realtime.current!.emit('till.closed', data: '{}');
    await h.settle();
    expect(h.server.callsTo(salesRoute), hasLength(2));
    h.realtime.current!.emit('floor.table_updated', data: '{}');
    await h.settle();
    expect(h.server.callsTo(salesRoute), hasLength(2));
  });

  testWidgets('REP-ALL-020 reduced motion: charts do not animate', (
    tester,
  ) async {
    await _overview(tester);
    expect(
      tester.widget<OpsBarChart>(inPage(find.byType(OpsBarChart))),
      isNotNull,
    );
    // The harness runs with reduced motion: DashMotion is zero.
    final ctx = tester.element(inPage(find.byType(OpsBarChart)));
    expect(DashMotion.of(ctx, DashMotion.slow), Duration.zero);
  });

  testWidgets('REP-ALL-024 (divergence) tooltips name their series in the '
      'active language', (tester) async {
    final h = await _overview(tester, locale: 'ar', size: DashSize.tablet);
    final chart = tester.widget<OpsBarChart>(
      inPage(find.byKey(const ValueKey('ops-by-category'))),
    );
    expect(chart.tooltip(0), startsWith('${h.t('dashboard.revenue')}: '));
    expect(chart.tooltip(0), isNot(contains('revenue')));
  });

  testWidgets('REP-OPS-063 phone: KPIs two up, the charts stacked', (
    tester,
  ) async {
    final h = await _overview(tester, size: DashSize.phone);
    final pay = tester.getRect(chartCard('Revenue by Payment Method'));
    final cat = tester.getRect(chartCard('By Category'));
    expect(cat.top, greaterThan(pay.bottom - 1));
    final revenue = tester.getRect(find.byKey(const ValueKey('revenue')));
    final tax = tester.getRect(find.byKey(const ValueKey('tax')));
    final orders = tester.getRect(find.byKey(const ValueKey('orders')));
    expect(tax.top, revenue.top);
    expect(orders.top, greaterThan(revenue.bottom - 1));
    await h.shot('operations/overview');
  });

  for (final (size, rows) in [
    (DashSize.desktop, 1),
    // The web's lg:grid-cols-6 holds at a 1024 window (the kit strip counts
    // columns by the window, as the web's media queries do).
    (DashSize.tablet, 1),
    (DashSize.phone, 3),
  ]) {
    testWidgets('REP-ALL-023 KPI cards: six in $rows row(s) on '
        '${size.name}', (tester) async {
      await _overview(tester, size: size);
      final tops = {
        for (final k in [
          'revenue',
          'tax',
          'orders',
          'line_items',
          'aov',
          'voided',
        ])
          tester.getRect(find.byKey(ValueKey(k))).top,
      };
      expect(tops, hasLength(rows));
    });
  }

  testWidgets('REP-ALL-023 a figure too wide for its card is shortened; a '
      'tap shows the label and the exact amount', (tester) async {
    const big = 98765432109876;
    final s = opsServer();
    s.server.on('GET', salesRoute, (req) {
      final r = opsBranchSales(
        branchId: req.param('branchId'),
        branchName: 'All branches',
        orders: const [],
      ).toJson();
      return MockResponse.ok({...r, 'total_revenue': big});
    });
    final h = await _overview(
      tester,
      size: DashSize.phone,
      server: s.server,
      db: s.db,
    );
    final f = h.container.read(formatProvider);
    final exact = f.fmtMoney(big);
    final card = find.byKey(const ValueKey('revenue'));
    final press = find.descendant(
      of: card,
      matching: find.byType(DashPressable),
    );
    expect(press, findsOneWidget);
    expect(
      tester.widget<DashPressable>(press).semanticLabel,
      'Revenue: $exact',
    );
    await h.tap(press);
    expect(find.text(exact), findsOneWidget);
    expect(find.text('REVENUE'), findsOneWidget);
    await h.shot('operations/kpi-popover');
  });

  testWidgets('REP-OPS-063 wide: the two charts side by side from 1024', (
    tester,
  ) async {
    await _overview(tester);
    final pay = tester.getRect(chartCard('Revenue by Payment Method'));
    final cat = tester.getRect(chartCard('By Category'));
    expect(cat.top, pay.top);
    expect(cat.height, pay.height);
  });
}
