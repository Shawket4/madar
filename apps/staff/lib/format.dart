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

/// `HH:mm`, 24-hour — the WIRE shape. The API takes and stores times of day
/// as `HH:mm` (a request's from/to, a timesheet edit); only what a person
/// READS is 12-hour. Never use [formatTimeOfDay] to build a payload.
String hhmmWire(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

/// A wire `HH:mm` (as the API stores a request's from/to) READ BACK for
/// display, 12-hour. Anything that is not `HH:mm` passes through unchanged.
String formatWireTime(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm);
  if (m == null) return hhmm;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return hhmm;
  return formatTimeOfDay(h, min);
}

/// A wall-clock time, 12-hour — a picked time, the live clock. `06:02 PM`,
/// Arabic `06:02 م`. Mirrors the core's `display::hhmm12` and the design
/// system's `MadarFormat.clock`; every time of day the app shows is 12-hour.
String formatTimeOfDay(int hour, int minute) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  final meridiem = hour < 12 ? (_ar ? 'ص' : 'AM') : (_ar ? 'م' : 'PM');
  return '${_two(h12)}:${_two(minute)} $meridiem';
}

/// Renders an instant's 12-hour clock time in the BRANCH's timezone. Wired to the core
/// at boot (`MadarBridge.formatClock`, which reads the zone the staff payloads
/// carry) — the same formatter the till prints with.
String Function(String rfc3339)? branchClock;

/// The 12-hour clock time of an RFC3339 instant, in the branch's timezone — never the
/// phone's. A phone abroad still shows the shop's clock. Without a core
/// (unit tests) the instant reads in UTC, never device-local.
String formatClock(String rfc3339) {
  if (rfc3339.isEmpty) return '—';
  final parsed = DateTime.tryParse(rfc3339);
  if (parsed == null) return '—';
  final viaCore = branchClock;
  if (viaCore != null) return viaCore(rfc3339);
  final t = parsed.toUtc();
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
