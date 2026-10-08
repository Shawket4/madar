/// Spreadsheet export and import: the web's `src/lib/excel.ts` (the branded
/// workbook and the CSV sibling) and `src/lib/export-all.ts` (walking a paged
/// list to the end, with a hard ceiling).
///
/// Everything excel.ts decides (cell values, number formats, the banner,
/// subtitle, stat pills, zebra rows, the SUM totals row) is decided HERE, into
/// a [WorkbookSpec]; [ExportGateway.buildXlsx] only writes it to bytes (the
/// core's xlsx writer in real mode, a recorder in tests).
library;

import 'package:dashboard_core/src/format/format.dart';
import 'package:dashboard_core/src/format/icu_number.dart';
import 'package:dashboard_core/src/format/tz.dart';
import 'package:dashboard_core/src/gateways/files.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `ColumnType`.
enum ExcelColumnType {
  text,
  money,
  moneyRaw,
  number,
  integer,
  percent,
  date,
  dateTime,
  bool,
}

/// One column (`ExcelColumn<T>`).
class ExcelColumn<T> {
  const ExcelColumn({
    required this.header,
    required this.accessor,
    this.key,
    this.type,
    this.width,
    this.total = false,
  });

  final String? key;
  final String header;

  /// The raw value: String, num, DateTime, bool or null.
  final Object? Function(T row) accessor;
  final ExcelColumnType? type;
  final double? width;

  /// Include in the SUM totals row.
  final bool total;
}

/// A stat pill above the table (`ExcelStat`).
class ExcelStat {
  const ExcelStat({required this.label, required this.value, this.type});

  final String label;

  /// num or String.
  final Object value;

  /// `money`, `number` or `text` (null = text).
  final String? type;
}

/// One sheet (`ExcelSheet<T>`).
class ExcelSheet<T> {
  const ExcelSheet({
    required this.name,
    required this.title,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.stats = const [],
    this.totals = false,
  });

  final String name;
  final String title;
  final String? subtitle;
  final List<ExcelColumn<T>> columns;
  final List<T> rows;
  final List<ExcelStat> stats;
  final bool totals;

  int get rowCount => rows.length;

  /// Each row's raw values, column by column (typed here, where `T` is known).
  List<List<Object?>> rawRows() => [
    for (final r in rows) [for (final c in columns) c.accessor(r)],
  ];

  List<ExcelColumnType?> get columnTypes => [for (final c in columns) c.type];
}

/// `ExcelConfig` / `CsvConfig`.
class ExcelConfig {
  const ExcelConfig({
    required this.filename,
    required this.sheets,
    this.meta,
    this.logoUrl,
  });

  final String filename;
  final String? meta;

  /// The banner logo; null = Madar's.
  final String? logoUrl;
  final List<ExcelSheet<Object?>> sheets;
}

/// The workbook palette (`PALETTE`, ARGB).
abstract final class ExcelPalette {
  static const String brand = 'FF0D6273';
  static const String accent = 'FF2E94A6';
  static const String white = 'FFFFFFFF';
  static const String zebra = 'FFEDF2F3';
  static const String border = 'FFD7E0E1';
  static const String text = 'FF14181E';
  static const String muted = 'FF76828B';
}

/// `numFmt(type)`.
String? excelNumFmt(ExcelColumnType? type) => switch (type) {
  ExcelColumnType.money || ExcelColumnType.moneyRaw => '#,##0.00 "EGP"',
  ExcelColumnType.number => '#,##0.00',
  ExcelColumnType.integer => '#,##0',
  ExcelColumnType.percent => '0.0%',
  ExcelColumnType.date => 'dd mmm yyyy',
  ExcelColumnType.dateTime => 'dd mmm yyyy hh:mm AM/PM',
  _ => null,
};

/// `colLetter(0)` = `A`, 26 = `AA`.
String excelColumnLetter(int index) {
  var n = index;
  var s = '';
  do {
    s = String.fromCharCode(65 + n % 26) + s;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return s;
}

/// `cleanSheetName`: no `: \ / ? * [ ]`, at most 31 characters.
String cleanSheetName(String name) {
  final s = name.replaceAll(RegExp(r'[:\\/?*\[\]]'), '');
  return s.length > 31 ? s.substring(0, 31) : s;
}

num _jsNumber(Object raw) {
  if (raw is num) return raw.isNaN ? 0 : raw;
  if (raw is bool) return raw ? 1 : 0;
  final s = raw.toString().trim();
  if (s.isEmpty) return 0;
  final v = num.tryParse(s);
  return (v == null || v.isNaN) ? 0 : v;
}

bool _truthy(Object raw) => switch (raw) {
  final bool b => b,
  final num n => n != 0 && !n.isNaN,
  final String s => s.isNotEmpty,
  _ => true,
};

/// `coerce(raw, type)`: the value a cell holds. Dates become Excel serials on
/// [zone]'s wall clock.
Object? excelCellValue(Object? raw, ExcelColumnType? type, String zone) {
  if (raw == null) return null;
  switch (type) {
    case ExcelColumnType.money:
      return raw is num ? raw / 100 : 0;
    case ExcelColumnType.moneyRaw:
    case ExcelColumnType.number:
    case ExcelColumnType.integer:
    case ExcelColumnType.percent:
      return raw is num ? raw : _jsNumber(raw);
    case ExcelColumnType.date:
    case ExcelColumnType.dateTime:
      final d = parseJsDate(raw is DateTime ? raw : raw.toString());
      if (d == null) return null;
      return toExcelDateSerial(d, zone);
    case ExcelColumnType.bool:
      return _truthy(raw) ? '✓' : '—';
    case ExcelColumnType.text:
    case null:
      return raw is String ? raw : _jsString(raw);
  }
}

String _jsString(Object raw) {
  if (raw is double &&
      raw.isFinite &&
      raw == raw.truncateToDouble() &&
      raw.abs() < 1e21) {
    return raw.toInt().toString();
  }
  if (raw is DateTime) return raw.toString();
  return raw.toString();
}

/// A formula cell.
class ExcelFormula {
  const ExcelFormula(this.formula);

  final String formula;

  Map<String, Object?> toJson() => {'formula': formula};
}

/// A stat pill, laid out: merged over [fromCol]..[toCol] in rows 4-5.
class StatSpec {
  const StatSpec({
    required this.label,
    required this.value,
    required this.fromCol,
    required this.toCol,
    this.numFmt,
  });

  final String label;
  final Object value;
  final String fromCol;
  final String toCol;
  final String? numFmt;

  Map<String, Object?> toJson() => {
    'label': label,
    'value': value,
    'from_col': fromCol,
    'to_col': toCol,
    'num_fmt': numFmt,
  };
}

/// One column, laid out.
class ColumnSpec {
  const ColumnSpec({required this.header, required this.width, this.numFmt});

  final String header;
  final double width;
  final String? numFmt;

  Map<String, Object?> toJson() => {
    'header': header,
    'width': width,
    'num_fmt': numFmt,
  };
}

/// One sheet exactly as `buildSheet` lays it out: banner (row 1, merged to
/// the padded width, title right-aligned, logo top-left), subtitle (row 2),
/// spacer, stat pills (rows 4-5), spacer, header (row 7, frozen), data from
/// row 8 with zebra fill, then the totals row.
class SheetSpec {
  const SheetSpec({
    required this.name,
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.paddingWidths,
    required this.stats,
    required this.rows,
    this.totalsRow,
  });

  final String name;
  final String title;
  final String subtitle;
  final List<ColumnSpec> columns;

  /// Extra empty columns so the banner spans at least six (width 18 each).
  final List<double> paddingWidths;
  final List<StatSpec> stats;

  /// Cells: num, String, null.
  final List<List<Object?>> rows;

  /// Cells: [ExcelFormula], String.
  final List<Object?>? totalsRow;

  static const int headerRow = 7;
  static const int firstDataRow = 8;

  Map<String, Object?> toJson() => {
    'name': name,
    'title': title,
    'subtitle': subtitle,
    'columns': [for (final c in columns) c.toJson()],
    'padding_widths': paddingWidths,
    'stats': [for (final s in stats) s.toJson()],
    'rows': rows,
    'totals_row': totalsRow == null
        ? null
        : [for (final c in totalsRow!) c is ExcelFormula ? c.toJson() : c],
    'header_row': headerRow,
    'first_data_row': firstDataRow,
  };
}

/// A whole workbook, ready to write.
class WorkbookSpec {
  const WorkbookSpec({
    required this.sheets,
    this.creator = 'Madar',
    this.logoUrl,
  });

  final String creator;

  /// Null = Madar's own logo.
  final String? logoUrl;
  final List<SheetSpec> sheets;

  Map<String, Object?> toJson() => {
    'creator': creator,
    'logo_url': logoUrl,
    'palette': {
      'brand': ExcelPalette.brand,
      'accent': ExcelPalette.accent,
      'white': ExcelPalette.white,
      'zebra': ExcelPalette.zebra,
      'border': ExcelPalette.border,
      'text': ExcelPalette.text,
      'muted': ExcelPalette.muted,
    },
    'sheets': [for (final s in sheets) s.toJson()],
  };
}

/// One sheet read from an imported workbook: rows of cell values (String,
/// num, bool, DateTime or null), the first row usually the header.
class SheetData {
  const SheetData({required this.name, required this.rows});

  final String name;
  final List<List<Object?>> rows;
}

/// Writes and reads `.xlsx` (real mode: the core).
abstract interface class ExportGateway {
  /// The workbook's bytes.
  Future<List<int>> buildXlsx(WorkbookSpec spec);

  /// Every sheet of an `.xlsx` file the person picked.
  Future<List<SheetData>> readXlsx(List<int> bytes);
}

final exportGatewayProvider = Provider<ExportGateway>(
  (ref) => throw StateError('exportGatewayProvider must be overridden at boot'),
);

/// What an export came to. [message] is the toast the web shows.
sealed class ExportOutcome {
  const ExportOutcome();

  String message(Translator t);
}

/// Every sheet was empty (`excel.nothingToExport`, an error toast).
class ExportNothing extends ExportOutcome {
  const ExportNothing();

  @override
  String message(Translator t) =>
      t('excel.nothingToExport', defaultValue: 'Nothing to export');
}

/// Written (`excel.done`, a success toast).
class ExportDone extends ExportOutcome {
  const ExportDone({required this.rows, required this.filename, this.savedTo});

  final int rows;
  final String filename;

  /// Where the file went; null when the person cancelled the save.
  final String? savedTo;

  @override
  String message(Translator t) =>
      t('excel.done', count: rows, defaultValue: 'Exported $rows rows');
}

/// It failed (`excel.failed`, an error toast).
class ExportFailed extends ExportOutcome {
  const ExportFailed(this.error);

  final Object error;

  @override
  String message(Translator t) =>
      t('excel.failed', defaultValue: 'Export failed');
}

/// `exportToExcel` / `exportToCsv`, over the gateways.
class DashExporter {
  const DashExporter({
    required this.exports,
    required this.files,
    required this.format,
    required this.t,
    DateTime Function()? clock,
  }) : _clock = clock;

  final ExportGateway exports;
  final FileGateway files;

  /// The active language and zone (dates in the sheet are on its clock).
  final DashFormat format;
  final Translator t;
  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  /// `-YYYY-MM-DD` (UTC, as `new Date().toISOString().slice(0, 10)`).
  String _stamp() => isoString(_now).substring(0, 10);

  /// The spec `exportToExcel` would build for [config].
  WorkbookSpec workbookSpec(ExcelConfig config) => WorkbookSpec(
    logoUrl: config.logoUrl,
    sheets: [for (final s in config.sheets) _sheetSpec(s, config.meta)],
  );

  SheetSpec _sheetSpec(ExcelSheet<Object?> sheet, String? meta) {
    final cols = sheet.columns;
    final types = sheet.columnTypes;
    final generated =
        '${t('excel.generated', defaultValue: 'Generated')}: '
        '${format.fmtDateTimeFull(_now)}';
    final subtitle = [
      sheet.subtitle,
      meta,
      generated,
    ].where((s) => s != null && s.isNotEmpty).join('  ·  ');
    final stats = <StatSpec>[];
    if (sheet.stats.isNotEmpty) {
      final span = cols.length ~/ sheet.stats.length;
      final s = span < 1 ? 1 : span;
      for (var i = 0; i < sheet.stats.length; i++) {
        final stat = sheet.stats[i];
        final last = i * s + s - 1;
        stats.add(
          StatSpec(
            label: stat.label,
            value: stat.value,
            fromCol: excelColumnLetter(i * s),
            toCol: excelColumnLetter(
              last < cols.length - 1 ? last : cols.length - 1,
            ),
            numFmt: switch (stat.type) {
              'money' => '#,##0.00 "EGP"',
              'number' => '#,##0',
              _ => null,
            },
          ),
        );
      }
    }
    final rows = [
      for (final raw in sheet.rawRows())
        [
          for (var c = 0; c < raw.length; c++)
            excelCellValue(raw[c], types[c], format.timezone),
        ],
    ];
    List<Object?>? totals;
    if (sheet.totals && sheet.rows.isNotEmpty) {
      const start = SheetSpec.firstDataRow;
      final end = start + sheet.rows.length - 1;
      totals = [
        for (var i = 0; i < cols.length; i++)
          cols[i].total
              ? ExcelFormula(
                  'SUM(${excelColumnLetter(i)}$start:${excelColumnLetter(i)}$end)',
                )
              : i == 0
              ? t('excel.totals', defaultValue: 'TOTALS')
              : '',
      ];
    }
    return SheetSpec(
      name: cleanSheetName(sheet.name),
      title: sheet.title,
      subtitle: subtitle,
      columns: [
        for (final c in cols)
          ColumnSpec(
            header: c.header,
            width: c.width ?? 20,
            numFmt: excelNumFmt(c.type),
          ),
      ],
      paddingWidths: [for (var i = cols.length; i < 6; i++) 18],
      stats: stats,
      rows: rows,
      totalsRow: totals,
    );
  }

  /// The branded `.xlsx`, saved as `<filename>-<YYYY-MM-DD>.xlsx`.
  Future<ExportOutcome> exportToExcel(ExcelConfig config) async {
    if (config.sheets.every((s) => s.rows.isEmpty)) {
      return const ExportNothing();
    }
    try {
      final bytes = await exports.buildXlsx(workbookSpec(config));
      final name = '${config.filename}-${_stamp()}.xlsx';
      final saved = await files.saveBytes(
        bytes,
        filename: name,
        mimeType: MimeTypes.xlsx,
      );
      final total = config.sheets.fold<int>(0, (s, sh) => s + sh.rows.length);
      return ExportDone(rows: total, filename: name, savedTo: saved);
    } on Object catch (e) {
      return ExportFailed(e);
    }
  }

  /// The CSV text `exportToCsv` writes for [config] (first sheet only).
  String csvText(ExcelConfig config) {
    final sheet = config.sheets.first;
    final header = [
      for (final c in sheet.columns) _csvCell(c.header),
    ].join(',');
    final types = sheet.columnTypes;
    final lines = [
      for (final raw in sheet.rawRows())
        [
          for (var c = 0; c < raw.length; c++) _csvValue(raw[c], types[c]),
        ].join(','),
    ];
    return [header, ...lines].join('\r\n');
  }

  /// The plain CSV sibling, saved as `<filename>-<YYYY-MM-DD>.csv`. A CSV is
  /// one flat file: a multi-sheet config exports only the first sheet.
  Future<ExportOutcome> exportToCsv(ExcelConfig config) async {
    if (config.sheets.isEmpty || config.sheets.every((s) => s.rows.isEmpty)) {
      return const ExportNothing();
    }
    try {
      final name = '${config.filename}-${_stamp()}.csv';
      final saved = await saveText(files, csvText(config), name);
      return ExportDone(
        rows: config.sheets.first.rows.length,
        filename: name,
        savedTo: saved,
      );
    } on Object catch (e) {
      return ExportFailed(e);
    }
  }

  static String _csvCell(String v) =>
      RegExp('[",\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;

  static String _csvValue(Object? raw, ExcelColumnType? type) {
    if (raw == null) return '';
    switch (type) {
      case ExcelColumnType.money:
        return _csvCell(raw is num ? _jsString(raw / 100) : _jsString(raw));
      case ExcelColumnType.date:
      case ExcelColumnType.dateTime:
        final d = parseJsDate(raw is DateTime ? raw : raw.toString());
        return d == null ? '' : isoString(d);
      default:
        return _csvCell(raw is String ? raw : _jsString(raw));
    }
  }
}

// ── export-all.ts ─────────────────────────────────────────────────────────

/// The most rows one file may carry (`EXPORT_ROW_CEILING`).
const int exportRowCeiling = 50000;

/// Rows asked for per request while walking (`PAGE`).
const int exportPageSize = 500;

/// Marks a read as part of an export (`EXPORT_REQUEST`): pass as headers.
const Map<String, String> exportRequestHeaders = {'X-Madar-Export': '1'};

/// Raised when a dataset is too large to export (`ExportTooLargeError`).
class ExportTooLargeError implements Exception {
  const ExportTooLargeError(this.rows);

  final int rows;

  /// `export.tooLarge`, with the counts grouped.
  String message(Translator t) => t(
    'export.tooLarge',
    args: {
      'rows': icuDecimal('en-US', rows),
      'max': icuDecimal('en-US', exportRowCeiling),
    },
    defaultValue:
        'That is about {{rows}} rows, and a spreadsheet built in the browser '
        'tops out around {{max}}. Narrow the dates or the branch and try again.',
  );

  @override
  String toString() => 'ExportTooLargeError($rows rows)';
}

/// One slice of a paged list.
class ExportPage<T> {
  const ExportPage(this.rows, {this.total});

  final List<T> rows;

  /// The endpoint's total, when it reports one.
  final int? total;
}

/// Walks a paged endpoint to the end (`fetchAllPages`): stops on an EMPTY
/// page (never a short one: endpoints clamp the limit), advances by what
/// arrived, refuses past [exportRowCeiling] (on the first page when a total
/// is reported).
Future<List<T>> fetchAllPages<T>(
  Future<ExportPage<T>> Function(int offset, int limit) page,
) async {
  final out = <T>[];
  var offset = 0;
  for (;;) {
    final p = await page(offset, exportPageSize);
    final total = p.total;
    if (total != null && total > exportRowCeiling) {
      throw ExportTooLargeError(total);
    }
    out.addAll(p.rows);
    if (p.rows.isEmpty) break;
    if (total != null && out.length >= total) break;
    if (out.length > exportRowCeiling) throw ExportTooLargeError(out.length);
    offset += p.rows.length;
  }
  return out;
}
