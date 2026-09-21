import 'package:design_system/design_system.dart';
import 'package:staff_core/src/data.dart';

/// The core's words: madar-core `i18n.rs`, the one table every Madar app
/// reads. Installed at boot — the staff bridge's `tr` on a device, the
/// i18n.rs reader in tests.
String Function(String key) words = (key) => key;

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

/// Content that arrives already bilingual (names; what the server words).
String loc(Bilingual b) => isAr ? b.ar : b.en;

/// Money is piastres everywhere; pounds exist only here (AT-2).
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
String dayMonth(DateTime d) => '${d.day} ${tr('staff.month_${d.month}')}';
String dayLabel(DateTime d) => '${weekday(d.weekday)} ${dayMonth(d)}';
String mins(int m) => m >= 60
    ? tr('staff.hours_minutes', {
        'h': m ~/ 60,
        'm': (m % 60).toString().padLeft(2, '0'),
      })
    : tr('staff.minutes', {'m': m});
