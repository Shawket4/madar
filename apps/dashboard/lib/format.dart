import 'package:intl/intl.dart';

String _numLocale(String locale) => locale == 'ar' ? 'ar' : 'en';

/// Display symbol for a currency: EGP → "ج.م" in Arabic, "EGP" otherwise.
String moneySymbol(String currency, String locale) {
  final code = currency.toUpperCase();
  if (code == 'EGP') return locale == 'ar' ? 'ج.م' : 'EGP';
  return code;
}

/// Locale-aware money from minor units (piastres). English:
/// "EGP 1,240.50"; Arabic: Arabic-Indic digits + "ج.م" trailing.
String fmtMoney(int minor, {required String currency, required String locale}) {
  final value = minor / 100.0;
  final nf = NumberFormat.currency(
    locale: _numLocale(locale),
    symbol: '',
    decimalDigits: 2,
  );
  final amount = nf.format(value).trim();
  final sym = moneySymbol(currency, locale);
  return locale == 'ar' ? '$amount $sym' : '$sym $amount';
}

/// Locale-aware grouped integer (Arabic-Indic digits in Arabic).
String fmtInt(int n, {required String locale}) =>
    NumberFormat.decimalPattern(_numLocale(locale)).format(n);

/// Compact money for chart axes: "1.2k" / "٣٥٠" / "4M".
String fmtAxisMoney(double value, {required String locale}) {
  final v = value.abs();
  final nf = NumberFormat('#,##0.#', _numLocale(locale));
  if (v >= 1000000) return '${nf.format(value / 1000000)}M';
  if (v >= 1000) return '${nf.format(value / 1000)}k';
  return fmtInt(value.round(), locale: locale);
}

/// Short axis label for a timeseries period string: "9/7" (daily) or the hour
/// (hourly). Falls back to the raw string if it isn't a parseable date.
String fmtAxisDate(
  String period, {
  required bool hourly,
  required String locale,
}) {
  final dt = DateTime.tryParse(period);
  if (dt == null) return period.length > 5 ? period.substring(5) : period;
  if (hourly) return fmtInt(dt.hour, locale: locale);
  return '${fmtInt(dt.day, locale: locale)}/${fmtInt(dt.month, locale: locale)}';
}
