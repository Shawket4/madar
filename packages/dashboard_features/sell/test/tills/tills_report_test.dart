// Tills (SELL-TIL-045–055, -062): the till report panel (`?report=`).
import 'package:dashboard_api/dashboard_api.dart' show DeductionLogRow;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/tills/till_report_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tills_support.dart';

Finder get _panel => find.byType(TillReportView);

Finder _section(String key) =>
    find.descendant(of: _panel, matching: find.byKey(ValueKey(key)));

String _texts(WidgetTester tester, Finder finder) => [
  for (final e in find
      .descendant(of: finder, matching: find.byType(RichText))
      .evaluate())
    (e.widget as RichText).text.toPlainText(),
].join(' | ');

/// Opens [tillId]'s report at [branchId] and scrolls it whole into the tree.
Future<DashHarness> _report(
  WidgetTester tester,
  String tillId, {
  String? branchId,
  Persona persona = Persona.owner,
  MockServer? server,
  MockDb? db,
  DashSize size = DashSize.desktop,
}) => pumpTills(
  tester,
  query: 'report=$tillId',
  branchId: branchId,
  persona: persona,
  server: server,
  db: db,
  size: size,
);

void main() {
  testWidgets('SELL-TIL-045 the panel: "Till Report", the teller, Close; '
      '448 wide from the end side', (tester) async {
    final h = await _report(tester, TillIds.helioMorning);
    expect(find.descendant(of: _panel, matching: find.text('Till Report')),
        findsOneWidget);
    expect(find.descendant(of: _panel, matching: find.text('Ali Hassan')),
        findsWidgets);
    // The panel (its start border inside) is 448 wide.
    final size = tester.getSize(find.byType(DashSurface).last);
    expect(size.width, closeTo(tillReportWidth, 1));
    // The end side: flush with the window's right edge in English.
    expect(tester.getTopRight(find.byType(DashSurface).last).dx, 1440);
    expect(h.server.callsTo(tillReport).single.path,
        '/tills/${TillIds.helioMorning}/report');
    expect(h.server.callsTo(tillSummary).single.path,
        '/reports/tills/${TillIds.helioMorning}/summary');
  });

  testWidgets('SELL-TIL-045 phone: the report full screen', (tester) async {
    await _report(tester, TillIds.helioMorning, size: DashSize.phone);
    expect(tester.getSize(find.byType(DashSurface).last).width, 390);
  });

  testWidgets('SELL-TIL-046 report loading: four skeletons, "Loading…"', (
    tester,
  ) async {
    final s = tillsServer();
    final gate = s.server.hold('GET', tillReport);
    final h = await _report(
      tester,
      TillIds.helioMorning,
      server: s.server,
      db: s.db,
    );
    final loading = find.byKey(const ValueKey('till-report-loading'));
    expect(
      find.descendant(of: loading, matching: find.byType(DashSkeleton)),
      findsNWidgets(4),
    );
    expect(find.descendant(of: _panel, matching: find.text('Loading…')),
        findsOneWidget);
    gate.release();
    await h.settle();
    expect(loading, findsNothing);
  });

  testWidgets('SELL-TIL-046 report error: its words and Retry', (
    tester,
  ) async {
    final s = tillsServer();
    s.server.fail(
      'GET',
      tillReport,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await _report(
      tester,
      TillIds.helioMorning,
      server: s.server,
      db: s.db,
    );
    expect(
      find.descendant(
        of: _panel,
        matching: find.text('Could not load the till report. Please try again.'),
      ),
      findsOneWidget,
    );
    s.server.clearFailures();
    await h.tap(find.descendant(of: _panel, matching: find.text('Retry')));
    expect(_section('till-report-info'), findsOneWidget);
  });

  testWidgets('SELL-TIL-047 info: opened, closed, device, order numbers, '
      'bills at close, held orders left open, badges', (tester) async {
    await _report(tester, TillIds.zamalekLastEvening, branchId: SeedIds.zamalek);
    final text = _texts(tester, _section('till-report-info'));
    for (final w in [
      'Opened',
      'Closed',
      'Device',
      'Order numbers',
      'Open bills at close',
      'Held orders left open',
      'Old open bills at close',
    ]) {
      expect(text, contains(w));
    }
    expect(text, contains('1 · EGP 85.00'));
    expect(text, matches(RegExp(r'T\d-\d+ – T\d-\d+')));
  });

  testWidgets('SELL-TIL-047/019 the flag in the report switches it to the '
      'other till', (tester) async {
    final h = await _report(tester, TillIds.helioSecond);
    final info = _section('till-report-info');
    expect(_texts(tester, info), contains('Verified on LAN'));
    await h.tap(
      find.descendant(of: info, matching: find.text('See the other till')),
    );
    expect(h.location.queryParameters['report'], TillIds.helioMorning);
    expect(h.server.callsTo(tillReport).last.path,
        '/tills/${TillIds.helioMorning}/report');
    expect(find.byType(TillReportView), findsOneWidget);
  });

  testWidgets('SELL-TIL-048/049 Sales (orders, revenue, discounts, tax, '
      'voided count) and Payment summary (methods, net, tips, of which cash, '
      'voided amount) against the orders', (tester) async {
    final s = tillsServer();
    final id = TillIds.zamalekLastEvening;
    final orders = s.db['orders'].where((o) => o['till_id'] == id).toList();
    bool sold(MockRow o) => o['status'] != 'voided' && o['status'] != 'refunded';
    // One cash tip on a paid order.
    orders.firstWhere(sold)
      ..['tip_amount'] = 2500
      ..['tip_payment_method'] = 'cash';
    int sum(Iterable<MockRow> rows, String f) =>
        rows.fold(0, (a, o) => a + ((o[f] as int?) ?? 0));
    final paid = orders.where(sold).toList();
    final voided = orders.where((o) => o['status'] == 'voided').toList();
    expect(voided, isNotEmpty);
    final h = await _report(
      tester,
      id,
      branchId: SeedIds.zamalek,
      server: s.server,
      db: s.db,
    );
    final fmt = h.container.read(formatProvider);
    String line(String key, String label) {
      final lines = tester
          .widgetList<ReportLine>(
            find.descendant(of: _section(key), matching: find.byType(ReportLine)),
          )
          .where((l) => l.label == label);
      return lines.single.value;
    }

    expect(line('till-summary', 'Orders'), '${paid.length}');
    expect(line('till-summary', 'Revenue'), fmt.fmtMoney(sum(paid, 'total_amount')));
    expect(line('till-summary', 'Discounts'), fmt.fmtMoney(sum(paid, 'discount_amount')));
    expect(line('till-summary', 'Tax'), fmt.fmtMoney(sum(paid, 'tax_amount')));
    expect(line('till-summary', 'Order voided'), '${voided.length}');
    expect(line('till-payments', 'Tips'), fmt.fmtMoney(2500));
    expect(line('till-payments', 'of which cash'), fmt.fmtMoney(2500));
    expect(line('till-payments', 'Voided'), fmt.fmtMoney(sum(voided, 'total_amount')));
    final payments = _texts(tester, _section('till-payments'));
    expect(payments, contains('Payment summary'));
    expect(payments, contains('Net payments'));
    expect(payments, matches(RegExp(r'Card \(\d+\)')));
    expect(h.server.callsTo(tillSummary), hasLength(1));
  });

  testWidgets('SELL-TIL-049 no payments: "No results found"', (tester) async {
    await _report(tester, TillIds.emptyTill, branchId: SeedIds.newCairo);
    expect(_texts(tester, _section('till-payments')), contains('No results found'));
    // An empty till used no stock: the section is hidden.
    expect(_section('till-deductions'), findsNothing);
  });

  testWidgets('SELL-TIL-050 Payment check (stacked in the 448 panel): '
      'method, status, note, system total, declared', (tester) async {
    await _report(tester, TillIds.zamalekLastEvening, branchId: SeedIds.zamalek);
    final table = _section('reconciliation-table');
    expect(_texts(tester, table), contains('Payment check'));
    final card = find.descendant(
      of: table,
      matching: find.byKey(const ValueKey('reconciliation-line-card')),
    );
    final text = _texts(tester, card);
    for (final w in [
      'Card',
      "Doesn't match",
      'One card slip is missing from the batch.',
      'System total',
      'Declared',
    ]) {
      expect(text, contains(w), reason: w);
    }
    final cash = find.descendant(
      of: table,
      matching: find.byKey(const ValueKey('reconciliation-line-cash')),
    );
    expect(_texts(tester, cash), contains('Checked'));
    // No word is broken across lines: the Method column is gone.
    expect(find.descendant(of: table, matching: find.byType(Table)), findsNothing);
  });

  testWidgets('SELL-TIL-051/062 Cash reconciliation: the edited float (+), '
      'carryover, in/out, expected, counted, unsigned discrepancy', (
    tester,
  ) async {
    final h = await _report(
      tester,
      TillIds.zamalekLastEvening,
      branchId: SeedIds.zamalek,
    );
    final cash = _section('till-cash');
    final text = _texts(tester, cash);
    for (final w in [
      'Cash reconciliation',
      'Opening Cash',
      'Expected (carryover)',
      'Opening cash edited',
      'Found EGP 50 left in the drawer from the morning till.',
      'Cash in',
      'Cash out',
      'Expected cash',
      'Cash counted in drawer',
      'Discrepancy',
    ]) {
      expect(text, contains(w), reason: w);
    }
    expect(_texts(tester, _section('opening-edited')), contains('+EGP 50.00'));
    final till = h.db!['tills'].get(TillIds.zamalekLastEvening);
    final d = till['cash_discrepancy']! as int;
    final fmt = h.container.read(formatProvider);
    final disc = _texts(tester, _section('report-discrepancy'));
    expect(disc, contains(fmt.fmtMoney(d)));
    expect(disc, isNot(contains('+')));
  });

  testWidgets('SELL-TIL-052 Spot reports viewed: viewer, time, unlocked by, '
      'Printed', (tester) async {
    await _report(tester, TillIds.helioMorning);
    final views = _section('till-spot-views');
    final text = _texts(tester, views);
    expect(text, contains('Spot reports viewed'));
    expect(text, contains('Rana'));
    expect(text, contains('unlocked by'));
    expect(
      find.descendant(of: views, matching: find.byKey(const ValueKey('spot-view-printed'))),
      findsOneWidget,
    );
  });

  testWidgets('SELL-TIL-052 nobody viewed it; a failed read shows the server '
      'words', (tester) async {
    final s = tillsServer();
    s.server.fail(
      'GET',
      tillSpotViews,
      MockResponse.error(500, 'Database error: spot views offline'),
      times: null,
    );
    await _report(
      tester,
      TillIds.seeded('heliopolis', 2, 'evening'),
      server: s.server,
      db: s.db,
    );
    expect(
      _texts(tester, _section('spot-views-error')),
      'spot views offline',
    );
  });

  testWidgets('SELL-TIL-052 empty spot views', (tester) async {
    await _report(tester, TillIds.seeded('heliopolis', 2, 'evening'));
    expect(
      _texts(tester, _section('spot-views-empty')),
      'Nobody has viewed the spot report for this till.',
    );
  });

  testWidgets('SELL-TIL-053 Stock used: net quantities with units, most '
      'used first, and what voids put back', (tester) async {
    final id = TillIds.zamalekLastEvening;
    final h = await _report(tester, id, branchId: SeedIds.zamalek);
    final stock = _section('till-deductions');
    final text = _texts(tester, stock);
    expect(text, contains('Stock used'));
    expect(text, matches(RegExp(r'\d ml')));
    // The voided order's stock came back.
    expect(text, matches(RegExp(r'\d+(\.\d+)? \w+ put back by voids')));
    expect(h.server.callsTo(tillDeductions).single.path,
        '/reports/tills/$id/deductions');
  });

  test('SELL-TIL-053 summarizeDeductions: net of restocks per item and '
      'unit, returned kept apart, most used then by name', () {
    DeductionLogRow row(String item, String name, String unit, double q,
            String source) =>
        DeductionLogRow(
          id: '$item$q$source',
          orderId: 'o',
          inventoryItemId: item,
          itemName: name,
          unit: unit,
          quantityDeducted: q,
          source: source,
          createdAt: DateTime.utc(2026, 10, 8),
        );
    final totals = summarizeDeductions([
      row('beans', 'Espresso beans', 'g', 18, 'sale'),
      row('beans', 'Espresso beans', 'g', 18, 'sale'),
      row('beans', 'Espresso beans', 'g', -18, 'void_restock'),
      row('milk', 'Full-cream milk', 'ml', 200, 'sale'),
      row('cup', 'Paper cup', 'pcs', 1, 'sale'),
      row('lid', 'Lid', 'pcs', 1, 'sale'),
    ]);
    expect([for (final d in totals) d.name], [
      'Full-cream milk',
      'Espresso beans',
      'Lid',
      'Paper cup',
    ]);
    final beans = totals[1];
    expect(beans.used, 18);
    expect(beans.returned, 18);
    expect(totals.first.returned, 0);
  });

  testWidgets('SELL-TIL-053 a refused stock read: its own words', (
    tester,
  ) async {
    // Hana (limited) may read tills but not stock.
    await _report(
      tester,
      TillIds.maadiMorning,
      branchId: SeedIds.maadi,
      persona: Persona.limited,
    );
    expect(
      _texts(tester, _section('deductions-error')),
      "Couldn't load the stock used by this till.",
    );
  });

  testWidgets('SELL-TIL-054/062 Cash movements: note (or the direction), who '
      '· when, signed money', (tester) async {
    await _report(tester, TillIds.helioMorning);
    final moves = _section('till-movements');
    final text = _texts(tester, moves);
    expect(text, contains('Cash movements'));
    expect(text, contains('Change float from the safe'));
    expect(text, contains('+EGP 200.00'));
    expect(text, contains('−EGP 85.00'));
    expect(text, contains('Ali Hassan · '));
  });

  testWidgets('SELL-TIL-062 a movement without a note is titled by its '
      'direction', (tester) async {
    final s = tillsServer();
    for (final m in s.db['till_cash_movements'].rows) {
      if (m['till_id'] == TillIds.helioMorning) m['note'] = '';
    }
    await _report(
      tester,
      TillIds.helioMorning,
      server: s.server,
      db: s.db,
    );
    final text = _texts(tester, _section('till-movements'));
    expect(text, allOf(contains('Cash in'), contains('Cash out')));
  });

  testWidgets('SELL-TIL-062 section order: info, Sales, Payment summary, '
      'Payment check, Cash, Spot views, Stock used, Cash movements', (
    tester,
  ) async {
    await _report(tester, TillIds.zamalekLastEvening, branchId: SeedIds.zamalek);
    final order = [
      'till-report-info',
      'till-summary',
      'till-payments',
      'reconciliation-table',
      'till-cash',
      'till-spot-views',
      'till-deductions',
      'till-movements',
    ];
    final ys = [for (final k in order) tester.getTopLeft(_section(k)).dy];
    final sorted = [...ys]..sort();
    expect(ys, sorted);
  });
}
