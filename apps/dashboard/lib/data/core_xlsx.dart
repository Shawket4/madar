/// Spreadsheet export and import in the core (real mode): `xlsx_write` draws
/// the workbook dashboard_core's [WorkbookSpec] lays out (the web's
/// `src/lib/excel.ts`), `xlsx_read` reads every sheet of a picked file (the
/// web's `readSheet`). Pure conversions are top-level functions the tests
/// drive without the native library.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_core/dashboard_core.dart'
    show ExportGateway, SheetData, WorkbookSpec;
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart' as rb;

/// Writes `.xlsx` bytes from a spec JSON (+ the banner logo).
typedef XlsxWriter =
    Future<Uint8List> Function(String specJson, Uint8List? logo);

/// Reads a file's sheets as JSON.
typedef XlsxReader = Future<String> Function(List<int> bytes);

/// The banner logo for a workbook (`logoUrl` null = Madar's own); null draws
/// none.
typedef LogoLoader = Future<Uint8List?> Function(String? logoUrl);

Future<Uint8List> _bridgeWrite(String specJson, Uint8List? logo) =>
    rb.xlsxWrite(specJson: specJson, logo: logo);

Future<String> _bridgeRead(List<int> bytes) => rb.xlsxRead(bytes: bytes);

/// The core's xlsx writer and reader. A failure is the core's [rb.MadarError]
/// (`Validation` for a bad spec or an unreadable file).
class CoreXlsx {
  const CoreXlsx({XlsxWriter? writer, XlsxReader? reader})
    : _write = writer ?? _bridgeWrite,
      _read = reader ?? _bridgeRead;

  final XlsxWriter _write;
  final XlsxReader _read;

  /// The `.xlsx` bytes for [spec] (a `WorkbookSpec.toJson()`, optionally with
  /// `"rtl": true`). A `logo` entry holding image bytes is drawn in each
  /// sheet's banner and not sent as JSON.
  Future<Uint8List> write(Map<String, Object?> spec) {
    final (json, logo) = splitXlsxSpec(spec);
    return _write(json, logo);
  }

  /// Every sheet of [bytes], in order.
  Future<List<SheetData>> read(List<int> bytes) async =>
      decodeSheets(await _read(bytes));
}

/// [ExportGateway] over the core. [rightToLeft] turns the sheets
/// right-to-left (an Arabic export; the web never does); [logo] supplies the
/// banner image.
class CoreExportGateway implements ExportGateway {
  const CoreExportGateway({
    this.xlsx = const CoreXlsx(),
    this.logo,
    this.rightToLeft,
  });

  final CoreXlsx xlsx;
  final LogoLoader? logo;
  final bool Function()? rightToLeft;

  @override
  Future<List<int>> buildXlsx(WorkbookSpec spec) async {
    final image = await logo?.call(spec.logoUrl);
    return xlsx.write({
      ...spec.toJson(),
      if (rightToLeft?.call() ?? false) 'rtl': true,
      'logo': ?image,
    });
  }

  @override
  Future<List<SheetData>> readXlsx(List<int> bytes) => xlsx.read(bytes);
}

/// [spec] as the JSON the core reads and the logo bytes beside it. A
/// `DateTime` anywhere becomes its ISO-8601 UTC text.
(String, Uint8List?) splitXlsxSpec(Map<String, Object?> spec) {
  final rest = Map<String, Object?>.of(spec);
  final logo = rest.remove('logo');
  final bytes = switch (logo) {
    final Uint8List b => b,
    final List<int> b => Uint8List.fromList(b),
    _ => null,
  };
  final json = jsonEncode(
    rest,
    toEncodable: (v) => v is DateTime ? v.toUtc().toIso8601String() : v,
  );
  return (json, bytes);
}

/// The core's `[{name, rows}]` as [SheetData]: cells are String, int,
/// double, bool or null (a date cell reads `YYYY-MM-DD`, as on the web).
List<SheetData> decodeSheets(String json) {
  final sheets = jsonDecode(json) as List<Object?>;
  return [
    for (final s in sheets.cast<Map<String, Object?>>())
      SheetData(
        name: s['name']! as String,
        rows: [
          for (final r in (s['rows']! as List<Object?>).cast<List<Object?>>())
            List<Object?>.of(r),
        ],
      ),
  ];
}
