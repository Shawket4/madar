import 'package:design_system/design_system.dart';
import 'package:intl/intl.dart';

import 'app/providers.dart';

/// The language dates are written in. [LocaleNotifier] keeps it in step with
/// the UI. Dates follow the display contract (docs/design/SPEC.md §9,
/// docs/design/format_fixtures.json): 24-hour `HH:mm`, Latin digits in both
/// languages, `Sep 12` / `12 سبتمبر` — never intl's locale digits.
String formatLocale = 'en';

bool get _ar => MadarFormat.isArabic(formatLocale);

String _two(int n) => n.toString().padLeft(2, '0');

const _enMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _arMonths = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];
const _enDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _arDays = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

String _month(DateTime d, {bool short = false}) {
  if (_ar) return _arMonths[d.month - 1];
  final m = _enMonths[d.month - 1];
  return short ? m.substring(0, 3) : m;
}

String _weekday(DateTime d, {bool short = false}) {
  if (_ar) return _arDays[d.weekday - 1];
  final w = _enDays[d.weekday - 1];
  return short ? w.substring(0, 3) : w;
}

/// `HH:mm` of a wall-clock time — a picked time, the live clock.
String formatTimeOfDay(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

/// `HH:mm` from an RFC3339 instant, in the device's local zone.
///
/// The BUSINESS date always comes from the server (in the branch's timezone);
/// only the wall-clock rendering of an instant is local, which is what someone
/// looking at their phone expects to see.
String formatClock(String rfc3339) {
  if (rfc3339.isEmpty) return '—';
  final parsed = DateTime.tryParse(rfc3339);
  if (parsed == null) return '—';
  final t = parsed.toLocal();
  return formatTimeOfDay(t.hour, t.minute);
}

/// `Sep 12` / `12 سبتمبر` — compact enough for a list row.
String formatDay(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  final m = _month(parsed, short: true);
  return _ar ? '${parsed.day} $m' : '$m ${parsed.day}';
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
  return '${_weekday(parsed)} ${parsed.day} ${_month(parsed)}';
}

/// "Mon 17" — a weekday with its day number, for the next-shift strip.
String formatWeekday(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return '${_weekday(parsed, short: true)} ${parsed.day}';
}

/// "Sat" — the three-letter weekday on a date tile.
String formatWeekdayShort(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return _weekday(parsed, short: true);
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
  return from.month == to.month
      ? '${from.day}–${to.day} ${_month(to)}'
      : '${from.day} ${_month(from)} – ${to.day} ${_month(to)}';
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
