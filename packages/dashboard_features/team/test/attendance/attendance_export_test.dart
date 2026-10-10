// Export Excel on the Attendance page (TEAM-ATT-021, TEAM-ALL-024): the
// page's query again with `X-Madar-Export: 1`, one branded sheet, and the
// toasts of `exportToExcel`.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'attendance_support.dart';

List<MockCall> exportCalls(DashHarness h) => h.server
    .callsTo(listT, method: 'GET')
    .where((c) => c.headers['X-Madar-Export'] == '1')
    .toList();

Finder exportButton() => inPage(find.byType(DashExportButton));

/// Two records: Laila's phone punch at Zamalek, Omar's manager punch at a
/// Tokyo branch, auto-closed.
List<MockRow> twoRows() => [
  recordRow(
    id: 'r-laila',
    employeeKey: 'laila',
    date: day(-1),
    status: 'late',
    workShiftName: 'Morning',
    inAt: cairo(day(-1), '09:02'),
    outAt: cairo(day(-1), '17:00'),
    inMethod: 'mobile_gps',
    outMethod: 'mobile_gps',
    late: 2,
    early: 30,
    worked: 478,
    distance: 14.6,
  ),
  recordRow(
    id: 'r-omar',
    employeeKey: 'omar',
    date: day(-2),
    branchId: SeedIds.heliopolis,
    inAt: '${day(-2)}T00:00:00.000Z',
    outAt: '${day(-2)}T09:00:00.000Z',
    inMethod: 'manager',
    outMethod: 'auto',
    worked: 540,
    overtime: 45,
    punchReason: 'Phone died',
  ),
];

void main() {
  testWidgets('TEAM-ATT-021 / TEAM-ALL-024 Export Excel re-reads the window '
      'as an export and writes Madar-Attendance-<date>.xlsx: one sheet, the '
      'status as its subtitle, from → to, the totals', (tester) async {
    final h = await pumpAttendance(tester);
    final rows = windowRows(h.db!).length;
    await h.tap(exportButton());
    final call = exportCalls(h).single;
    expect(call.query, {
      'from': [day(-6)],
      'to': [day()],
    });
    await h.expectToast('Exported $rows rows', keep: true);
    expect(find.text('Gathering data…'), findsNothing);
    expect(h.files.saved.single.filename, 'Madar-Attendance-2026-10-08.xlsx');
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.name, 'Attendance');
    expect(sheet.title, 'Attendance');
    expect(
      sheet.subtitle,
      startsWith('All statuses  ·  ${day(-6)} → ${day()}  ·  Generated: '),
    );
    expect(
      [for (final c in sheet.columns) c.header],
      [
        'Name',
        'Work shift',
        'Date',
        'Status',
        'In',
        'In distance (m)',
        'Out',
        'Auto-closed',
        'In by',
        'Out by',
        'Why punched in',
        'Why punched out',
        'Worked (minutes)',
        'Late (minutes)',
        'Left early (minutes)',
        'Overtime (minutes)',
      ],
    );
    expect(sheet.rows, hasLength(rows));
    final last = 7 + rows;
    expect(sheet.totalsRow!.first, 'TOTALS');
    expect(
      [for (final c in sheet.totalsRow!.skip(12)) (c! as ExcelFormula).formula],
      ['SUM(M8:M$last)', 'SUM(N8:N$last)', 'SUM(O8:O$last)', 'SUM(P8:P$last)'],
    );
    await h.flushTimers();
  });

  testWidgets('TEAM-ALL-024 the cells: words for status and methods, ✓/— '
      'for auto-closed, minutes as numbers, In/Out on the ACTIVE zone\'s '
      'clock', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) {
        db['branches'].find(SeedIds.heliopolis)!['timezone'] = 'Asia/Tokyo';
        onlyRecords(db, twoRows());
      },
    );
    await h.tap(exportButton());
    await h.flushTimers();
    final rows = h.exports.built.single.sheets.single.rows;
    final laila = rows.firstWhere((r) => r.first == 'Laila Ehab');
    final omar = rows.firstWhere((r) => r.first == 'Omar Khaled');
    expect(laila.sublist(0, 2), ['Laila Ehab', 'Morning']);
    expect(laila[3], 'Late');
    expect(laila[5], 15);
    expect(laila[7], '—');
    expect(laila.sublist(8, 12), ['', '', '', '']);
    expect(laila.sublist(12), [478, 2, 30, 0]);
    expect(omar[1], 'Unscheduled');
    expect(omar[5], isNull);
    expect(omar[7], '✓');
    expect(omar.sublist(8, 11), ['by a manager', 'auto-closed', 'Phone died']);
    // 00:00Z at the Tokyo branch is written on Cairo's clock (03:00).
    expect(
      omar[4],
      toExcelDateSerial(DateTime.parse('${day(-2)}T00:00:00Z'), 'Africa/Cairo'),
    );
  });

  testWidgets('TEAM-ATT-021 the status filter is the subtitle and part of '
      'the re-read; the search box never narrows the file', (tester) async {
    final h = await pumpAttendance(tester);
    await h.tap(pageText('All statuses'));
    await h.tap(find.text('Late').hitTestable());
    final late = windowRows(h.db!).where((r) => r['status'] == 'late').length;
    await h.enterText(inPage(find.byType(DashSearchInput)), 'adham');
    await h.settle();
    await h.tap(exportButton());
    expect(exportCalls(h).single.query['status'], ['late']);
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.subtitle, startsWith('Late  ·  '));
    expect(sheet.rows, hasLength(late));
    await h.flushTimers();
  });

  testWidgets('TEAM-ALL-024 nothing came back: "Nothing to export", no file', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    onlyRecords(h.db!, []);
    await h.tap(exportButton());
    await h.expectToast('Nothing to export');
    expect(h.exports.built, isEmpty);
    expect(h.files.saved, isEmpty);
  });

  testWidgets('TEAM-ALL-024 a failed write: "Export failed"; the button is '
      'busy meanwhile', (tester) async {
    final h = await pumpAttendance(tester);
    final hold = Completer<void>();
    h.exports
      ..hold = hold.future
      ..failNext = Exception('disk full');
    await h.tap(exportButton());
    expect(tester.widget<DashExportButton>(exportButton()).loading, isTrue);
    expect(find.text('Gathering data…'), findsOneWidget);
    hold.complete();
    await h.settle();
    await h.expectToast('Export failed', keep: true);
    expect(tester.widget<DashExportButton>(exportButton()).loading, isFalse);
    expect(h.files.saved, isEmpty);
    await h.flushTimers();
  });

  testWidgets('TEAM-ATT-021 a refused re-read toasts the refusal\'s words', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    h.server.fail('GET', listT, MockResponse.error(429, 'Too many requests'));
    await h.tap(exportButton());
    await h.expectToast(h.t('errors.tooManyRequests'));
    expect(h.exports.built, isEmpty);
    expect(tester.widget<DashExportButton>(exportButton()).loading, isFalse);
  });

  testWidgets('TEAM-ATT-021 disabled with no rows', (tester) async {
    await pumpAttendance(tester, edit: (db) => onlyRecords(db, []));
    expect(tester.widget<DashExportButton>(exportButton()).enabled, isFalse);
  });
}
