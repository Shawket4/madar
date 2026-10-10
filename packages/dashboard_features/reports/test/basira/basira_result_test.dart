// Basira's result rows (REP-BAS-019–025, 032 and the table of 034), driven
// through the page with the mock's real answers and scripted blocks, plus
// the pure rules behind them.
import 'package:dashboard_api/dashboard_api.dart' as wire;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/basira/basira_charts.dart';
import 'package:dashboard_reports/src/basira/basira_models.dart';
import 'package:dashboard_reports/src/basira/basira_result.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _card([int i = 0]) => inPage(find.byType(BasiraBlockCard)).at(i);

Finder _inCard(Finder f, [int i = 0]) =>
    find.descendant(of: _card(i), matching: f);

/// Asks a question whose answer is exactly [blocks].
Future<void> _answer(
  DashHarness h,
  List<Map<String, Object?>> blocks, {
  String text = 'Here it is.',
}) async {
  mockOf(h).script([
    {
      'event': 'answer',
      'response': {
        'kind': 'answer',
        'text': text,
        'results': blocks,
        'provider': 'gemini',
        'timezone': 'Africa/Cairo',
      },
    },
  ]);
  await askByTyping(h, 'Show me');
}

Map<String, Object?> _col(String key, String label, String kind) => {
  'key': key,
  'label': label,
  'kind': kind,
};

Map<String, Object?> _block({
  String viz = 'table',
  List<Map<String, Object?>>? columns,
  List<Map<String, Object?>>? rows,
  int? rowCount,
  bool truncated = false,
  String? title = 'Figures',
  Map<String, Object?>? scope,
  Map<String, Object?>? spec,
  String? from,
  String? to,
}) {
  final r =
      rows ??
      [
        {'item': 'Latte', 'revenue': 123450, 'qty': 12},
        {'item': 'Mocha', 'revenue': null, 'qty': 3},
      ];
  return {
    'title': ?title,
    'spec': spec ?? {'dataset': 'sales_items'},
    'columns':
        columns ??
        [
          _col('item', 'Item', 'label'),
          _col('revenue', 'Revenue', 'money'),
          _col('qty', 'Qty', 'count'),
        ],
    'rows': r,
    'row_count': rowCount ?? r.length,
    'truncated': truncated,
    'grain': 'categorical',
    'viz': viz,
    'scope':
        scope ??
        {'all_branches': true, 'branches': <String>[], 'label': 'All (4)'},
    'period_from': ?from,
    'period_to': ?to,
  };
}

void main() {
  group('the card', () {
    testWidgets('REP-BAS-019 a card: title, the result, and "What was '
        'queried" that opens the query', (tester) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'Top 3 products');
      expect(_inCard(find.text(ownDirection('Top products'))), findsOneWidget);
      expect(_inCard(find.byType(BasiraBarChart)), findsOneWidget);
      final toggle = _inCard(find.text('What was queried'));
      expect(toggle, findsOneWidget);
      AnimatedRotation chevron() => tester.widget<AnimatedRotation>(
        _inCard(find.byType(AnimatedRotation)),
      );
      expect(chevron().turns, 0);
      expect(_inCard(find.textContaining('sales_items')), findsNothing);
      await h.tap(toggle);
      expect(chevron().turns, 0.5);
      expect(_inCard(find.textContaining('sales_items')), findsOneWidget);
      await h.shot('basira/provenance');
      await h.tap(toggle);
      expect(_inCard(find.textContaining('sales_items')), findsNothing);
    });

    testWidgets('REP-BAS-019 a wide result scrolls inside its card, never '
        'the page', (tester) async {
      final h = await pumpBasira(tester, size: DashSize.phone);
      await askByTyping(h, 'When are we busiest?');
      final sideways = _inCard(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      expect(sideways, findsOneWidget);
      final card = tester.getRect(_card());
      expect(card.right, lessThanOrEqualTo(390));
    });

    testWidgets('REP-BAS-020 a badge for a branch nobody has; the branches '
        'when not all; none for all branches', (tester) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'Revenue at our Alexandria branch');
      expect(
        _inCard(
          find.text('No branch matched “Alexandria” — showing all branches'),
        ),
        findsOneWidget,
      );
      await askByTyping(h, 'Compare Maadi and Zamalek this month');
      expect(_inCard(find.text('Maadi, Zamalek'), 1), findsOneWidget);
      await askByTyping(h, 'Top 3 products');
      expect(_inCard(find.byType(BasiraScopeBadge), 2), findsNothing);
    });

    testWidgets('REP-BAS-020 Arabic words for the unmatched badge', (
      tester,
    ) async {
      final h = await pumpBasira(tester, locale: 'ar');
      await askByTyping(h, 'Revenue at our Alexandria branch');
      expect(
        _inCard(
          find.text(
            h.t('basira.unmatchedBranch', args: {'name': 'Alexandria'}),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-BAS-021 the query: dataset · by dims · measures · '
        'filters, then the period · scope · rows', (tester) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'Top 3 products');
      await h.tap(_inCard(find.text('What was queried')));
      expect(
        _inCard(
          find.text(
            'sales_items · by item · revenue, quantity · status=completed',
          ),
        ),
        findsOneWidget,
      );
      expect(
        _inCard(
          find.text('2026-09-01 → 2026-09-30 · All branches (4) · 3 rows'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('REP-BAS-021 a stored answer says "stored"; no period is '
        '"all time"', (tester) async {
      final h = await pumpBasira(tester);
      await h.tap(inRail(find.text('Top 5 products last month')));
      await h.tap(_inCard(find.text('What was queried')));
      expect(
        _inCard(
          find.text(
            '2026-09-01 → 2026-09-30 · All branches (4) · 5 rows · stored',
          ),
        ),
        findsOneWidget,
      );
      await h.tap(inRail(find.text('New conversation')));
      await _answer(h, [_block()]);
      await h.tap(_inCard(find.text('What was queried')));
      expect(_inCard(find.text('sales_items')), findsOneWidget);
      expect(_inCard(find.text('all time · All (4) · 2 rows')), findsOneWidget);
    });

    testWidgets('REP-BAS-021 (divergence) Arabic: the period in the org\'s '
        'days and "by" in Arabic', (tester) async {
      final h = await pumpBasira(tester, locale: 'ar');
      await askByTyping(h, 'Top 3 products');
      await h.tap(_inCard(find.text(h.t('basira.provenance'))));
      expect(
        _inCard(
          find.text(
            '${ownDirection('sales_items')} · حسب ${ownDirection('item')} · '
            '${ownDirection('revenue, quantity')} · '
            '${ownDirection('status=completed')}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        _inCard(
          find.textContaining('${ownDirection('2026-09-01 → 2026-09-30')} · '),
        ),
        findsOneWidget,
      );
      expect(_inCard(find.textContaining('· 3 صف')), findsOneWidget);
    });

    testWidgets('REP-BAS-022 a result with no rows says so, never a zero', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      await _answer(h, [_block(viz: 'kpi', rows: const [], rowCount: 0)]);
      expect(_inCard(find.text('No activity in this period')), findsOneWidget);
      expect(_inCard(find.text('EGP 0.00')), findsNothing);
    });

    testWidgets('REP-BAS-025 a truncated result says how many rows show', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'List orders for today');
      expect(_inCard(find.text('Showing the first 50 rows.')), findsOneWidget);
    });
  });

  group('the views', () {
    testWidgets('REP-BAS-023 kpi: a big figure per measure, formatted by '
        'kind', (tester) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'How much did we take today?');
      for (final label in ['Revenue', 'Orders', 'Average ticket']) {
        expect(_inCard(find.text(label)), findsOneWidget);
      }
      final row = mockOf(h)
          .turnsOf(
            mockOf(h).conversationsOf(SeedIds.owner).first['id']! as String,
          )
          .single;
      final rows =
          (((row['specs']! as List).single as Map)['snapshot']! as Map)['rows']!
              as List;
      final figures = rows.single as Map;
      final fmt = DashFormat(lang: 'en');
      expect(
        _inCard(find.text(ltr(fmt.fmtMoney(figures['revenue']! as int)))),
        findsOneWidget,
      );
      expect(
        _inCard(find.text(ltr(fmt.fmtNumber(figures['orders']! as int)))),
        findsOneWidget,
      );
    });

    testWidgets('REP-BAS-023 line/area: an area per measure, a day with no '
        'sales left as a gap, money plotted in pounds', (tester) async {
      final h = await pumpBasira(tester);
      await _answer(h, [
        _block(
          viz: 'line',
          columns: [
            _col('day', 'Day', 'date'),
            _col('revenue', 'Revenue', 'money'),
          ],
          rows: [
            {'day': '2026-10-01', 'revenue': 150000},
            {'day': '2026-10-02', 'revenue': null},
            {'day': '2026-10-03', 'revenue': 99950},
          ],
        ),
      ]);
      final chart = tester.widget<BasiraAreaChart>(
        _inCard(find.byType(BasiraAreaChart)),
      );
      expect(chart.labels, ['2026-10-01', '2026-10-02', '2026-10-03']);
      expect(chart.series.single.values, [1500.0, null, 999.5]);
      expect(chart.series.single.label, 'Revenue');
      expect(chart.series.single.format(999.5), 'EGP 999.50');
      final line = tester.widget<LineChart>(_inCard(find.byType(LineChart)));
      final spots = line.data.lineBarsData.single.spots;
      expect(spots[1], FlSpot.nullSpot);
      expect(line.data.lineBarsData.single.spots, hasLength(3));
      // No legend; a plain-number value axis 52 wide.
      expect(_inCard(find.byType(DashChartLegend)), findsNothing);
      expect(
        line.data.titlesData.leftTitles.sideTitles.reservedSize,
        basiraValueAxis,
      );
      await h.shot('basira/area');
    });

    testWidgets('REP-BAS-023 bar: at most two measures; labels tilt past '
        'six', (tester) async {
      final h = await pumpBasira(tester);
      await _answer(h, [
        _block(
          viz: 'bar',
          columns: [
            _col('item', 'Item', 'label'),
            _col('revenue', 'Revenue', 'money'),
            _col('qty', 'Qty', 'count'),
            _col('avg', 'Average', 'number'),
          ],
          rows: [
            for (var i = 0; i < 7; i++)
              {'item': 'Item $i', 'revenue': 1000 * i, 'qty': i, 'avg': 1.5},
          ],
        ),
      ]);
      final chart = tester.widget<BasiraBarChart>(
        _inCard(find.byType(BasiraBarChart)),
      );
      expect(chart.horizontal, isFalse);
      expect([for (final s in chart.series) s.label], ['Revenue', 'Qty']);
      final tilted = tester
          .widgetList<SideTitleWidget>(_inCard(find.byType(SideTitleWidget)))
          .where((w) => w.angle != 0);
      expect(tilted, hasLength(7));
      await h.shot('basira/bar-tilted');
    });

    testWidgets('REP-BAS-023 bar: six or fewer labels stand straight', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      await _answer(h, [_block(viz: 'bar')]);
      final tilted = tester
          .widgetList<SideTitleWidget>(_inCard(find.byType(SideTitleWidget)))
          .where((w) => w.angle != 0);
      expect(tilted, isEmpty);
    });

    testWidgets('REP-BAS-023 row: horizontal bars on a 120 label axis', (
      tester,
    ) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'Top 3 products');
      final chart = tester.widget<BasiraBarChart>(
        _inCard(find.byType(BasiraBarChart)),
      );
      expect(chart.horizontal, isTrue);
      final bars = tester.widget<BarChart>(_inCard(find.byType(BarChart)));
      expect(bars.data.rotationQuarterTurns, 1);
      expect(
        bars.data.titlesData.bottomTitles.sideTitles.reservedSize,
        basiraLabelAxis,
      );
    });

    testWidgets('REP-BAS-023 pie and donut on the first measure with a '
        'legend; with no measure, a table', (tester) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'Payment mix this month');
      final donut = tester.widget<DashDonutChart>(
        _inCard(find.byType(DashDonutChart)),
      );
      expect(donut.pie, isFalse);
      expect(donut.legend, isTrue);
      expect(_inCard(find.text('Cash')), findsOneWidget);
      await _answer(h, [_block(viz: 'pie')]);
      final pie = tester.widget<DashDonutChart>(
        _inCard(find.byType(DashDonutChart), 1),
      );
      expect(pie.pie, isTrue);
      expect([for (final s in pie.slices) s.value], [1234.5, 0]);
      await _answer(h, [
        _block(
          viz: 'donut',
          columns: [_col('item', 'Item', 'label')],
          rows: [
            {'item': 'Latte'},
          ],
        ),
      ]);
      expect(_inCard(find.byType(BasiraTable), 2), findsOneWidget);
    });

    testWidgets('REP-BAS-023 table and anything else: a table', (tester) async {
      final h = await pumpBasira(tester);
      await _answer(h, [_block(viz: 'auto'), _block()]);
      expect(_inCard(find.byType(BasiraTable)), findsOneWidget);
      expect(_inCard(find.byType(BasiraTable), 1), findsOneWidget);
    });

    testWidgets('REP-BAS-023/034 the table: every column, figures at the '
        'end, 25 rows a page, no Columns menu', (tester) async {
      final h = await pumpBasira(tester);
      await askByTyping(h, 'List orders for today');
      final table = tester.widget<DashDataTable<Map<String, Object?>>>(
        _inCard(find.byType(DashDataTable<Map<String, Object?>>)),
      );
      expect(table.pageSize, 25);
      expect(table.hideViewOptions, isTrue);
      expect(
        [for (final c in table.columns) c.label],
        ['Order', 'Branch', 'Time', 'Total'],
      );
      expect(
        [for (final c in table.columns) c.numeric],
        [false, false, false, true],
      );
      expect(_inCard(find.text('Page 1 of 2')), findsOneWidget);
    });

    testWidgets('REP-BAS-024 cells by kind in a table: money, counts, a '
        'null as a dash', (tester) async {
      final h = await pumpBasira(tester);
      await _answer(h, [_block()]);
      expect(_inCard(find.textContaining('EGP 1,234.50')), findsOneWidget);
      expect(_inCard(find.textContaining('—')), findsOneWidget);
      expect(_inCard(find.textContaining('12')), findsOneWidget);
    });

    testWidgets('REP-BAS-032 the heatmap: rows × sorted columns, a tooltip '
        'per cell; with one dimension, a table', (tester) async {
      final h = await pumpBasira(tester);
      await _answer(h, [
        _block(
          viz: 'heatmap',
          columns: [
            _col('day', 'Day', 'label'),
            _col('hour', 'Hour', 'label'),
            _col('orders', 'Orders', 'count'),
          ],
          rows: [
            {'day': 'Sat', 'hour': '10', 'orders': 4},
            {'day': 'Sat', 'hour': '09', 'orders': 0},
            {'day': 'Sun', 'hour': '10', 'orders': 8},
          ],
        ),
        _block(
          viz: 'heatmap',
          columns: [_col('day', 'Day', 'label'), _col('n', 'N', 'count')],
          rows: [
            {'day': 'Sat', 'n': 1},
          ],
        ),
      ]);
      final heat = _inCard(find.byType(BasiraHeatmap));
      expect(heat, findsOneWidget);
      final cols = [
        for (final t in tester.widgetList<Text>(
          find.descendant(of: heat, matching: find.byType(Text)),
        ))
          t.data,
      ];
      expect(cols.take(4), ['09', '10', 'Sat', 'Sun']);
      final tips = [
        for (final t in tester.widgetList<Tooltip>(
          find.descendant(of: heat, matching: find.byType(Tooltip)),
        ))
          t.message,
      ];
      expect(tips, [
        'Sat · 09 · 0',
        'Sat · 10 · 4',
        'Sun · 09 · 0',
        'Sun · 10 · 8',
      ]);
      expect(_inCard(find.byType(BasiraTable), 1), findsOneWidget);
      await h.shot('basira/heatmap');
    });
  });

  group('rules', () {
    setUpAll(ensureTimeZones);
    final en = Translator(_strings, 'en');
    final ar = Translator(_strings, 'ar');
    final fmtEn = DashFormat(lang: 'en');
    final fmtAr = DashFormat(lang: 'ar');

    String cell(Object? v, wire.ColumnKind k, {bool arabic = false}) =>
        basiraCell(v, k, arabic ? fmtAr : fmtEn, arabic ? ar : en);

    test('REP-BAS-024 cells by kind', () {
      expect(cell(null, wire.ColumnKind.money), '—');
      expect(cell(123450, wire.ColumnKind.money), 'EGP 1,234.50');
      expect(cell(1234, wire.ColumnKind.count), '1,234');
      expect(cell(3.14159, wire.ColumnKind.number), '3.1');
      expect(cell(42, wire.ColumnKind.minutes), '42m');
      expect(cell(60, wire.ColumnKind.minutes), '1h');
      expect(cell(65, wire.ColumnKind.minutes), '1h 5m');
      expect(cell('Latte', wire.ColumnKind.label), 'Latte');
      expect(cell('2026-10-01', wire.ColumnKind.date), '2026-10-01');
      expect(cell(7.0, wire.ColumnKind.label), '7');
      expect(cell('n/a', wire.ColumnKind.money), '—');
    });

    test('REP-BAS-024 (divergence) minutes round once: 119.6 is 2h, not '
        '"1h 60m"', () {
      expect(cell(119.6, wire.ColumnKind.minutes), '2h');
    });

    test('REP-BAS-024 (divergence) Arabic minute and hour units', () {
      expect(cell(42, wire.ColumnKind.minutes, arabic: true), '42 د');
      expect(cell(65, wire.ColumnKind.minutes, arabic: true), '1 س 5 د');
    });

    test('REP-BAS-024 measures and dimensions by kind; money plots in '
        'pounds', () {
      expect(
        [for (final k in wire.ColumnKind.values) isMeasureKind(k)],
        [true, true, false, false, true, true],
      );
      expect(plotValue(123450, wire.ColumnKind.money), 1234.5);
      expect(plotValue(12, wire.ColumnKind.count), 12);
      expect(plotValue(null, wire.ColumnKind.money), isNull);
      expect(dimensionText(null), '—');
    });

    test('REP-BAS-023 the value axis prints plain numbers', () {
      expect(basiraTick(100000), '100000');
      expect(basiraTick(2.5), '2.5');
      expect(basiraTick(0), '0');
    });

    test('REP-BAS-032 opacity: 0.06 for zero, else 0.15 + 0.85 × v / max', () {
      final g = basiraHeatmapGrid(
        const [
          {'d': 'Mon', 'h': '10', 'v': 10},
          {'d': 'Mon', 'h': '09', 'v': 5},
          {'d': 'Tue', 'h': '09', 'v': 0},
        ],
        'd',
        'h',
        'v',
      );
      expect(g.rows, ['Mon', 'Tue']);
      expect(g.cols, ['09', '10']);
      expect(g.value('Tue', '10'), 0);
      expect(g.opacity(0), 0.06);
      expect(g.opacity(10), closeTo(1, 1e-9));
      expect(g.opacity(5), closeTo(0.575, 1e-9));
    });

    test('REP-BAS-021 the provenance and the org\'s calendar days', () {
      final block = wire.ResultBlock.fromJson(
        _block(
          spec: {
            'dataset': 'sales_items',
            'dimensions': ['item', 'size'],
            'measures': ['revenue'],
            'filters': {'status': 'completed', 'channel': 'dine_in'},
          },
          from: '2026-08-31T21:00:00+00:00',
          to: '2026-09-30T20:59:59.999+00:00',
        ),
      );
      final (what, where) = basiraProvenance(
        block,
        stale: true,
        t: en,
        timezone: 'Africa/Cairo',
      );
      expect(
        what,
        'sales_items · by item × size · revenue · '
        'status=completed channel=dine_in',
      );
      expect(where, '2026-09-01 → 2026-09-30 · All (4) · 2 rows · stored');
    });

    test('REP-BAS-014/016 frames: a data payload, a whole SSE frame; '
        'unreadable or unknown frames are dropped', () {
      expect(
        decodeChatFrame('{"event":"thinking","step":2}'),
        isA<wire.ChatFrameThinking>().having((f) => f.step, 'step', 2),
      );
      expect(
        decodeChatFrame('event: x\ndata: {"event":"error","message":"no"}'),
        isA<wire.ChatFrameError>(),
      );
      expect(decodeChatFrame('data: {oops'), isNull);
      expect(decodeChatFrame('{"event":"telemetry"}'), isNull);
      expect(decodeChatFrame(': keep-alive'), isNull);
    });

    test('REP-BAS-010 stored turns: snapshots become blocks; a query with '
        'no snapshot is left out', () {
      final turn = wire.StoredTurn.fromJson({
        'id': 't1',
        'seq': 1,
        'question': 'q',
        'kind': 'answer',
        'created_at': '2026-10-06T15:20:00Z',
        'specs': [
          {
            'title': 'Kept',
            'spec': {'dataset': 'sales'},
            'captured_at': '2026-10-06T15:20:00Z',
            'snapshot': {
              'columns': [_col('n', 'N', 'count')],
              'rows': [
                {'n': 1},
              ],
              'viz': 'kpi',
              'grain': 'scalar',
              'scope': {'all_branches': true, 'branches': [], 'label': 'All'},
            },
          },
          {
            'title': 'Old',
            'spec': {'dataset': 'sales'},
          },
        ],
      });
      final blocks = blocksFromStoredTurn(turn);
      expect([for (final b in blocks) b.title], ['Kept']);
      expect(blocks.single.rowCount, 1);
      expect(blocks.single.viz, wire.Viz.kpi);
      expect(capturedAtOf(turn), '2026-10-06T15:20:00Z');
    });
  });
}

/// A tiny word table for the pure rules (the page tests use the real one).
final Strings _strings = Strings({
  'en': {
    'basira.minutesShort': '{{m}}m',
    'basira.hoursShort': '{{h}}h',
    'basira.hoursMinutesShort': '{{h}}h {{m}}m',
    'basira.provenanceBy': 'by {{dims}}',
    'basira.allTime': 'all time',
    'basira.rows': 'rows',
    'basira.stored': 'stored',
  },
  'ar': {
    'basira.minutesShort': '{{m}} د',
    'basira.hoursShort': '{{h}} س',
    'basira.hoursMinutesShort': '{{h}} س {{m}} د',
  },
});
