// excel.ts / export-all.ts / download.ts, over the recording gateways.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_api/dashboard_api.dart' show PublicBrand;
import 'package:dashboard_api/mock.dart' show MockResponse, MockServer;
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

  group('ADM-APP-126: exportToExcel', () {
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

  // excel.test.ts "a sheet of tables": the same sheet, laid out into the
  // spec the core's writer draws (rust-core xlsx.rs reads this layout back).
  group('a sheet of tables (buildBlockSheet)', () {
    const recipes = ExcelBlockSheet(
      name: 'Recipes',
      title: 'Recipes',
      stats: [ExcelStat(label: 'Items', value: 1, type: 'number')],
      widths: [30, 8, 14, 14],
      groups: [
        ExcelGroup(
          group: 'Coffee',
          blocks: [
            ExcelBlock(
              title: 'Latte',
              note: 'Follows Flat white',
              header: ['Ingredient', 'Unit', 'Small', 'Large'],
              rows: [
                [
                  'Espresso beans',
                  'g',
                  ExcelCell(18, ExcelColumnType.quantity),
                  ExcelCell(18.5, ExcelColumnType.quantity),
                ],
                [
                  'Vanilla syrup',
                  'ml',
                  null,
                  ExcelCell(20, ExcelColumnType.quantity),
                ],
              ],
              footer: [
                [
                  'Cost',
                  null,
                  ExcelCell(205, ExcelColumnType.money),
                  ExcelCell(285, ExcelColumnType.money),
                ],
              ],
              caption: "How it's made: 1. Pull a double shot",
            ),
          ],
        ),
      ],
    );
    const egp = '#,##0.00 "EGP"';

    test('every sheet\'s head, then the group band and each table in order, '
        'from row 7', () async {
      final out = await exporter().exportToExcel(
        const ExcelConfig(
          filename: 'recipes',
          meta: 'Coffee',
          sheets: [recipes],
          doneMessage: 'Exported 1 recipe',
        ),
      );
      expect(out, isA<ExportDone>());
      expect(files.saved.single.filename, 'recipes-2026-10-08.xlsx');
      final built = exports.built.single;
      expect(built.sheets, isEmpty, reason: 'no table sheet in this book');
      final s = built.allSheets.single as BlockSheetSpec;
      expect(s.name, 'Recipes');
      expect(s.title, 'Recipes');
      expect(s.subtitle, 'Coffee  ·  Generated: 08 Oct 2026, 10:30 AM');
      // Padded to six, like every sheet.
      expect(s.widths, [30, 8, 14, 14, 18, 18]);
      // The pills share out the table's own columns, not the padding.
      expect(s.stats.single.label, 'Items');
      expect('${s.stats.single.fromCol}:${s.stats.single.toCol}', 'A:D');
      expect(s.stats.single.numFmt, '#,##0');

      String line(BlockRowSpec r) =>
          '${r.row} ${r.kind.name} ${r.height}'
          '${r.text == null ? '' : ' "${r.text}"'}'
          '${r.note == null ? '' : ' note "${r.note}"'}'
          '${r.cells.isEmpty ? '' : ' ${r.cells}'}'
          '${r.zebra ? ' zebra' : ''}${r.ruled ? ' ruled' : ''}';
      expect(s.rows.map(line), [
        '7 group 24 "Coffee"',
        '8 gap 6',
        '9 title 22 "Latte" note "   Follows Flat white"',
        '10 header 22 [Ingredient, Unit, Small, Large]',
        '11 body 20 [Espresso beans, g, 18, 18.5] zebra',
        // A size without the line is a blank, still striped (white).
        '12 body 20 [Vanilla syrup, ml, null, 20]',
        // Money is piastres ÷ 100, bold, ruled above.
        '13 footer 20 [Cost, null, 2.05, 2.85] ruled',
        '14 caption 18 "How it\'s made: 1. Pull a double shot"',
        '15 gap 10',
      ]);
      // No fixed decimals on a quantity (Excel's General); EGP on money.
      expect(s.rows[4].numFmts, [null, null, null, null]);
      expect(s.rows[6].numFmts, [null, null, egp, egp]);

      final j = json.decode(json.encode(built.toJson())) as Map;
      final sheet = (j['sheets'] as List).single as Map;
      expect(sheet['kind'], 'blocks');
      expect(sheet['widths'], [30, 8, 14, 14, 18, 18]);
      expect((sheet['rows'] as List)[6], {
        'kind': 'footer',
        'row': 13,
        'height': 20,
        'cells': ['Cost', null, 2.05, 2.85],
        'num_fmts': [null, null, egp, egp],
        'ruled': true,
      });
      expect((sheet['rows'] as List)[2], {
        'kind': 'title',
        'row': 9,
        'height': 22,
        'text': 'Latte',
        'note': '   Follows Flat white',
      });
    });

    test('counts tables, not rows, and says what it was told to', () async {
      final out = await exporter().exportToExcel(
        const ExcelConfig(
          filename: 'recipes',
          sheets: [recipes],
          doneMessage: 'Exported 1 recipe',
        ),
      );
      expect((out as ExportDone).rows, 1);
      expect(out.message(Translator(strings, 'en')), 'Exported 1 recipe');
      final nothing = await exporter().exportToExcel(
        const ExcelConfig(
          filename: 'recipes',
          sheets: [
            ExcelBlockSheet(
              name: 'Recipes',
              title: 'Recipes',
              widths: [30],
              groups: [],
            ),
          ],
        ),
      );
      expect(nothing, isA<ExportNothing>());
    });

    test('a table with no header, a note-less title, no caption', () {
      final spec = exporter().workbookSpec(
        const ExcelConfig(
          filename: 'r',
          sheets: [
            ExcelBlockSheet(
              name: 'R',
              title: 'R',
              widths: [34],
              groups: [
                ExcelGroup(
                  group: 'No recipe yet',
                  blocks: [
                    ExcelBlock(
                      title: '2 items',
                      note: '',
                      header: ['Item'],
                      rows: [
                        ['Water'],
                        ['Tea  ·  Hot'],
                      ],
                    ),
                    ExcelBlock(title: 'Bare', header: [], rows: []),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      final s = spec.allSheets.single as BlockSheetSpec;
      expect(s.rows.map((r) => '${r.row} ${r.kind.name}'), [
        '7 group',
        '8 gap',
        '9 title',
        '10 header',
        '11 body',
        '12 body',
        '13 gap',
        '14 title',
        '15 gap',
      ]);
      expect(s.rows[2].note, isNull, reason: 'an empty note is no note');
      expect(s.stats, isEmpty);
    });

    test('a book and a table sheet in one workbook, in order; the table '
        'sheet\'s JSON is unchanged', () async {
      final spec = exporter().workbookSpec(
        ExcelConfig(filename: 'r', sheets: [recipes, sheet]),
      );
      expect(spec.allSheets.map((s) => s.runtimeType), [
        BlockSheetSpec,
        SheetSpec,
      ]);
      expect(spec.sheets.single.title, 'Orders');
      final j = json.decode(json.encode(spec.toJson())) as Map;
      final sheets = j['sheets'] as List;
      expect(sheets.first['kind'], 'blocks');
      expect((sheets.last as Map).keys, [
        'name',
        'title',
        'subtitle',
        'columns',
        'padding_widths',
        'stats',
        'rows',
        'totals_row',
        'header_row',
        'first_data_row',
      ]);
    });

    test('a CSV is the table sheets only: a sheet of tables has no flat '
        'form', () async {
      final out = await exporter().exportToCsv(
        ExcelConfig(filename: 'lines', sheets: [recipes, sheet]),
      );
      expect(out, isA<ExportDone>());
      expect(files.saved.single.asString, startsWith('Item,Total,At'));
      final none = await exporter().exportToCsv(
        const ExcelConfig(filename: 'lines', sheets: [recipes]),
      );
      expect(none, isA<ExportNothing>());
    });

    test('captionHeight: one 12 pt line per width-unit-and-a-tenth, at '
        'least 18', () {
      const widths = <double>[34, 9, 15, 15, 18, 18]; // 109 → 119 a line
      expect(captionHeight('short', widths), 18);
      expect(captionHeight('a\nb\nc', widths), 42);
      expect(captionHeight('x' * 120, widths), 30);
      expect(
        captionHeight('x' * 10, const <double>[2]),
        18,
        reason: '20 a line',
      );
      expect(captionHeight('x' * 41, const <double>[2]), 42);
    });

    test('quantity: an amount as it is, in General', () {
      expect(excelNumFmt(ExcelColumnType.quantity), isNull);
      expect(excelCellValue(18.0, ExcelColumnType.quantity, 'UTC'), 18);
      expect(excelCellValue('12.25', ExcelColumnType.quantity, 'UTC'), 12.25);
      expect(excelCellValue('x', ExcelColumnType.quantity, 'UTC'), 0);
      expect(
        const ExcelCell(18, ExcelColumnType.quantity),
        const ExcelCell(18.0, ExcelColumnType.quantity),
      );
      expect(
        const ExcelCell(18, ExcelColumnType.quantity),
        isNot(const ExcelCell(18, ExcelColumnType.money)),
      );
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

  test('export logo: the own brand only, trimmed, blank is none '
      '(use-brand.ts, use-export-logo.ts)', () {
    PublicBrand brand({required bool own, String? logo}) => PublicBrand(
      accentColor: '#000000',
      backgroundColor: '#ffffff',
      customBranding: own,
      foregroundColor: '#000000',
      logoIsMark: false,
      logoUrl: logo,
      name: 'Sabah',
      orgId: 'org',
    );
    expect(exportLogoUrl(null), isNull); // null = Madar's logo
    expect(
      exportLogoUrl(brand(own: true, logo: ' https://x/l.png ')),
      'https://x/l.png',
    );
    expect(exportLogoUrl(brand(own: true, logo: '   ')), isNull);
    expect(exportLogoUrl(brand(own: true)), isNull);
    expect(exportLogoUrl(brand(own: false, logo: 'https://x/l.png')), isNull);
  });

  test('apiWithHeaders: every request carries the export mark '
      '(EXPORT_REQUEST)', () async {
    final server = MockServer()
      ..on('GET', '/branches', (_) => MockResponse.ok(const <Object?>[]));
    await apiWithHeaders(
      server,
      exportRequestHeaders,
    ).branches.listBranches(orgId: 'o');
    expect(server.calls.single.headers['X-Madar-Export'], '1');
  });
}
