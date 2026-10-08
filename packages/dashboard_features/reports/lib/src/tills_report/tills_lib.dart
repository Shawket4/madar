/// The arithmetic behind the Till sessions report, ported from the web's
/// `features/reports/tills/lib.ts` (inventory section 11.4, "Tills"):
///
/// - [meanTimeOfDay]: the CIRCULAR mean of clock times (a plain mean of
///   23:50 and 00:10 is noon, the one time neither till was open);
/// - [salesStats]: the bill average is over orders, not tills;
/// - [timingStats]: length only for closed sessions with a non-negative
///   span, the longest such session, how many are still running;
/// - [byHour]: opens and closes in 24 local-hour buckets;
/// - [isRangeRefused]: the API's 400 for a range it will not list whole.
///
/// Every clock reading is in the active zone (the branch's, else the org's),
/// never the device's.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, TillSessionRow;
import 'package:dashboard_core/dashboard_core.dart';

/// JavaScript's `Math.round` (half up, toward +∞), not Dart's half away
/// from zero.
int jsRound(num v) => (v + 0.5).floor();

/// Minutes past local midnight of [instant] in [zone].
int minutesOfDay(DateTime instant, String zone) {
  final z = inZone(instant, zone);
  return z.hour * 60 + z.minute;
}

/// The local hour (0–23) of [instant] in [zone].
int hourOf(DateTime instant, String zone) => inZone(instant, zone).hour;

/// The average time of day of [minutes] (each past midnight), averaged as
/// angles on the clock face: null when there is nothing to average or the
/// times cancel out exactly (opens spread evenly round the clock have no
/// centre — saying 00:00 would be a fiction).
int? meanTimeOfDay(List<int> minutes) {
  if (minutes.isEmpty) return null;
  var x = 0.0;
  var y = 0.0;
  for (final m in minutes) {
    final angle = m / 1440 * 2 * math.pi;
    x += math.cos(angle);
    y += math.sin(angle);
  }
  if (x.abs() < 1e-9 && y.abs() < 1e-9) return null;
  final mean = math.atan2(y / minutes.length, x / minutes.length);
  final mins = jsRound(mean / (2 * math.pi) * 1440);
  return ((mins % 1440) + 1440) % 1440;
}

/// Minutes past midnight on the app's 12-hour clock (`07:05 AM`,
/// `07:05 م`), the same shape as the table's Opened at; "—" for null.
String fmtMinutesOfDay(DashFormat f, int? mins) {
  if (mins == null) return '—';
  final h = (mins ~/ 60).toString().padLeft(2, '0');
  final m = (mins % 60).toString().padLeft(2, '0');
  return f.fmtWireTime('$h:$m');
}

/// The drawer is still running (`status` is the API's word for it).
bool isOpen(TillSessionRow r) => r.status == 'open';

/// Closed by a manager without the teller's count: Declared and Variance
/// are unknown, not zero.
bool isForceClosed(TillSessionRow r) => r.status == 'force_closed';

/// The API refuses a range it will not list whole (400: more than 5000
/// sessions, or `to` before `from`). Retrying cannot help; a shorter period
/// can.
bool isRangeRefused(Object? error) =>
    error is ApiException && error.status == 400;

/// The Status column of the export: "Open" / "Force-closed" / "Closed".
String tillStatusLabel(Translator t, TillSessionRow r) => isOpen(r)
    ? t('reports.tills.stillOpen')
    : isForceClosed(r)
    ? t('reports.tills.forceClosed')
    : t('reports.tills.statusClosed');

/// The Sales tab's sums (money in piastres).
class TillSalesStats {
  const TillSalesStats({
    required this.tills,
    required this.orders,
    required this.sales,
    required this.avgOrderValue,
    required this.avgSalesPerTill,
  });

  final int tills;
  final int orders;

  /// Net of refunds: the API's `net_sales`.
  final int sales;

  /// The average bill over every sale of the period.
  final int avgOrderValue;

  /// The average takings per till session.
  final int avgSalesPerTill;
}

TillSalesStats salesStats(List<TillSessionRow> rows) {
  final orders = rows.fold<int>(0, (n, r) => n + r.ordersCount);
  final sales = rows.fold<int>(0, (n, r) => n + r.netSales);
  return TillSalesStats(
    tills: rows.length,
    orders: orders,
    sales: sales,
    avgOrderValue: orders > 0 ? jsRound(sales / orders) : 0,
    avgSalesPerTill: rows.isNotEmpty ? jsRound(sales / rows.length) : 0,
  );
}

/// The Open & close tab's figures.
class TillTimingStats {
  const TillTimingStats({
    required this.avgOpen,
    required this.avgClose,
    required this.avgDurationMs,
    required this.longest,
    required this.openNow,
  });

  /// Minutes past midnight, circular-averaged.
  final int? avgOpen;
  final int? avgClose;

  /// Milliseconds; only closed sessions have a length.
  final int? avgDurationMs;
  final TillSessionRow? longest;

  /// Sessions still running: no close time to average.
  final int openNow;
}

/// The session's length in milliseconds, null while it runs.
int? durationMs(TillSessionRow r) {
  final closed = r.closedAt;
  if (closed == null) return null;
  return closed.millisecondsSinceEpoch - r.openedAt.millisecondsSinceEpoch;
}

TillTimingStats timingStats(List<TillSessionRow> rows, String zone) {
  final closed = [
    for (final r in rows)
      if (r.closedAt != null) r,
  ];
  TillSessionRow? longest;
  var longestMs = 0;
  var total = 0;
  var measured = 0;
  for (final r in closed) {
    final ms = durationMs(r);
    // A clock skew or a bad close can land a negative span: it is not an
    // average of anything.
    if (ms == null || ms < 0) continue;
    total += ms;
    measured += 1;
    if (longest == null || ms > longestMs) {
      longest = r;
      longestMs = ms;
    }
  }
  return TillTimingStats(
    avgOpen: meanTimeOfDay([
      for (final r in rows) minutesOfDay(r.openedAt, zone),
    ]),
    avgClose: meanTimeOfDay([
      for (final r in closed) minutesOfDay(r.closedAt ?? r.openedAt, zone),
    ]),
    avgDurationMs: measured > 0 ? jsRound(total / measured) : null,
    longest: longest,
    openNow: rows.length - closed.length,
  );
}

/// One hour of the opens-and-closes chart.
class TillHourBucket {
  TillHourBucket(this.hour);

  final int hour;
  int opened = 0;
  int closed = 0;
}

/// Opens and closes by local hour: a session past midnight counts in the
/// hour it opened AND the hour it closed.
List<TillHourBucket> byHour(List<TillSessionRow> rows, String zone) {
  final buckets = [for (var h = 0; h < 24; h++) TillHourBucket(h)];
  for (final r in rows) {
    buckets[hourOf(r.openedAt, zone)].opened += 1;
    final closed = r.closedAt;
    if (closed != null) buckets[hourOf(closed, zone)].closed += 1;
  }
  return buckets;
}

/// [rows] by net sales, best first; ties keep the API's order (newest
/// first), as the web's stable sort does.
List<TillSessionRow> rankBySales(List<TillSessionRow> rows) {
  final indexed = [for (final (i, r) in rows.indexed) (i, r)];
  indexed.sort((a, b) {
    final d = b.$2.netSales.compareTo(a.$2.netSales);
    return d != 0 ? d : a.$1.compareTo(b.$1);
  });
  return [for (final (_, r) in indexed) r];
}
