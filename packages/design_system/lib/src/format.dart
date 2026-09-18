/// Display formats — money, elapsed time, a row's timestamp, bidi isolation.
///
/// THE RULES LIVE IN THE CORE. `rust-core/crates/madar-core/src/display.rs` is
/// the source of truth and is exposed on the bridge (`bridge.formatMoney`,
/// `bridge.formatElapsed`, `bridge.formatStamp`,
/// `bridge.currencyLabel`). This file is the kit's SYNCHRONOUS MIRROR of those
/// rules, for the places that cannot cross the bridge: a `Text` inside the
/// kit, a 200-row table's cells. It is not a second opinion — both suites read
/// `docs/design/format_fixtures.json`, and a rule that drifts on either side
/// fails a test on that side.
///
/// Figures are Western digits in both languages (see `MadarType`'s note); only
/// the words and their order change in Arabic. See docs/design/SPEC.md §9.
library;

import 'package:flutter/widgets.dart';

abstract final class MadarFormat {
  /// U+2212 MINUS SIGN — the width of `+`, never a hyphen.
  static const String minus = '\u2212';

  /// U+2066 LEFT-TO-RIGHT ISOLATE.
  static const String lri = '\u2066';

  /// U+2069 POP DIRECTIONAL ISOLATE.
  static const String pdi = '\u2069';

  /// [s] wrapped in an LTR isolate — a figure, a ref, a phone number dropped
  /// into a sentence that may be Arabic. The isolate keeps the figure's own
  /// order AND stops it from reordering the words around it (the
  /// "المبيعات 42 ·" bug).
  static String ltr(String s) => '$lri$s$pdi';

  /// U+2068 FIRST STRONG ISOLATE.
  static const String fsi = '\u2068';

  /// [s] isolated in its OWN direction — for a stamp (`12 سبتمبر · 18:02`
  /// / `Sep 12 · 18:02`) dropped into a sentence. Never [ltr] a stamp: an
  /// LTR isolate flips an Arabic stamp into "سبتمبر 12".
  static String isolate(String s) => '$fsi$s$pdi';

  /// Whether [locale] (`ar`, `ar-EG`, `ar_EG`) is Arabic.
  static bool isArabic(String locale) =>
      locale.split(RegExp('[-_]')).first.toLowerCase() == 'ar';

  /// The language the kit formats in for [context]: the app's [Locale] when
  /// one is installed, else English.
  static String localeOf(BuildContext context) =>
      Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';

  /// `123450` → `1,234.50`. Grouped with `,`, two decimals, no sign.
  static String groupAmount(int minor) {
    final abs = minor.abs();
    final whole = (abs ~/ 100).toString();
    final out = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
      out.write(whole[i]);
    }
    out
      ..write('.')
      ..write((abs % 100).toString().padLeft(2, '0'));
    return out.toString();
  }

  /// `EGP` in English, `ج.م` in Arabic; an unknown code stays the code.
  static String currencyLabel(String code, {String locale = 'en'}) {
    final upper = code.trim().toUpperCase();
    if (!isArabic(locale)) return upper;
    return _arCurrency[upper] ?? upper;
  }

  static const Map<String, String> _arCurrency = {
    'EGP': 'ج.م',
    'SAR': 'ر.س',
    'AED': 'د.إ',
    'KWD': 'د.ك',
    'QAR': 'ر.ق',
    'BHD': 'د.ب',
    'OMR': 'ر.ع',
    'JOD': 'د.أ',
  };

  /// THE money string.
  ///
  /// * English: `EGP 1,234.50` · `−EGP 50.00` · `+EGP 20.00`.
  /// * Arabic: `<LRI>1,234.50<PDI> ج.م` — the signed figure isolated LTR, the label
  ///   after it. Lay an Arabic money string out in the ambient (RTL)
  ///   direction; the isolate already protects the figure.
  ///
  /// [signed] prefixes `+` on a positive amount (a ledger line). Zero is
  /// never signed. An empty [currency] drops the label.
  static String money(
    int minor, {
    String currency = '',
    String locale = 'en',
    bool signed = false,
  }) {
    final sign = minor < 0 ? minus : (signed && minor > 0 ? '+' : '');
    final amount = groupAmount(minor);
    final label = currencyLabel(currency, locale: locale);
    if (isArabic(locale)) {
      final figure = ltr('$sign$amount');
      return label.isEmpty ? figure : '$figure $label';
    }
    return label.isEmpty ? '$sign$amount' : '$sign$label $amount';
  }

  /// How long something has been going: `42m` · `1h 05m` · `2d 03h`; Arabic
  /// `42 د` · `1 س 05 د` · `2 ي 03 س`. Seconds are dropped, a negative
  /// duration reads `0m`. Arabic output must be laid out RTL — never force a
  /// `Text` around it to LTR.
  static String elapsed(Duration d, {String locale = 'en'}) {
    final secs = d.inSeconds < 0 ? 0 : d.inSeconds;
    final mins = secs ~/ 60;
    final hours = mins ~/ 60;
    final days = hours ~/ 24;
    final ar = isArabic(locale);
    String two(int n) => n.toString().padLeft(2, '0');
    if (hours == 0) return ar ? '$mins د' : '${mins}m';
    if (days == 0) {
      final m = two(mins % 60);
      return ar ? '$hours س $m د' : '${hours}h ${m}m';
    }
    final h = two(hours % 24);
    return ar ? '$days ي $h س' : '${days}d ${h}h';
  }

  static const List<String> _enMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const List<String> _arMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  /// A clock time, 12-hour, in [locale]: `06:02 PM`, Arabic `06:02 م`. The
  /// hour is zero-padded — the mirror of the core's `display::hhmm12`. Every
  /// time of day the app shows reads this shape; figures stay Western and
  /// only the meridiem word changes. `docs/design/SPEC.md` §Formats.
  static String clock(int hour, int minute, {String locale = 'en'}) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final meridiem = hour < 12
        ? (isArabic(locale) ? 'ص' : 'AM')
        : (isArabic(locale) ? 'م' : 'PM');
    return '${two(h12)}:${two(minute)} $meridiem';
  }

  /// A row's timestamp, 12-hour: `06:02 PM` on the same day as [now];
  /// `Sep 12 · 06:02 PM` (`12 سبتمبر · 06:02 م`) this year;
  /// `Sep 12, 2025 · 06:02 PM` before. Both are wall-clock in the SAME zone —
  /// the branch's. A screen holding an RFC3339 string asks the bridge instead
  /// (`formatStamp`), which converts the zone.
  static String stamp(DateTime at, DateTime now, {String locale = 'en'}) {
    final time = clock(at.hour, at.minute, locale: locale);
    if (at.year == now.year && at.month == now.month && at.day == now.day) {
      return time;
    }
    final sameYear = at.year == now.year;
    if (isArabic(locale)) {
      final month = _arMonths[at.month - 1];
      return sameYear
          ? '${at.day} $month · $time'
          : '${at.day} $month ${at.year} · $time';
    }
    final month = _enMonths[at.month - 1];
    return sameYear
        ? '$month ${at.day} · $time'
        : '$month ${at.day}, ${at.year} · $time';
  }
}
