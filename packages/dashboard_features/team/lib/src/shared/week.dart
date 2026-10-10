/// The Dawam week (TEAM-ALL-011): it runs Saturday → Friday in every week
/// view, and a weekday on the wire is Postgres `EXTRACT(DOW)`: 0 = Sunday …
/// 6 = Saturday (`staff/util.ts` `WEEKDAYS`, `lib/week.ts` `WEEK_ORDER`,
/// `dawam/week.ts`, `inputs/weekday-picker.tsx` `summarizeDays`).
///
/// Dates here are ISO `yyyy-mm-dd` calendar dates, never moved through a
/// time zone: a branch's day is the day the server named.
library;

import 'package:dashboard_kit/dashboard_kit.dart' show DashKitFormats;

/// The first day of the week: Saturday, as a DOW number.
const int weekStartDow = 6;

/// DOW numbers in week order: Sat, Sun, Mon, Tue, Wed, Thu, Fri.
const List<int> weekOrder = [6, 0, 1, 2, 3, 4, 5];

/// The short label key of each DOW (`WEEKDAYS`): `staff.sun` … `staff.sat`,
/// indexed by DOW.
const List<String> weekdayKeys = [
  'staff.sun',
  'staff.mon',
  'staff.tue',
  'staff.wed',
  'staff.thu',
  'staff.fri',
  'staff.sat',
];

/// A weekday's name in [lang] (`weekdayName`): `Sat` / `السبت`; [dow] is
/// 0 = Sunday … 6 = Saturday.
String weekdayName(int dow, String lang) {
  // weekdaysShort() starts on Saturday.
  final names = DashKitFormats(languageCode: lang).weekdaysShort();
  return names[(dow - weekStartDow + 7) % 7];
}

/// Summarises a set of weekdays in week order (`summarizeDays`): all seven →
/// [everyDay], none → [none], a run of three or more → "Sat – Wed", shorter
/// runs listed "Thu, Fri" (Arabic separator "، ").
String summarizeDays(
  Iterable<int> days,
  String lang,
  String everyDay,
  String none,
) {
  final set = days.toSet();
  if (set.length == 7) return everyDay;
  if (set.isEmpty) return none;
  final ordered = [
    for (final d in weekOrder)
      if (set.contains(d)) d,
  ];
  final runs = <List<int>>[];
  for (final d in ordered) {
    final last = runs.isEmpty ? null : runs.last;
    if (last != null &&
        weekOrder.indexOf(d) == weekOrder.indexOf(last.last) + 1) {
      last.add(d);
    } else {
      runs.add([d]);
    }
  }
  final sep = lang == 'ar' ? '، ' : ', ';
  return runs
      .map(
        (r) => r.length >= 3
            ? '${weekdayName(r.first, lang)} – ${weekdayName(r.last, lang)}'
            : r.map((d) => weekdayName(d, lang)).join(sep),
      )
      .join(sep);
}

DateTime _toDate(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String _toIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// [iso] moved by [n] calendar days.
String addDays(String iso, int n) =>
    _toIso(_toDate(iso).add(Duration(days: n)));

/// 0 = Sunday … 6 = Saturday, the backend's weekday numbering.
int weekdayOf(String iso) => _toDate(iso).weekday % 7;

/// The Saturday on or before [iso].
String weekStartOf(String iso) => addDays(iso, -((weekdayOf(iso) + 1) % 7));

/// The seven ISO dates of the week starting [start].
List<String> weekDays(String start) => [
  for (var i = 0; i < 7; i++) addDays(start, i),
];

/// Whole weeks from the week holding [today] to the week starting [week]
/// (`weeksFromNow`): 0 this week, 1 next, −1 last.
int weeksFromNow(String week, String today) =>
    (_toDate(week).difference(_toDate(weekStartOf(today))).inDays / 7).round();
