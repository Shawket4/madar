import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart' show RecordingFileGateway;
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/data/core_xlsx.dart';

/// A 4×2 lossless WebP: how the backend stores an org's logo.
const String _webpLogo = 'UklGRh4AAABXRUJQVlA4TBEAAAAvA0AAAAdQsTZ0rv+BiOh/AAA=';

void main() {
  test('the spec goes as JSON, the logo as bytes beside it', () {
    final (json, logo) = splitXlsxSpec({
      'creator': 'Madar',
      'logo': [1, 2, 3],
      'sheets': [
        {
          'rows': [
            [DateTime.utc(2026, 10, 8), 12.5],
          ],
        },
      ],
    });
    expect(logo, Uint8List.fromList([1, 2, 3]));
    expect(jsonDecode(json), {
      'creator': 'Madar',
      'sheets': [
        {
          'rows': [
            ['2026-10-08T00:00:00.000Z', 12.5],
          ],
        },
      ],
    });
    expect(splitXlsxSpec({'sheets': <Object?>[]}).$2, isNull);
  });

  test('the core\'s sheets decode to SheetData', () {
    final sheets = decodeSheets(
      '[{"name":"People","rows":[[null,"Name","Salary"],[null,"منى",6500,"2026-09-15"]]},'
      '{"name":"Notes","rows":[]}]',
    );
    expect(sheets.map((s) => s.name), ['People', 'Notes']);
    expect(sheets.first.rows, [
      [null, 'Name', 'Salary'],
      [null, 'منى', 6500, '2026-09-15'],
    ]);
    expect(sheets.last.rows, isEmpty);
  });

  test('the export gateway sends the laid-out spec, RTL and logo', () async {
    String? sentJson;
    Uint8List? sentLogo;
    String? askedLogo = 'unset';
    final gateway = CoreExportGateway(
      xlsx: CoreXlsx(
        writer: (json, logo) async {
          sentJson = json;
          sentLogo = logo;
          return Uint8List.fromList([0x50, 0x4B]);
        },
        reader: (bytes) async => '[{"name":"S","rows":[["a"]]}]',
      ),
      logo: (url) async {
        askedLogo = url;
        return Uint8List.fromList([9]);
      },
      rightToLeft: () => true,
    );
    const spec = WorkbookSpec(
      sheets: [
        SheetSpec(
          name: 'Orders',
          title: 'الطلبات',
          subtitle: 'Generated: 08 Oct 2026',
          columns: [ColumnSpec(header: 'Total', width: 20, numFmt: '#,##0')],
          paddingWidths: [18, 18, 18, 18, 18],
          stats: [],
          rows: [
            [12],
          ],
          totalsRow: ['TOTALS'],
        ),
      ],
    );
    final bytes = await gateway.buildXlsx(spec);
    expect(bytes, [0x50, 0x4B]);
    expect(askedLogo, isNull, reason: "null asks for Madar's own logo");
    expect(sentLogo, Uint8List.fromList([9]));
    final sent = jsonDecode(sentJson!) as Map<String, Object?>;
    expect(sent['rtl'], isTrue);
    expect(sent.containsKey('logo'), isFalse);
    final sheet = (sent['sheets']! as List).single as Map<String, Object?>;
    expect(sheet['title'], 'الطلبات');
    expect(sheet['header_row'], 7);
    expect(sheet['first_data_row'], 8);

    final read = await gateway.readXlsx(const [1]);
    expect(read.single.rows, [
      ['a'],
    ]);
  });

  test('left-to-right and logo-less by default', () async {
    String? sentJson;
    Uint8List? sentLogo = Uint8List(1);
    final gateway = CoreExportGateway(
      xlsx: CoreXlsx(
        writer: (json, logo) async {
          sentJson = json;
          sentLogo = logo;
          return Uint8List(0);
        },
      ),
    );
    await gateway.buildXlsx(const WorkbookSpec(sheets: []));
    expect(jsonDecode(sentJson!), isNot(contains('rtl')));
    expect(sentLogo, isNull);
  });

  // Through the real core: a sheet of tables (the recipe book) is laid out
  // in Dart, drawn by the writer and reads back where the web puts it.
  test(
    'a recipe book goes through the core: the tables, then the lines',
    () async {
      final now = DateTime.utc(2026, 10, 8, 7, 30);
      final files = RecordingFileGateway();
      const xlsx = CoreXlsx();
      final exporter = DashExporter(
        exports: const CoreExportGateway(xlsx: xlsx),
        files: files,
        format: DashFormat(lang: 'en', clock: () => now),
        t: Translator(Strings(const {}), 'en'),
        clock: () => now,
      );
      final outcome = await exporter.exportToExcel(
        ExcelConfig(
          filename: 'Madar-Recipes',
          doneMessage: 'Exported 1 recipe',
          sheets: [
            const ExcelBlockSheet(
              name: 'Recipes',
              title: 'Recipes',
              stats: [ExcelStat(label: 'Items', value: 1, type: 'number')],
              widths: [34, 9, 15],
              groups: [
                ExcelGroup(
                  group: 'Coffee',
                  blocks: [
                    ExcelBlock(
                      title: 'Latte',
                      note: 'Inactive',
                      header: ['Ingredient', 'Unit', 'Small'],
                      rows: [
                        [
                          'Beans',
                          'g',
                          ExcelCell(18.5, ExcelColumnType.quantity),
                        ],
                      ],
                      footer: [
                        ['Cost', null, ExcelCell(205, ExcelColumnType.money)],
                      ],
                      caption: "How it's made\n1. Pull a shot",
                    ),
                  ],
                ),
              ],
            ),
            ExcelSheet<(String, num)>(
              name: 'Ingredient lines',
              title: 'Ingredient lines',
              rows: const [('Beans', 18.5)],
              columns: [
                ExcelColumn(header: 'Ingredient', accessor: (r) => r.$1),
                ExcelColumn(
                  header: 'Quantity',
                  accessor: (r) => r.$2,
                  type: ExcelColumnType.quantity,
                ),
              ],
            ),
          ],
        ),
      );
      expect(
        outcome,
        isA<ExportDone>(),
        reason: outcome is ExportFailed ? '${outcome.error}' : null,
      );
      expect(
        outcome.message(Translator(Strings(const {}), 'en')),
        'Exported 1 recipe',
      );
      final sheets = await xlsx.read(files.saved.single.bytes);
      expect(sheets.map((s) => s.name), ['Recipes', 'Ingredient lines']);
      expect(sheets.first.rows, [
        ['Recipes'],
        ['Generated: 08 Oct 2026, 10:30 AM'],
        ['Items'],
        [1],
        ['Coffee'],
        ['Latte   Inactive'],
        ['Ingredient', 'Unit', 'Small'],
        ['Beans', 'g', 18.5],
        ['Cost', null, 2.05],
        ["How it's made\n1. Pull a shot"],
      ]);
      expect(sheets.last.rows.sublist(2), [
        ['Ingredient', 'Quantity'],
        ['Beans', 18.5],
      ]);
    },
  );

  // Through the real core: the writer used to refuse a WebP logo, so every
  // Excel export of a shop with its own logo said "Export failed" while the
  // web's went through.
  test('a branded shop exports with its WebP logo through the core', () async {
    final now = DateTime.utc(2026, 10, 8, 7, 30);
    final files = RecordingFileGateway();
    final exporter = DashExporter(
      exports: CoreExportGateway(logo: (_) async => base64Decode(_webpLogo)),
      files: files,
      format: DashFormat(lang: 'en', clock: () => now),
      t: Translator(Strings(const {}), 'en'),
      clock: () => now,
    );
    final outcome = await exporter.exportToExcel(
      ExcelConfig(
        filename: 'Madar-Customers',
        logoUrl: 'https://api.madar-pos.cloud/uploads/org/logos/g.webp',
        sheets: [
          ExcelSheet<(String, int)>(
            name: 'Customers',
            title: 'Customers',
            totals: true,
            rows: const [('Mona', 650000), ('Ali', 0)],
            columns: [
              ExcelColumn(header: 'Name', accessor: (r) => r.$1),
              ExcelColumn(
                header: 'Total spent',
                accessor: (r) => r.$2,
                type: ExcelColumnType.money,
                total: true,
              ),
            ],
          ),
        ],
      ),
    );
    expect(
      outcome,
      isA<ExportDone>(),
      reason: outcome is ExportFailed ? '${outcome.error}' : null,
    );
    final bytes = files.saved.single.bytes;
    expect(bytes.sublist(0, 2), [0x50, 0x4B], reason: 'an xlsx is a zip');
    expect(
      latin1.decode(bytes).contains('xl/media/image1.png'),
      isTrue,
      reason: 'the logo is drawn, as a PNG',
    );
  });
}
