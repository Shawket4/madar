// The home's frame, driven through the real app shell: the scope it opens
// with, the prefetch, the retry policy, the responsive layout, motion,
// keyboard and theme (inventory rows OVW-HOME-007, -009, -017, -022, -031,
// -041, -044, -056, -063, -064, -072, -079, -099, -103, -105, -108, -111,
// -113).
import 'dart:convert';
import 'dart:math' as math;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_overview/src/home/delivery.dart';
import 'package:dashboard_overview/src/home/home_charts.dart';
import 'package:dashboard_overview/src/home/home_kpis.dart';
import 'package:dashboard_overview/src/home/home_page.dart';
import 'package:dashboard_overview/src/home/home_parts.dart';
import 'package:dashboard_overview/src/home/home_providers.dart';
import 'package:dashboard_overview/src/home/keep_building.dart';
import 'package:dashboard_overview/src/mock/home_figures.dart';
import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _sales = '/reports/branches/{branchId}/sales';
const _series = '/reports/branches/{branchId}/sales/timeseries';
const _cmp = '/reports/orgs/{orgId}/comparison';
const _delivery = '/reports/branches/{branchId}/delivery-sales';
const _watch = '/insights/branches/{branchId}/margin-watch';

const _from = '2026-09-08T21:00:00.000Z';
const _to = '2026-10-08T20:59:59.999Z';

/// The KPI card labelled [label] in the home's top strip.
Finder kpiCard(String label) => find.descendant(
  of: find.byType(HomeKpiStrip),
  matching: find.byWidgetPredicate(
    (w) => w is DashStatCard && w.label == label,
  ),
);

/// The scope line's part reading [text].
Finder scopePart(String text) => find.descendant(
  of: find.byType(HomeScopeLine),
  matching: find.text(HomeScopeLine.keep(text)),
);

/// The figure a stat card shows right now (mid count-up included).
String shownFigure(WidgetTester tester, Finder card) => tester
    .widget<Text>(
      find.descendant(
        of: find.descendant(
          of: card,
          matching: find.byType(DashAnimatedNumber),
        ),
        matching: find.byType(Text),
      ),
    )
    .data!;

/// Resizes the window after the app is up (a width between the harness's
/// phone, tablet and desktop).
Future<void> resize(DashHarness h, double width, [double height = 900]) async {
  h.tester.view.physicalSize = Size(width, height) * DashSize.pixelRatio;
  await h.settle();
}

/// How many distinct rows [cards] sit on.
int rowsOf(WidgetTester tester, Finder cards) => {
  for (final e in cards.evaluate())
    tester.getTopLeft(find.byWidget(e.widget)).dy.round(),
}.length;

/// Whether keyboard focus is on [target] (or inside it).
bool focusedOn(WidgetTester tester, Finder target) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  final el = tester.element(target);
  if (ctx == el) return true;
  var inside = false;
  ctx.visitAncestorElements((a) => !(inside = a == el));
  if (inside) return true;
  el.visitAncestorElements((a) => !(inside = a == ctx));
  return inside;
}

/// Presses Tab until focus lands on [target]; false after [max] presses.
Future<bool> tabTo(WidgetTester tester, Finder target, {int max = 120}) async {
  for (var i = 0; i < max; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (focusedOn(tester, target)) return true;
  }
  return false;
}

void main() {
  group('scope the home opens with', () {
    testWidgets('OVW-HOME-007 a bare entry restores the last branch and '
        'period', (tester) async {
      final h = await pumpHome(
        tester,
        prefs: {
          ScopePrefKeys.branch: jsonEncode({
            'org': SeedIds.sabahOrg,
            'branch': SeedIds.maadi,
          }),
          ScopePrefKeys.preset: '7d',
        },
      );
      final q = h.server.callsTo(_sales).last;
      expect(q.path, '/reports/branches/${SeedIds.maadi}/sales');
      expect(q.query['from'], ['2026-10-01T21:00:00.000Z']);
      expect(scopePart('Maadi'), findsOneWidget);
      expect(scopePart('Last 7 days'), findsOneWidget);
    });

    testWidgets('OVW-HOME-007 a stored custom period opens as the last 30 '
        'days', (tester) async {
      final h = await pumpHome(tester, prefs: {ScopePrefKeys.preset: 'custom'});
      expect(h.server.callsTo(_cmp).last.query['from'], [_from]);
      expect(scopePart('Last 30 days'), findsOneWidget);
    });

    testWidgets('OVW-HOME-017 a stored branch that is gone heals to all '
        'branches', (tester) async {
      final h = await pumpHome(
        tester,
        prefs: {
          ScopePrefKeys.branch: jsonEncode({
            'org': SeedIds.sabahOrg,
            'branch': '11111111-2222-3333-4444-555555555555',
          }),
        },
      );
      expect(h.container.read(currentScopeProvider).branchId, isNull);
      expect(scopePart('All branches'), findsOneWidget);
      expect(inHome(find.byType(HomeOpenTillsCard)), findsNothing);
    });

    testWidgets('OVW-HOME-017 a deep link to a branch that is gone heals to '
        'all branches', (tester) async {
      final h = await pumpHome(
        tester,
        path: '/?branchId=11111111-2222-3333-4444-555555555555',
      );
      await h.settle();
      expect(h.container.read(currentScopeProvider).branchId, isNull);
      expect(inHome(find.byType(HomeOpenTillsCard)), findsNothing);
    });

    testWidgets('OVW-HOME-009 pointing at Dashboard warms the home; opening '
        'it asks nothing twice', (tester) async {
      final h = await pumpHome(tester, path: '/tills');
      h.allowUnmatched = true; // the tills page is another area's
      expect(h.server.callsTo(_series), isEmpty);
      final row = find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Dashboard'),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(row));
      await h.settle();
      expect(h.server.callsTo(_series), hasLength(1), reason: 'warmed');
      expect(h.server.callsTo(_cmp), hasLength(1), reason: 'warmed');
      expect(h.server.callsTo(_series).single.query['granularity'], ['daily']);
      await h.tap(row);
      expect(h.location.path, '/');
      expect(find.byType(HomePage), findsOneWidget);
      expect(h.server.callsTo(_series), hasLength(1), reason: 'from cache');
      expect(h.server.callsTo(_cmp), hasLength(1), reason: 'from cache');
    });
  });

  group('retries', () {
    testWidgets('OVW-HOME-105 the app\'s policy: a refusal once, a failure '
        'twice, a 429 four times', (tester) async {
      Future<int> asks(MockResponse answer, {int? times}) async {
        final s = homeServer();
        s.server.fail('GET', _series, answer, times: times);
        final c = ProviderContainer(
          retry: webRetry,
          overrides: [
            transportProvider.overrideWithValue(s.server),
            orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
          ],
        );
        const key = (
          id: allBranchesId,
          from: _from,
          to: _to,
          granularity: 'daily',
        );
        final sub = c.listen(homeTimeseriesProvider(key), (_, _) {});
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        sub.close();
        c.dispose();
        return s.server.callsTo(_series).length;
      }

      expect(await asks(MockResponse.denied('orders.read'), times: null), 1);
      expect(await asks(MockResponse.error(500, 'boom'), times: null), 2);
      expect(await asks(MockResponse.error(500, 'boom')), 2);
      expect(await asks(MockResponse.error(429, 'Slow down'), times: null), 4);
    });

    testWidgets('OVW-HOME-105 a card\'s Retry asks only its own read', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _series, MockResponse.error(500, 'boom'));
      final h = await pumpHome(tester, server: s.server, db: s.db);
      int count(String t) => h.server.callsTo(t).length;
      final others = {
        for (final t in [_cmp, _delivery, _watch]) t: count(t),
      };
      await h.tap(
        find.descendant(
          of: find.byType(HomeRevenueTrendCard),
          matching: find.text('Retry'),
        ),
      );
      expect(inHome(find.byType(DashLineChart)), findsOneWidget);
      for (final e in others.entries) {
        expect(count(e.key), e.value, reason: e.key);
      }
    });
  });

  group('layout', () {
    testWidgets('OVW-HOME-022 the scope line: dots between parts, wrapping '
        'between them on a phone', (tester) async {
      final s = homeServer();
      s.db['branches'].update(SeedIds.zamalek, {
        'name': 'Zamalek — 26th of July Street',
      });
      await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        size: DashSize.phone,
        path: '/?branchId=${SeedIds.zamalek}',
      );
      final line = find.byType(HomeScopeLine);
      expect(
        find.descendant(of: line, matching: find.text('·')),
        findsNWidgets(2),
      );
      final branch = tester.getTopLeft(
        scopePart('Zamalek — 26th of July Street'),
      );
      final zone = tester.getTopLeft(scopePart('Cairo time'));
      expect(zone.dy, greaterThan(branch.dy), reason: 'wrapped');
    });

    for (final (lang, rtl) in [('en', false), ('ar', true)]) {
      testWidgets('OVW-HOME-031 keep building: one row on a phone, the X at '
          'the top end ($lang)', (tester) async {
        await pumpHome(tester, size: DashSize.phone, locale: lang);
        final card = find.byType(HomeKeepBuildingCard);
        final box = tester.getRect(card);
        final cta = tester.getRect(
          find.descendant(of: card, matching: find.byType(DashButton)),
        );
        final x = tester.getRect(
          find.descendant(of: card, matching: find.byType(DashIconButton)),
        );
        expect(cta.center.dy, closeTo(box.center.dy, box.height / 4));
        expect(x.top, closeTo(box.top, 1));
        if (rtl) {
          expect(x.left, closeTo(box.left, 1));
          expect(cta.left, lessThan(box.center.dx));
        } else {
          expect(x.right, closeTo(box.right, 1));
          expect(cta.right, greaterThan(box.center.dx));
        }
      });
    }

    testWidgets('OVW-HOME-044 KPI columns: 2 on a phone, 3 from 640, 5 in a '
        'row on a desktop', (tester) async {
      final h = await pumpHome(tester, size: DashSize.phone);
      final cards = find.descendant(
        of: find.byType(HomeKpiStrip),
        matching: find.byType(DashStatCard),
      );
      expect(cards, findsNWidgets(5));
      expect(rowsOf(tester, cards), 3);
      await resize(h, 700);
      expect(rowsOf(tester, cards), 2);
      // The kit counts columns by the window, as the web's media queries:
      // a 1024 window is lg, so the five sit in one row.
      await resize(h, 1024, 768);
      expect(rowsOf(tester, cards), 1);
      await resize(h, 1440);
      expect(rowsOf(tester, cards), 1);
    });

    testWidgets('OVW-HOME-044 four cards (no tips): 2 columns until 1024', (
      tester,
    ) async {
      final s = homeServer();
      for (final o in s.db['orders'].rows) {
        o['tip_amount'] = null;
      }
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        size: DashSize.phone,
      );
      final cards = find.descendant(
        of: find.byType(HomeKpiStrip),
        matching: find.byType(DashStatCard),
      );
      expect(cards, findsNWidgets(4));
      expect(rowsOf(tester, cards), 2);
      await resize(h, 700);
      expect(rowsOf(tester, cards), 2);
      await resize(h, 1440);
      expect(rowsOf(tester, cards), 1);
    });

    testWidgets('OVW-HOME-056 an open till\'s pills wrap under its name on a '
        'phone', (tester) async {
      final s = homeServer();
      final open = s.db['tills'].rows.firstWhere(
        (t) => t['branch_id'] == SeedIds.maadi && t['status'] == 'open',
      );
      open['teller_name'] = 'Mohamed Abdel-Rahman El-Gendy';
      open['verification'] = 'unverified';
      open['opened_while_another_open'] = true;
      await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        size: DashSize.phone,
        path: '/?branchId=${SeedIds.maadi}',
      );
      final name = tester.getRect(textHas('Mohamed Abdel-Rahman El-Gendy'));
      final pill = tester.getRect(
        homeText('Opened while another till was open'),
      );
      expect(pill.top, greaterThan(name.bottom - 1));
    });

    testWidgets('OVW-HOME-103 channel cards: one column on a phone, two from '
        '640', (tester) async {
      final h = await pumpHome(tester, size: DashSize.phone);
      final bars = find.descendant(
        of: find.byType(HomeDeliveryKpis),
        matching: find.byWidgetPredicate(
          (w) => w is DashProgressBar && w.semanticLabel == 'Revenue share',
        ),
      );
      expect(bars, findsNWidgets(4));
      expect(rowsOf(tester, bars), 4);
      await resize(h, 700);
      expect(rowsOf(tester, bars), 2);
      await resize(h, 1440);
      expect(rowsOf(tester, bars), 2);
    });

    for (final (size, gutter) in [
      (DashSize.phone, 16.0),
      (DashSize.desktop, 32.0),
    ]) {
      testWidgets('OVW-HOME-108 the page frame at ${size.name}: gutter '
          '$gutter, 24 between sections', (tester) async {
        await pumpHome(tester, size: size);
        final page = tester.getRect(find.byType(HomePage));
        final title = tester.getRect(homeText('Welcome back, Nour El-Sayed'));
        expect(title.left - page.left, gutter);
        final kb = tester.getRect(find.byType(HomeKeepBuildingCard));
        final strip = tester.getRect(find.byType(HomeKpiStrip));
        expect(strip.top - kb.bottom, Space.xl);
      });
    }

    testWidgets('OVW-HOME-108 a wide window: 24 gutter from 640, content '
        'capped at 1600 from the start', (tester) async {
      final h = await pumpHome(tester, size: DashSize.phone);
      await resize(h, 700);
      var page = tester.getRect(find.byType(HomePage));
      expect(
        tester.getRect(find.byType(HomeKpiStrip)).left - page.left,
        Space.xl,
      );
      await resize(h, 2600, 1200);
      page = tester.getRect(find.byType(HomePage));
      final strip = tester.getRect(find.byType(HomeKpiStrip));
      expect(strip.width, 1600);
      expect(strip.left - page.left, Space.xxl);
    });
  });

  group('motion', () {
    testWidgets('OVW-HOME-041 figures count up once, then jump', (
      tester,
    ) async {
      final s = homeServer();
      final gate = s.server.hold('GET', _sales);
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        reducedMotion: false,
        path: '/?branchId=${SeedIds.maadi}',
      );
      final fmt = h.container.read(formatProvider);
      int revenue() => SalesTotals(
        ordersIn(
          s.db,
          [SeedIds.maadi],
          from: DateTime.parse(_from),
          to: DateTime.parse(_to),
        ),
      ).revenue;
      final card = kpiCard('Revenue');
      gate.release();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(shownFigure(tester, card), isNot(fmt.fmtMoney(revenue())));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(shownFigure(tester, card), fmt.fmtMoney(revenue()));
      // A later change shows the new figure at once.
      final o = s.db['orders'].rows.lastWhere(
        (o) => o['branch_id'] == SeedIds.maadi && o['status'] == 'completed',
      );
      o['total_amount'] = (o['total_amount']! as int) + 100000;
      h.realtime.current!.emit('till.closed', data: '{}');
      await h.settle(rounds: 1);
      expect(shownFigure(tester, card), fmt.fmtMoney(revenue()));
      await h.settle();
    });

    testWidgets('OVW-HOME-041 reduced motion: the figure at once', (
      tester,
    ) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
      final t = SalesTotals(
        ordersIn(
          h.db!,
          [SeedIds.maadi],
          from: DateTime.parse(_from),
          to: DateTime.parse(_to),
        ),
      );
      expect(
        shownFigure(tester, kpiCard('Revenue')),
        h.container.read(formatProvider).fmtMoney(t.revenue),
      );
    });

    testWidgets('OVW-HOME-079 branch rows stagger in 40 ms apart', (
      tester,
    ) async {
      final s = homeServer();
      final gate = s.server.hold('GET', _cmp);
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        reducedMotion: false,
      );
      gate.release();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      List<double> shown() => [
        for (final e
            in find
                .byWidgetPredicate((w) => w is HomeReveal && w.step == 40)
                .evaluate())
          tester
              .widget<FadeTransition>(
                find
                    .descendant(
                      of: find.byWidget(e.widget),
                      matching: find.byType(FadeTransition),
                    )
                    .first,
              )
              .opacity
              .value,
      ];
      final early = shown();
      expect(early, hasLength(4));
      for (var i = 1; i < early.length; i++) {
        expect(early[i], lessThan(early[i - 1]), reason: 'row ${i + 1}');
      }
      expect(early.last, 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(shown().every((v) => v == 1), isTrue);
      await h.settle();
    });

    testWidgets('OVW-HOME-079 reduced motion: rows in place at once', (
      tester,
    ) async {
      await pumpHome(tester);
      final fades = find.descendant(
        of: find.byWidgetPredicate((w) => w is HomeReveal && w.step == 40),
        matching: find.byType(FadeTransition),
      );
      expect(fades, findsWidgets);
      for (final f in tester.widgetList<FadeTransition>(fades)) {
        expect(f.opacity.value, 1);
      }
    });
  });

  group('charts', () {
    for (final (lang, rtl) in [('en', false), ('ar', true)]) {
      testWidgets(
        'OVW-HOME-063 the money axis on the ${rtl ? 'right' : 'left'} '
        '($lang)',
        (tester) async {
          await pumpHome(tester, locale: lang);
          final chart = inHome(find.byType(DashLineChart));
          final sides = {
            for (final w in tester.widgetList<SideTitleWidget>(
              find.descendant(
                of: chart,
                matching: find.byType(SideTitleWidget),
              ),
            ))
              w.meta.axisSide,
          };
          expect(sides, contains(rtl ? AxisSide.right : AxisSide.left));
          expect(sides, isNot(contains(rtl ? AxisSide.left : AxisSide.right)));
          // The oldest day: at the start of the reading direction (the kit
          // mirrors time in Arabic; see the divergence log).
          final labels = tester.widget<DashLineChart>(chart).labels;
          final oldest = tester.getCenter(
            find.descendant(of: chart, matching: find.text(labels.first)),
          );
          final mid = tester.getCenter(chart);
          expect(oldest.dx, rtl ? greaterThan(mid.dx) : lessThan(mid.dx));
        },
      );
    }

    testWidgets('OVW-HOME-064 pointing at the trend shows the day and its '
        'revenue', (tester) async {
      final h = await pumpHome(tester);
      final chart = inHome(find.byType(DashLineChart));
      final c = tester.widget<DashLineChart>(chart);
      expect(c.series.single.label, 'Revenue');
      expect(c.formatValue!(1234567), 'EGP 12,345.67');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(LineChart)));
      await h.settle();
      await h.shot('home/trend-tooltip');
    });

    testWidgets('OVW-HOME-072 pointing at a slice names it and its money', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      final fmt = h.container.read(formatProvider);
      final donut = inHome(find.byType(DashDonutChart));
      final cash = revenueByMethod(
        ordersIn(
          h.db!,
          [
            SeedIds.heliopolis,
            SeedIds.maadi,
            SeedIds.newCairo,
            SeedIds.zamalek,
          ],
          from: DateTime.parse(_from),
          to: DateTime.parse(_to),
        ),
      )['cash']!;
      final center = tester.getCenter(donut);
      const r = HomeMetrics.donut / 2 * 0.86;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        center + Offset(r * math.sin(0.2), -r * math.cos(0.2)),
      );
      await h.settle();
      expect(
        find.descendant(of: donut, matching: find.text('Cash')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: donut,
          matching: find.text(dashFigure(fmt.fmtMoney(cash))),
        ),
        findsOneWidget,
      );
      await h.shot('home/payment-slice');
    });

    testWidgets('OVW-HOME-099 a phone: compact channel revenue, tap for the '
        'full', (tester) async {
      final h = await pumpHome(tester, size: DashSize.phone);
      final fmt = h.container.read(formatProvider);
      final d = deliverySalesReport(
        deliveryOrdersIn(
          h.db!,
          [
            SeedIds.heliopolis,
            SeedIds.maadi,
            SeedIds.newCairo,
            SeedIds.zamalek,
          ],
          from: DateTime.parse(_from),
          to: DateTime.parse(_to),
        ),
      );
      final top = d.channels.reduce((a, b) => a.revenue >= b.revenue ? a : b);
      final section = find.byType(HomeDeliveryKpis);
      expect(
        find.descendant(
          of: section,
          matching: find.text(fmt.fmtMoneyCompact(top.revenue)),
        ),
        findsOneWidget,
      );
      // The strip's total and the payment mix's Talabat line read the same
      // figure (one channel took every delivery).
      final full = find.text(fmt.fmtMoney(top.revenue));
      final before = full.evaluate().length;
      await h.tap(
        find.descendant(
          of: section,
          matching: find.text(fmt.fmtMoneyCompact(top.revenue)),
        ),
      );
      expect(full, findsNWidgets(before + 1));
      await h.shot('home/channel-revenue-popover');
    });
  });

  group('keyboard', () {
    testWidgets('OVW-HOME-111 Tab walks the page in order; Enter follows a '
        'link', (tester) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
      h.allowUnmatched = true; // the profitability ledger is another area's
      final kb = find.byType(HomeKeepBuildingCard);
      final cta = find.descendant(of: kb, matching: find.byType(DashButton));
      expect(await tabTo(tester, cta), isTrue, reason: 'Keep building');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        focusedOn(
          tester,
          find.descendant(of: kb, matching: find.byType(DashIconButton)),
        ),
        isTrue,
        reason: 'Dismiss',
      );
      final viewAll = find.ancestor(
        of: homeText('View all'),
        matching: find.byType(HomeLink),
      );
      expect(await tabTo(tester, viewAll, max: 40), isTrue, reason: 'View all');
      final profit = find.ancestor(
        of: homeText('Menu profitability'),
        matching: find.byType(HomeLink),
      );
      expect(await tabTo(tester, profit, max: 40), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(h.location.path, '/reports/operations');
    });

    testWidgets('OVW-HOME-111 Escape closes a figure\'s popover', (
      tester,
    ) async {
      final h = await pumpHome(tester, size: DashSize.phone);
      final fmt = h.container.read(formatProvider);
      final rows = h.db!['branches'].rows;
      final b = rows.firstWhere((r) => r['id'] == SeedIds.newCairo);
      final revenue = SalesTotals(
        ordersIn(
          h.db!,
          [b['id']! as String],
          from: DateTime.parse(_from),
          to: DateTime.parse(_to),
        ),
      ).revenue;
      await h.tap(find.bySemanticsLabel(fmt.fmtMoney(revenue)));
      expect(find.text(fmt.fmtMoney(revenue)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(find.text(fmt.fmtMoney(revenue)), findsNothing);
    });
  });

  group('theme', () {
    testWidgets('OVW-HOME-113 switching theme recolours the charts and asks '
        'nothing again', (tester) async {
      final h = await pumpHome(tester);
      final donut = inHome(find.byType(DashDonutChart));
      Color cash() => tester.widget<DashDonutChart>(donut).slices.first.color!;
      Color line() => tester
          .widget<DashLineChart>(inHome(find.byType(DashLineChart)))
          .series
          .single
          .color!;
      final light = (cash(), line());
      expect(light.$1, tester.element(donut).madarColors.success);
      final before = h.server.calls.where((c) => !c.stream).length;
      await h.container.read(themePrefProvider.notifier).set(ThemePref.dark);
      await h.settle();
      final c = tester.element(donut).madarColors;
      expect(cash(), c.success);
      expect(cash(), isNot(light.$1));
      expect(line(), c.brand);
      expect(line(), isNot(light.$2));
      final again = h.server.calls
          .skip(before)
          .where((x) => x.path.startsWith('/reports'));
      expect(again, isEmpty);
    });
  });
}
