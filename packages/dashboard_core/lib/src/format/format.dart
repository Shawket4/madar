/// The web's `src/lib/format.ts`, ported exactly: one money shape for the
/// whole ecosystem, Western digits in both languages, 12-hour clocks, every
/// date in the branch's time zone (never the device's).
///
/// The web reads the language and the zone from global state; here they are
/// fields of [DashFormat] (the `formatProvider` builds one from the active
/// language and scope). Method names keep the web's, so a port reads 1:1:
/// `fmt.fmtMoney(row.total)`.
library;

import 'package:dashboard_core/src/format/icu_number.dart';
import 'package:dashboard_core/src/format/tz.dart';

export 'package:dashboard_core/src/format/icu_number.dart'
    show NumberOptions, SignDisplay;

/// The web's `DEFAULT_CURRENCY`.
const String defaultCurrency = 'EGP';

/// U+2212, the true minus.
const String minusSign = '−';

/// Left-to-right isolate / pop directional isolate.
const String lri = '\u2066';
const String pdi = '\u2069';

/// Wrap a figure so it reads left-to-right inside RTL text.
String ltr(String s) => '$lri$s$pdi';

const Map<String, String> _currencyAr = {
  'EGP': 'ج.م',
  'SAR': 'ر.س',
  'AED': 'د.إ',
  'KWD': 'د.ك',
  'QAR': 'ر.ق',
  'BHD': 'د.ب',
  'OMR': 'ر.ع',
  'JOD': 'د.أ',
};

/// Chart period granularity (`fmtPeriod`).
enum PeriodGranularity { hourly, daily, monthly, peakHours, peakDays }

/// Piastres (integer) -> pounds.
double piastresToEgp(num p) => p / 100;

/// Pounds (user input) -> integer piastres. Rounds, never truncates:
/// `19.99 * 100` is `1998.9999…`.
int egpToPiastres(num egp) => _jsRound(egp * 100);

int _jsRound(num v) => (v + 0.5).floor();

/// `initials("Ahmad Ghazal")` -> `AG`.
String initials([String name = '']) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

/// Display unit: `l` -> `L`, everything else as given; null -> ''.
String fmtUnit(String? unit) {
  const map = {'g': 'g', 'kg': 'kg', 'ml': 'ml', 'l': 'L', 'pcs': 'pcs'};
  if (unit == null || unit.isEmpty) return '';
  return map[unit] ?? unit;
}

/// A discount's stored value: a FRACTION for a percentage, minor units for a
/// fixed one. Reads `value_rate`, falling back to the legacy 0-100 `value`.
num rateOf({required num value, num? valueRate, String? dtype}) =>
    valueRate ?? (dtype == 'percentage' ? value / 100 : value);

/// The formatter for one language and one zone.
class DashFormat {
  const DashFormat({
    this.lang = 'en',
    this.timezone = appTimezone,
    this.currency = defaultCurrency,
    DateTime Function()? clock,
  }) : _clock = clock;

  /// `en` or `ar`.
  final String lang;

  /// The active branch/org zone (IANA).
  final String timezone;

  /// The currency money is labelled with. The web always uses its
  /// `DEFAULT_CURRENCY`; kept a field so a non-EGP org can be shown later.
  final String currency;

  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  bool get isArabic => lang.startsWith('ar');

  /// `en-GB` / `ar-EG`, the web's `getLocale()`.
  String get icuLocale => isArabic ? 'ar-EG' : 'en-GB';

  DashFormat copyWith({String? lang, String? timezone, String? currency}) =>
      DashFormat(
        lang: lang ?? this.lang,
        timezone: timezone ?? this.timezone,
        currency: currency ?? this.currency,
        clock: _clock,
      );

  // ── Money ──────────────────────────────────────────────────────────────

  /// The currency's label in the active language: `EGP` / `ج.م`.
  String currencyLabel([String? code]) {
    final c = code ?? currency;
    return isArabic ? (_currencyAr[c] ?? c) : c;
  }

  String _moneyShape(String figure, String sign) {
    final signChar = sign == '-' ? minusSign : sign;
    final label = currencyLabel();
    return isArabic
        ? '${ltr('$signChar$figure')} $label'
        : '$signChar$label $figure';
  }

  /// Piastres as money: `EGP 1,234.50` / `1,234.50 ج.م` (LTR-isolated). Two decimals by
  /// default; [maxFractionDigits] 0 rounds to whole pounds. Null (or not
  /// finite) means "unknown", not free: an em dash.
  String fmtMoney(
    num? piastres, {
    int? fractionDigits,
    int? maxFractionDigits,
    bool signed = false,
    bool currency = true,
  }) {
    if (piastres == null || !piastres.isFinite) return '—';
    final value = piastresToEgp(piastres);
    final fd = fractionDigits ?? 2;
    final max = maxFractionDigits ?? (fd > 2 ? fd : 2);
    final min = fd < max ? fd : max;
    final figure = icuDecimal(
      'en-US',
      value.abs(),
      NumberOptions(minimumFractionDigits: min, maximumFractionDigits: max),
    );
    final zero = num.parse(figure.replaceAll(',', '')) == 0;
    final sign = zero ? '' : (value < 0 ? '-' : (signed ? '+' : ''));
    if (!currency) {
      final s = '${sign == '-' ? minusSign : sign}$figure';
      return isArabic ? ltr(s) : s;
    }
    return _moneyShape(figure, sign);
  }

  /// Signed ledger money: `+EGP 20.00` / `−EGP 50.00`.
  String fmtMoneySigned(num? piastres) => fmtMoney(piastres, signed: true);

  /// Compact money: `EGP 1.2K`. Null renders an em dash.
  String fmtMoneyCompact(num? piastres) {
    if (piastres == null || !piastres.isFinite) return '—';
    final value = piastresToEgp(piastres);
    final figure = icuCompact('en-US', value.abs(), maximumFractionDigits: 1);
    return _moneyShape(figure, value < 0 && figure != '0' ? '-' : '');
  }

  // ── Numbers ────────────────────────────────────────────────────────────

  /// A plain number in the language, Western digits, true minus.
  String fmtNumber(num? n, [NumberOptions opts = const NumberOptions()]) =>
      icuDecimal(icuLocale, n ?? 0, opts).replaceAll('-', minusSign);

  /// Compact plain number: `2.2K` / `2.2 ألف`.
  String fmtNumberCompact(num? n) => icuCompact(
    icuLocale,
    n ?? 0,
    maximumFractionDigits: 1,
  ).replaceAll('-', minusSign);

  /// A ratio as a percentage with up to one decimal: `12.3%`.
  String fmtPercent(num ratio) => icuPercent(
    icuLocale,
    ratio,
    const NumberOptions(maximumFractionDigits: 1),
  ).replaceAll('-', minusSign);

  /// A part's share of a total; 0% when the total is 0.
  String fmtShare(num part, num total) {
    if (total == 0 || total.isNaN) return fmtPercent(0);
    return fmtPercent(part / total);
  }

  // ── Dates ──────────────────────────────────────────────────────────────

  static const List<String> _monthsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  String _month(int month1) => (isArabic ? _monthsAr : _monthsEn)[month1 - 1];

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `06:02 PM` / `06:02 م` (the web's `upMeridiem` applied).
  String _clock12(int hour, int minute) {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final pm = hour >= 12;
    final mer = isArabic ? (pm ? 'م' : 'ص') : (pm ? 'PM' : 'AM');
    return '${_two(h12)}:${_two(minute)} $mer';
  }

  String get _comma => isArabic ? '،' : ',';

  DateTime? _instant(Object? iso) {
    if (iso == null || (iso is String && iso.isEmpty)) return null;
    final d = parseJsDate(iso);
    // `new Intl.DateTimeFormat().format(new Date("nope"))` throws.
    if (d == null) throw RangeError('Invalid time value');
    return d;
  }

  /// `12 Sept 2026` / `12 سبتمبر 2026`.
  String fmtDate(Object? iso) {
    final d = _instant(iso);
    if (d == null) return '—';
    final z = inZone(d, timezone);
    return '${_two(z.day)} ${_month(z.month)} ${z.year}';
  }

  /// `06:02 PM`, in [tz] (a record's branch) or the active zone.
  String fmtTime(Object? iso, [String? tz]) {
    final d = _instant(iso);
    if (d == null) return '—';
    final z = inZone(d, tz ?? timezone);
    return _clock12(z.hour, z.minute);
  }

  /// `12 Sept, 06:02 PM`, in [tz] or the active zone.
  String fmtDateTime(Object? iso, [String? tz]) {
    final d = _instant(iso);
    if (d == null) return '—';
    final z = inZone(d, tz ?? timezone);
    return '${_two(z.day)} ${_month(z.month)}$_comma ${_clock12(z.hour, z.minute)}';
  }

  /// `12 Sept 2026, 06:02 PM`.
  String fmtDateTimeFull(Object? iso) {
    final d = _instant(iso);
    if (d == null) return '—';
    final z = inZone(d, timezone);
    return '${_two(z.day)} ${_month(z.month)} ${z.year}$_comma '
        '${_clock12(z.hour, z.minute)}';
  }

  /// Elapsed time: `0m` · `42m` · `1h 05m` · `1d 03h` (ar `42 د` …, isolated).
  String fmtElapsedMs(num ms) {
    var v = ms;
    if (!v.isFinite || v < 0) v = 0;
    final (d, h, m) = isArabic ? ('ي', 'س', 'د') : ('d', 'h', 'm');
    final sep = isArabic ? ' ' : '';
    final mins = (v / 60000).floor();
    final days = mins ~/ 1440;
    final hours = (mins % 1440) ~/ 60;
    final rest = mins % 60;
    final out = days > 0
        ? '$days$sep$d ${_two(hours)}$sep$h'
        : hours > 0
        ? '$hours$sep$h ${_two(rest)}$sep$m'
        : '$rest$sep$m';
    return isArabic ? ltr(out) : out;
  }

  /// From [start] to [end] (or now).
  String fmtDuration(Object? start, [Object? end]) {
    if (start == null || (start is String && start.isEmpty)) return '—';
    final s = parseJsDate(start);
    final e = end == null ? _now : parseJsDate(end);
    if (s == null || e == null) return '—';
    return fmtElapsedMs(e.millisecondsSinceEpoch - s.millisecondsSinceEpoch);
  }

  String _dayKey(DateTime instant) {
    final z = inZone(instant, timezone);
    return '${z.year.toString().padLeft(4, '0')}-${_two(z.month)}-${_two(z.day)}';
  }

  /// A moment, as short as it can be: `06:02 PM` today · `12 Sept · 06:02
  /// PM` this year · `31 Dec 2025 · 11:30 PM` otherwise.
  String fmtStamp(Object? iso, [DateTime? now]) {
    if (iso == null || (iso is String && iso.isEmpty)) return '—';
    final d = parseJsDate(iso);
    if (d == null) return '—';
    final n = now ?? _now;
    final z = inZone(d, timezone);
    final time = _clock12(z.hour, z.minute);
    final dk = _dayKey(d);
    final nk = _dayKey(n);
    if (dk == nk) return time;
    final sameYear = dk.substring(0, 4) == nk.substring(0, 4);
    final date = sameYear
        ? '${z.day} ${_month(z.month)}'
        : '${z.day} ${_month(z.month)} ${z.year}';
    return '$date · $time';
  }

  /// A chart period label for [granularity].
  String fmtPeriod(String iso, PeriodGranularity granularity) {
    final d = parseJsDate(iso);
    if (d == null) throw RangeError('Invalid time value');
    final z = inZone(d, timezone);
    switch (granularity) {
      case PeriodGranularity.hourly:
        return '${z.day} ${_month(z.month)}$_comma ${_clock12(z.hour, z.minute)}';
      case PeriodGranularity.monthly:
        return '${_month(z.month)} ${z.year}';
      case PeriodGranularity.daily:
      case PeriodGranularity.peakHours:
      case PeriodGranularity.peakDays:
        return '${z.day} ${_month(z.month)}';
    }
  }

  /// [fmtPeriod] taking the web's granularity string (`hourly`,
  /// `peak_hours`, …).
  String fmtPeriodNamed(String iso, String granularity) =>
      fmtPeriod(iso, switch (granularity) {
        'hourly' => PeriodGranularity.hourly,
        'monthly' => PeriodGranularity.monthly,
        'peak_hours' => PeriodGranularity.peakHours,
        'peak_days' => PeriodGranularity.peakDays,
        _ => PeriodGranularity.daily,
      });

  /// A 0-23 hour as a 12-hour label: 0 -> `12:00 AM`, 13 -> `01:00 PM`.
  String fmtHour(int h) => _clock12(((h % 24) + 24) % 24, 0);

  /// A wire `HH:MM` for display, 12-hour; anything else unchanged.
  String fmtWireTime(String hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm);
    if (m == null) return hhmm;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return hhmm;
    return _clock12(h, min);
  }

  // ── Day boundaries in the active zone (the web's `cairo*` helpers) ─────

  /// "Now" on the active zone's wall clock.
  DateTime cairoNow() => inZone(_now, timezone);

  /// ISO instant for the start (or last ms) of a calendar day in the active
  /// zone. [month0] is 0-based, as in JavaScript.
  String cairoDateISO(int year, int month0, int day, {bool endOfDay = false}) =>
      dayBoundaryISO(timezone, year, month0, day, endOfDay: endOfDay);

  /// Calendar parts of [iso] in the active zone (month 0-based).
  ({int y, int m, int d}) cairoParts(String iso) {
    final d = parseJsDate(iso);
    if (d == null) throw RangeError('Invalid time value');
    final z = inZone(d, timezone);
    return (y: z.year, m: z.month - 1, d: z.day);
  }
}

/// UTC ISO instant for the start (or last ms) of a calendar day in [zone]
/// (`dayBoundaryISO`). [month0] is 0-based.
String dayBoundaryISO(
  String zone,
  int year,
  int month0,
  int day, {
  bool endOfDay = false,
}) => isoString(
  endOfDay
      ? wallClock(zone, year, month0, day, 23, 59, 59, 999)
      : wallClock(zone, year, month0, day),
);

/// Excel (1900 system) serial for [instant] on [zone]'s wall clock
/// (`toExcelDateSerial`).
double toExcelDateSerial(DateTime instant, String zone) {
  final z = inZone(instant, zone);
  final wall = DateTime.utc(
    z.year,
    z.month,
    z.day,
    z.hour,
    z.minute,
    z.second,
    z.millisecond,
  );
  return 25569 + wall.millisecondsSinceEpoch / 86400000;
}
