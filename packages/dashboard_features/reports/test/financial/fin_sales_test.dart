// Financial's Revenue and Channel tabs and the Channel export
// (REP-FIN-054…065; REP-ALL-010…014, 020, 026, 027).
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/financial/fin_charts.dart';
import 'package:dashboard_reports/src/financial/fin_data.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

FinChart chart(WidgetTester t, String key) =>
    t.widget<FinChart>(find.byKey(ValueKey(key)));

Finder card(String key) => find.byKey(ValueKey(key));

Finder inCard(String key, Finder f) =>
    find.descendant(of: card(key), matching: f);

Future<DashHarness> openRevenue(
  WidgetTester t, {
  ({MockServer server, MockDb db})? s,
  String? gran,
  String locale = 'en',
}) async {
  final h = await pumpFin(t, server: s?.server, db: s?.db, locale: locale);
  await openTab(h, h.t('reports.financial.tabs.revenue'));
  if (gran != null) {
    await pickSegment(h, 'fin-granularity', h.t('analytics.granularity.$gran'));
  }
  return h;
}

List<String> lineLabels(List<FinTipLine> lines) => [
  for (final l in lines) l.label,
];

void main() {
  group('revenue', () {
    testWidgets('REP-FIN-054 the granularity control: Peak Hours, Peak Days, '
        'Daily (picked), Monthly', (t) async {
      final h = await openRevenue(t);
      final c = t.widget<DashSegmentedControl<String>>(
        find.byKey(const ValueKey('fin-granularity')),
      );
      expect(
        [for (final o in c.options) o.label],
        ['Peak Hours', 'Peak Days', 'Daily', 'Monthly'],
      );
      expect(c.value, 'daily');
      expect(callsTo(h, seriesRoute).single.query['granularity'], ['daily']);
    });

    testWidgets('REP-FIN-055 Daily: an area "Revenue Over Time" of each '
        'day\'s revenue, labelled "8 Oct", compact money ticks', (t) async {
      final h = await openRevenue(t);
      final s = h.container.read(currentScopeProvider);
      final points = h.container
          .read(finSeriesProvider(s.finSeries('daily')))
          .requireValue;
      final f = h.container.read(formatProvider);
      final c = chart(t, 'fin-revenue-chart');
      expect(c.area, isTrue);
      expect(c.labels, [
        for (final p in points) f.fmtPeriodNamed(p.period, 'daily'),
      ]);
      expect(c.labels.last, matches(RegExp(r'^\d{1,2} [A-Z][a-z]+$')));
      expect(c.values, [for (final p in points) p.revenue.toDouble()]);
      expect(c.formatY(120000), 'EGP 1.2K');
      expect(
        inCard('fin-revenue-card', find.text('Revenue Over Time')),
        findsOneWidget,
      );
      final call = callsTo(h, seriesRoute).single;
      expect(call.path, '/reports/branches/$allBranchesId/sales/timeseries');
      expect(call.query.keys.toSet(), {'from', 'to', 'granularity'});
    });

    testWidgets('REP-FIN-056 Monthly: bars per month ("Oct 2026")', (t) async {
      final h = await openRevenue(t, gran: 'monthly');
      expect(callsTo(h, seriesRoute).last.query['granularity'], ['monthly']);
      final c = chart(t, 'fin-revenue-chart');
      expect(c.area, isFalse);
      expect(c.labels, contains('Oct 2026'));
      expect(
        inCard('fin-revenue-card', find.text('Revenue Over Time')),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-057 Peak hours: the average revenue a day per hour, '
        '12-hour labels, every 3rd shown, "Revenue by Hour"', (t) async {
      final h = await openRevenue(t, gran: 'peak_hours');
      final call = callsTo(h, peakHoursRoute).single;
      expect(call.query.keys.toSet(), {'from', 'to'});
      final s = h.container.read(currentScopeProvider);
      final hours = h.container
          .read(finPeakHoursProvider(s.finSales))
          .requireValue;
      final c = chart(t, 'fin-revenue-chart');
      expect(c.labels.take(3), ['12:00 AM', '01:00 AM', '02:00 AM']);
      expect(c.values, [for (final p in hours) p.avgRevenuePerDay.toDouble()]);
      expect(c.every, 3);
      expect(c.area, isFalse);
      expect(
        inCard('fin-revenue-card', find.text('Revenue by Hour')),
        findsOneWidget,
      );
      expect(callsTo(h, seriesRoute), hasLength(1), reason: 'daily, earlier');
    });

    testWidgets('REP-FIN-058 Peak days: Sun … Sat, "Revenue by Day of Week"', (
      t,
    ) async {
      final h = await openRevenue(t, gran: 'peak_days');
      expect(callsTo(h, peakDaysRoute), hasLength(1));
      final c = chart(t, 'fin-revenue-chart');
      expect(c.labels, ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']);
      expect(c.every, 1);
      expect(
        inCard('fin-revenue-card', find.text('Revenue by Day of Week')),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-059 the daily tooltip: Revenue, then each paying '
        'method largest first, then Orders, Items Sold, Add-ons Sold', (
      t,
    ) async {
      final h = await openRevenue(t);
      final s = h.container.read(currentScopeProvider);
      final points = h.container
          .read(finSeriesProvider(s.finSeries('daily')))
          .requireValue;
      final f = h.container.read(formatProvider);
      final i = points.length ~/ 2;
      final p = points[i];
      final lines = chart(t, 'fin-revenue-chart').tooltip(i);
      final methods = [
        for (final e in (p.revenueByMethod! as Map).entries)
          if ((e.value as num) > 0) (e.key as String, (e.value as num).toInt()),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      expect(lineLabels(lines), [
        'Revenue',
        for (final (m, _) in methods) h.t('payments.$m'),
        'Orders',
        'Items Sold',
        'Add-ons Sold',
      ]);
      expect(lines.first.value, f.fmtMoney(p.revenue));
      expect(lines.first.strong, isTrue);
      expect(lines[1].dot, isNotNull);
      expect(lines[1].value, f.fmtMoney(methods.first.$2));
      expect(lines.last.value, f.fmtNumber(p.addons));
    });

    testWidgets('REP-FIN-060 the peak tooltip: Avg / Day, Share, Period '
        'Total, then Orders, Items Sold, Add-ons Sold', (t) async {
      final h = await openRevenue(t, gran: 'peak_hours');
      final s = h.container.read(currentScopeProvider);
      final p = h.container
          .read(finPeakHoursProvider(s.finSales))
          .requireValue[12];
      final f = h.container.read(formatProvider);
      final lines = chart(t, 'fin-revenue-chart').tooltip(12);
      expect(lineLabels(lines), [
        'Avg / Day',
        'Share',
        'Period Total',
        'Orders',
        'Items Sold',
        'Add-ons Sold',
      ]);
      expect(lines[0].value, f.fmtMoney(p.avgRevenuePerDay));
      expect(lines[1].value, f.fmtPercent(p.revenuePct / 100));
      expect(lines[2].value, f.fmtMoney(p.revenue));
      final orders = chart(t, 'fin-orders-chart').tooltip(12);
      expect(
        orders[0].value,
        f.fmtNumber(
          p.avgOrdersPerDay,
          const NumberOptions(maximumFractionDigits: 1),
        ),
      );
      expect(orders[1].value, f.fmtPercent(p.ordersPct / 100));
      expect(orders[2].value, f.fmtNumber(p.orders));
    });

    testWidgets('REP-FIN-061 Orders: titled per granularity, orders (or the '
        'daily average, 1 dp ticks) as bars', (t) async {
      final h = await openRevenue(t);
      expect(
        inCard('fin-orders-card', find.text('Orders Over Time')),
        findsOneWidget,
      );
      final daily = chart(t, 'fin-orders-chart');
      expect(daily.area, isFalse);
      expect(daily.yWidth, 36);
      expect(lineLabels(daily.tooltip(0)), ['Orders']);
      await pickSegment(h, 'fin-granularity', 'Peak Hours');
      expect(
        inCard('fin-orders-card', find.text('Orders by Hour')),
        findsOneWidget,
      );
      expect(chart(t, 'fin-orders-chart').formatY(2.5), '2.5');
      await pickSegment(h, 'fin-granularity', 'Peak Days');
      expect(
        inCard('fin-orders-card', find.text('Orders by Day of Week')),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-062 Discounts: an area over time, bars for the peak '
        'views, money in the tooltip', (t) async {
      final h = await openRevenue(t);
      expect(
        inCard('fin-discounts-card', find.text('Discounts Over Time')),
        findsOneWidget,
      );
      expect(chart(t, 'fin-discounts-chart').area, isTrue);
      expect(lineLabels(chart(t, 'fin-discounts-chart').tooltip(0)), [
        'Discounts',
      ]);
      await pickSegment(h, 'fin-granularity', 'Peak Hours');
      expect(chart(t, 'fin-discounts-chart').area, isFalse);
      expect(
        inCard('fin-discounts-card', find.text('Discounts by Hour')),
        findsOneWidget,
      );
      await pickSegment(h, 'fin-granularity', 'Peak Days');
      expect(
        inCard('fin-discounts-card', find.text('Discounts by Day of Week')),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-063 one loading state for the three cards, never '
        '"No data"', (t) async {
      final s = finServer();
      final gate = s.server.hold('GET', seriesRoute);
      final h = await openRevenue(t, s: s);
      for (final k in [
        'fin-revenue-card',
        'fin-orders-card',
        'fin-discounts-card',
      ]) {
        expect(inCard(k, find.byType(DashSkeleton)), findsOneWidget, reason: k);
        expect(inCard(k, find.text('No data for this period')), findsNothing);
      }
      gate.release();
      await h.settle();
      expect(find.byType(FinChart), findsNWidgets(3));
      await h.shot('financial/revenue-loaded');
    });

    testWidgets('REP-FIN-063 one error for the three, the web\'s '
        'ChartError: "Couldn\'t load this", no server words; Retry reads '
        'the active query again', (t) async {
      final s = finServer();
      final boom = MockResponse.error(500, 'Sales are unavailable.');
      // Twice: the press's warm-up fails, is dropped, and the tab reads again.
      s.server.fail('GET', peakDaysRoute, boom, times: 2);
      final h = await openRevenue(t, s: s, gran: 'peak_days');
      for (final k in [
        'fin-revenue-card',
        'fin-orders-card',
        'fin-discounts-card',
      ]) {
        expect(inCard(k, find.text("Couldn't load this")), findsOneWidget);
        expect(
          inCard(k, find.text(h.refusalWords(boom))),
          findsNothing,
          reason: k,
        );
      }
      final series = callsTo(h, seriesRoute).length;
      final peaks = callsTo(h, peakDaysRoute).length;
      await h.tap(inCard('fin-orders-card', find.text('Retry')));
      expect(callsTo(h, peakDaysRoute), hasLength(peaks + 1));
      expect(callsTo(h, seriesRoute), hasLength(series));
      expect(find.byType(FinChart), findsNWidgets(3));
    });

    testWidgets('REP-FIN-063 nothing in the period: "No data for this period" '
        'in each card', (t) async {
      final s = finServer();
      s.server.on('GET', seriesRoute, (req) => MockResponse.ok(<Object?>[]));
      await openRevenue(t, s: s);
      expect(pageText('No data for this period'), findsNWidgets(3));
    });

    testWidgets('REP-ALL-020 the plot reads left to right in Arabic', (
      t,
    ) async {
      await openRevenue(t, locale: 'ar');
      expect(
        Directionality.of(
          t.element(
            find
                .descendant(
                  of: find.byKey(const ValueKey('fin-revenue-chart')),
                  matching: find.byType(LayoutBuilder),
                )
                .first,
          ),
        ),
        TextDirection.ltr,
      );
    });
  });

  group('channel', () {
    Future<DashHarness> openChannel(
      WidgetTester t, {
      ({MockServer server, MockDb db})? s,
      String locale = 'en',
    }) async {
      final h = await pumpFin(t, server: s?.server, db: s?.db, locale: locale);
      await openTab(h, h.t('reports.financial.tabs.channel'));
      return h;
    }

    List<ChannelBreakdownRow> rows(DashHarness h) => h.container
        .read(
          finChannelsProvider(h.container.read(currentScopeProvider).finSales),
        )
        .requireValue;

    testWidgets('REP-FIN-064 "Revenue by Channel": a bar per channel, named; '
        '"Channel Details": Channel, Orders, Revenue, AOV', (t) async {
      final h = await openChannel(t);
      final call = callsTo(h, channelRoute).single;
      expect(call.query.keys.toSet(), {'from', 'to'});
      expect(call.headers.containsKey('X-Madar-Export'), isFalse);
      final c = chart(t, 'fin-channel-chart');
      final r = rows(h);
      expect(c.labels.toSet(), {'Dine-in', 'Takeaway', 'Delivery'});
      expect(c.values, [for (final x in r) x.revenue.toDouble()]);
      expect(c.every, 1);
      expect(lineLabels(c.tooltip(0)), ['Revenue']);
      for (final h2 in ['CHANNEL', 'ORDERS', 'REVENUE', 'AOV']) {
        expect(
          inCard('fin-channel-table-card', find.text(h2)),
          findsOneWidget,
          reason: h2,
        );
      }
      final f = h.container.read(formatProvider);
      expect(
        inCard(
          'fin-channel-table-card',
          figure(f.fmtMoney(r.first.avgOrderValue)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-064 an unknown channel shows its code', (t) async {
      final s = finServer();
      s.server.on('GET', channelRoute, (req) {
        return MockResponse.ok([
          const ChannelBreakdownRow(
            channel: 'kiosk',
            orders: 3,
            revenue: 45000,
            avgOrderValue: 15000,
          ),
        ]);
      });
      await openChannel(t, s: s);
      expect(chart(t, 'fin-channel-chart').labels, ['kiosk']);
      expect(
        inCard('fin-channel-table-card', find.text('kiosk')),
        findsOneWidget,
      );
    });

    testWidgets('REP-FIN-064 loading, error with Retry (the table with the '
        'server\'s words, the chart without), empty', (t) async {
      final s = finServer();
      final gate = s.server.hold('GET', channelRoute);
      final h = await openChannel(t, s: s);
      expect(
        inCard('fin-channel-chart-card', find.byType(DashSkeleton)),
        findsOneWidget,
      );
      expect(pageText('No data for this period'), findsNothing);
      gate.release();
      await h.settle();
      // A failure with nothing to show yet: a period never read.
      final boom = MockResponse.error(500, 'Channels are down.');
      s.server.fail('GET', channelRoute, boom);
      await h.container
          .read(scopeProvider.notifier)
          .setPreset(ScopePreset.last7Days);
      await h.settle();
      expect(
        inCard('fin-channel-chart-card', find.text("Couldn't load this")),
        findsOneWidget,
      );
      expect(
        inCard('fin-channel-table-card', find.text(h.refusalWords(boom))),
        findsOneWidget,
      );
      expect(pageText(h.refusalWords(boom)), findsOneWidget);
      await h.tap(inCard('fin-channel-chart-card', find.text('Retry')));
      expect(find.byType(FinChart), findsOneWidget);
      s.server.on('GET', channelRoute, (req) => MockResponse.ok(<Object?>[]));
      h.container.invalidate(finChannelsProvider);
      await h.settle();
      expect(pageText('No data for this period'), findsNWidgets(2));
    });

    group('export', () {
      Finder exportButton() => find.byKey(const ValueKey('fin-channel-export'));
      Future<void> menu(DashHarness h, String item) async {
        await h.tap(exportButton());
        await h.tap(find.text(item).last);
      }

      String stamp(DashHarness h) =>
          isoString(h.container.read(clockProvider)()).substring(0, 10);

      testWidgets('REP-FIN-065 / REP-ALL-011 Excel: re-read with the export '
          'header, "Channel Details" with totals, the period as meta', (
        t,
      ) async {
        final h = await openChannel(t);
        await menu(h, 'Export Excel');
        final reread = callsTo(h, channelRoute).last;
        expect(callsTo(h, channelRoute), hasLength(2));
        expect(reread.headers['X-Madar-Export'], '1');
        expect(reread.query.containsKey('limit'), isFalse);
        final r = rows(h);
        await h.expectToast('Exported ${r.length} rows');
        final sheet = h.exports.built.single.sheets.single;
        expect(sheet.name, 'Channel Details');
        expect(
          [for (final c in sheet.columns) c.header],
          ['Channel', 'Orders', 'Revenue', 'AOV'],
        );
        expect(sheet.subtitle, startsWith('Last 30 days'));
        expect(sheet.totalsRow!.first, 'TOTALS');
        expect(
          sheet.rows.first.first,
          isIn(['Dine-in', 'Takeaway', 'Delivery']),
        );
        expect(
          h.files.saved.single.filename,
          'Madar-Analytics-channel-${stamp(h)}.xlsx',
        );
      });

      testWidgets('REP-FIN-065 / REP-ALL-012 CSV: the first sheet, the count', (
        t,
      ) async {
        final h = await openChannel(t);
        await menu(h, 'Export CSV');
        await h.expectToast('Exported ${rows(h).length} rows');
        expect(
          h.files.saved.single.filename,
          'Madar-Analytics-channel-${stamp(h)}.csv',
        );
      });

      testWidgets('REP-ALL-026 only Excel spins the button', (t) async {
        final h = await openChannel(t);
        final hold = Completer<void>();
        h.exports.hold = hold.future;
        await menu(h, 'Export Excel');
        expect(t.widget<DashExportButton>(exportButton()).loading, isTrue);
        hold.complete();
        await h.settle();
        expect(t.widget<DashExportButton>(exportButton()).loading, isFalse);
        await h.flushTimers();
      });

      testWidgets('REP-ALL-027 / 014 a throttled re-read toasts the server\'s '
          'words and writes nothing', (t) async {
        final s = finServer();
        final h = await openChannel(t, s: s);
        final limited = MockResponse.error(
          429,
          'Too many exports just now. Try again in a minute.',
          code: 'EXPORT_RATE_LIMITED',
        );
        s.server.fail('GET', channelRoute, limited);
        await menu(h, 'Export Excel');
        await h.expectToast(h.refusalWords(limited));
        expect(h.files.saved, isEmpty);
      });

      testWidgets('REP-ALL-013 nothing in the period: "Nothing to export"', (
        t,
      ) async {
        final s = finServer();
        s.server.on('GET', channelRoute, (req) => MockResponse.ok(<Object?>[]));
        final h = await openChannel(t, s: s);
        await menu(h, 'Export Excel');
        await h.expectToast('Nothing to export');
        expect(h.files.saved, isEmpty);
      });
    });
  });
}
