// Legal › Tax (REP-LEG-008…012): the read and its states, the VAT gate, the
// rate note, the six figures against hand-computed sums, and the export.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/legal/tax_tab.dart';
import 'package:dashboard_reports/src/mock/legal_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legal_support.dart';

Finder _inTax(Finder f) =>
    find.descendant(of: find.byType(LegalTaxTab), matching: f);

Finder get _export => _inTax(find.byType(DashExportButton));

Future<void> _menu(DashHarness h, String item) async {
  await h.tap(_export);
  await h.tap(find.text(item).last);
}

String _stamp(DashHarness h) =>
    isoString(h.container.read(clockProvider)()).substring(0, 10);

DashStatCard _kpi(WidgetTester tester, String key) =>
    tester.widget<DashStatCard>(_inTax(find.byKey(ValueKey(key))));

/// The Tax figures, summed by hand from the seed's Sabah orders created in
/// the default period: taxable = Σ (subtotal − discount) and revenue = Σ
/// total over the sold orders; tax = Σ tax over every order not voided.
({int taxable, int tax, int service, int revenue}) _expected(MockDb db) {
  final from = DateTime.parse(defaultFrom);
  final to = DateTime.parse(defaultTo);
  var taxable = 0, tax = 0, service = 0, revenue = 0;
  for (final o in db['orders'].rows) {
    if (!SeedIds.sabahBranches.contains(o['branch_id'])) continue;
    final at = DateTime.parse('${o['created_at']}');
    if (at.isBefore(from) || at.isAfter(to)) continue;
    final status = o['status'];
    if (status == 'voided') continue;
    tax += (o['tax_amount'] as num? ?? 0).toInt();
    if (status == 'refunded') continue;
    taxable +=
        (o['subtotal'] as num).toInt() -
        (o['discount_amount'] as num? ?? 0).toInt();
    service += (o['service_charge_amount'] as num? ?? 0).toInt();
    revenue += (o['total_amount'] as num).toInt();
  }
  return (taxable: taxable, tax: tax, service: service, revenue: revenue);
}

void main() {
  testWidgets('REP-LEG-008 loading: a 112 px skeleton, no figures', (
    tester,
  ) async {
    final s = legalServer();
    final gate = s.server.hold('GET', taxRoute);
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    final skeleton = _inTax(find.byType(DashSkeleton));
    expect(skeleton, findsOneWidget);
    expect(tester.getSize(skeleton).height, 112);
    expect(_inTax(find.byType(DashStatCard)), findsNothing);
    expect(find.text(h.t('reports.legal.noVat')), findsNothing);
    await h.shot('legal/tax-loading');
    gate.release();
    await h.settle();
    expect(_inTax(find.byType(DashSkeleton)), findsNothing);
    expect(_inTax(find.byType(DashStatCard)), findsNWidgets(6));
  });

  testWidgets('REP-LEG-008 error: "Couldn\'t load this" + Retry, which asks '
      'the tax report alone again; the error stays while it runs', (
    tester,
  ) async {
    final s = legalServer();
    s.server.fail(
      'GET',
      taxRoute,
      MockResponse.error(500, 'Internal error'),
      times: 1,
    );
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    expect(_inTax(find.byType(DashErrorState)), findsOneWidget);
    expect(_inTax(find.text(h.t('common.loadFailed'))), findsOneWidget);
    expect(_inTax(find.byType(DashStatCard)), findsNothing);
    await h.shot('legal/tax-error');
    final gate = s.server.hold('GET', taxRoute);
    await tester.tap(_inTax(find.text(h.t('common.retry'))));
    await tester.pump();
    await tester.pump();
    // Retrying: still the error, its button spinning, never the empty words.
    expect(_inTax(find.byType(DashErrorState)), findsOneWidget);
    expect(
      tester
          .widget<DashErrorState>(_inTax(find.byType(DashErrorState)))
          .retrying,
      isTrue,
    );
    expect(find.text(h.t('reports.legal.noVat')), findsNothing);
    gate.release();
    await h.settle();
    expect(h.server.callsTo(taxRoute), hasLength(2));
    expect(legalCalls(h), hasLength(2));
    expect(_inTax(find.byType(DashStatCard)), findsNWidgets(6));
  });

  testWidgets('REP-LEG-008 a server refusal shows the error state, asked once '
      '(no retry on a 403)', (tester) async {
    final s = legalServer();
    s.server.fail(
      'GET',
      taxRoute,
      MockResponse.denied('reports.legal'),
      times: null,
    );
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    expect(_inTax(find.byType(DashErrorState)), findsOneWidget);
    expect(h.server.callsTo(taxRoute), hasLength(1));
  });

  testWidgets('REP-LEG-009 not VAT-registered: the Landmark empty state', (
    tester,
  ) async {
    final s = legalServer();
    s.db['orgs'].update(SeedIds.sabahOrg, {'tax_rate': 0});
    for (final o in s.db['orders'].rows) {
      o['tax_amount'] = 0;
    }
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    final empty = _inTax(find.byType(DashEmptyState));
    expect(empty, findsOneWidget);
    expect(tester.widget<DashEmptyState>(empty).icon, 'landmark');
    expect(
      _inTax(find.text('This organization has no VAT configured')),
      findsOneWidget,
    );
    expect(
      _inTax(
        find.text(
          'Set a tax rate under Settings to see a tax report '
          'here.',
        ),
      ),
      findsOneWidget,
    );
    expect(_export, findsNothing);
    await h.shot('legal/tax-no-vat');
  });

  testWidgets('REP-LEG-009 a zero rate today still reports tax collected '
      'under an earlier one', (tester) async {
    final s = legalServer();
    s.db['orgs'].update(SeedIds.sabahOrg, {'tax_rate': 0});
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    expect(find.text(h.t('reports.legal.noVat')), findsNothing);
    expect(_kpi(tester, 'tax_collected').value, _expected(s.db).tax);
    expect(_inTax(find.text('Org tax rate: 0%')), findsOneWidget);
  });

  testWidgets('REP-LEG-010 the rate note: the org\'s ratio as a percent', (
    tester,
  ) async {
    final h = await pumpLegal(tester);
    final f = fmtOf(h);
    expect(
      _inTax(find.text('Org tax rate: ${f.fmtPercent(0.14)}')),
      findsOneWidget,
    );
    expect(f.fmtPercent(0.14), '14%');
    expect(f.fmtPercent(0.125), '12.5%');
  });

  testWidgets('REP-LEG-011 six figures, in order, against the seed summed '
      'by hand', (tester) async {
    final s = legalServer();
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    final want = _expected(s.db);
    final cards = tester
        .widgetList<DashStatCard>(_inTax(find.byType(DashStatCard)))
        .toList();
    expect(
      [for (final c in cards) c.label],
      [
        'Taxable Sales',
        'Tax Collected',
        'Refunded Tax',
        'Net Tax Due',
        'Service Charge',
        'Revenue',
      ],
    );
    expect([
      for (final c in cards) c.format,
    ], everyElement(DashStatFormat.money));
    expect(_kpi(tester, 'taxable_sales').value, want.taxable);
    expect(_kpi(tester, 'tax_collected').value, want.tax);
    expect(_kpi(tester, 'refunded_tax').value, 0);
    expect(_kpi(tester, 'net_tax_due').value, want.tax);
    expect(_kpi(tester, 'service_charge').value, want.service);
    expect(_kpi(tester, 'net_revenue').value, want.revenue);
    expect(want.taxable, greaterThan(0));
    expectAnyText(moneyForms(fmtOf(h), want.tax));
  });

  testWidgets('REP-LEG-011 a refund nets the tax due and the revenue', (
    tester,
  ) async {
    final s = legalServer();
    final before = _expected(s.db);
    final order = s.db['orders'].rows.firstWhere(
      (o) =>
          o['branch_id'] == SeedIds.heliopolis &&
          o['status'] == 'completed' &&
          '${o['created_at']}'.compareTo(defaultFrom) > 0,
    );
    final refund = recordLegalRefund(
      s.db,
      orderId: order['id']! as String,
      amount: 11400,
      reason: 'Cold drink',
      issuedBy: SeedIds.user('nour'),
      issuedAt: s.db.clock.now,
    );
    expect(refund['tax'], 1400);
    await pumpLegal(tester, server: s.server, db: s.db);
    expect(_kpi(tester, 'refunded_tax').value, 1400);
    expect(_kpi(tester, 'net_tax_due').value, before.tax - 1400);
    expect(_kpi(tester, 'net_revenue').value, before.revenue - 11400);
  });

  testWidgets('REP-LEG-012 / REP-ALL-011 Tax to Excel: one sheet "Tax", the '
      'rate note under it, a row per figure, Tax-<date>.xlsx', (tester) async {
    final s = legalServer();
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    final want = _expected(s.db);
    final asked = legalCalls(h).length;
    await _menu(h, 'Export Excel');
    final spec = h.exports.built.single;
    final sheet = spec.sheets.single;
    expect(sheet.name, 'Tax');
    expect(sheet.title, 'Tax');
    expect(sheet.subtitle, startsWith('Org tax rate: 14%'));
    expect([for (final c in sheet.columns) c.header], ['Figure', 'Amount']);
    expect(sheet.columns[1].numFmt, '#,##0.00 "EGP"');
    expect(
      [for (final r in sheet.rows) r[0]],
      [
        'Taxable Sales',
        'Tax Collected',
        'Refunded Tax',
        'Net Tax Due',
        'Service Charge',
        'Revenue',
      ],
    );
    expect(sheet.rows[0][1], want.taxable / 100);
    expect(sheet.rows[5][1], want.revenue / 100);
    expect(sheet.totalsRow, isNull);
    expect(h.files.saved.single.filename, 'Tax-${_stamp(h)}.xlsx');
    // Built from what is on screen: no request.
    expect(legalCalls(h), hasLength(asked));
    await h.expectToast('Exported 6 rows');
  });

  testWidgets('REP-LEG-012 / REP-ALL-012 Tax to CSV: Tax-<date>.csv, pounds', (
    tester,
  ) async {
    final s = legalServer();
    final h = await pumpLegal(tester, server: s.server, db: s.db);
    await _menu(h, 'Export CSV');
    final file = h.files.saved.single;
    expect(file.filename, 'Tax-${_stamp(h)}.csv');
    final lines = file.asString.split('\r\n');
    expect(lines.first, 'Figure,Amount');
    expect(lines, hasLength(7));
    expect(lines[2], startsWith('Tax Collected,'));
    expect(h.exports.built, isEmpty);
    await h.expectToast('Exported 6 rows');
  });

  testWidgets('REP-LEG-012 (divergence) the Arabic export is Arabic: its '
      'file, sheet and column names', (tester) async {
    final h = await pumpLegal(tester, locale: 'ar');
    await _menu(h, h.t('common.exportExcel'));
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.name, 'الضريبة');
    expect(
      [for (final c in sheet.columns) c.header],
      [h.t('reports.legal.taxColFigure'), h.t('reports.legal.colAmount')],
    );
    expect(sheet.columns.first.header, isNot('Figure'));
    expect(h.files.saved.single.filename, startsWith('الضريبة-'));
    await h.flushTimers();
  });

  testWidgets('REP-LEG-012 / REP-ALL-026 the Excel export spins while it '
      'builds', (tester) async {
    final h = await pumpLegal(tester);
    final hold = h.exports.hold = Future<void>.delayed(
      const Duration(seconds: 2),
    );
    await h.tap(_export);
    await tester.tap(find.text('Export Excel').last);
    await tester.pump();
    await tester.pump();
    final button = tester.widget<DashButton>(
      find.descendant(of: _export, matching: find.byType(DashButton)),
    );
    expect(button.loading, isTrue);
    await tester.pump(const Duration(seconds: 2));
    await hold;
    h.exports.hold = null;
    await h.settle();
    expect(h.files.saved, hasLength(1));
    await h.flushTimers();
  });

  testWidgets('REP-ALL-011 a failed build says "Export failed"', (
    tester,
  ) async {
    final h = await pumpLegal(tester);
    h.exports.failNext = StateError('disk full');
    await _menu(h, 'Export Excel');
    expect(h.files.saved, isEmpty);
    await h.expectToast('Export failed');
  });
}
