import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/data/core_xlsx.dart';

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
}
