import 'package:design_system/design_system.dart';
import 'package:staff_core/src/data.dart';

/// The core's words: madar-core `i18n.rs`, the one table every Madar app
/// reads. Installed at boot — the staff bridge's `tr` on a device, the
/// i18n.rs reader in tests.
String Function(String key) words = (key) => key;

/// The core's words in a named language (`en` / `ar`), whatever the app's:
/// the payslip PDF prints in the language picked on its button (PAY-10).
/// Installed at boot beside [words].
String Function(String lang, String key) wordsIn = (lang, key) => key;

/// [tr] in a named language.
String trIn(String lang, String key, [Map<String, Object> args = const {}]) {
  var s = wordsIn(lang, key);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// The active language, kept in step by `localeProvider` (the dashboard's
/// `formatLocale` pattern) so formatting helpers need no `ref`.
String currentLang = 'ar';

/// The phone's 12/24-hour setting (APP-5), read by the app root.
bool use24h = false;

bool get isAr => currentLang == 'ar';

/// A core string with its `{placeholders}` filled, as the POS fills its own.
/// A date argument is written the way every date here is.
String tr(String key, [Map<String, Object> args = const {}]) {
  var s = words(key);
  args.forEach((k, v) {
    s = s.replaceAll('{$k}', v is DateTime ? dayMonth(v) : '$v');
  });
  return s;
}

/// The CLDR plural category of a count [n] in [lang] (the language on
/// screen by default): English `one` / `other`; Arabic `zero`, `one`, `two`,
/// `few` (3–10), `many` (11–99) and `other` (100, 101, 102, …), counted on
/// the last two digits as Arabic counts (103 is few, 111 many).
String pluralOf(int n, [String? lang]) {
  final c = n.abs();
  if ((lang ?? currentLang) != 'ar') return c == 1 ? 'one' : 'other';
  final r = c % 100;
  return switch (c) {
    0 => 'zero',
    1 => 'one',
    2 => 'two',
    _ when r >= 3 && r <= 10 => 'few',
    _ when r >= 11 => 'many',
    _ => 'other',
  };
}

/// [tr] for a phrase with a count [n]: the core's form for it, `<key>_one`,
/// `_two`, `_few`, `_many` (i18n.rs, PLURAL FORMS), else [key] itself, the
/// "other" form. [args] fills it as [tr] does, the count included ("1
/// person has no salary", never "1 people have").
String trCount(String key, int n, [Map<String, Object> args = const {}]) {
  final form = '${key}_${pluralOf(n)}';
  return tr(words(form) == form ? key : form, args);
}

/// Content that arrives already bilingual (names; what the server words).
String loc(Bilingual b) => isAr ? b.ar : b.en;

/// Money is piastres everywhere; pounds exist only here (AT-2).
/// A figure the server may not have sent: "—" rather than a made-up 0.
String egpOrDash(int? minor) => minor == null ? '—' : egp(minor);

String egp(int minor, {bool signed = false}) => MadarFormat.money(
  minor,
  currency: 'EGP',
  locale: currentLang,
  signed: signed,
);

/// Latin digits in both languages (APP-4).
String hm(DateTime d) {
  final m = d.minute.toString().padLeft(2, '0');
  if (use24h) return '${d.hour.toString().padLeft(2, '0')}:$m';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:$m ${d.hour < 12 ? tr('staff.am') : tr('staff.pm')}';
}

String hmMin(int minuteOfDay) =>
    hm(DateTime(2000).add(Duration(minutes: minuteOfDay)));

String weekday(int w) => tr('staff.day_$w');

/// A weekday that recurs: "Fridays" ("can't work on Fridays").
String weekdays(int w) => tr('staff.weekdays_$w');

/// "Omar said they can't work on Fridays." (E2E roster m1: the day in full,
/// never "Fris").
String cantWorkWords(String name, int w) =>
    tr('staff.said_they_can_t_work_s', {'name': name, 'day': weekdays(w)});

String dayMonth(DateTime d) => '${d.day} ${tr('staff.month_${d.month}')}';
String dayLabel(DateTime d) => '${weekday(d.weekday)} ${dayMonth(d)}';
String mins(int m) => m >= 60
    ? tr('staff.hours_minutes', {
        'h': m ~/ 60,
        'm': (m % 60).toString().padLeft(2, '0'),
      })
    : tr('staff.minutes', {'m': m});
