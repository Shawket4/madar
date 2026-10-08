/// Basira's page-side shapes (`features/basira/types.ts`, `history.ts`):
/// an [BasiraExchange] is what the transcript draws; a stored turn's
/// snapshots become the same [wire.ResultBlock]s a live answer streams
/// ([blocksFromStoredTurn]); a streamed `data:` payload becomes a
/// [wire.ChatFrame] or nothing ([decodeChatFrame]).
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' as wire;

/// A question and whatever came back for it — not a stored turn: a turn
/// being streamed has partial state (results before the text, a step, an
/// error) a stored one never has.
class BasiraExchange {
  const BasiraExchange({
    required this.id,
    required this.question,
    this.answer,
    this.kind,
    this.results = const [],
    this.step,
    this.querying,
    this.error,
    this.pending = false,
    this.fromHistory = false,
    this.capturedAt,
  });

  final String id;
  final String question;

  /// Present once the turn finished (a clarify carries its question here).
  final String? answer;

  /// `answer`, `clarify` or `incomplete`.
  final String? kind;
  final List<wire.ResultBlock> results;

  /// While streaming: the loop's step (from 1).
  final int? step;

  /// While streaming: what is being looked up right now.
  final String? querying;
  final String? error;

  /// True until a terminal frame (or a failure) arrives.
  final bool pending;

  /// Restored from history: its blocks are the stored snapshots.
  final bool fromHistory;

  /// When the stored figures were taken (restored exchanges only).
  final String? capturedAt;

  static const Object _keep = Object();

  BasiraExchange copyWith({
    Object? answer = _keep,
    Object? kind = _keep,
    List<wire.ResultBlock>? results,
    Object? step = _keep,
    Object? querying = _keep,
    Object? error = _keep,
    bool? pending,
  }) => BasiraExchange(
    id: id,
    question: question,
    answer: identical(answer, _keep) ? this.answer : answer as String?,
    kind: identical(kind, _keep) ? this.kind : kind as String?,
    results: results ?? this.results,
    step: identical(step, _keep) ? this.step : step as int?,
    querying: identical(querying, _keep) ? this.querying : querying as String?,
    error: identical(error, _keep) ? this.error : error as String?,
    pending: pending ?? this.pending,
    fromHistory: fromHistory,
    capturedAt: capturedAt,
  );
}

/// One query a stored turn ran (`StoredQuery`): its spec, when its figures
/// were captured and the snapshot of what it returned (absent on turns
/// stored before snapshots existed).
class BasiraStoredQuery {
  const BasiraStoredQuery({
    required this.spec,
    this.title,
    this.presetId,
    this.capturedAt,
    this.snapshot,
  });

  final Map<String, Object?> spec;
  final String? title;
  final String? presetId;
  final String? capturedAt;
  final Map<String, Object?>? snapshot;

  /// The stored turn's `specs` array, as the wire carries it (untyped).
  static List<BasiraStoredQuery> listOf(Object? specs) {
    if (specs is! List) return const [];
    return [
      for (final s in specs)
        if (s is Map)
          BasiraStoredQuery(
            spec: _map(s['spec']) ?? const {'dataset': ''},
            title: s['title'] as String?,
            presetId: s['preset_id'] as String?,
            capturedAt: s['captured_at'] as String?,
            snapshot: _map(s['snapshot']),
          ),
    ];
  }
}

Map<String, Object?>? _map(Object? v) =>
    v is Map ? v.map((k, x) => MapEntry('$k', x)) : null;

/// Everything renderable in a stored turn, oldest query first. A query with
/// no snapshot is left out — an empty chart would claim the query found
/// nothing, which is worse than "this was not kept" (REP-BAS-010).
List<wire.ResultBlock> blocksFromStoredTurn(wire.StoredTurn turn) => [
  for (final q in BasiraStoredQuery.listOf(turn.specs)) ?blockFromStored(q),
];

/// The live block shape rebuilt from a stored query; null without a
/// snapshot (or with one this client cannot read).
wire.ResultBlock? blockFromStored(BasiraStoredQuery q) {
  final snap = q.snapshot;
  if (snap == null) return null;
  final rows = snap['rows'];
  try {
    return wire.ResultBlock.fromJson({
      'title': ?q.title,
      'preset_id': ?q.presetId,
      'spec': q.spec,
      'columns': snap['columns'] ?? const <Object?>[],
      'rows': rows ?? const <Object?>[],
      'row_count': snap['row_count'] ?? (rows is List ? rows.length : 0),
      'truncated': snap['truncated'] == true,
      // A snapshot without a shape draws as a table, as the web's
      // renderer falls through to its default.
      'grain': snap['grain'] ?? 'table',
      'viz': snap['viz'] ?? 'table',
      'facet_by': ?snap['facet_by'],
      'scope':
          snap['scope'] ??
          const {'all_branches': true, 'branches': <String>[], 'label': ''},
      'period_from': ?snap['period_from'],
      'period_to': ?snap['period_to'],
    });
  } on Object {
    return null;
  }
}

/// When the turn's stored figures were taken: the first query that says.
String? capturedAtOf(wire.StoredTurn turn) {
  for (final q in BasiraStoredQuery.listOf(turn.specs)) {
    if (q.capturedAt != null) return q.capturedAt;
  }
  return null;
}

/// One streamed payload as a frame. The transport hands one `data:` JSON
/// per item; a whole SSE frame (`event: …\ndata: {…}`) is read too. A
/// payload that does not parse — or names an event this client does not
/// know — is dropped: the terminal frame still carries the whole answer.
wire.ChatFrame? decodeChatFrame(String raw) {
  var text = raw.trim();
  if (!text.startsWith('{')) {
    String? data;
    for (final line in text.split('\n')) {
      if (line.startsWith('data: ')) {
        data = line.substring(6);
        break;
      }
    }
    if (data == null) return null;
    text = data;
  }
  try {
    final json = jsonDecode(text);
    if (json is! Map) return null;
    final frame = wire.ChatFrame.fromJson(
      json.map((k, v) => MapEntry('$k', v)),
    );
    return frame is wire.ChatFrameUnknown ? null : frame;
  } on Object {
    return null;
  }
}

// ── columns ──────────────────────────────────────────────────────────────

/// Money, counts, numbers and minutes are measures; the rest dimensions.
bool isMeasureKind(wire.ColumnKind kind) =>
    kind == wire.ColumnKind.money ||
    kind == wire.ColumnKind.count ||
    kind == wire.ColumnKind.number ||
    kind == wire.ColumnKind.minutes;

List<wire.Column> dimensionsOf(List<wire.Column> columns) => [
  for (final c in columns)
    if (!isMeasureKind(c.kind)) c,
];

List<wire.Column> measuresOf(List<wire.Column> columns) => [
  for (final c in columns)
    if (isMeasureKind(c.kind)) c,
];

/// A cell's value as a number, or null (null, absent or not a number).
num? numOf(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.isNaN ? null : raw;
  final n = num.tryParse('$raw');
  return n == null || n.isNaN ? null : n;
}

/// What a chart plots: money arrives as piastres and is drawn in pounds.
double? plotValue(Object? raw, wire.ColumnKind kind) {
  final n = numOf(raw);
  if (n == null) return null;
  return kind == wire.ColumnKind.money ? n / 100 : n.toDouble();
}

/// A dimension cell as the web's chart data holds it: the value's text, or
/// an em dash for null.
String dimensionText(Object? raw) => raw == null ? '—' : _jsText(raw);

String _jsText(Object raw) {
  if (raw is double && raw == raw.truncateToDouble() && raw.abs() < 1e21) {
    return raw.toInt().toString();
  }
  return '$raw';
}

/// A row cell as text, as the web's `String(value)` prints it.
String rawText(Object? raw) => raw == null ? '' : _jsText(raw);
