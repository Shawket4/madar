// excel.ts / export-all.ts / download.ts, over the recording gateways.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart';
import 'package:flutter_test/flutter_test.dart';

class Row {
  const Row(this.name, this.total, this.at, {this.paid = true, this.qty = 1});

  final String name;
  final int total;
  final String at;
  final bool paid;
  final int qty;
}

Strings _strings() => Strings({
  'en': parseStringTable(File('assets/i18n/en.json').readAsStringSync()),
  'ar': parseStringTable(File('assets/i18n/ar.json').readAsStringSync()),
});

void main() {
  setUpAll(ensureTimeZones);

  final now = DateTime.utc(2026, 10, 8, 7, 30);
  final strings = _strings();
  late RecordingExportGateway exports;
  late RecordingFileGateway files;
  DashExporter exporter([String lang = 'en']) => DashExporter(
    exports: exports,
    files: files,
    format: DashFormat(lang: lang, clock: () => now),
    t: Translator(strings, lang),
    clock: () => now,
  );

  setUp(() {
    exports = RecordingExportGateway();
    files = RecordingFileGateway();
  });

  final rows = [
    const Row('Latte, oat', 6500, '2026-10-07T21:30:00Z', qty: 2),
    const Row('Espresso "double"', 4000, '2026-10-08T06:15:00Z', paid: false),
  ];
  final sheet = ExcelSheet<Row>(
    name: 'Orders: Oct/2026 [Maadi]*?',
    title: 'Orders',
    subtitle: 'Maadi',
    rows: rows,
    totals: true,
    stats: const [
      ExcelStat(label: 'Revenue', value: 105, type: 'money'),
      ExcelStat(label: 'Orders', value: 2, type: 'number'),
    ],
    columns: [
      ExcelColumn(header: 'Item', accessor: (r) => r.name),
      ExcelColumn(
        header: 'Total',
        accessor: (r) => r.total,
        type: ExcelColumnType.money,
        total: true,
      ),
      ExcelColumn(
        header: 'At',
        accessor: (r) => r.at,
        type: ExcelColumnType.dateTime,
        width: 24,
      ),
      ExcelColumn(
        header: 'Paid',
        accessor: (r) => r.paid,
        type: ExcelColumnType.bool,
      ),
      ExcelColumn(
        header: 'Qty',
        accessor: (r) => r.qty,
        type: ExcelColumnType.integer,
        total: true,
      ),
    ],
  );

  group('exportToExcel', () {
    test('builds the sheet exactly as buildSheet lays it out', () async {
      final out = await exporter().exportToExcel(
        ExcelConfig(filename: 'orders', meta: 'Sabah Coffee', sheets: [sheet]),
      );
      expect(out, isA<ExportDone>());
      final done = out as ExportDone;
      expect(done.rows, 2);
      expect(done.filename, 'orders-2026-10-08.xlsx');
      expect(files.saved.single.filename, 'orders-2026-10-08.xlsx');
      expect(files.saved.single.mimeType, MimeTypes.xlsx);
      expect(done.message(Translator(strings, 'en')), 'Exported 2 rows');

      final s = exports.built.single.sheets.single;
      expect(s.name, 'Orders Oct2026 Maadi');
      expect(s.title, 'Orders');
      expect(
        s.subtitle,
        'Maadi  ·  Sabah Coffee  ·  Generated: 08 Oct 2026, 10:30 AM',
      );
      expect(s.columns.map((c) => c.header), [
        'Item',
        'Total',
        'At',
        'Paid',
        'Qty',
      ]);
      expect(s.columns.map((c) => c.numFmt), [
        null, '#,##0.00 "EGP"', 'dd mmm yyyy hh:mm AM/PM', null, '#,##0', //
      ]);
      expect(s.columns.map((c) => c.width), [20, 20, 24, 20, 20]);
      expect(s.paddingWidths, [18]);
      // Money in pounds, dates as Excel serials on the branch's clock.
      expect(s.rows[0][0], 'Latte, oat');
      expect(s.rows[0][1], 65.0);
      expect(
        s.rows[0][2],
        toExcelDateSerial(
          DateTime.parse('2026-10-07T21:30:00Z'),
          'Africa/Cairo',
        ),
      );
      expect(s.rows[0][3], '✓');
      expect(s.rows[1][3], '—');
      expect(s.rows[0][4], 2);
      // Stat pills spread over the columns.
      expect(s.stats.map((x) => '${x.fromCol}:${x.toCol}'), ['A:B', 'C:D']);
      expect(s.stats.first.numFmt, '#,##0.00 "EGP"');
      // SUM over the data rows (8..9).
      final totals = s.totalsRow!;
      expect(totals[0], 'TOTALS');
      expect((totals[1]! as ExcelFormula).formula, 'SUM(B8:B9)');
      expect(totals[2], '');
      expect((totals[4]! as ExcelFormula).formula, 'SUM(E8:E9)');
      // The spec is plain JSON for the core's writer.
      final j = json.decode(json.encode(exports.built.single.toJson())) as Map;
      expect((j['sheets'] as List).single['totals_row'][1], {
        'formula': 'SUM(B8:B9)',
      });
      expect(j['palette']['brand'], 'FF0D6273');
    });

    test('Arabic words in the generated sheet', () async {
      await exporter(
        'ar',
      ).exportToExcel(ExcelConfig(filename: 'o', sheets: [sheet]));
      final s = exports.built.single.sheets.single;
      expect(s.totalsRow![0], strings.translate('ar', 'excel.totals'));
      expect(s.subtitle, contains(strings.translate('ar', 'excel.generated')));
    });

    test('nothing to export, and a failure, say so', () async {
      final empty = ExcelSheet<Row>(
        name: 'x',
        title: 'x',
        rows: const [],
        columns: sheet.columns,
      );
      final nothing = await exporter().exportToExcel(
        ExcelConfig(filename: 'x', sheets: [empty]),
      );
      expect(nothing, isA<ExportNothing>());
      expect(nothing.message(Translator(strings, 'en')), 'Nothing to export');
      expect(exports.built, isEmpty);
      exports.failNext = StateError('disk full');
      final failed = await exporter().exportToExcel(
        ExcelConfig(filename: 'x', sheets: [sheet]),
      );
      expect(failed, isA<ExportFailed>());
      expect(
        failed.message(Translator(strings, 'ar')),
        strings.translate('ar', 'excel.failed'),
      );
    });

    test('helpers: column letters, sheet names, cell values', () {
      expect(excelColumnLetter(0), 'A');
      expect(excelColumnLetter(25), 'Z');
      expect(excelColumnLetter(26), 'AA');
      expect(excelColumnLetter(701), 'ZZ');
      expect(cleanSheetName('a' * 40), 'a' * 31);
      expect(excelCellValue('12.5', ExcelColumnType.number, 'UTC'), 12.5);
      expect(excelCellValue('', ExcelColumnType.number, 'UTC'), 0);
      expect(excelCellValue('x', ExcelColumnType.integer, 'UTC'), 0);
      expect(excelCellValue('nope', ExcelColumnType.date, 'UTC'), isNull);
      expect(excelCellValue('abc', ExcelColumnType.money, 'UTC'), 0);
      expect(excelCellValue(0, ExcelColumnType.bool, 'UTC'), '—');
      expect(excelCellValue(3.0, null, 'UTC'), '3');
      expect(excelCellValue(null, ExcelColumnType.text, 'UTC'), isNull);
    });
  });

  group('exportToCsv', () {
    test('RFC 4180 quoting, pounds, ISO dates, CRLF', () async {
      final out = await exporter().exportToCsv(
        ExcelConfig(filename: 'orders', sheets: [sheet, sheet]),
      );
      expect(out, isA<ExportDone>());
      final f = files.saved.single;
      expect(f.filename, 'orders-2026-10-08.csv');
      expect(
        f.asString,
        'Item,Total,At,Paid,Qty\r\n'
        '"Latte, oat",65,2026-10-07T21:30:00.000Z,true,2\r\n'
        '"Espresso ""double""",40,2026-10-08T06:15:00.000Z,false,1',
      );
    });
  });

  group('fetchAllPages (export-all.ts)', () {
    test(
      'walks to an EMPTY page, advancing by what arrived (clamped limits)',
      () async {
        final asked = <(int, int)>[];
        final all = await fetchAllPages<int>((offset, limit) async {
          asked.add((offset, limit));
          // The endpoint clamps to 200.
          final rows = [
            for (var i = offset; i < offset + 200 && i < 450; i++) i,
          ];
          return ExportPage(rows);
        });
        expect(all, List.generate(450, (i) => i));
        expect(asked, [(0, 500), (200, 500), (400, 500), (450, 500)]);
      },
    );

    test('stops at the reported total', () async {
      var calls = 0;
      final all = await fetchAllPages<int>((offset, limit) async {
        calls++;
        return ExportPage(List.generate(limit, (i) => offset + i), total: 500);
      });
      expect(all, hasLength(500));
      expect(calls, 1);
    });

    test(
      'refuses past the ceiling, on the first page when the total says so',
      () async {
        var calls = 0;
        await expectLater(
          fetchAllPages<int>((o, l) async {
            calls++;
            return ExportPage(const [1], total: exportRowCeiling + 1);
          }),
          throwsA(
            isA<ExportTooLargeError>().having(
              (e) => e.rows,
              'rows',
              exportRowCeiling + 1,
            ),
          ),
        );
        expect(calls, 1);
        await expectLater(
          fetchAllPages<int>((o, l) async => ExportPage(List.filled(l, 0))),
          throwsA(isA<ExportTooLargeError>()),
        );
        expect(
          const ExportTooLargeError(61234).message(Translator(strings, 'en')),
          allOf(contains('61,234'), contains('50,000')),
        );
        expect(exportRequestHeaders, {'X-Madar-Export': '1'});
      },
    );
  });

  group('download.ts', () {
    test('a data: URI is decoded and saved', () async {
      final png = base64.encode([137, 80, 78, 71]);
      final where = await saveDataUri(
        files,
        'data:image/png;base64,$png',
        'qr.png',
      );
      expect(where, '/mock/downloads/qr.png');
      expect(files.saved.single.bytes, [137, 80, 78, 71]);
      expect(files.saved.single.mimeType, 'image/png');
      expect(
        () => saveDataUri(files, 'https://x/y.png', 'y.png'),
        throwsFormatException,
      );
    });

    test('a cancelled save is not an error', () async {
      files.cancelNextSave = true;
      final out = await exporter().exportToExcel(
        ExcelConfig(filename: 'o', sheets: [sheet]),
      );
      expect((out as ExportDone).savedTo, isNull);
    });
  });
}
