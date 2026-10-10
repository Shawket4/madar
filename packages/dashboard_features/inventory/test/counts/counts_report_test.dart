// The variance report of a finalized count: its read, the three KPIs, the
// table, its loading and error states, closing it, and the edge cells
// (INV-CNT-049…054, -066).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _minus = '−';

DashStatCard _kpi(WidgetTester tester, String key) =>
    tester.widget<DashStatCard>(inReport(find.byKey(ValueKey(key))));

Finder _row(String key) =>
    inReport(byKey('variance-row-${InvIds.ingredient(key)}'));

Finder _inRow(String key, Finder f) =>
    find.descendant(of: _row(key), matching: f);

Future<DashHarness> _open(
  WidgetTester tester,
  String id, {
  ({MockServer server, MockDb db})? s,
  DashSize size = DashSize.desktop,
}) async {
  final h = await pumpCounts(
    tester,
    server: s?.server,
    db: s?.db,
    size: size,
    branch: SeedIds.zamalek,
  );
  expect(h.server.callsTo(reportRoute), isEmpty, reason: 'read when open');
  await h.tap(inTable(byKey('counts-report-$id')));
  expect(report, findsOneWidget);
  return h;
}

void main() {
  testWidgets('INV-CNT-049/050 title, unknown costs, the three KPIs', (
    tester,
  ) async {
    final h = await _open(tester, zamalekFull);
    expect(inReport(find.text('Variance report')), findsOneWidget);
    expect(inReport(find.text('1 item(s) with unknown cost')), findsOneWidget);
    expect(
      h.server.callsTo(reportRoute).single.path,
      '/stocktakes/$zamalekFull/variance-report',
    );
    final shrink = _kpi(tester, 'shrink');
    expect(shrink.label, 'Shrinkage');
    expect(shrink.value, 35600);
    expect(shrink.format, DashStatFormat.money);
    expect(shrink.icon, 'arrow-down-circle');
    expect(shrink.tone, DashTone.danger);
    final over = _kpi(tester, 'over');
    expect(over.label, 'Overage');
    expect(over.value, 2770);
    expect(over.tone, DashTone.success);
    expect(over.icon, 'arrow-up-circle');
    final net = _kpi(tester, 'net');
    expect(net.label, 'Net variance');
    expect(net.value, -32830);
    expect(net.tone, DashTone.danger);
    expect(net.icon, 'scale');
    expect(inReport(find.text('EGP 356.00')), findsOneWidget);
    expect(inReport(find.text('${_minus}EGP 328.30')), findsOneWidget);
  });

  testWidgets('INV-CNT-050 a net gain is green', (tester) async {
    final s = countsServer();
    // The milk recount with the Full Cream loss taken out: +1,440 only.
    final item = itemRow(s.db, zamalekMilk, 'full-cream');
    item['counted_qty'] = item['book_qty'];
    await _open(tester, zamalekMilk, s: s);
    expect(_kpi(tester, 'net').value, 1440);
    expect(_kpi(tester, 'net').tone, DashTone.success);
    expect(inReport(find.text('0 item(s) with unknown cost')), findsOneWidget);
  });

  testWidgets('INV-CNT-051 the table: by name; flagged pill, category, book, '
      'counted, signed difference, value, reason', (tester) async {
    await _open(tester, zamalekFull);
    for (final c in [
      'INGREDIENT',
      'BOOK STOCK',
      'COUNTED',
      'DIFFERENCE',
      'VALUE',
      'REASON',
    ]) {
      expect(inReport(find.text(c)), findsOneWidget, reason: c);
    }
    expect(_inRow('croissant', find.text('Flagged')), findsOneWidget);
    expect(_inRow('croissant', find.text('Bakery')), findsOneWidget);
    expect(_inRow('croissant', find.text('67 pcs')), findsOneWidget);
    expect(_inRow('croissant', find.text('62')), findsOneWidget);
    final diff = tester.widget<Text>(
      _inRow('croissant', find.text('${_minus}5')),
    );
    expect(
      diff.style!.color,
      DashTone.danger.foreground(tester.element(report).madarColors),
    );
    expect(
      _inRow('croissant', find.text('${_minus}EGP 45.00')),
      findsOneWidget,
    );
    expect(_inRow('croissant', find.text('Miscount')), findsOneWidget);
    expect(_inRow('full-cream', find.text('+490')), findsOneWidget);
    expect(_inRow('full-cream', find.text('EGP 24.50')), findsOneWidget);
    expect(_inRow('full-cream', find.text('Flagged')), findsNothing);
    expect(_inRow('full-cream', find.text('—')), findsOneWidget);
    // Unknown cost: no value.
    expect(_inRow('hibiscus', find.text('—')), findsNWidgets(2));
    // Book equal to the opening: no "was … at start".
    expect(_inRow('croissant', textHas('at start')), findsNothing);
  });

  testWidgets('INV-CNT-051 book moved since the count opened: "was … at '
      'start"', (tester) async {
    final s = countsServer();
    itemRow(s.db, zamalekFull, 'croissant')['opening_qty'] = 70.0;
    await _open(tester, zamalekFull, s: s);
    expect(
      _inRow('croissant', textHas('was ${ltr('70')} at start')),
      findsOneWidget,
    );
  });

  testWidgets('INV-CNT-052 loading: five bars and the KPIs\' skeletons; no '
      'unknown-cost line yet', (tester) async {
    final s = countsServer();
    final gate = s.server.hold('GET', reportRoute);
    final h = await _open(tester, zamalekFull, s: s);
    expect(
      find.descendant(
        of: inReport(byKey('variance-loading')),
        matching: find.byType(DashSkeleton),
      ),
      findsNWidgets(5),
    );
    expect(_kpi(tester, 'shrink').loading, isTrue);
    expect(_kpi(tester, 'net').loading, isTrue);
    expect(inReport(textHas('unknown cost')), findsNothing);
    gate.release();
    await h.settle();
    expect(inReport(byKey('variance-table')), findsOneWidget);
    expect(_kpi(tester, 'shrink').loading, isFalse);
  });

  testWidgets('INV-CNT-053 error: its own words and Retry, no KPIs; Retry '
      'reads only the report', (tester) async {
    final s = countsServer();
    final boom = MockResponse.error(500, 'Report is resting');
    s.server.fail('GET', reportRoute, boom, times: null);
    final h = await _open(tester, zamalekFull, s: s);
    expect(
      inReport(find.text("Couldn't load the variance report")),
      findsOneWidget,
    );
    expect(inReport(find.text(h.refusalWords(boom))), findsNothing);
    expect(inReport(byKey('variance-kpis')), findsNothing);
    s.server.clearFailures();
    final before = h.server.calls.length;
    await h.tap(inReport(find.text('Retry')));
    expect(h.server.calls.sublist(before).map((c) => c.template), [
      reportRoute,
    ]);
    expect(inReport(byKey('variance-kpis')), findsOneWidget);
    expect(inReport(byKey('variance-table')), findsOneWidget);
  });

  testWidgets('INV-CNT-054 read-only; closes with ✕, Escape or a tap '
      'outside', (tester) async {
    final h = await _open(tester, zamalekFull);
    expect(inReport(find.byType(DashButton)), findsNothing);
    await h.tap(inReport(find.bySemanticsLabel('Close')));
    expect(report, findsNothing);
    await h.tap(inTable(byKey('counts-report-$zamalekFull')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(report, findsNothing);
    await h.tap(inTable(byKey('counts-report-$zamalekFull')));
    await tester.tapAt(const Offset(4, 450));
    await h.settle();
    expect(report, findsNothing);
  });

  testWidgets('INV-CNT-066 no rows: the header alone; null cells read "—"', (
    tester,
  ) async {
    final s = countsServer();
    s.db[InvTables.stocktakeItems].removeWhere(
      (i) => i['stocktake_id'] == zamalekMilk,
    );
    final full = itemRow(s.db, zamalekFull, 'sugar');
    full['counted_qty'] = null;
    final h = await _open(tester, zamalekMilk, s: s);
    expect(inReport(find.text('INGREDIENT')), findsOneWidget);
    expect(inReport(byKey('variance-table')), findsOneWidget);
    expect(inReport(find.byType(DashEmptyState)), findsNothing);
    expect(_kpi(tester, 'shrink').value, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    await h.tap(inTable(byKey('counts-report-$zamalekFull')));
    // Counted, Difference, Value, Reason: "—"; the difference uncoloured.
    expect(_inRow('sugar', find.text('—')), findsNWidgets(4));
    final dash = tester
        .widgetList<Text>(_inRow('sugar', find.text('—')))
        .map((t) => t.style?.color)
        .toSet();
    expect(
      dash,
      isNot(
        contains(
          DashTone.danger.foreground(tester.element(report).madarColors),
        ),
      ),
    );
  });

  testWidgets('INV-CNT-049 phone: a centred card, the table scrolls '
      'sideways', (tester) async {
    await _open(tester, zamalekFull, size: DashSize.phone);
    expectPhoneDialog(tester);
    expect(
      find.descendant(
        of: inReport(byKey('variance-table')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
  });
}
