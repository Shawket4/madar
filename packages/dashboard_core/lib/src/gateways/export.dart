/// Spreadsheet export and import: the web's `src/lib/excel.ts` (the branded
/// workbook and the CSV sibling) and `src/lib/export-all.ts` (walking a paged
/// list to the end, with a hard ceiling).
///
/// Everything excel.ts decides (cell values, number formats, the banner,
/// subtitle, stat pills, zebra rows, the SUM totals row; for a sheet of
/// tables, which row is a band, a title, a header, a body or a footer row,
/// and every row's height) is decided HERE, into a [WorkbookSpec];
/// [ExportGateway.buildXlsx] only writes it to bytes (the core's xlsx writer
/// in real mode, a recorder in tests).
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart'
    show ApiRequest, ApiResponse, ApiTransport, DashboardApi, PublicBrand;
import 'package:dashboard_core/src/format/format.dart';
import 'package:dashboard_core/src/format/icu_number.dart';
import 'package:dashboard_core/src/format/tz.dart';
import 'package:dashboard_core/src/gateways/files.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:flutter/foundation.dart';
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

  /// An amount as it is (18, 0.5, 12.25): no fixed decimals.
  quantity,
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

/// A sheet of either kind (`AnySheet`): one table ([ExcelSheet]) or a sheet
/// of tables ([ExcelBlockSheet]). Both wear the same banner, subtitle and
/// stat pills.
sealed class AnyExcelSheet {
  const AnyExcelSheet();

  String get name;
  String get title;
  String? get subtitle;
  List<ExcelStat> get stats;

  /// What the sheet holds, for "nothing to export" and the done toast: its
  /// rows, or a sheet of tables' tables (`sheetSize`).
  int get size;
}

/// One sheet (`ExcelSheet<T>`).
class ExcelSheet<T> extends AnyExcelSheet {
  const ExcelSheet({
    required this.name,
    required this.title,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.stats = const [],
    this.totals = false,
  });

  @override
  final String name;
  @override
  final String title;
  @override
  final String? subtitle;
  final List<ExcelColumn<T>> columns;
  final List<T> rows;
  @override
  final List<ExcelStat> stats;
  final bool totals;

  int get rowCount => rows.length;

  @override
  int get size => rows.length;

  /// Each row's raw values, column by column (typed here, where `T` is known).
  List<List<Object?>> rawRows() => [
    for (final r in rows) [for (final c in columns) c.accessor(r)],
  ];

  List<ExcelColumnType?> get columnTypes => [for (final c in columns) c.type];
}

/// One typed cell of a table in a sheet of tables (`ExcelCell`'s
/// `{ value, type }` form). A row's other cells are plain: a String, or null
/// for a blank.
@immutable
class ExcelCell {
  const ExcelCell(this.value, [this.type]);

  /// The raw value: String, num, DateTime, bool or null.
  final Object? value;
  final ExcelColumnType? type;

  @override
  bool operator ==(Object other) =>
      other is ExcelCell && other.value == value && other.type == type;

  @override
  int get hashCode => Object.hash(value, type);

  @override
  String toString() => 'ExcelCell($value, ${type?.name})';
}

/// One titled table inside a sheet of several (`ExcelBlock`: a drink's
/// recipe). Its first column is the row's label; the rest are values. A
/// cell is a String, an [ExcelCell] or null.
class ExcelBlock {
  const ExcelBlock({
    required this.title,
    required this.header,
    required this.rows,
    this.note,
    this.footer,
    this.caption,
  });

  final String title;

  /// Muted words after the title (what it follows, that it is off the menu).
  final String? note;

  /// Column headers.
  final List<String> header;

  /// Body rows, zebra-striped like every sheet's.
  final List<List<Object?>> rows;

  /// Summary rows under the body (cost, price, food cost): bold, ruled above.
  final List<List<Object?>>? footer;

  /// A wrapped line under the table (how it's made).
  final String? caption;
}

/// A band naming what the tables under it belong to (`ExcelGroup`: a
/// category).
class ExcelGroup {
  const ExcelGroup({required this.group, required this.blocks});

  final String group;
  final List<ExcelBlock> blocks;
}

/// A sheet of tables rather than one (`ExcelBlockSheet`, `kind: "blocks"`):
/// the same banner, subtitle and stat pills as every sheet, then groups of
/// titled tables, one after another.
class ExcelBlockSheet extends AnyExcelSheet {
  const ExcelBlockSheet({
    required this.name,
    required this.title,
    required this.widths,
    required this.groups,
    this.subtitle,
    this.stats = const [],
  });

  @override
  final String name;
  @override
  final String title;
  @override
  final String? subtitle;
  @override
  final List<ExcelStat> stats;

  /// One width per column, shared by every table (a sheet has one set of
  /// columns).
  final List<double> widths;
  final List<ExcelGroup> groups;

  /// Its tables.
  @override
  int get size => groups.fold(0, (n, g) => n + g.blocks.length);
}

/// `ExcelConfig` / `CsvConfig`.
class ExcelConfig {
  const ExcelConfig({
    required this.filename,
    required this.sheets,
    this.meta,
    this.logoUrl,
    this.doneMessage,
  });

  final String filename;
  final String? meta;

  /// The banner logo; null = Madar's.
  final String? logoUrl;

  /// Sheets of either kind, in order. A CSV takes the first table sheet.
  final List<AnyExcelSheet> sheets;

  /// The success toast's words, when "Exported N rows" would miscount (a
  /// sheet of tables).
  final String? doneMessage;
}

/// The logo an export wears (`useExportLogo` over `use-brand.ts`): the shop's
/// own only on the branding tier, trimmed, and a blank one none; null means
/// Madar's. Pass `ref.read(publicBrandProvider).value`.
String? exportLogoUrl(PublicBrand? brand) {
  final logo = brand?.logoUrl?.trim() ?? '';
  return brand?.customBranding == true && logo.isNotEmpty ? logo : null;
}

/// The workbook palette (`PALETTE`, ARGB): ink on paper (owner, 2026-11-25:
/// "use ink for all export tokens"). Every band, title and figure is ink; the
/// page is white with a cool tint for the zebra rows; secondary words slate.
abstract final class ExcelPalette {
  /// The ink every export draws in.
  static const String ink = 'FF14181E';

  /// The one typeface (the web's `EXPORT_FONT`): the dashboard's own. The
  /// core's writer sets every cell in it (`xlsx.rs` `FONT`). A spreadsheet
  /// cannot embed a font, so a viewer without it sees their app's default.
  static const String font = 'IBM Plex Sans Arabic';

  /// The banner title, the header and totals bands.
  static const String brand = ink;

  /// Group bands and stat figures.
  static const String accent = ink;
  static const String white = 'FFFFFFFF';
  static const String zebra = 'FFEDF2F3';
  static const String border = 'FFD7E0E1';
  static const String text = ink;
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
  // Excel's own General format: 18, 0.5, 12.25, never "18.00".
  ExcelColumnType.quantity => null,
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

/// `captionHeight`: how tall a merged, wrapped line of [text] must be across
/// columns of these [widths]. Excel never grows a merged row to fit, so the
/// height is set: about one character per width unit at 9 pt, 12 pt a line.
int captionHeight(String text, List<double> widths) {
  final total = widths.fold<double>(0, (a, w) => a + w);
  final perLine = math.max(20, (total * 1.1).floor());
  final lines = text
      .split('\n')
      .fold<int>(0, (n, l) => n + math.max(1, (l.length / perLine).ceil()));
  return math.max(18, lines * 12 + 6);
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
    case ExcelColumnType.quantity:
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

/// One sheet of a [WorkbookSpec], laid out: a table ([SheetSpec]) or a sheet
/// of tables ([BlockSheetSpec]).
sealed class AnySheetSpec {
  const AnySheetSpec();

  String get name;
  String get title;
  String get subtitle;
  List<StatSpec> get stats;

  Map<String, Object?> toJson();
}

/// One sheet exactly as `buildSheet` lays it out: banner (row 1, merged to
/// the padded width, title right-aligned, logo top-left), subtitle (row 2),
/// spacer, stat pills (rows 4-5), spacer, header (row 7, frozen), data from
/// row 8 with zebra fill, then the totals row.
class SheetSpec extends AnySheetSpec {
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

  @override
  final String name;
  @override
  final String title;
  @override
  final String subtitle;
  final List<ColumnSpec> columns;

  /// Extra empty columns so the banner spans at least six (width 18 each).
  final List<double> paddingWidths;
  @override
  final List<StatSpec> stats;

  /// Cells: num, String, null.
  final List<List<Object?>> rows;

  /// Cells: [ExcelFormula], String.
  final List<Object?>? totalsRow;

  static const int headerRow = 7;
  static const int firstDataRow = 8;

  // No `kind`: the writer's default, and the JSON every table sheet has
  // always sent.
  @override
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

/// What one row of a sheet of tables is (`buildBlockSheet`).
enum BlockRowKind {
  /// A category's band: accent fill, white bold 12, across the sheet.
  group,

  /// An empty row of its own height (6 pt under a band, 10 pt after a table).
  gap,

  /// A table's title, bold 12 in the brand ink, its note muted 9 after it.
  title,

  /// The header band: brand fill, white bold, wrapped.
  header,

  /// A zebra-striped row of values.
  body,

  /// A bold summary row under the body (the first ruled off above).
  footer,

  /// A wrapped, muted line across the sheet.
  caption,
}

/// One row of a sheet of tables, laid out: where it is, how tall, and what it
/// holds. Its first cell is the row's label (left, indented); the rest are
/// centred, as every sheet's values.
class BlockRowSpec {
  const BlockRowSpec({
    required this.kind,
    required this.row,
    required this.height,
    this.text,
    this.note,
    this.cells = const [],
    this.numFmts = const [],
    this.zebra = false,
    this.ruled = false,
  });

  final BlockRowKind kind;

  /// 1-based.
  final int row;

  /// Points.
  final int height;

  /// A band's, a title's or a caption's words (merged across the sheet).
  final String? text;

  /// The title's muted words, spaced as drawn after it.
  final String? note;

  /// A header's, body's or footer's values, one per column of the table:
  /// num, String or null (a styled blank).
  final List<Object?> cells;

  /// One per cell; null = General.
  final List<String?> numFmts;

  /// A body row on the zebra fill (else white).
  final bool zebra;

  /// A footer row with the thin brand rule above (the first).
  final bool ruled;

  bool get _hasCells => switch (kind) {
    BlockRowKind.header || BlockRowKind.body || BlockRowKind.footer => true,
    _ => false,
  };

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'row': row,
    'height': height,
    'text': ?text,
    'note': ?note,
    if (_hasCells) 'cells': cells,
    if (_hasCells) 'num_fmts': numFmts,
    if (kind == BlockRowKind.body) 'zebra': zebra,
    if (kind == BlockRowKind.footer) 'ruled': ruled,
  };
}

/// A sheet of tables exactly as `buildBlockSheet` lays it out: rows 1-6 as
/// every sheet's head (banner, subtitle, stat pills over the table's own
/// columns), then [rows] from row 7; portrait, one page wide, nothing frozen.
class BlockSheetSpec extends AnySheetSpec {
  const BlockSheetSpec({
    required this.name,
    required this.title,
    required this.subtitle,
    required this.widths,
    required this.stats,
    required this.rows,
  });

  @override
  final String name;
  @override
  final String title;
  @override
  final String subtitle;

  /// Every column's width, padded to at least six (18 each): the band, the
  /// titles and the captions span them all.
  final List<double> widths;
  @override
  final List<StatSpec> stats;
  final List<BlockRowSpec> rows;

  static const int firstRow = 7;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'blocks',
    'name': name,
    'title': title,
    'subtitle': subtitle,
    'widths': widths,
    'stats': [for (final s in stats) s.toJson()],
    'rows': [for (final r in rows) r.toJson()],
  };
}

/// A whole workbook, ready to write.
class WorkbookSpec {
  /// A workbook of table sheets.
  const WorkbookSpec({
    required List<SheetSpec> sheets,
    this.creator = 'Madar',
    this.logoUrl,
  }) : allSheets = sheets;

  /// Sheets of either kind, in order.
  const WorkbookSpec.of(this.allSheets, {this.creator = 'Madar', this.logoUrl});

  final String creator;

  /// Null = Madar's own logo.
  final String? logoUrl;

  /// Every sheet, in order.
  final List<AnySheetSpec> allSheets;

  /// The table sheets, in order (every sheet but a sheet of tables).
  List<SheetSpec> get sheets => [
    for (final s in allSheets)
      if (s is SheetSpec) s,
  ];

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
    'sheets': [for (final s in allSheets) s.toJson()],
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
  const ExportDone({
    required this.rows,
    required this.filename,
    this.savedTo,
    this.doneMessage,
  });

  /// The rows written, a sheet of tables counting its tables.
  final int rows;
  final String filename;

  /// Where the file went; null when the person cancelled the save.
  final String? savedTo;

  /// The toast's words when the config gave its own
  /// ([ExcelConfig.doneMessage]).
  final String? doneMessage;

  @override
  String message(Translator t) =>
      doneMessage ??
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
  WorkbookSpec workbookSpec(ExcelConfig config) =>
      WorkbookSpec.of(logoUrl: config.logoUrl, [
        for (final s in config.sheets)
          switch (s) {
            ExcelSheet() => _sheetSpec(s, config.meta),
            ExcelBlockSheet() => _blockSheetSpec(s, config.meta),
          },
      ]);

  /// Row 2 of every sheet (`drawHead`): its subtitle, the meta, and when.
  String _subtitle(String? subtitle, String? meta) {
    final generated =
        '${t('excel.generated', defaultValue: 'Generated')}: '
        '${format.fmtDateTimeFull(_now)}';
    return [
      subtitle,
      meta,
      generated,
    ].where((s) => s != null && s.isNotEmpty).join('  ·  ');
  }

  /// The stat pills of rows 4-5 (`drawHead`), sharing out the first
  /// [columns] columns, and never fewer columns than there are pills: a recipe
  /// book whose widest drink has one size is three columns and four pills,
  /// and sharing three among four put two pills on one cell, which the writer
  /// refused ("Export failed").
  static List<StatSpec> _stats(List<ExcelStat> stats, int columns) {
    final out = <StatSpec>[];
    if (stats.isEmpty) return out;
    final across = columns > stats.length ? columns : stats.length;
    final span = across ~/ stats.length;
    final s = span < 1 ? 1 : span;
    for (var i = 0; i < stats.length; i++) {
      final stat = stats[i];
      final last = i * s + s - 1;
      out.add(
        StatSpec(
          label: stat.label,
          value: stat.value,
          fromCol: excelColumnLetter(i * s),
          toCol: excelColumnLetter(last < across - 1 ? last : across - 1),
          numFmt: switch (stat.type) {
            'money' => '#,##0.00 "EGP"',
            'number' => '#,##0',
            _ => null,
          },
        ),
      );
    }
    return out;
  }

  SheetSpec _sheetSpec(ExcelSheet<Object?> sheet, String? meta) {
    final cols = sheet.columns;
    final types = sheet.columnTypes;
    final subtitle = _subtitle(sheet.subtitle, meta);
    final stats = _stats(sheet.stats, cols.length);
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

  /// `buildBlockSheet`'s layout: from row 7, per group a band and a 6 pt
  /// spacer; per table its title (the note after it), the header band,
  /// zebra body rows from the first, bold footer rows (the first ruled
  /// above), the caption at [captionHeight], then a 10 pt gap. A body or
  /// footer row is padded with blanks to the table's columns.
  BlockSheetSpec _blockSheetSpec(ExcelBlockSheet sheet, String? meta) {
    final widths = [
      ...sheet.widths,
      for (var i = sheet.widths.length; i < 6; i++) 18.0,
    ];
    final rows = <BlockRowSpec>[];
    var r = BlockSheetSpec.firstRow;
    BlockRowSpec values(
      BlockRowKind kind,
      List<Object?> raw,
      int ncols, {
      bool zebra = false,
      bool ruled = false,
    }) {
      final cells = [...raw, for (var i = raw.length; i < ncols; i++) null];
      return BlockRowSpec(
        kind: kind,
        row: r,
        height: 20,
        cells: [for (final c in cells) _blockValue(c)],
        numFmts: [
          for (final c in cells) c is ExcelCell ? excelNumFmt(c.type) : null,
        ],
        zebra: zebra,
        ruled: ruled,
      );
    }

    for (final group in sheet.groups) {
      rows
        ..add(
          BlockRowSpec(
            kind: BlockRowKind.group,
            row: r,
            height: 24,
            text: group.group,
          ),
        )
        ..add(BlockRowSpec(kind: BlockRowKind.gap, row: r + 1, height: 6));
      r += 2;
      for (final block in group.blocks) {
        final ncols = math.max(1, block.header.length);
        final note = block.note;
        rows.add(
          BlockRowSpec(
            kind: BlockRowKind.title,
            row: r++,
            height: 22,
            text: block.title,
            note: note == null || note.isEmpty ? null : '   $note',
          ),
        );
        if (block.header.isNotEmpty) {
          rows.add(
            BlockRowSpec(
              kind: BlockRowKind.header,
              row: r++,
              height: 22,
              cells: block.header,
              numFmts: [for (final _ in block.header) null],
            ),
          );
        }
        for (final (i, cells) in block.rows.indexed) {
          rows.add(values(BlockRowKind.body, cells, ncols, zebra: i.isEven));
          r++;
        }
        for (final (i, cells) in (block.footer ?? const []).indexed) {
          rows.add(values(BlockRowKind.footer, cells, ncols, ruled: i == 0));
          r++;
        }
        final caption = block.caption;
        if (caption != null && caption.isNotEmpty) {
          rows.add(
            BlockRowSpec(
              kind: BlockRowKind.caption,
              row: r++,
              height: captionHeight(caption, widths),
              text: caption,
            ),
          );
        }
        rows.add(BlockRowSpec(kind: BlockRowKind.gap, row: r++, height: 10));
      }
    }
    return BlockSheetSpec(
      name: cleanSheetName(sheet.name),
      title: sheet.title,
      subtitle: _subtitle(sheet.subtitle, meta),
      widths: widths,
      stats: _stats(sheet.stats, sheet.widths.length),
      rows: rows,
    );
  }

  /// A block cell's value (`cellOf` + `coerce`): an [ExcelCell] by its type,
  /// a plain one as text.
  Object? _blockValue(Object? cell) => cell is ExcelCell
      ? excelCellValue(cell.value, cell.type, format.timezone)
      : excelCellValue(cell, null, format.timezone);

  /// The branded `.xlsx`, saved as `<filename>-<YYYY-MM-DD>.xlsx`.
  Future<ExportOutcome> exportToExcel(ExcelConfig config) async {
    if (config.sheets.every((s) => s.size == 0)) {
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
      final total = config.sheets.fold<int>(0, (s, sh) => s + sh.size);
      return ExportDone(
        rows: total,
        filename: name,
        savedTo: saved,
        doneMessage: config.doneMessage,
      );
    } on Object catch (e, st) {
      return _failed(e, st);
    }
  }

  /// The table sheets of [config]: a CSV's (`CsvConfig` holds only those; a
  /// sheet of tables has no flat form).
  static List<ExcelSheet<Object?>> _tables(ExcelConfig config) => [
    for (final s in config.sheets)
      if (s is ExcelSheet<Object?>) s,
  ];

  /// The CSV text `exportToCsv` writes for [config] (first table sheet only).
  String csvText(ExcelConfig config) {
    final sheet = _tables(config).first;
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
    final tables = _tables(config);
    if (tables.isEmpty || tables.every((s) => s.rows.isEmpty)) {
      return const ExportNothing();
    }
    try {
      final name = '${config.filename}-${_stamp()}.csv';
      final saved = await saveText(files, csvText(config), name);
      return ExportDone(
        rows: tables.first.rows.length,
        filename: name,
        savedTo: saved,
      );
    } on Object catch (e, st) {
      return _failed(e, st);
    }
  }

  /// The toast says only "Export failed": the cause goes to the log.
  static ExportFailed _failed(Object e, StackTrace st) {
    debugPrint('Export failed: $e\n$st');
    return ExportFailed(e);
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

/// The API with [headers] on every request over [inner] (the generated
/// client has no per-call headers): an export's re-reads pass
/// [exportRequestHeaders], so the backend counts them against the export
/// budget. The added headers win on a clash.
DashboardApi apiWithHeaders(ApiTransport inner, Map<String, String> headers) =>
    DashboardApi(_HeaderTransport(inner, headers));

class _HeaderTransport implements ApiTransport {
  _HeaderTransport(this.inner, this.headers);

  final ApiTransport inner;
  final Map<String, String> headers;

  ApiRequest _with(ApiRequest r) => ApiRequest(
    method: r.method,
    path: r.path,
    query: r.query,
    body: r.body,
    files: r.files,
    headers: {...r.headers, ...headers},
  );

  @override
  Future<ApiResponse> send(ApiRequest request) => inner.send(_with(request));

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(_with(request));
}

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
