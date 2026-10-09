// The Financial page frame: tabs per capability, the Restricted page, the
// header actions per tab, the inventory scope toggle, the nav warm-up and
// the live refresh (REP-FIN-001…005, 073, 074; REP-ALL-005, 009, 029).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The page tabs' labels as shown.
List<String> tabLabels(DashHarness h) => [
  for (final e
      in find
          .descendant(
            of: find.byKey(const ValueKey('fin-tabs')),
            matching: find.byType(Text),
          )
          .evaluate())
    (e.widget as Text).data ?? '',
];

void main() {
  testWidgets('REP-FIN-001/003 the owner sees the six tabs in the web\'s '
      'order; Menu profitability opens first', (tester) async {
    final h = await pumpFin(tester);
    expect(tabLabels(h), [
      h.t('reports.financial.tabs.profitability'),
      h.t('reports.financial.tabs.revenue'),
      h.t('reports.financial.tabs.channel'),
      h.t('reports.financial.tabs.valuation'),
      h.t('reports.financial.tabs.supplierSpend'),
      h.t('reports.financial.tabs.materialCostTrend'),
    ]);
    expect(pageText('Financial'), findsOneWidget);
    expect(pageText('Menu profitability'), findsNWidgets(2));
    expect(callsTo(h, ledgerRoute), hasLength(1));
  });

  testWidgets('REP-FIN-001/003 with only inventory.read: Valuation shows '
      'and opens first; spend and trend are never asked', (tester) async {
    final s = finServer();
    authzCaps(s.server, Persona.owner, keep: {Cap.inventoryRead});
    final h = await pumpFin(tester, server: s.server, db: s.db);
    expect(tabLabels(h), [h.t('reports.financial.tabs.valuation')]);
    expect(pageText('Total value'), findsOneWidget);
    for (final r in [
      ledgerRoute,
      branchSpendRoute,
      orgSpendRoute,
      branchTrendRoute,
      orgTrendRoute,
      seriesRoute,
      channelRoute,
    ]) {
      expect(callsTo(h, r), isEmpty, reason: r);
    }
    expect(callsTo(h, orgValuationRoute), hasLength(1));
  });

  testWidgets('REP-FIN-001 the limited cashier (orders.read only) sees the '
      'three sales tabs', (tester) async {
    final h = await pumpFin(tester, persona: Persona.limited);
    expect(tabLabels(h), [
      h.t('reports.financial.tabs.profitability'),
      h.t('reports.financial.tabs.revenue'),
      h.t('reports.financial.tabs.channel'),
    ]);
  });

  testWidgets('REP-FIN-002 / REP-ALL-005 with no tab visible the page is '
      'Restricted, titled Financial, and nothing is asked', (tester) async {
    final s = finServer();
    authzCaps(s.server, Persona.owner, keep: {});
    final h = await pumpFin(tester, server: s.server, db: s.db);
    expect(find.byType(Restricted), findsOneWidget);
    expect(find.text(h.t('reports.noAccess')), findsOneWidget);
    expect(find.text(h.t('common.restrictedTitle')), findsOneWidget);
    expect(readCount(h), 0);
    await h.shot('financial/restricted');
  });

  testWidgets('REP-FIN-003 a picked tab that becomes invisible falls back to '
      'the first visible tab', (tester) async {
    final s = finServer();
    final h = await pumpFin(tester, server: s.server, db: s.db);
    await openTab(h, h.t('reports.financial.tabs.supplierSpend'));
    expect(find.byKey(const ValueKey('fin-spend')), findsOneWidget);
    authzCaps(s.server, Persona.owner, drop: {Cap.purchasingOrdersRead});
    await h.container.read(authzProvider.notifier).refresh();
    await h.settle();
    expect(
      tabLabels(h),
      isNot(contains(h.t('reports.financial.tabs.supplierSpend'))),
    );
    expect(find.byKey(const ValueKey('fin-spend')), findsNothing);
    expect(pageText('Menu profitability'), findsNWidgets(2));
  });

  testWidgets('REP-FIN-004 header actions: none on Menu profitability and '
      'Revenue; the analytics export on Channel; the inventory export on '
      'the three inventory tabs', (tester) async {
    final h = await pumpFin(tester);
    Finder channel() => find.byKey(const ValueKey('fin-channel-export'));
    Finder inv() => find.byKey(const ValueKey('fin-inventory-export'));
    expect(channel(), findsNothing);
    expect(inv(), findsNothing);
    // The ledger's own export sits in its toolbar, not the header.
    expect(find.byKey(const ValueKey('fin-ledger-export')), findsOneWidget);
    await openTab(h, h.t('reports.financial.tabs.revenue'));
    expect(channel(), findsNothing);
    expect(inv(), findsNothing);
    expect(inPage(find.byType(DashExportButton)), findsNothing);
    await openTab(h, h.t('reports.financial.tabs.channel'));
    expect(channel(), findsOneWidget);
    for (final k in [
      'reports.financial.tabs.valuation',
      'reports.financial.tabs.supplierSpend',
      'reports.financial.tabs.materialCostTrend',
    ]) {
      await openTab(h, h.t(k));
      expect(inv(), findsOneWidget, reason: k);
      expect(channel(), findsNothing);
    }
  });

  testWidgets('REP-FIN-005 the scope toggle shows on the inventory tabs '
      'only; with All branches it starts on Whole organization', (
    tester,
  ) async {
    final h = await pumpFin(tester);
    Finder toggle() => find.byKey(const ValueKey('fin-inv-scope'));
    expect(toggle(), findsNothing);
    await openTab(h, h.t('reports.financial.tabs.channel'));
    expect(toggle(), findsNothing);
    await openTab(h, h.t('reports.financial.tabs.valuation'));
    expect(toggle(), findsOneWidget);
    expect(callsTo(h, orgValuationRoute), hasLength(1));
    expect(callsTo(h, branchValuationRoute), isEmpty);
  });

  testWidgets('REP-FIN-005 "This branch" with All branches asks nothing: '
      'zero KPIs and the by-category words, spend and trend empty', (
    tester,
  ) async {
    final h = await pumpFin(tester);
    await openTab(h, h.t('reports.financial.tabs.valuation'));
    await pickSegment(h, 'fin-inv-scope', 'This branch');
    expect(pageText(h.t('inventory.reports.noValuation')), findsOneWidget);
    expect(
      find.descendant(of: kpiCard('Total value'), matching: figure('EGP 0.00')),
      findsWidgets,
    );
    await openTab(h, h.t('reports.financial.tabs.supplierSpend'));
    expect(pageText(h.t('inventory.reports.noDataPeriod')), findsOneWidget);
    await openTab(h, h.t('reports.financial.tabs.materialCostTrend'));
    expect(pageText(h.t('inventory.reports.noCostTrend')), findsOneWidget);
    for (final r in [
      branchValuationRoute,
      branchSpendRoute,
      branchTrendRoute,
    ]) {
      expect(callsTo(h, r), isEmpty, reason: r);
    }
  });

  testWidgets('REP-FIN-005 with a branch picked the toggle starts on This '
      'branch and keeps its value when the scope bar changes', (tester) async {
    final h = await pumpFin(tester, branchId: SeedIds.maadi);
    await openTab(h, h.t('reports.financial.tabs.supplierSpend'));
    expect(callsTo(h, branchSpendRoute).single.path, contains(SeedIds.maadi));
    await h.container.read(scopeProvider.notifier).setBranch(null);
    await h.settle();
    // Still "This branch": with All branches it asks nothing more.
    expect(callsTo(h, branchSpendRoute), hasLength(1));
    expect(callsTo(h, orgSpendRoute), isEmpty);
    expect(pageText(h.t('inventory.reports.noDataPeriod')), findsOneWidget);
  });

  testWidgets('REP-FIN-054 the granularity is page state: it survives a '
      'trip to another tab', (tester) async {
    final h = await pumpFin(tester);
    await openTab(h, h.t('reports.financial.tabs.revenue'));
    await pickSegment(h, 'fin-granularity', 'Monthly');
    await openTab(h, h.t('reports.financial.tabs.channel'));
    await openTab(h, h.t('reports.financial.tabs.revenue'));
    expect(callsTo(h, seriesRoute).last.query['granularity'], ['monthly']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fin-revenue-card')),
        matching: find.text(h.t('analytics.revenueOverTime')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('REP-ALL-029 pointing at the Financial row warms the ledger; '
      'opening it asks nothing more', (tester) async {
    final h = await pumpFin(tester, path: '/reports/legal');
    List<MockCall> ledgers() => callsTo(h, ledgerRoute);
    expect(ledgers(), isEmpty);
    final row = find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text(h.t('nav.reportsFinancial')),
    );
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find
          .descendant(
            of: find.byType(DashSidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await h.settle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row));
    await h.settle();
    expect(ledgers(), hasLength(1), reason: 'warmed on hover');
    expect(ledgers().single.query.containsKey('cost_basis'), isFalse);
    await h.tap(row);
    expect(h.location.path, finPath);
    expect(ledgers(), hasLength(1), reason: 'served from the cache');
  });

  testWidgets('REP-ALL-009 a till event refreshes the Revenue reads, not '
      'the ledger; resync refreshes the ledger too', (tester) async {
    final h = await pumpFin(tester, branchId: SeedIds.heliopolis);
    expect(callsTo(h, ledgerRoute), hasLength(1));
    h.realtime.current!.emit('till.opened', data: '{}');
    await h.settle();
    expect(callsTo(h, ledgerRoute), hasLength(1), reason: '/insights');
    await openTab(h, h.t('reports.financial.tabs.revenue'));
    final series = callsTo(h, seriesRoute).length;
    h.realtime.current!.emit('till.closed', data: '{}');
    await h.settle();
    expect(callsTo(h, seriesRoute), hasLength(series + 1));
    await openTab(h, h.t('reports.financial.tabs.profitability'));
    final ledgers = callsTo(h, ledgerRoute).length;
    h.realtime.current!.emit('resync');
    await h.settle();
    expect(callsTo(h, ledgerRoute).length, greaterThan(ledgers));
  });

  testWidgets('REP-FIN-073 Revenue: Orders and Discounts side by side from '
      '1024 px, stacked on a tablet in portrait', (tester) async {
    final h = await pumpFin(tester);
    await openTab(h, h.t('reports.financial.tabs.revenue'));
    double dy(String k) => tester.getTopLeft(find.byKey(ValueKey(k))).dy;
    expect(dy('fin-orders-card'), dy('fin-discounts-card'));
    tester.view.physicalSize = const Size(800, 1100) * DashSize.pixelRatio;
    await h.settle();
    expect(dy('fin-orders-card'), lessThan(dy('fin-discounts-card')));
  });

  testWidgets('REP-FIN-073 the 1024 tablet is the web\'s lg viewport: the '
      'pair sits side by side', (tester) async {
    final h = await pumpFin(tester, size: DashSize.tablet);
    await openTab(h, h.t('reports.financial.tabs.revenue'));
    double dy(String k) => tester.getTopLeft(find.byKey(ValueKey(k))).dy;
    expect(dy('fin-orders-card'), dy('fin-discounts-card'));
  });

  double shownOf(WidgetTester tester, String k) => tester
      .widget<FadeTransition>(
        find
            .ancestor(
              of: find.byKey(ValueKey(k)),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;

  /// Opens Revenue with one frame, no settling.
  Future<void> openRevenueRaw(WidgetTester tester, DashHarness h) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('fin-tabs')),
        matching: find.text(h.t('reports.financial.tabs.revenue')),
      ),
    );
    await tester.pump();
  }

  testWidgets('REP-FIN-073 the pair fades up in turn, 60 ms apart', (
    tester,
  ) async {
    double shown(String k) => shownOf(tester, k);
    final h = await pumpFin(tester, reducedMotion: false);
    await openRevenueRaw(tester, h);
    expect(shown('fin-orders-card'), lessThan(1));
    await tester.pump(const Duration(milliseconds: 60));
    final orders = shown('fin-orders-card');
    final discounts = shown('fin-discounts-card');
    expect(orders, greaterThan(0));
    expect(discounts, lessThan(orders), reason: 'the second starts 60 ms on');
    await h.settle();
    expect(shown('fin-orders-card'), 1);
    expect(shown('fin-discounts-card'), 1);
  });

  testWidgets('REP-FIN-073 under reduced motion the pair is simply there', (
    tester,
  ) async {
    final h = await pumpFin(tester);
    await openRevenueRaw(tester, h);
    expect(shownOf(tester, 'fin-orders-card'), 1);
    expect(shownOf(tester, 'fin-discounts-card'), 1);
  });

  testWidgets('REP-FIN-074 Valuation ignores the period; Decisions ignore '
      'it too; Repricing asks with no params at all', (tester) async {
    final h = await pumpFin(tester);
    await openInner(h, h.t('insights.profitability.repricingTab'));
    expect(callsTo(h, repricingRoute).single.query, isEmpty);
    await openInner(h, h.t('insights.profitability.decisionsTab'));
    expect(callsTo(h, decisionsRoute).single.query.keys, ['org_id']);
    await openTab(h, h.t('reports.financial.tabs.valuation'));
    expect(callsTo(h, orgValuationRoute).single.query, isEmpty);
  });
}
