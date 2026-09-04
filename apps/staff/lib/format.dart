import 'package:intl/intl.dart';

import 'app/providers.dart';

/// `HH:mm` from an RFC3339 instant, in the device's local zone.
///
/// The BUSINESS date always comes from the server (in the branch's timezone);
/// only the wall-clock rendering of an instant is local, which is what someone
/// looking at their phone expects to see.
String formatClock(String rfc3339) {
  if (rfc3339.isEmpty) return '—';
  final parsed = DateTime.tryParse(rfc3339);
  if (parsed == null) return '—';
  return DateFormat.Hm().format(parsed.toLocal());
}

/// `d MMM` — compact enough for a list row.
String formatDay(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('d MMM').format(parsed);
}

/// Minutes as "7h 25m" / "25 min". Zero is an em-dash, not "0m": on an
/// attendance row, nothing recorded and nothing worked read very differently.
String formatDuration(int minutes, Translate t) {
  if (minutes <= 0) return '—';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return t('common.minutes', {'n': '$m'});
  return t('common.hoursMinutes', {'h': '$h', 'm': '$m'});
}

/// Centidays back to a human day count: 250 → "2.5", 300 → "3".
String formatDays(int centidays) {
  final days = centidays / 100;
  return days == days.roundToDouble()
      ? days.round().toString()
      : days.toStringAsFixed(1);
}

/// Piastres → a display amount. The core keeps money in integer minor units all
/// the way to here precisely so no float ever touches a payslip.
String formatMoney(int minor, String currency) {
  final major = minor / 100;
  final formatted = NumberFormat('#,##0.##').format(major);
  return currency.isEmpty ? formatted : '$currency $formatted';
}

/// `yyyy-mm-dd` for an API range parameter.
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// "Saturday 15 August" — the line under the live clock.
String formatLongDate(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('EEEE d MMMM').format(parsed);
}

/// "Mon 17" — a weekday with its day number, for the next-shift strip.
String formatWeekday(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('EEE d').format(parsed);
}

/// "Sat" — the three-letter weekday on a date tile.
String formatWeekdayShort(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('EEE').format(parsed);
}

/// The day number alone, for a date tile.
String dayOfMonth(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  return parsed == null ? isoDate : '${parsed.day}';
}

/// "15–21 August" — a week pager's label.
String formatRange(String fromIso, String toIso) {
  final from = DateTime.tryParse(fromIso);
  final to = DateTime.tryParse(toIso);
  if (from == null || to == null) return '$fromIso – $toIso';
  final month = DateFormat('MMMM');
  return from.month == to.month
      ? '${from.day}–${to.day} ${month.format(to)}'
      : '${from.day} ${month.format(from)} – ${to.day} ${month.format(to)}';
}

/// Piastres → `4,471.50`, thousands-separated, always two decimals.
///
/// The currency word is placed by the CALLER (prefix in English, suffix in
/// Arabic), so this returns the bare figure. A leading minus survives.
String formatAmount(int minor) {
  final negative = minor < 0;
  final major = minor.abs() / 100;
  final text = NumberFormat('#,##0.00').format(major);
  return negative ? '−$text' : text;
}
