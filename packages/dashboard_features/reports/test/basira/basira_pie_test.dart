// Basira's pie and donut answer when pressed (owner, 2026-10-25: "its
// generated pie charts ... should show the data when pressed on a slice"):
// a slice or its legend entry reads its label, figure and share of the
// total, pulls out, and a second press or a press elsewhere lets it go.
import 'dart:math' as math;

import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/src/basira/basira_charts.dart';
import 'package:dashboard_reports/src/basira/basira_result.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _card() => inPage(find.byType(BasiraBlockCard)).first;

Finder _inCard(Finder f) => find.descendant(of: _card(), matching: f);

/// Asks a question whose answer is a pie (or donut) of revenue by category.
Future<void> _askPie(DashHarness h, {String viz = 'pie'}) async {
  final block = {
    'title': 'Sales by category',
    'spec': {'dataset': 'sales_items'},
    'columns': [
      {'key': 'category', 'label': 'Category', 'kind': 'label'},
      {'key': 'revenue', 'label': 'Revenue', 'kind': 'money'},
    ],
    'rows': [
      {'category': 'Coffee', 'revenue': 750000},
      {'category': 'Pastry', 'revenue': 250000},
    ],
    'row_count': 2,
    'truncated': false,
    'grain': 'categorical',
    'viz': viz,
    'scope': {'all_branches': true, 'branches': <String>[], 'label': ''},
  };
  mockOf(h).script([
    {
      'event': 'answer',
      'response': {
        'kind': 'answer',
        'text': 'Coffee leads.',
        'results': [block],
        'provider': 'gemini',
        'timezone': 'Africa/Cairo',
      },
    },
  ]);
  await askByTyping(h, 'Sales by category as a pie');
}

Finder _detail() => find.byKey(const ValueKey('basira-pie-detail'));

/// The panel's lines, joined, without the bidi marks the formatters add.
String _detailText(WidgetTester tester) => [
  for (final e
      in find.descendant(of: _detail(), matching: find.byType(Text)).evaluate())
    (e.widget as Text).data ?? '',
].join(' | ').replaceAll(RegExp('[\u200e\u200f\u2066-\u2069]'), '');

/// [fraction] of the radius from the centre, [degrees] clockwise from the
/// top (the first slice starts at the top and runs clockwise).
Offset _at(WidgetTester tester, double degrees, [double fraction = 0.5]) {
  final box = tester.getRect(_inCard(find.byType(PieChart)));
  final r = box.width / 2 * fraction;
  final a = (degrees - 90) * math.pi / 180;
  return box.center + Offset(math.cos(a) * r, math.sin(a) * r);
}

PieChartData _data(WidgetTester tester) =>
    tester.widget<PieChart>(_inCard(find.byType(PieChart))).data;

void main() {
  testWidgets('a tapped slice reads its label, money and share, pulls out, '
      'and a second tap, a tap elsewhere, lets it go', (tester) async {
    final h = await pumpBasira(tester, size: DashSize.phone);
    await _askPie(h);
    expect(_detailText(tester), 'Tap a slice to see its figures');

    // Coffee is 75%: from the top round to nine o'clock; three o'clock.
    await tester.tapAt(_at(tester, 90));
    await tester.pumpAndSettle();
    expect(_detailText(tester), 'Coffee | EGP 7,500.00 | 75% of the total');
    expect(
      _data(tester).sections[0].radius,
      greaterThan(_data(tester).sections[1].radius),
    );
    await h.shot('basira/pie-pressed');

    await tester.tapAt(_at(tester, 90));
    await tester.pumpAndSettle();
    expect(_detailText(tester), 'Tap a slice to see its figures');
    expect(_data(tester).sections[0].radius, _data(tester).sections[1].radius);

    // Pastry, the last quarter; then a tap outside the chart lets it go.
    await tester.tapAt(_at(tester, 315));
    await tester.pumpAndSettle();
    expect(_detailText(tester), 'Pastry | EGP 2,500.00 | 25% of the total');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(_detailText(tester), 'Tap a slice to see its figures');
  });

  testWidgets('a legend entry selects the same slice and is announced with '
      'its whole reading', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await pumpBasira(tester);
    await _askPie(h, viz: 'donut');
    final entry = _inCard(
      find.bySemanticsLabel('Pastry: EGP 2,500.00, 25% of the total'),
    );
    expect(entry, findsOneWidget);
    final key = _inCard(find.byKey(const ValueKey('basira-pie-legend-1')));
    await h.tap(key);
    await tester.pumpAndSettle();
    expect(_detailText(tester), 'Pastry | EGP 2,500.00 | 25% of the total');
    expect(tester.getSemantics(entry), isSemantics(isSelected: true));
    expect(
      _data(tester).sections[1].radius,
      greaterThan(_data(tester).sections[0].radius),
    );
    await h.shot('basira/donut-legend');
    await h.tap(key);
    await tester.pumpAndSettle();
    expect(_detailText(tester), 'Tap a slice to see its figures');
    semantics.dispose();
  });

  testWidgets('in Arabic: the reading in Arabic, money in the Arabic shape, '
      'the plot still left to right', (tester) async {
    final h = await pumpBasira(tester, size: DashSize.phone, locale: 'ar');
    await _askPie(h);
    expect(_detailText(tester), 'اضغط على شريحة لترى أرقامها');
    await tester.tapAt(_at(tester, 90));
    await tester.pumpAndSettle();
    final text = _detailText(tester);
    expect(text, contains('Coffee'));
    expect(text, contains('7,500.00 ج.م'));
    expect(text, contains('75% من الإجمالي'));
    expect(
      Directionality.of(tester.element(_inCard(find.byType(PieChart)))),
      TextDirection.ltr,
    );
    expect(Directionality.of(tester.element(_detail())), TextDirection.rtl);
    await h.shot('basira/pie-pressed');
  });

  test('readings: counts as integers, unknown as a dash, shares of what is '
      'drawn', () {
    final r = basiraSliceReadings(
      labels: ['Dine-in', 'Takeaway', 'Delivery', 'Unknown'],
      values: [1200, 600, 200, null],
      format: (v) => v.toStringAsFixed(0),
      percent: (x) => '${(x * 100).toStringAsFixed(0)}%',
    );
    expect([for (final x in r) x.value], ['1200', '600', '200', '—']);
    expect([for (final x in r) x.share], ['60%', '30%', '10%', '0%']);
  });
}
