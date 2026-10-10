// Charts: Recharts' nice ticks (below zero too), x labels thinned by the
// room they take and kept inside the plot, time left to right in Arabic,
// gaps in a line, the flat area fill, the horizontal bar chart, and a
// tap's selection kept after the finger lifts (the web's tooltips).
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _plain(double v) => v.toStringAsFixed(0);

const _blue = Color(0xFF2563EB);

final _hours = [
  for (var h = 0; h < 24; h++)
    '${(h % 12 == 0 ? 12 : h % 12).toString().padLeft(2, '0')}:00 '
        '${h < 12 ? 'AM' : 'PM'}',
];

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

Future<void> _pump(
  WidgetTester tester,
  Widget chart, {
  String lang = 'en',
  double width = 600,
}) async {
  await pumpDashApp(
    tester,
    Scaffold(
      body: Center(
        child: SizedBox(width: width, child: chart),
      ),
    ),
    lang: lang,
  );
  await tester.pumpAndSettle();
}

/// The rects of the [labels] drawn, in label order.
List<Rect> _drawn(WidgetTester tester, List<String> labels) => [
  for (final l in labels)
    if (find.text(l).evaluate().isNotEmpty) tester.getRect(find.text(l)),
];

void _expectApartAndInside(List<Rect> rects, Rect plot) {
  final byX = [...rects]..sort((a, b) => a.left.compareTo(b.left));
  for (var k = 0; k + 1 < byX.length; k++) {
    expect(byX[k].right, lessThanOrEqualTo(byX[k + 1].left), reason: 'apart');
  }
  for (final r in rects) {
    expect(r.left, greaterThanOrEqualTo(plot.left - 0.5), reason: 'inside');
    expect(r.right, lessThanOrEqualTo(plot.right + 0.5), reason: 'inside');
  }
}

DashLineChart _line(
  List<String> labels,
  List<double> values, {
  bool ltr = true,
}) => DashLineChart(
  labels: labels,
  series: [DashSeries(label: 'Revenue', values: values, color: _blue)],
  formatY: _plain,
  ltr: ltr,
);

LineChartData _lineData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

void main() {
  // Real faces: label thinning depends on real widths.
  setUpAll(loadDashFonts);

  test('dashNiceTicks: Recharts steps, below zero, whole, all zero', () {
    expect(dashNiceTicks(0, 272), [0, 70, 140, 210, 280]);
    expect(dashNiceTicks(0, 100), [0, 25, 50, 75, 100]);
    expect(dashNiceTicks(0, 10), [0, 3, 6, 9, 12]);
    expect(dashNiceTicks(0, 1000), [0, 250, 500, 750, 1000]);
    expect(dashNiceTicks(0, 2489300), [0, 650000, 1300000, 1950000, 2600000]);
    expect(dashNiceTicks(0, 0.5), [0, 0.15, 0.3, 0.45, 0.6]);
    expect(dashNiceTicks(-30, 100), [-35, 0, 35, 70, 105]);
    expect(dashNiceTicks(-50, -10), [-60, -45, -30, -15, 0]);
    expect(dashNiceTicks(0, 3), [0, 0.75, 1.5, 2.25, 3]);
    expect(dashNiceTicks(0, 3, allowDecimals: false), [0, 1, 2, 3, 4]);
    expect(dashNiceTicks(0, 0), [0, 1, 2, 3, 4]);
    // The old ceiling stays for its callers.
    expect(dashNiceCeil(272), 500);
  });

  testWidgets('the line chart takes Recharts ticks, below zero too', (
    tester,
  ) async {
    await _pump(tester, _line(_months.sublist(0, 3), [0, 50, 272]));
    expect((_lineData(tester).minY, _lineData(tester).maxY), (0, 280));
    expect(_lineData(tester).titlesData.leftTitles.sideTitles.interval, 70);

    await _pump(tester, _line(_months.sublist(0, 3), [-30, 40, 100]));
    expect((_lineData(tester).minY, _lineData(tester).maxY), (-35, 105));
  });

  testWidgets('Arabic: time runs left to right, the y axis on the right; '
      'ltr off mirrors it', (tester) async {
    const days = ['Sat', 'Sun', 'Mon'];
    await _pump(tester, _line(days, [1, 2, 3]), lang: 'ar');
    expect(
      tester.getCenter(find.text('Sat')).dx,
      lessThan(tester.getCenter(find.text('Mon')).dx),
    );
    final data = _lineData(tester);
    expect(data.titlesData.rightTitles.sideTitles.showTitles, isTrue);
    expect(data.titlesData.leftTitles.sideTitles.showTitles, isFalse);
    // The first value is drawn at the left.
    expect(data.lineBarsData.single.spots.first, const FlSpot(0, 1));

    await _pump(tester, _line(days, [1, 2, 3], ltr: false), lang: 'ar');
    expect(
      tester.getCenter(find.text('Sat')).dx,
      greaterThan(tester.getCenter(find.text('Mon')).dx),
    );
  });

  testWidgets('x labels: thinned by their width, inside the plot, the '
      'latest always named', (tester) async {
    final values = [for (var i = 0; i < 24; i++) i * 10.0];
    await _pump(tester, _line(_hours, values), width: 360);
    final narrow = _drawn(tester, _hours);
    expect(narrow.length, inInclusiveRange(2, 23));
    expect(find.text(_hours.last), findsOneWidget);
    _expectApartAndInside(narrow, tester.getRect(find.byType(LineChart)));

    await _pump(tester, _line(_hours, values), width: 1200);
    final wide = _drawn(tester, _hours);
    expect(wide.length, greaterThan(narrow.length));
    _expectApartAndInside(wide, tester.getRect(find.byType(LineChart)));

    // Arabic, mirrored: still apart and inside.
    await _pump(tester, _line(_hours, values, ltr: false), width: 360);
    expect(find.text(_hours.last), findsOneWidget);
    _expectApartAndInside(
      _drawn(tester, _hours),
      tester.getRect(find.byType(LineChart)),
    );
  });

  testWidgets('the bar chart shows every label when they fit', (tester) async {
    Widget bars() => DashBarChart(
      labels: _months,
      series: [
        DashSeries(
          label: 'Orders',
          values: [for (var i = 0; i < 12; i++) i + 1.0],
        ),
      ],
      formatY: _plain,
    );
    await _pump(tester, bars(), width: 900);
    expect(_drawn(tester, _months), hasLength(12));

    await _pump(tester, bars(), width: 220);
    final few = _drawn(tester, _months);
    expect(few.length, lessThan(12));
    expect(find.text('Dec'), findsOneWidget);
    _expectApartAndInside(few, tester.getRect(find.byType(BarChart)));
  });

  testWidgets('a bar below zero hangs from the zero line', (tester) async {
    await _pump(
      tester,
      DashBarChart(
        labels: const ['Cash', 'Card'],
        series: [
          const DashSeries(label: 'Net', values: [-30, 100]),
        ],
        formatY: _plain,
      ),
    );
    final data = tester.widget<BarChart>(find.byType(BarChart)).data;
    expect((data.minY, data.maxY), (-35, 105));
    final rod = data.barGroups.first.barRods.single;
    expect((rod.fromY, rod.toY), (0, -30));
    expect(rod.borderRadius!.bottomLeft.x, greaterThan(0));
    expect(rod.borderRadius!.topLeft.x, 0);
  });

  testWidgets('a NaN is a gap in the line; the area is a flat 12% fill', (
    tester,
  ) async {
    await _pump(tester, _line(_months.sublist(0, 5), [1, 2, double.nan, 4, 5]));
    final bar = _lineData(tester).lineBarsData.single;
    expect(bar.spots.where((s) => s.isNull()), hasLength(1));
    expect(bar.spots, hasLength(5));
    expect(bar.belowBarData.gradient, isNull);
    expect(bar.belowBarData.color, _blue.withValues(alpha: 0.12));
    // 0…5 by Recharts: a step of 2.
    expect((_lineData(tester).minY, _lineData(tester).maxY), (0, 8));
  });

  group('DashHBarChart', () {
    Widget hbar({bool ltr = false, List<double> values = const [100, 50]}) =>
        DashHBarChart(
          labels: const ['Ahmed', 'Mona'],
          series: [DashSeries(label: 'Revenue', values: values, color: _blue)],
          formatX: _plain,
          formatValue: (v) => 'EGP ${v.toStringAsFixed(0)}',
          labelWidth: 110,
          ltr: ltr,
        );

    List<Rect> bars(WidgetTester tester) =>
        tester
            .widgetList<Container>(find.byType(Container))
            .where((c) => (c.decoration as BoxDecoration?)?.color == _blue)
            .map((c) => tester.getRect(find.byWidget(c)))
            .toList()
          ..sort((a, b) => a.top.compareTo(b.top));

    testWidgets('names at the start, bars by value, ticks apart', (
      tester,
    ) async {
      await _pump(tester, hbar());
      final b = bars(tester);
      expect(b, hasLength(2));
      expect(b[1].width / b[0].width, closeTo(0.5, 0.01));
      expect(tester.getRect(find.text('Ahmed')).right, lessThan(b[0].left));
      final ticks = _drawn(tester, [
        for (final t in ['0', '25', '50', '75', '100']) dashFigure(t),
      ]);
      expect(ticks.length, greaterThanOrEqualTo(2));
      _expectApartAndInside(ticks, tester.getRect(find.byType(DashHBarChart)));
    });

    testWidgets('Arabic mirrors it; ltr keeps the names on the left', (
      tester,
    ) async {
      await _pump(tester, hbar(), lang: 'ar');
      expect(
        tester.getRect(find.text('Ahmed')).left,
        greaterThan(bars(tester)[0].right),
      );
      await _pump(tester, hbar(ltr: true), lang: 'ar');
      expect(
        tester.getRect(find.text('Ahmed')).right,
        lessThan(bars(tester)[0].left),
      );
    });

    testWidgets('a tap on a row shows its figure; each row is named', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, hbar());
      expect(find.bySemanticsLabel('Mona, Revenue EGP 50'), findsOneWidget);
      expect(find.textContaining('EGP 50'), findsNothing);
      await tester.tap(find.text('Mona'));
      await tester.pumpAndSettle();
      expect(find.textContaining('EGP 50'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a value below zero grows toward the start from zero', (
      tester,
    ) async {
      await _pump(tester, hbar(values: const [100, -30]));
      final b = bars(tester);
      // The zero line is where the positive bar starts.
      expect(b[1].right, closeTo(b[0].left, 0.5));
      expect(b[1].width, greaterThan(0));
    });
  });

  // fl_chart's own touches showed a tooltip only while a finger was down;
  // the web keeps the tapped one until a tap elsewhere.
  group('a tap keeps its selection', () {
    String tipText(String text, List<TextSpan>? children) =>
        TextSpan(text: text, children: children).toPlainText();

    /// The kit line chart's tooltip and dot, or null when none is shown.
    String? lineTip(WidgetTester tester) {
      final data = _lineData(tester);
      if (data.showingTooltipIndicators.isEmpty) return null;
      final spots = data.showingTooltipIndicators.single.showingSpots;
      final x = spots.first.spotIndex;
      expect(data.lineBarsData.first.showingIndicators, [x]);
      final item = data.lineTouchData.touchTooltipData
          .getTooltipItems(spots)
          .first!;
      return tipText(item.text, item.children);
    }

    // The plot: past a 40 wide y axis, above the x labels.
    Rect plot(WidgetTester tester, Type chart) {
      final r = tester.getRect(find.byType(chart));
      return Rect.fromLTRB(r.left + 40, r.top, r.right, r.bottom - 28);
    }

    Widget line() => DashLineChart(
      labels: const ['Jan', 'Feb', 'Mar'],
      series: [
        const DashSeries(label: 'Revenue', values: [10, 50, 272]),
      ],
      formatY: _plain,
      yReserved: 40,
    );

    testWidgets('line: the nearest point stays after the tap; the point '
        'again or a tap outside clears it', (tester) async {
      await _pump(tester, line());
      final p = plot(tester, LineChart);
      expect(lineTip(tester), isNull);

      // Nearer Mar than Feb, nowhere near the line itself.
      await tester.tapAt(Offset(p.left + p.width * 0.8, p.top + 4));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(lineTip(tester), allOf(contains('Mar'), contains('272')));

      await tester.tapAt(Offset(p.right - 2, p.center.dy));
      await tester.pumpAndSettle();
      expect(lineTip(tester), isNull);

      await tester.tapAt(Offset(p.left + 2, p.center.dy));
      await tester.pumpAndSettle();
      expect(lineTip(tester), contains('Jan'));
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(lineTip(tester), isNull);
    });

    testWidgets('line: a drag scrubs, a long press holds, both stay', (
      tester,
    ) async {
      await _pump(tester, line());
      final p = plot(tester, LineChart);
      await tester.dragFrom(
        Offset(p.left + 2, p.center.dy),
        Offset(p.width / 2, 0),
      );
      await tester.pumpAndSettle();
      expect(lineTip(tester), contains('Feb'));

      await tester.longPressAt(Offset(p.right - 2, p.center.dy));
      await tester.pumpAndSettle();
      expect(lineTip(tester), contains('Mar'));
    });

    testWidgets('line: a mouse shows it on hover, a click keeps it, '
        'leaving drops it', (tester) async {
      await _pump(tester, line());
      final p = plot(tester, LineChart);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(Offset(p.center.dx, p.center.dy));
      await tester.pumpAndSettle();
      expect(lineTip(tester), contains('Feb'));
      await mouse.down(Offset(p.center.dx, p.center.dy));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(lineTip(tester), contains('Feb'));
      await mouse.moveTo(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(lineTip(tester), isNull);
    });

    testWidgets('bar: a tap anywhere in a bar column stays; a tap '
        'between bars clears it', (tester) async {
      await _pump(
        tester,
        DashBarChart(
          labels: const ['Cash', 'Card'],
          series: [
            const DashSeries(label: 'Orders', values: [100, 20]),
          ],
          formatY: _plain,
          yReserved: 40,
        ),
      );
      BarChartData data() =>
          tester.widget<BarChart>(find.byType(BarChart)).data;
      String? tip() {
        for (final (g, group) in data().barGroups.indexed) {
          if (group.showingTooltipIndicators.isEmpty) continue;
          final r = group.showingTooltipIndicators.single;
          final item = data().barTouchData.touchTooltipData.getTooltipItem(
            group,
            g,
            group.barRods[r],
            r,
          )!;
          return tipText(item.text, item.children);
        }
        return null;
      }

      final p = plot(tester, BarChart);
      // High above the short Card bar.
      await tester.tapAt(Offset(p.left + p.width * 0.75, p.top + 4));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(tip(), allOf(contains('Card'), contains('20')));

      await tester.tapAt(Offset(p.center.dx, p.center.dy));
      await tester.pumpAndSettle();
      expect(tip(), isNull);
    });

    testWidgets('donut: a tapped slice stays in the centre; the hole '
        'clears it', (tester) async {
      await _pump(
        tester,
        DashDonutChart(
          slices: const [
            DashSlice(label: 'Cash', value: 3),
            DashSlice(label: 'Card', value: 1),
          ],
          centerLabel: 'Total',
          centerValue: '4',
          formatValue: (v) => 'EGP ${v.toStringAsFixed(0)}',
          legend: false,
        ),
      );
      final centre = tester.getCenter(find.byType(PieChart));
      // Cash runs clockwise from the top for three quarters: the right.
      await tester.tapAt(centre + const Offset(78, 0));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Cash'), findsOneWidget);
      expect(find.textContaining('EGP 3'), findsOneWidget);

      await tester.tapAt(centre);
      await tester.pumpAndSettle();
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
    });

    testWidgets('hbar: a tapped row stays; the row again or a tap outside '
        'clears it', (tester) async {
      await _pump(
        tester,
        DashHBarChart(
          labels: const ['Ahmed', 'Mona'],
          series: [
            const DashSeries(label: 'Revenue', values: [100, 50]),
          ],
          formatX: _plain,
          formatValue: (v) => 'EGP ${v.toStringAsFixed(0)}',
        ),
      );
      await tester.tap(find.text('Mona').first);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('EGP 50'), findsOneWidget);
      await tester.tap(find.text('Mona').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('EGP 50'), findsNothing);

      await tester.tap(find.text('Ahmed').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('EGP 100'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.textContaining('EGP 100'), findsNothing);
    });
  });
}
