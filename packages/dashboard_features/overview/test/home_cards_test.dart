// The home's charts, rankings, margin watch and delivery section, driven
// through the real app shell (inventory rows OVW-HOME-057 to -113).
import 'package:dashboard_api/dashboard_api.dart'
    show
        BranchComparison,
        DeliveryChannelSales,
        DeliverySalesReport,
        LedgerTotals,
        MarginLedgerRow,
        MarginWatch,
        Signal;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:dashboard_overview/src/home/delivery.dart';
import 'package:dashboard_overview/src/home/keep_building.dart';
import 'package:dashboard_overview/src/home/home_charts.dart';
import 'package:dashboard_overview/src/home/home_data.dart';
import 'package:dashboard_overview/src/home/home_parts.dart';
import 'package:dashboard_overview/src/home/margin_watch.dart';
import 'package:dashboard_overview/src/mock/home_figures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _sales = '/reports/branches/{branchId}/sales';
const _series = '/reports/branches/{branchId}/sales/timeseries';
const _cmp = '/reports/orgs/{orgId}/comparison';
const _delivery = '/reports/branches/{branchId}/delivery-sales';
const _watch = '/insights/branches/{branchId}/margin-watch';

const _from = '2026-09-08T21:00:00.000Z';
const _to = '2026-10-08T20:59:59.999Z';

final _sabah = [
  SeedIds.heliopolis,
  SeedIds.maadi,
  SeedIds.newCairo,
  SeedIds.zamalek,
];

List<MockRow> orders(DashHarness h, List<String> ids, {String from = _from}) =>
    ordersIn(h.db!, ids, from: DateTime.parse(from), to: DateTime.parse(_to));

DashStatCard kpi(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashStatCard && w.label == label).first,
);

/// A failure the web retries once and then shows (a 500).
MockResponse boom() => MockResponse.error(500, 'Internal error');

void main() {
  group('revenue trend', () {
    testWidgets('OVW-HOME-057/061/062 one point per day, daily labels', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      final chart = tester.widget<DashLineChart>(find.byType(DashLineChart));
      expect(chart.labels, hasLength(30));
      expect(chart.labels.first, '9 Sept');
      expect(chart.labels.last, '8 Oct');
      final total = chart.series.single.values.fold<double>(0, (s, v) => s + v);
      expect(total, SalesTotals(orders(h, _sabah)).revenue);
      expect(chart.series.single.label, 'Revenue');
      expect(chart.height, HomeMetrics.chart);
      expect(chart.formatY(123456), 'EGP 1.2K');
      expect(chart.formatValue!(123456), 'EGP 1,234.56');
    });

    testWidgets('OVW-HOME-062 hourly labels for today', (tester) async {
      await pumpHome(tester, path: '/?preset=today');
      final chart = tester.widget<DashLineChart>(find.byType(DashLineChart));
      expect(chart.labels.first, matches(RegExp(r'^8 Oct, \d\d:00 (AM|PM)$')));
    });

    testWidgets('OVW-HOME-062 Arabic period labels', (tester) async {
      await pumpHome(tester, locale: 'ar', path: '/?preset=today');
      final chart = tester.widget<DashLineChart>(find.byType(DashLineChart));
      expect(chart.labels.first, matches(RegExp(r'^8 أكتوبر، \d\d:00 (ص|م)$')));
    });

    testWidgets('OVW-HOME-058 loading: a skeleton', (tester) async {
      final s = homeServer();
      final gate = s.server.hold('GET', _series);
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(find.byType(DashLineChart), findsNothing);
      expect(find.byType(HomeSkeleton), findsOneWidget);
      gate.release();
      await h.settle();
      expect(find.byType(DashLineChart), findsOneWidget);
    });

    testWidgets('OVW-HOME-059 error and Retry', (tester) async {
      final s = homeServer();
      s.server.fail('GET', _series, boom());
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText("Couldn't load the revenue trend"), findsOneWidget);
      final before = h.server.callsTo(_series).length;
      await h.tap(
        find.descendant(
          of: find.ancestor(
            of: homeText("Couldn't load the revenue trend"),
            matching: find.byType(DashErrorState),
          ),
          matching: homeText('Retry'),
        ),
      );
      expect(h.server.callsTo(_series).length, before + 1);
      expect(find.byType(DashLineChart), findsOneWidget);
    });

    testWidgets('OVW-HOME-060 empty: the sentence', (tester) async {
      final s = homeServer();
      s.server.on('GET', _series, (req) => MockResponse.ok(const []));
      await pumpHome(tester, server: s.server, db: s.db);
      expect(
        homeText('Sales for this period will appear here.'),
        findsOneWidget,
      );
    });

    testWidgets('OVW-HOME-065 a till event refetches it (branch picked)', (
      tester,
    ) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
      final before = h.server.callsTo(_series).length;
      h.realtime.current!.emit('till.closed', data: '{}');
      await h.settle();
      expect(h.server.callsTo(_series).length, before + 1);
    });
  });

  group('payment mix', () {
    testWidgets('OVW-HOME-066/071 all branches: summed, largest first', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      final map = revenueByMethod(orders(h, _sabah));
      final sorted = map.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final fmt = h.container.read(formatProvider);
      final total = sorted.fold(0, (s, e) => s + e.value);
      Finder inCard(String text) => find.descendant(
        of: find.byType(HomePaymentMixCard),
        matching: find.text(text),
      );
      for (final e in sorted) {
        expect(inCard(fmt.fmtMoney(e.value)), findsOneWidget);
        expect(inCard(fmt.fmtShare(e.value, total)), findsOneWidget);
      }
      final names = tester
          .widget<DashDonutChart>(find.byType(DashDonutChart))
          .slices
          .map((s) => s.label)
          .toList();
      expect(names.first, 'Cash');
      expect(names, hasLength(sorted.length));
    });

    testWidgets('OVW-HOME-066 a branch: its own buckets', (tester) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.zamalek}');
      final map = revenueByMethod(orders(h, [SeedIds.zamalek]));
      final fmt = h.container.read(formatProvider);
      expect(homeText(fmt.fmtMoney(map['cash'])), findsOneWidget);
    });

    testWidgets('OVW-HOME-067 loading: a skeleton', (tester) async {
      final s = homeServer();
      final gate = s.server.hold('GET', _cmp);
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(find.byType(DashDonutChart), findsNothing);
      gate.release();
      await h.settle();
      expect(find.byType(DashDonutChart), findsOneWidget);
    });

    testWidgets('OVW-HOME-068 error: Retry asks the comparison again', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _cmp, boom());
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText("Couldn't load the payment mix"), findsOneWidget);
      expect(homeText("Couldn't load branch performance"), findsOneWidget);
      final before = h.server.callsTo(_cmp).length;
      await h.tap(
        find.descendant(
          of: find.ancestor(
            of: homeText("Couldn't load the payment mix"),
            matching: find.byType(DashErrorState),
          ),
          matching: homeText('Retry'),
        ),
      );
      expect(h.server.callsTo(_cmp).length, before + 1);
      expect(find.byType(DashDonutChart), findsOneWidget);
    });

    testWidgets('OVW-HOME-068 a branch: Retry asks branch sales again', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _sales, boom());
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        path: '/?branchId=${SeedIds.maadi}',
      );
      final before = h.server.callsTo(_sales).length;
      await h.tapText('Retry');
      expect(h.server.callsTo(_sales).length, before + 1);
      expect(homeText("Couldn't load the payment mix"), findsNothing);
    });

    testWidgets('OVW-HOME-069 nothing taken: the sentence', (tester) async {
      final s = homeServer();
      s.db['orders'].clear();
      await pumpHome(tester, server: s.server, db: s.db);
      expect(find.byType(DashDonutChart), findsNothing);
      // Trend and payment mix say it; branch performance still lists the
      // branches at zero.
      expect(
        homeText('Sales for this period will appear here.'),
        findsNWidgets(2),
      );
      expect(homeText('Heliopolis'), findsOneWidget);
    });

    testWidgets('OVW-HOME-070/071 an org-defined method shows its code', (
      tester,
    ) async {
      final s = homeServer();
      final o = s.db['orders'].rows.lastWhere(
        (o) => o['status'] == 'completed',
      );
      o['payment_legs'] = [
        {'method': 'instapay', 'amount': o['total_amount'], 'is_cash': false},
      ];
      await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText('instapay'), findsOneWidget);
    });

    testWidgets('OVW-HOME-070 method colours come from the theme', (
      tester,
    ) async {
      await pumpHome(tester);
      final chart = tester.widget<DashDonutChart>(find.byType(DashDonutChart));
      final BuildContext ctx = tester.element(find.byType(DashDonutChart));
      final c = ctx.madarColors;
      expect(chart.slices.first.color, c.success); // cash
      expect(chart.slices[1].color, c.info); // card
    });
  });

  group('branch performance', () {
    testWidgets('OVW-HOME-073/077 ranked by revenue, orders, bars', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      final ranked = rankBranches([for (final id in _sabah) _row(h, id)]);
      final fmt = h.container.read(formatProvider);
      var y = -1.0;
      for (final r in ranked) {
        final name = homeText(r.row.branchName).last;
        expect(tester.getTopLeft(name).dy, greaterThan(y));
        y = tester.getTopLeft(name).dy;
        expect(homeText(fmt.fmtMoney(r.row.totalRevenue)), findsOneWidget);
        expect(
          homeHas(
            '${fmt.fmtNumber(r.row.totalOrders)}\u2069 orders',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Revenue share for ${r.row.branchName}'),
          findsOneWidget,
        );
      }
      final bars = tester.widgetList<DashProgressBar>(
        find.byType(DashProgressBar),
      );
      expect(bars.first.value, 100);
    });

    testWidgets('OVW-HOME-073 a branch picked still ranks every branch', (
      tester,
    ) async {
      await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
      expect(
        find.bySemanticsLabel(RegExp('^Revenue share for ')),
        findsNWidgets(4),
      );
    });

    testWidgets('OVW-HOME-074/075 loading, then error and Retry', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _cmp, boom());
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText("Couldn't load branch performance"), findsOneWidget);
      final before = h.server.callsTo(_cmp).length;
      await h.tap(
        find.descendant(
          of: find.ancestor(
            of: homeText("Couldn't load branch performance"),
            matching: find.byType(DashErrorState),
          ),
          matching: homeText('Retry'),
        ),
      );
      expect(h.server.callsTo(_cmp).length, before + 1);
      expect(
        find.bySemanticsLabel(RegExp('^Revenue share for ')),
        findsNWidgets(4),
      );
    });

    testWidgets('OVW-HOME-076 no branches: the sentence', (tester) async {
      final s = homeServer();
      s.server.on(
        'GET',
        _cmp,
        (req) =>
            MockResponse.ok({'org_id': SeedIds.sabahOrg, 'branches': const []}),
      );
      await pumpHome(tester, server: s.server, db: s.db);
      expect(
        homeText('Sales for this period will appear here.'),
        findsNWidgets(2),
      );
    });

    testWidgets('OVW-HOME-076/077 a branch with no sales: minimum bar', (
      tester,
    ) async {
      final s = homeServer();
      s.db['orders'].removeWhere((o) => o['branch_id'] == SeedIds.zamalek);
      await pumpHome(tester, server: s.server, db: s.db);
      final bars = tester
          .widgetList<DashProgressBar>(find.byType(DashProgressBar))
          .where((b) => b.semanticLabel == 'Revenue share for Zamalek');
      expect(bars.single.value, 2);
    });

    testWidgets('OVW-HOME-078 phone: compact revenue, tap for the full', (
      tester,
    ) async {
      final h = await pumpHome(tester, size: DashSize.phone);
      final r = _row(h, SeedIds.newCairo);
      final fmt = h.container.read(formatProvider);
      expect(homeText(fmt.fmtMoneyCompact(r.totalRevenue)), findsOneWidget);
      await h.tap(find.bySemanticsLabel(fmt.fmtMoney(r.totalRevenue)));
      expect(find.text(fmt.fmtMoney(r.totalRevenue)), findsOneWidget);
      await h.shot('home/branch-revenue-popover');
    });
  });

  group('margin watch', () {
    testWidgets('OVW-HOME-080/084/086/087/089/090 the headline and the lists', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      final w = marginWatch(
        branchId: nilBranchId,
        orders: orders(h, _sabah),
        prevOrders: const [],
        from: DateTime.parse(_from),
        to: DateTime.parse(_to),
      );
      final fmt = h.container.read(formatProvider);
      final t = h.container.read(tProvider);
      expect(homeText('Margin watch'), findsOneWidget);
      expect(homeText(fmt.fmtMoney(w.totals.marginKnown)), findsOneWidget);
      expect(
        homeText(fmt.fmtPercent(w.totals.marginPct! / 100)),
        findsOneWidget,
      );
      expect(homeText('${w.openSignals} open signals'), findsOneWidget);
      expect(
        homeText('${w.rowsCostUnknown} items missing cost'),
        findsOneWidget,
      );
      expect(homeText('Top earners'), findsOneWidget);
      expect(homeText('Needs attention'), findsOneWidget);
      for (final r in [...w.top, ...w.bottom]) {
        expect(homeText(fmt.fmtMoney(r.margin)), findsWidgets);
        final second = r.flags.isNotEmpty
            ? signalReason(t, fmt, r.flags.first)
            : '${r.quantitySold} sold · ${fmt.fmtPercent(r.marginPct! / 100)}';
        expect(homeText(second), findsWidgets, reason: r.itemName);
        final size = r.sizeLabel == 'one_size' ? '' : ' · ${r.sizeLabel}';
        expect(
          homeText('${r.itemName}$size', findRichText: true),
          findsWidgets,
        );
      }
      // 30 days back from the seed start: no previous margin, no change.
      expect(find.bySemanticsLabel(RegExp('vs previous period')), findsNothing);
    });

    testWidgets('OVW-HOME-085 the change vs the previous period', (
      tester,
    ) async {
      final h = await pumpHome(tester, path: '/?preset=7d');
      final w = marginWatch(
        branchId: nilBranchId,
        orders: orders(h, _sabah, from: '2026-10-01T21:00:00.000Z'),
        prevOrders: ordersIn(
          h.db!,
          _sabah,
          from: DateTime.parse('2026-09-24T21:00:00.001Z'),
          to: DateTime.parse('2026-10-01T21:00:00.000Z'),
        ),
        from: DateTime.parse('2026-10-01T21:00:00.000Z'),
        to: DateTime.parse(_to),
      );
      final t = w.totals;
      final delta = (t.marginKnown - t.prevMarginKnown) / t.prevMarginKnown;
      final fmt = h.container.read(formatProvider);
      expect(
        find.bySemanticsLabel(
          '${fmt.fmtPercent(delta.abs())} vs previous period',
        ),
        findsOneWidget,
      );
    });

    testWidgets('OVW-HOME-081/082 error: Retry spins while it asks', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _watch, boom());
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText("Couldn't load margin watch"), findsOneWidget);
      final gate = s.server.hold('GET', _watch);
      await h.tap(
        find.descendant(
          of: find.ancestor(
            of: homeText("Couldn't load margin watch"),
            matching: find.byType(DashErrorState),
          ),
          matching: homeText('Retry'),
        ),
      );
      final state = tester.widget<DashErrorState>(
        find.ancestor(
          of: homeText("Couldn't load margin watch"),
          matching: find.byType(DashErrorState),
        ),
      );
      expect(state.retrying, isTrue);
      gate.release();
      await h.settle();
      expect(homeText("Couldn't load margin watch"), findsNothing);
      expect(homeText('Top earners'), findsOneWidget);
    });

    testWidgets('OVW-HOME-083 empty: the sentence', (tester) async {
      final s = homeServer();
      s.db['orders'].clear();
      await pumpHome(tester, server: s.server, db: s.db);
      expect(
        homeText('Margins appear here once items sell in this period'),
        findsOneWidget,
      );
    });

    testWidgets('OVW-HOME-088 an empty list: "No results found"', (
      tester,
    ) async {
      final s = homeServer();
      s.server.on(
        'GET',
        _watch,
        (req) => MockResponse.ok(
          MarginWatch(
            branchId: nilBranchId,
            targetPct: 60,
            openSignals: 0,
            rowsCostUnknown: 0,
            totals: const LedgerTotals(
              revenue: 50000,
              costKnown: 20000,
              marginKnown: 30000,
              marginPct: 60,
              revenueCostUnknown: 0,
              prevRevenue: 0,
              prevMarginKnown: 0,
              belowTargetGap: 0,
            ),
            top: const [
              MarginLedgerRow(
                menuItemId: 'x',
                sizeLabel: 'one_size',
                itemName: 'Cortado',
                onMenu: true,
                quantitySold: 0,
                revenue: 50000,
                cost: 20000,
                margin: 30000,
                prevQuantity: 0,
                flags: [],
              ),
            ],
            bottom: const [],
          ),
        ),
      );
      await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText('No results found'), findsOneWidget);
      expect(homeText('Cortado', findRichText: true), findsOneWidget);
      expect(homeHas('open signal'), findsNothing);
    });

    testWidgets('OVW-HOME-092 Menu profitability opens the ledger', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      h.allowUnmatched = true;
      await h.tapText('Menu profitability');
      expect(h.location.path, '/reports/operations');
    });

    testWidgets('OVW-HOME-093 only a resync refreshes it', (tester) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
      final before = h.server.callsTo(_watch).length;
      h.realtime.current!.emit('till.opened', data: '{}');
      await h.settle();
      expect(h.server.callsTo(_watch).length, before);
      h.realtime.current!.emit('resync');
      await h.settle();
      expect(h.server.callsTo(_watch).length, before + 1);
    });

    testWidgets('OVW-HOME-091 every signal reads in plain words', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      final t = h.container.read(tProvider);
      final fmt = h.container.read(formatProvider);
      String r(String kind, Map<String, Object?> p) =>
          signalReason(t, fmt, Signal(kind: kind, link: '', params: p));
      expect(
        r('below_cost', {'margin': -1250}),
        'Sells below cost — margin −EGP 12.50',
      );
      expect(
        r('below_target', {'margin_pct': 52.34, 'target_pct': 60}),
        'Margin 52.3% is under the 60% target',
      );
      expect(
        r('below_target', {
          'margin_pct': 52,
          'target_pct': 60,
          'adaptive_bar': 2.5,
        }),
        'Margin 52% is under the 60% target (bar raised 2.5 pts — these are often dismissed)',
      );
      expect(
        r('cost_spike', {'ingredient': 'Milk', 'pct': 12.25}),
        'Milk cost moved 12.3% this period',
      );
      expect(
        r('price_candidate', {'suggested_price': 9500}),
        'Top seller under target — suggested price EGP 95.00',
      );
      expect(
        r('price_candidate', {
          'caution': true,
          'last_margin_per_day_delta': -3000,
        }),
        startsWith(
          'Still under target, but the last price change cost EGP 30.00/day',
        ),
      );
      expect(
        r('price_candidate', {
          'suggested_price': 9500,
          'elasticity': -1.2,
          'expected_margin_per_day_delta': -50,
        }),
        contains('EGP 95.00 is the best measured price (≈+EGP 0.00/day'),
      );
      expect(r('removal_candidate', {}), 'No sales this period');
      expect(r('recipe_incomplete', {}), 'Recipe incomplete — cost unknown');
      expect(r('mystery', {}), 'mystery');
    });
  });

  group('delivery', () {
    testWidgets('OVW-HOME-094/095/098/100/101 totals and channel cards', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      final d = deliverySalesReport(
        deliveryOrdersIn(
          h.db!,
          _sabah,
          from: DateTime.parse(_from),
          to: DateTime.parse(_to),
        ),
      );
      expect(homeText('Delivery'), findsOneWidget);
      expect(homeText('By channel'), findsOneWidget);
      expect(kpi(tester, 'Delivery revenue').value, d.totalRevenue);
      expect(kpi(tester, 'Delivered orders').value, d.totalOrders);
      expect(
        tester
            .widgetList<DashStatCard>(
              find.byWidgetPredicate(
                (w) => w is DashStatCard && w.label == 'Avg ticket',
              ),
            )
            .last
            .value,
        d.avgOrderValue,
      );
      expect(kpi(tester, 'Delivery fees').value, 0);
      expect(homeText('In-mall delivery'), findsOneWidget);
      expect(homeText('Outside delivery'), findsOneWidget);
      // The other channels show their raw codes (the web's quirk).
      expect(homeText('umbrella'), findsOneWidget);
      expect(homeText('pickup'), findsOneWidget);
      expect(homeText('100%'), findsOneWidget);
      expect(homeText('0%'), findsNWidgets(3));
      expect(find.bySemanticsLabel('Revenue share'), findsNWidgets(4));
      final cancelled = d.channels[1].cancelledOrders;
      if (cancelled > 0) {
        expect(homeText('\u2066$cancelled\u2069 cancelled'), findsOneWidget);
      }
    });

    testWidgets('OVW-HOME-101 a cancelled count shows a warning pill', (
      tester,
    ) async {
      final s = homeServer();
      final o = s.db['orders'].rows.lastWhere(
        (o) => o['order_type'] == 'delivery' && o['status'] == 'completed',
      );
      o['status'] = 'voided';
      await pumpHome(tester, server: s.server, db: s.db);
      final pill = tester.widget<DashStatusPill>(
        find.byWidgetPredicate(
          (w) => w is DashStatusPill && w.label.endsWith('cancelled'),
        ),
      );
      expect(pill.tone, DashTone.warning);
    });

    testWidgets('OVW-HOME-096 loading: skeleton cards', (tester) async {
      final s = homeServer();
      final gate = s.server.hold('GET', _delivery);
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Delivery revenue').loading, isTrue);
      expect(inHome(find.byType(HomeChannelSkeleton)), findsNWidgets(2));
      expect(homeText('Outside delivery'), findsNothing);
      gate.release();
      await h.settle();
      expect(homeText('Outside delivery'), findsOneWidget);
    });

    testWidgets('OVW-HOME-097 error replaces the section body', (tester) async {
      final s = homeServer();
      s.server.fail('GET', _delivery, boom());
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText("Couldn't load delivery sales"), findsOneWidget);
      expect(homeText('Delivery revenue'), findsNothing);
      await h.tap(
        find.descendant(
          of: find.ancestor(
            of: homeText("Couldn't load delivery sales"),
            matching: find.byType(DashErrorState),
          ),
          matching: homeText('Retry'),
        ),
      );
      expect(homeText('Delivery revenue'), findsOneWidget);
    });

    testWidgets('OVW-HOME-102 no channels: the totals only', (tester) async {
      final s = homeServer();
      s.server.on(
        'GET',
        _delivery,
        (req) => MockResponse.ok(
          const DeliverySalesReport(
            avgOrderValue: 0,
            cancelledOrders: 0,
            channels: <DeliveryChannelSales>[],
            totalDeliveryFees: 0,
            totalOrders: 0,
            totalRevenue: 0,
          ),
        ),
      );
      await pumpHome(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Delivery revenue').value, 0);
      expect(find.bySemanticsLabel('Revenue share'), findsNothing);
    });

    testWidgets('OVW-HOME-104 till events refetch it, delivery events not', (
      tester,
    ) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
      final before = h.server.callsTo(_delivery).length;
      h.realtime.current!.emit('delivery.created', data: '{}');
      await h.settle();
      expect(h.server.callsTo(_delivery).length, before);
      h.realtime.current!.emit('till.closed', data: '{}');
      await h.settle();
      expect(h.server.callsTo(_delivery).length, before + 1);
    });
  });

  group('cross-cutting', () {
    testWidgets('OVW-HOME-106 all branches: no live stream', (tester) async {
      final h = await pumpHome(tester);
      expect(h.realtime.connections, isEmpty);
    });

    testWidgets('OVW-HOME-107 refused everywhere: zeros and error words', (
      tester,
    ) async {
      final s = homeServer();
      for (final t in [_sales, _series, _cmp, _delivery, _watch]) {
        s.server.fail(
          'GET',
          t,
          MockResponse.denied('orders.read'),
          times: null,
        );
      }
      await pumpHome(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Revenue').value, 0);
      for (final words in [
        "Couldn't load the revenue trend",
        "Couldn't load the payment mix",
        "Couldn't load branch performance",
        "Couldn't load margin watch",
        "Couldn't load delivery sales",
      ]) {
        expect(homeText(words), findsOneWidget, reason: words);
      }
    });

    testWidgets('OVW-HOME-109 sections fade in, then settle', (tester) async {
      final h = await pumpHome(tester, reducedMotion: false);
      await tester.pump(const Duration(seconds: 2));
      await h.settle();
      final fades = tester.widgetList<FadeTransition>(
        find.descendant(
          of: find.byType(HomeReveal),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fades, isNotEmpty);
      expect(fades.every((f) => f.opacity.value == 1), isTrue);
    });

    for (final (lang, arrow) in [('en', 'arrow-right'), ('ar', 'arrow-left')]) {
      testWidgets('OVW-HOME-110 $lang: direction, Western digits, arrows '
          'toward the end', (tester) async {
        final h = await pumpHome(tester, locale: lang);
        final rtl = lang == 'ar';
        expect(
          Directionality.of(tester.element(find.byType(DashLineChart))),
          rtl ? TextDirection.rtl : TextDirection.ltr,
        );
        final fmt = h.container.read(formatProvider);
        final t = SalesTotals(orders(h, _sabah));
        // The figure on screen: Western digits, the currency after it in
        // Arabic, the number isolated left to right.
        final label = rtl ? 'الإيرادات' : 'Revenue';
        final shown = tester
            .widget<Text>(
              find.descendant(
                of: find.descendant(
                  of: find.byWidgetPredicate(
                    (w) => w is DashStatCard && w.label == label,
                  ),
                  matching: find.byType(DashAnimatedNumber),
                ),
                matching: find.byType(Text),
              ),
            )
            .data!;
        expect(shown, fmt.fmtMoney(t.revenue));
        expect(shown, matches(RegExp('[0-9]')));
        expect(shown, isNot(matches(RegExp('[٠-٩]'))));
        if (rtl) {
          expect(shown, startsWith('\u2066'));
          expect(shown, endsWith('ج.م'));
          expect(homeText('اتجاه الإيرادات'), findsOneWidget);
        }
        // Arrows point toward the end of the line.
        final cta = tester.widget<DashButton>(
          find.descendant(
            of: find.byType(HomeKeepBuildingCard),
            matching: find.byType(DashButton),
          ),
        );
        expect(cta.trailingIcon, arrow);
        final link = find.ancestor(
          of: homeText(rtl ? 'ربحية القائمة' : 'Menu profitability'),
          matching: find.byType(HomeLink),
        );
        expect(
          tester
              .widget<DashIcon>(
                find.descendant(of: link, matching: find.byType(DashIcon)),
              )
              .name,
          arrow,
        );
      });
    }

    testWidgets('OVW-HOME-112 switching language asks nothing again', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      final before = h.server.calls.where((c) => !c.stream).length;
      await h.container.read(localeProvider.notifier).set('ar');
      await h.settle();
      expect(homeText('اتجاه الإيرادات'), findsOneWidget);
      expect(homeText('Revenue trend'), findsNothing);
      final reports = h.server.calls
          .skip(before)
          .where(
            (c) =>
                c.path.startsWith('/reports') || c.path.startsWith('/insights'),
          );
      expect(reports, isEmpty);
    });
  });
}

/// One branch's comparison row over the default period.
BranchComparison _row(DashHarness h, String id) =>
    branchComparisonRow(h.db!['branches'].get(id), orders(h, [id]));
