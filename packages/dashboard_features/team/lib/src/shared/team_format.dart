/// The team area's own figure formats (`staff/util.ts`, `inputs/time.ts`),
/// on top of dashboard_core's `DashFormat` (money, dates, `fmtWireTime`,
/// `fmtElapsedMs`), and "today" in the active zone (TEAM-ALL-012).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "42m", "7h 25m", "1d 03h" from a minute count (`fmtMinutes`): attendance
/// cells and the Team board's "late". Arabic units with a space, in an RTL
/// isolate; a negative count keeps its true minus inside the isolate; null →
/// "—".
String fmtMinutes(DashFormat f, num? minutes) {
  if (minutes == null) return '—';
  final out = f.fmtElapsedMs(minutes.abs() * 60000);
  if (minutes >= 0) return out;
  // Arabic opens with the isolate's mark (RLI): the minus goes after it.
  final open = f.isArabic ? out.substring(0, 1) : '';
  return '$open$minusSign${out.substring(open.length)}';
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
  // An LTR isolate would show "9 س 4 د" as "9 د 4 س" to an Arabic reader.
  return ar ? rtl(signed) : signed;
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

/// The line's start edge as a fixed side: free text set in its own direction
/// (`dashTextDirectionOf`, the web's `dir="auto"`) in a custom table cell
/// still sits where the kit's own cells put it.
TextAlign startEdge(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? TextAlign.right
    : TextAlign.left;
