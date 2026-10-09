// Operations' header export (REP-OPS-056…061) and the area's export rules
// as it uses them (REP-ALL-010…014, 025…027).
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/area_seed.dart';
import 'package:dashboard_reports/src/mock/operations_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get _export => inPage(find.byType(DashExportButton));

Future<void> _menu(DashHarness h, String item) async {
  await h.tap(_export);
  await h.tap(find.text(item).last);
}

/// The file name's UTC date stamp (the mock clock's).
String _stamp(DashHarness h) =>
    isoString(h.container.read(clockProvider)()).substring(0, 10);

List<MockRow> _orders(DashHarness h, List<String> branchIds) {
  final s = h.container.read(currentScopeProvider);
  return reportOrders(
    h.db!,
    branchIds: branchIds,
    from: DateTime.parse(s.from),
    to: DateTime.parse(s.to),
  );
}

void _expectExportRead(MockCall c) {
  expect(c.query['limit'], ['1000']);
  expect(c.headers['X-Madar-Export'], '1');
}

void main() {
  setUpAll(ensureTimeZones);

  testWidgets('REP-ALL-010 the export is a menu: "Export Excel" with a '
      'chevron, then Excel and CSV', (tester) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Items');
    final button = tester.widget<DashButton>(
      find.descendant(of: _export, matching: find.byType(DashButton)),
    );
    expect(button.label, 'Export Excel');
    expect(button.icon, 'download');
    expect(button.trailingIcon, 'chevron-down');
    await h.tap(_export);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('Export Excel'), findsNWidgets(2));
    await h.shot('operations/export-menu');
  });

  testWidgets('REP-OPS-056 / REP-ALL-011 / 025 Items to Excel: two sheets, '
      're-read with limit 1000 and the export header, the period as meta, '
      'Madar-Analytics-items-<date>.xlsx', (tester) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Items');
    final before = h.server.callsTo(itemsRoute).length;
    await _menu(h, 'Export Excel');
    final items = h.server.callsTo(itemsRoute);
    final addons = h.server.callsTo(addonsRoute);
    expect(items, hasLength(before + 1));
    _expectExportRead(items.last);
    _expectExportRead(addons.last);
    final spec = h.exports.built.single;
    expect([for (final s in spec.sheets) s.name], ['Items', 'Addon Sales']);
    expect(
      [for (final c in spec.sheets[0].columns) c.header],
      ['Name', 'Total sold'],
    );
    expect(spec.sheets[0].columns[0].width, 32);
    expect(
      [for (final c in spec.sheets[1].columns) c.header],
      ['Name', 'sold', 'Revenue'],
    );
    // The period as the meta line, then "Generated: …".
    expect(spec.sheets[0].subtitle, startsWith('Last 30 days'));
    expect(spec.sheets[0].subtitle, contains('Generated: '));
    // The totals row: TOTALS, then SUM.
    expect(spec.sheets[0].totalsRow!.first, 'TOTALS');
    expect(
      (spec.sheets[0].totalsRow![1]! as ExcelFormula).formula,
      startsWith('SUM(B'),
    );
    expect(
      (spec.sheets[1].totalsRow![2]! as ExcelFormula).formula,
      startsWith('SUM(C'),
    );
    // Money in pounds.
    final want = opsAddonSales(h.db!, _orders(h, SeedIds.sabahBranches));
    expect(spec.sheets[1].rows.first[2], want.first.revenue / 100);
    expect(spec.sheets[1].columns[2].numFmt, '#,##0.00 "EGP"');
    final file = h.files.saved.single;
    expect(file.filename, 'Madar-Analytics-items-${_stamp(h)}.xlsx');
    final rows = spec.sheets.fold<int>(0, (s, x) => s + x.rows.length);
    await h.expectToast('Exported $rows rows');
    // The org's own logo only with its own branding (REP-ALL-011).
    final brand = h.container.read(publicBrandProvider).value;
    expect(
      spec.logoUrl,
      (brand?.customBranding ?? false) ? brand?.logoUrl : isNull,
    );
  });

  testWidgets('REP-OPS-057 / REP-ALL-012 Items to CSV: the first sheet only, '
      'Madar-Analytics-items-<date>.csv, no spinner', (tester) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Items');
    await _menu(h, 'Export CSV');
    final file = h.files.saved.single;
    expect(file.filename, 'Madar-Analytics-items-${_stamp(h)}.csv');
    final lines = file.asString.split('\r\n');
    expect(lines.first, 'Name,Total sold');
    final want = opsCombinedItems(_orders(h, SeedIds.sabahBranches));
    expect(lines, hasLength(want.length + 1));
    expect(h.exports.built, isEmpty);
    await h.expectToast('Exported ${want.length} rows');
  });

  testWidgets('REP-OPS-058 Tellers: "Teller Details" with Role, Orders, '
      'Revenue, AOV, Order voided, Tills', (tester) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Tellers');
    await _menu(h, 'Export Excel');
    _expectExportRead(h.server.callsTo(tellersRoute).last);
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.name, 'Teller Details');
    expect(sheet.title, 'Teller Details');
    expect(
      [for (final c in sheet.columns) c.header],
      ['Role', 'Orders', 'Revenue', 'AOV', 'Order voided', 'Tills'],
    );
    // Totals on Orders, Revenue, voided, Tills; not AOV.
    final totals = sheet.totalsRow!;
    expect(totals[0], 'TOTALS');
    for (final i in [1, 2, 4, 5]) {
      expect(totals[i], isA<ExcelFormula>(), reason: '$i');
    }
    expect(totals[3], '');
    expect(
      h.files.saved.single.filename,
      'Madar-Analytics-tellers-${_stamp(h)}.xlsx',
    );
    await h.flushTimers();
  });

  testWidgets('REP-OPS-059 Waiters: the coverage subtitle with raw numbers', (
    tester,
  ) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Waiters');
    await _menu(h, 'Export Excel');
    _expectExportRead(h.server.callsTo(waitersRoute).last);
    final want = opsWaiterStats(_orders(h, SeedIds.sabahBranches));
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.name, 'Waiter Details');
    expect(
      sheet.subtitle,
      startsWith(
        '${want.attributedOrders} of ${want.totalOrders} orders came through '
        'waiters',
      ),
    );
    expect(
      [for (final c in sheet.columns) c.header],
      [
        'Waiter',
        'Orders',
        'Revenue',
        'AOV',
        'Items Sold',
        'Items / Order',
        'Order voided',
      ],
    );
    expect(
      h.files.saved.single.filename,
      'Madar-Analytics-waiters-${_stamp(h)}.xlsx',
    );
    await h.flushTimers();
  });

  testWidgets('REP-OPS-060 Branches: "Branch Details", void rate as a '
      'percent ratio', (tester) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Branches');
    await _menu(h, 'Export Excel');
    _expectExportRead(h.server.callsTo(comparisonRoute).last);
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.name, 'Branch Details');
    expect(
      [for (final c in sheet.columns) c.header],
      ['Branches', 'Orders', 'Revenue', 'AOV', 'Void Rate'],
    );
    expect(sheet.columns[4].numFmt, '0.0%');
    final rate = sheet.rows.first[4]! as num;
    expect(rate, lessThan(1));
    expect(sheet.rows, hasLength(4));
    expect(
      h.files.saved.single.filename,
      'Madar-Analytics-branches-${_stamp(h)}.xlsx',
    );
    await h.flushTimers();
  });

  testWidgets('REP-ALL-011 / 026 Excel: the spinner while it runs and '
      '"Gathering data…" once the rows are in', (tester) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Tellers');
    final done = Completer<void>();
    h.exports.hold = done.future;
    await _menu(h, 'Export Excel');
    final button = tester.widget<DashButton>(
      find.descendant(of: _export, matching: find.byType(DashButton)),
    );
    expect(button.loading, isTrue);
    expect(find.text('Gathering data…'), findsOneWidget);
    await h.shot('operations/export-running');
    done.complete();
    h.exports.hold = null;
    await h.settle();
    expect(
      tester
          .widget<DashButton>(
            find.descendant(of: _export, matching: find.byType(DashButton)),
          )
          .loading,
      isFalse,
    );
    await h.flushTimers();
  });

  testWidgets('REP-ALL-026 CSV: no spinner while the re-read runs', (
    tester,
  ) async {
    final s = opsServer();
    final h = await pumpOps(tester, server: s.server, db: s.db);
    await openTab(h, 'Tellers');
    final gate = s.server.hold('GET', tellersRoute);
    await _menu(h, 'Export CSV');
    expect(
      tester
          .widget<DashButton>(
            find.descendant(of: _export, matching: find.byType(DashButton)),
          )
          .loading,
      isFalse,
    );
    gate.release();
    await h.settle();
    await h.flushTimers();
  });

  testWidgets('REP-ALL-011 a failed build: "Export failed"', (tester) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Tellers');
    h.exports.failNext = StateError('disk full');
    await _menu(h, 'Export Excel');
    await h.expectToast('Export failed');
    expect(h.files.saved, isEmpty);
  });

  testWidgets('REP-ALL-013 nothing to export: "Nothing to export", no file '
      '(Excel and CSV)', (tester) async {
    final h = await pumpOps(tester);
    await h.container
        .read(scopeProvider.notifier)
        .setCustomRange('2026-01-01T00:00:00.000Z', '2026-01-02T00:00:00.000Z');
    await h.settle();
    await openTab(h, 'Tellers');
    await _menu(h, 'Export Excel');
    await h.expectToast('Nothing to export');
    await _menu(h, 'Export CSV');
    await h.expectToast('Nothing to export');
    expect(h.files.saved, isEmpty);
    expect(h.exports.built, isEmpty);
  });

  testWidgets('REP-OPS-061 / REP-ALL-014 a failed re-read: the server\'s '
      'words, the spinner stops', (tester) async {
    final s = opsServer();
    final h = await pumpOps(tester, server: s.server, db: s.db);
    await openTab(h, 'Waiters');
    final refusal = MockResponse.error(500, 'The waiters report is down');
    s.server.fail('GET', waitersRoute, refusal);
    await _menu(h, 'Export Excel');
    await h.expectToast(h.refusalWords(refusal));
    expect(
      tester
          .widget<DashButton>(
            find.descendant(of: _export, matching: find.byType(DashButton)),
          )
          .loading,
      isFalse,
    );
    s.server.fail('GET', waitersRoute, refusal);
    await _menu(h, 'Export CSV');
    await h.expectToast(h.refusalWords(refusal));
    expect(h.files.saved, isEmpty);
  });

  testWidgets('REP-ALL-027 the export throttle: past ten export reads a '
      'minute, 429 EXPORT_RATE_LIMITED in the language\'s words', (
    tester,
  ) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Items');
    // Each Items export is two counted reads: five exports use the ten.
    for (var i = 0; i < 5; i++) {
      await _menu(h, 'Export CSV');
      await h.flushTimers();
    }
    expect(h.files.saved, hasLength(5));
    await _menu(h, 'Export CSV');
    await h.expectToast('Too many exports just now. Try again in a minute.');
    expect(h.files.saved, hasLength(5));
    // The page's own reads are never counted.
    expect(
      h.server
          .callsTo(itemsRoute)
          .where((c) => c.headers['X-Madar-Export'] == null),
      hasLength(1),
    );
    // A minute later the budget is back.
    h.db!.clock.advance(const Duration(minutes: 1));
    await _menu(h, 'Export CSV');
    await h.flushTimers();
    expect(h.files.saved, hasLength(6));
  });

  testWidgets('REP-ALL-027 Arabic: the throttle\'s words in Arabic', (
    tester,
  ) async {
    final s = opsServer();
    final h = await pumpOps(
      tester,
      server: s.server,
      db: s.db,
      locale: 'ar',
      size: DashSize.phone,
    );
    await openTab(h, h.t('reports.operations.tabs.tellers'));
    s.server.fail(
      'GET',
      tellersRoute,
      MockResponse.error(
        429,
        'That is 10 exports in a minute.',
        code: 'EXPORT_RATE_LIMITED',
      ),
    );
    await _menu(h, h.t('common.exportCsv'));
    await h.expectToast(h.t('errors.codes.EXPORT_RATE_LIMITED'));
  });
}
