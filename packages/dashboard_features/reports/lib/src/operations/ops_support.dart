/// What the Operations tabs share: the web's `fmtDwell` and a stay's
/// elapsed form, the chart and payment colours and the words a failed read
/// shows.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── formatting ────────────────────────────────────────────────────────────

/// `fmtDwell` (`tables-util.ts:131-138`): "—" under a minute, "42m", "1h",
/// "1h 05m" — English letters in both languages, as the web writes them
/// (a clock-like unit; see the divergence log's question).
String fmtDwell(num minutes) {
  final m = (minutes + 0.5).floor();
  if (m < 1) return '—';
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '${h}h' : '${h}h ${r.toString().padLeft(2, '0')}m';
}

/// A sitting's stay (`table-history.tsx` `stay`): "—" under a minute, else
/// the shared elapsed shape (`42m`, `1h 05m`; Arabic `42 د`).
String fmtStay(DashFormat f, num minutes) =>
    minutes < 1 ? '—' : f.fmtElapsedMs(minutes * 60000);

/// `fmtNumber(v, {maximumFractionDigits})`.
String fmtNum(DashFormat f, num? v, {int maxDp = 0, int minDp = 0}) =>
    f.fmtNumber(
      v ?? 0,
      NumberOptions(minimumFractionDigits: minDp, maximumFractionDigits: maxDp),
    );

// ── colours ───────────────────────────────────────────────────────────────

/// The web's chart palette (`--chart-1…6`: brand, info, success, warning,
/// violet, destructive), from the theme's roles.
List<Color> opsChartPalette(MadarColors c) => [
  c.brand,
  c.info,
  c.success,
  c.warning,
  Color.lerp(c.info, c.danger, 0.5)!,
  c.danger,
];

/// `chartColor(i)`.
Color opsChartColor(MadarColors c, int i) {
  final p = opsChartPalette(c);
  return p[i % p.length];
}

/// `PAYMENT_COLORS[method] ?? chartColor(i)`.
Color opsPaymentColor(MadarColors c, String method, int i) => switch (method) {
  'cash' => c.success,
  'card' => c.info,
  'digital_wallet' => Color.lerp(c.info, c.danger, 0.5)!,
  'mixed' => c.warning,
  'talabat_online' => Color.lerp(c.warning, c.danger, 0.45)!,
  'talabat_cash' => Color.lerp(c.warning, c.danger, 0.2)!,
  _ => opsChartColor(c, i),
};

// ── errors ────────────────────────────────────────────────────────────────

/// `getErrorMessage`: a coded refusal in the language's words
/// (`errors.codes.<CODE>`, e.g. the export throttle), else the server's
/// message.
String opsErrorText(Object? e, Translator t) {
  if (e is ApiException) {
    final code = e.code;
    if (code != null && t.exists('errors.codes.$code')) {
      return t('errors.codes.$code');
    }
  }
  return errorMessage(e, t);
}

/// React Query's `isLoading`: the first load, with nothing to show yet.
extension OpsAsync<T> on AsyncValue<T> {
  bool get firstLoad => isLoading && !hasValue && !hasError;
}
