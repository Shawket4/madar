/// Exact answers for a narrower date range, computed from an answer already
/// held for a wider one (the owner's "smart inference": month to date is
/// held, the 1st to the 8th is asked, and every figure of it is in hand).
///
/// A deriver is registered ONLY where every field of the narrower answer is
/// provably the same as the server's: the wider answer carries a per-day (or
/// finer) breakdown, or the full row list (never a page, never a top-N), and
/// the backend's own query filters by a column every row carries. Totals
/// summed from rows are exact; distinct counts, top-N lists, averages over
/// the range's days and shares of a range total never are. The tests compare
/// each one with the mock server's own answer over many sub-ranges
/// (`apps/dashboard/test/offline_derivers_test.dart`).
///
/// Rejected (MadarRust handlers read 2026-10-09), never derived:
/// - `/reports/branches/{id}/sales`: subtotal, service charge, delivery fees,
///   tips, money in by method and the top items are in no per-day answer;
/// - `.../sales/peak-hours`, `peak-days`, `channel-breakdown`,
///   `items-combined`, `addons`, `tellers`, `waiters`, `delivery-sales`,
///   `/reports/orgs/{id}/comparison`, `/reports/bundles`, `/insights/...`
///   (margin watch, menu margin, repricing): totals over the whole range
///   (by hour of day, weekday, channel, item, person, branch), no per-day
///   breakdown;
/// - `waste-report`, `supplier-spend`: grouped over the range;
///   `po-lead-time`: averages; `material-cost-trend`: "3+ consecutive
///   rises" read over the range as a whole;
/// - `/staff/attendance/summary`: per person over the range;
///   `/staff/discipline-report`: distinct day counts;
/// - `/loyalty/liability-trend`: weekly buckets (weeks from Saturday);
///   `/loyalty/behavior`, `campaign-effectiveness`: range aggregates;
/// - `/orders`, `/inventory/branches/{id}/movements`: paginated;
///   `/staff/expense-advances`, `/staff/adjustments`: cut at 200/300 rows;
/// - `/staff/requests`: a span-overlap filter (not a column in a range);
///   `/bookings`: the page asks for one service day by `date`.
library;

import 'package:dashboard_core/src/format/tz.dart';
import 'package:dashboard_core/src/scope/scope.dart' show allBranchesId;

/// How a range's ends are written.
enum RangeKind {
  /// `timestamptz` instants (`2026-10-01T21:00:00.000Z`), both ends inclusive.
  instant,

  /// Calendar dates (`2026-10-01`), both ends inclusive.
  date,
}

/// What a narrower request asks for, as a deriver reads it.
class DeriveRequest {
  const DeriveRequest({
    required this.path,
    required this.match,
    required this.query,
    required this.from,
    required this.to,
    required this.zoneFor,
  });

  final String path;

  /// [RangeDeriver.path] matched on [path] (its groups: path parameters).
  final RegExpMatch match;
  final Map<String, List<String>> query;

  /// [DateTime] (UTC) for [RangeKind.instant], `YYYY-MM-DD` for
  /// [RangeKind.date].
  final Object from;
  final Object to;

  /// The zone the server cuts days in for a branch (null: every branch, the
  /// org's zone); null when it is not known for certain.
  final String? Function(String? branchId) zoneFor;

  /// The first value of query parameter [name].
  String? param(String name) {
    final v = query[name];
    return v == null || v.isEmpty ? null : v.first;
  }
}

/// A narrower answer from a wider one.
class RangeDeriver {
  const RangeDeriver({
    required this.path,
    required this.kind,
    required this.derive,
    this.source,
  });

  /// The request paths it answers.
  final RegExp path;

  /// The endpoint the wider answer comes from, when it is not [path]'s own.
  final String Function(String path)? source;
  final RangeKind kind;

  /// [wider] (decoded JSON, the answer for a range covering the asked one,
  /// every other parameter the same) narrowed to [want]; null when this case
  /// is not provably exact.
  final Object? Function(Object? wider, DeriveRequest want) derive;

  String sourceOf(String path) => source?.call(path) ?? path;

  /// The range the query asks for, or null when it does not name both ends
  /// properly.
  ({Object from, Object to})? rangeOf(Map<String, List<String>> query) {
    final f = query['from'];
    final t = query['to'];
    if (f == null || t == null || f.length != 1 || t.length != 1) return null;
    switch (kind) {
      case RangeKind.instant:
        final a = DateTime.tryParse(f.single)?.toUtc();
        final b = DateTime.tryParse(t.single)?.toUtc();
        if (a == null || b == null || b.isBefore(a)) return null;
        return (from: a, to: b);
      case RangeKind.date:
        final a = f.single;
        final b = t.single;
        if (!_isDate(a) || !_isDate(b) || b.compareTo(a) < 0) return null;
        return (from: a, to: b);
    }
  }

  /// Whether [wider] (another request's query) names a range covering
  /// [want]'s with every other parameter the same.
  bool covers(Map<String, List<String>> wider, DeriveRequest want) {
    final r = rangeOf(wider);
    if (r == null) return false;
    final others = {...wider.keys, ...want.query.keys}
      ..remove('from')
      ..remove('to');
    for (final k in others) {
      final a = wider[k] ?? const [];
      final b = want.query[k] ?? const [];
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
    }
    return switch (kind) {
      RangeKind.instant =>
        !(r.from as DateTime).isAfter(want.from as DateTime) &&
            !(r.to as DateTime).isBefore(want.to as DateTime),
      RangeKind.date =>
        (r.from as String).compareTo(want.from as String) <= 0 &&
            (r.to as String).compareTo(want.to as String) >= 0,
    };
  }
}

final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool _isDate(String s) => _date.hasMatch(s);

String _ymd(int y, int m, int d) =>
    '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-'
    '${d.toString().padLeft(2, '0')}';

/// The local days [from]..[to] cover in [zone], when the range is exactly
/// whole days there: [from] is a local midnight and [to] the last
/// millisecond before one (the period picker's ranges). Null otherwise.
({String first, String last})? wholeLocalDays(
  DateTime from,
  DateTime to,
  String zone,
) {
  final a = inZone(from, zone);
  if (!wallClock(zone, a.year, a.month - 1, a.day).isAtSameMomentAs(from)) {
    return null;
  }
  final end = to.add(const Duration(milliseconds: 1));
  final b = inZone(end, zone);
  if (!wallClock(zone, b.year, b.month - 1, b.day).isAtSameMomentAs(end)) {
    return null;
  }
  final last = DateTime.utc(b.year, b.month, b.day - 1);
  final first = _ymd(a.year, a.month, a.day);
  final lastDay = _ymd(last.year, last.month, last.day);
  if (lastDay.compareTo(first) < 0) return null;
  return (first: first, last: lastDay);
}

/// Every row of [wider] whose [field] lies in [want]'s range; null when
/// [wider] is not a list of objects carrying it.
List<Object?>? rowsInRange(
  Object? wider,
  DeriveRequest want,
  String field,
  RangeKind kind,
) {
  if (wider is! List) return null;
  final out = <Object?>[];
  for (final row in wider) {
    if (row is! Map) return null;
    final v = row[field];
    if (v is! String) return null;
    final bool inside;
    switch (kind) {
      case RangeKind.instant:
        final at = DateTime.tryParse(v);
        if (at == null) return null;
        inside =
            !at.isBefore(want.from as DateTime) &&
            !at.isAfter(want.to as DateTime);
      case RangeKind.date:
        if (!_isDate(v)) return null;
        inside =
            v.compareTo(want.from as String) >= 0 &&
            v.compareTo(want.to as String) <= 0;
    }
    if (inside) out.add(row);
  }
  return out;
}

/// `GET /reports/branches/{id}/sales/timeseries` (MadarRust
/// `branch_sales_timeseries`): one point per local day (or hour) that had
/// orders, cut in the scope's zone (the branch's, every branch: the org's),
/// orders filtered `created_at >= from AND created_at <= to`, and every
/// figure of a point summed from that bucket's own orders (refunds are the
/// order's own, whenever made). A range that is whole local days in that
/// zone is exactly the points of those days. Monthly points are not cut by
/// days: never derived.
Object? deriveTimeseries(Object? wider, DeriveRequest want) {
  final g = want.param('granularity') ?? 'daily';
  if (g != 'daily' && g != 'hourly') return null;
  if (wider is! List) return null;
  final id = want.match.group(1)!;
  final zone = want.zoneFor(id == allBranchesId ? null : id);
  if (zone == null) return null;
  final days = wholeLocalDays(
    want.from as DateTime,
    want.to as DateTime,
    zone,
  );
  if (days == null) return null;
  final out = <Object?>[];
  for (final p in wider) {
    if (p is! Map) return null;
    final period = p['period'];
    if (period is! String || period.length < 10) return null;
    final day = period.substring(0, 10);
    if (!_isDate(day)) return null;
    if (day.compareTo(days.first) >= 0 && day.compareTo(days.last) <= 0) {
      out.add(p);
    }
  }
  return out;
}

int _int(Object? v) => v is num ? v.toInt() : 0;

/// `GET /staff-pool/drinks/summary` from `GET /staff-pool/drinks` over the
/// same or a wider range (MadarRust `staff_pool/record.rs`): both read the
/// same rows (`business_date BETWEEN from AND to`, the same branch and
/// `overspent_only`), and the summary is counts and `COALESCE(SUM(...), 0)`
/// over them.
Object? deriveDrinksSummary(Object? wider, DeriveRequest want) {
  final rows = rowsInRange(wider, want, 'business_date', RangeKind.date);
  if (rows == null) return null;
  var quantity = 0;
  var overspent = 0;
  var comp = 0;
  var extras = 0;
  var cost = 0;
  var mismatches = 0;
  var unpriced = 0;
  for (final r in rows.cast<Map<Object?, Object?>>()) {
    quantity += _int(r['quantity']);
    if (r['overspent'] == true) overspent++;
    comp += _int(r['comp_minor']);
    extras += _int(r['extras_minor']);
    cost += _int(r['cost_minor']);
    final reported = r['comp_minor_reported'];
    if (reported != null && reported != r['comp_minor']) mismatches++;
    if (r['comp_minor'] == null) unpriced++;
  }
  return {
    'drinks': rows.length,
    'quantity': quantity,
    'overspent': overspent,
    'comp_minor': comp,
    'extras_minor': extras,
    'cost_minor': cost,
    'comp_mismatches': mismatches,
    'unpriced': unpriced,
  };
}

/// The registry the transport consults.
final List<RangeDeriver> rangeDerivers = [
  RangeDeriver(
    path: RegExp(r'^/reports/branches/([^/]+)/sales/timeseries$'),
    kind: RangeKind.instant,
    derive: deriveTimeseries,
  ),
  // MadarRust `branch_till_sessions`: tills with `opened_at` in [from, to],
  // every figure the whole till's own, newest first; past 5000 the range is
  // refused, never cut, so an answer is the full list.
  RangeDeriver(
    path: RegExp(r'^/reports/branches/[^/]+/tills$'),
    kind: RangeKind.instant,
    derive: (w, r) => rowsInRange(w, r, 'opened_at', RangeKind.instant),
  ),
  // MadarRust `staff_pool/record.rs` `list`: `business_date BETWEEN from AND
  // to`, every row the drink's own, no limit.
  RangeDeriver(
    path: RegExp(r'^/staff-pool/drinks$'),
    kind: RangeKind.date,
    derive: (w, r) => rowsInRange(w, r, 'business_date', RangeKind.date),
  ),
  RangeDeriver(
    path: RegExp(r'^/staff-pool/drinks/summary$'),
    source: (_) => '/staff-pool/drinks',
    kind: RangeKind.date,
    derive: deriveDrinksSummary,
  ),
  // MadarRust `list_attendance`: `business_date BETWEEN from AND to`, every
  // row the record's own (`month_closed` is its own month's), no limit.
  // `ORDER BY business_date DESC, lower(name)`: rows tied on both come in no
  // set order from the server either.
  RangeDeriver(
    path: RegExp(r'^/staff/attendance$'),
    kind: RangeKind.date,
    derive: (w, r) => rowsInRange(w, r, 'business_date', RangeKind.date),
  ),
];

/// The deriver answering [path], if any.
RangeDeriver? deriverFor(String path, [List<RangeDeriver>? registry]) {
  for (final d in registry ?? rangeDerivers) {
    if (d.path.hasMatch(path)) return d;
  }
  return null;
}
