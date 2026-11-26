// The CSV of one sheet: the data, for another program to read (the web's
// `src/lib/csv.ts`).
//
// Every export can be a CSV ([DashExporter.exportFile], the format chosen in
// the Export panel); this part writes the text. A CSV is one flat table, so
// it is one sheet: a workbook of several asks which (the panel's Sheet), and
// a sheet of tables (the recipe book) has no CSV.
//
// What is written, and why:
// - A UTF-8 byte-order mark first, so Excel opens Arabic as Arabic rather
//   than as mojibake (it reads a CSV without one in the machine's code page).
// - The header row, then the rows: no banner, no totals, nothing a program
//   would have to skip.
// - RFC 4180: CRLF between records; a field with a comma, quote or line
//   break in quotes, its quotes doubled.
// - Values a program can read, not the dashboard's display: money in pounds
//   with two decimals and no currency sign (1620 piastres → 16.20), numbers
//   without grouping, a percentage as 41.2% (Excel and Sheets read it back as
//   0.412), dates as 2026-11-26 and times as 2026-11-26 14:05 on the shop's
//   clock (madar-time, never the device's zone), yes/no as true / false.
// - Text a spreadsheet would run as a formula (=…, @…, +/- not followed by a
//   number) is prefixed with ': customer names come from the public sign-up,
//   and a CSV is opened in Excel.
part of 'export.dart';

/// The mark that tells Excel the file is UTF-8.
const String csvBom = '﻿';

/// Text a spreadsheet would evaluate: a formula, or a sign that is not a
/// number's.
final RegExp _formula = RegExp(r'^[=@\t\r]|^[+-](?![\d\s().,-]*$)');
final RegExp _needsQuotes = RegExp('[",\r\n]');
final RegExp _calendarDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// One field, guarded and quoted as RFC 4180 asks.
String csvField(String text) {
  final safe = _formula.hasMatch(text) ? "'$text" : text;
  return _needsQuotes.hasMatch(safe) ? '"${safe.replaceAll('"', '""')}"' : safe;
}

/// `n.toFixed(decimals)`, a negative zero written as zero.
String _fixed(num n, int decimals) =>
    (n == 0 ? 0 : n).toStringAsFixed(decimals);

/// A number without float noise or grouping: 0.30000000000000004 → "0.3".
String _plain(num n, int maxDecimals) {
  if (!n.isFinite) return '';
  final s = _fixed(n, maxDecimals);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// An instant on the shop's wall clock: its date, and with [time], `HH:MM`.
String _onShopClock(Object raw, String zone, {required bool time}) {
  // A calendar date is already the shop's: never move it through a zone.
  if (raw is String && _calendarDate.hasMatch(raw)) return raw;
  final d = parseJsDate(raw);
  if (d == null) return '';
  final w = inZone(d, zone);
  final date =
      '${w.year.toString().padLeft(4, '0')}-${_two(w.month)}-'
      '${_two(w.day)}';
  return time ? '$date ${_two(w.hour)}:${_two(w.minute)}' : date;
}

/// One value as the CSV writes it (see the part's note).
String csvValue(Object? raw, ExcelColumnType? type, String zone) {
  if (raw == null || raw == '') return '';
  String text() => csvField(raw is String ? raw : _jsString(raw));
  final n = _jsNumberOf(raw);
  return switch (type) {
    ExcelColumnType.money => raw is num ? _fixed(raw / 100, 2) : text(),
    ExcelColumnType.moneyRaw => n.isFinite ? _fixed(n, 2) : text(),
    ExcelColumnType.number => n.isFinite ? _plain(n, 4) : text(),
    // `Math.round`: half up, as JavaScript rounds.
    ExcelColumnType.integer => n.isFinite ? '${(n + 0.5).floor()}' : text(),
    ExcelColumnType.quantity => n.isFinite ? _plain(n, 3) : text(),
    ExcelColumnType.percent => n.isFinite ? '${_plain(n * 100, 2)}%' : text(),
    ExcelColumnType.date => _onShopClock(raw, zone, time: false),
    ExcelColumnType.dateTime => _onShopClock(raw, zone, time: true),
    ExcelColumnType.bool => _truthy(raw) ? 'true' : 'false',
    ExcelColumnType.text || null => text(),
  };
}

/// The whole file: the mark, the header, the rows.
String toCsv(ExcelSheet<Object?> sheet, String zone) {
  final types = sheet.columnTypes;
  final lines = [
    [for (final c in sheet.columns) csvField(c.header)].join(','),
    for (final raw in sheet.rawRows())
      [
        for (var c = 0; c < raw.length; c++) csvValue(raw[c], types[c], zone),
      ].join(','),
  ];
  return '$csvBom${lines.join('\r\n')}\r\n';
}
