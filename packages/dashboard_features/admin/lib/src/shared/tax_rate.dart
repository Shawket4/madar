/// Percent on screen, fraction on the wire (the web's
/// `features/orgs/tax-rate.ts`), shared by the organization editor and wizard
/// (orgs) and the branch editor's tax override (branches).
///
/// The backend stores `tax_rate` / `service_charge_rate` as a FRACTION
/// (`0.14` is 14%) and refuses anything above 1; people type and read a
/// percent. The conversion lives here, at the one boundary that needs it.
library;

/// The highest percent a rate field accepts ("Enter a rate between 0 and
/// 100"): it exists to catch a 14 typed where 0.14 belongs.
const double kMaxPercent = 100;

/// `0.14` → `14`, rounded to four places (the column is `numeric(5,4)`, and
/// `0.14 * 100` is `14.000000000000002` in binary floating point). Missing or
/// not finite → 0.
double fractionToPercent(num? fraction) {
  if (fraction == null || !fraction.isFinite) return 0;
  return (fraction * 100 * 10000).round() / 10000;
}

/// `14` → `0.14`, rounded to six places (a four-decimal percent is a
/// six-decimal fraction). Missing or not finite → 0.
double percentToFraction(num? percent) {
  if (percent == null || !percent.isFinite) return 0;
  return (percent / 100 * 1000000).round() / 1000000;
}

/// How a rate reads in a table or a summary: `0.14` → `"14%"`,
/// `0.145` → `"14.5%"` (JavaScript's number-to-string: no trailing `.0`).
String formatRate(num? fraction) => '${jsNumber(fractionToPercent(fraction))}%';

/// A number as JavaScript's `String(n)` writes it for the values these
/// screens show: whole numbers without `.0`.
String jsNumber(num value) {
  if (value.isFinite && value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}
