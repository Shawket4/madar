/// What the web's `dawam/reports-page.tsx` computes in the browser, as pure
/// functions: a report column (what the table shows and what the CSV gets),
/// the CSV itself (TEAM-RPT-007), a period's phase (TEAM-RPT-031) and the
/// labour share (TEAM-RPT-020/021).
library;

/// One column: its header and its raw value (`Col`): a number or a string.
class ReportCol<R> {
  const ReportCol(
    this.id,
    this.header,
    this.value, {
    this.money = false,
    this.numeric = false,
  });

  final String id;
  final String header;
  final Object Function(R row) value;

  /// Piastres: shown as money, exported in pounds.
  final bool money;
  final bool numeric;
}

/// JavaScript's `String(n)`: 1200 → "1200", 12.5 → "12.5" (never "1200.0").
String jsNumber(num n) =>
    n is int || n == n.truncateToDouble() ? '${n.toInt()}' : '$n';

/// Bidi isolates and direction marks the CSV drops (U+2066–2069, LRM, RLM).
final RegExp _bidi = RegExp('[\u2066-\u2069\u200e\u200f]');

/// `toCsv`: RFC 4180 (quoted only when needed, quotes doubled), CRLF between
/// lines, the headers first, money in pounds so a spreadsheet adds it up,
/// plain text with no bidi isolates. The caller adds the BOM.
String reportCsv<R>(List<ReportCol<R>> cols, List<R> rows) {
  String q(Object v) {
    final s = (v is num ? jsNumber(v) : '$v').replaceAll(_bidi, '');
    return RegExp('[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return [
    cols.map((c) => q(c.header)).join(','),
    for (final r in rows)
      cols
          .map((c) => q(c.money ? (c.value(r) as num) / 100 : c.value(r)))
          .join(','),
  ].join('\r\n');
}

/// open · approved · paid, from a period's server status (`phaseOf`).
String reportPhase(String status) => switch (status) {
  'generated' => 'approved',
  'paid' || 'closed' => 'paid',
  _ => 'open',
};

/// The labour share card: labour / sales × 100 to one decimal, "—" without
/// sales.
String labourShare(int labour, int sales) =>
    sales > 0 ? '${(labour / sales * 100).toStringAsFixed(1)}%' : '—';

/// The table's share: `labour_share_bp` / 100 to one decimal, or "—".
String labourShareBp(int? bp) =>
    bp == null ? '—' : '${(bp / 100).toStringAsFixed(1)}%';
