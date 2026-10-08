/// The team area's own figure formats (`staff/util.ts`, `inputs/time.ts`),
/// on top of dashboard_core's `DashFormat` (money, dates, `fmtWireTime`,
/// `fmtElapsedMs`), and "today" in the active zone (TEAM-ALL-012).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "42m", "7h 25m", "1d 03h" from a minute count (`fmtMinutes`): attendance
/// cells and the Team board's "late". Arabic units with a space, in an LTR
/// isolate; a negative count keeps its true minus inside the isolate; null →
/// "—".
String fmtMinutes(DashFormat f, num? minutes) {
  if (minutes == null) return '—';
  final out = f.fmtElapsedMs(minutes.abs() * 60000);
  if (minutes >= 0) return out;
  return out.startsWith(lri)
      ? '$lri$minusSign${out.substring(lri.length)}'
      : '$minusSign$out';
}

/// A span of work in hours and minutes, never days (`fmtHours`): "56h",
/// "7h 25m", "45m"; Arabic "س"/"د" with a space, wrapped LTR; negative → true
/// minus; null → "—".
String fmtHours(String lang, num? minutes) {
  if (minutes == null) return '—';
  final ar = lang == 'ar';
  final (h, m, sep) = ar ? ('س', 'د', ' ') : ('h', 'm', '');
  final total = minutes.abs().round();
  final hours = total ~/ 60;
  final rest = total % 60;
  final out = hours == 0
      ? '$rest$sep$m'
      : rest == 0
      ? '$hours$sep$h'
      : '$hours$sep$h $rest$sep$m';
  final signed = minutes < 0 ? '$minusSign$out' : out;
  return ar ? ltr(signed) : signed;
}

/// A shift's length (`formatSpan`): "8 h", "8 h 30 min", "45 min"; Arabic
/// "س"/"د".
String formatSpan(num minutes, String lang) {
  final total = minutes.round() < 0 ? 0 : minutes.round();
  final h = total ~/ 60;
  final m = total % 60;
  final hh = lang == 'ar' ? 'س' : 'h';
  final mm = lang == 'ar' ? 'د' : 'min';
  if (h == 0) return '$m $mm';
  if (m == 0) return '$h $hh';
  return '$h $hh $m $mm';
}

/// The ISO date [n] days from today, "today" being the calendar day in
/// [timezone] at [now] (`isoDaysFromToday`): UTC is still yesterday from
/// midnight to 03:00 in Cairo.
String isoDaysFromToday(
  int n, {
  required String timezone,
  required DateTime now,
}) {
  final local = inZone(now, timezone);
  final d = DateTime.utc(local.year, local.month, local.day + n);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Today in the active branch/org zone, by the app clock (`todayIso`).
String teamTodayIso(Ref ref, [int days = 0]) => isoDaysFromToday(
  days,
  timezone: ref.read(activeTimezoneProvider),
  now: ref.read(clockProvider)(),
);

/// [teamTodayIso] for widgets.
String teamTodayIsoOf(WidgetRef ref, [int days = 0]) => isoDaysFromToday(
  days,
  timezone: ref.read(activeTimezoneProvider),
  now: ref.read(clockProvider)(),
);
