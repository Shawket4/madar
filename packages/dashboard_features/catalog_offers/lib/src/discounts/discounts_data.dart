/// The discounts page's read and the rules the web runs in the browser
/// (`features/discounts/util.ts`, `features/orgs/tax-rate.ts`, the table's
/// global filter): the list, a value as the table and the form read it, the
/// form's checks and what Save sends.
library;

import 'package:dashboard_api/dashboard_api.dart' show ApiException, Discount;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/offers_cache.dart';
import '../shared/offers_format.dart' show jsNumber, jsNumberString;

/// X1 `GET /discounts?org_id=` (key `["/discounts", {org_id}]`): every
/// discount of the org, unpaginated, in the server's order (by name).
/// Refetched by any discount write (`invalidateDiscounts`) or a `resync`.
final discountsProvider = FutureProvider.autoDispose
    .family<List<Discount>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(OffersPaths.discounts));
      return ref.watch(apiProvider).discounts.listDiscounts(orgId: orgId);
    });

/// The two kinds a discount has on the wire.
abstract final class DiscountType {
  static const String percentage = 'percentage';
  static const String fixed = 'fixed';
}

/// The highest percentage (`MAX_PERCENT`).
const num maxPercent = 100;

/// The value box's step (`step="0.5"`).
const num valueStep = 0.5;

/// `Math.round`: half up, toward +∞.
int _jsRound(num v) => (v + 0.5).floor();

/// `rateOf(d)`: `value_rate`, else the legacy integer read back (a whole
/// percent → a fraction; piastres as they are).
num discountRate(Discount d) =>
    rateOf(value: d.value, valueRate: d.valueRate, dtype: d.dtype);

/// `fractionToPercent`: 0.14 → 14, 0.125 → 12.5 (four decimals at most).
num fractionToPercent(num? fraction) {
  if (fraction == null || !fraction.isFinite) return 0;
  return _jsRound(fraction * 100 * 10000) / 10000;
}

/// `percentToFraction`: 14 → 0.14 (six decimals at most).
num percentToFraction(num? percent) {
  if (percent == null || !percent.isFinite) return 0;
  return _jsRound(percent / 100 * 1000000) / 1000000;
}

/// `formatRate`: "14%", "12.5%" — not localised, the same in Arabic.
String formatRate(num? fraction) =>
    '${jsNumberString(fractionToPercent(fraction))}%';

/// The Value column: a percentage as its rate, a fixed amount as money.
String discountValueLabel(Discount d, DashFormat f) =>
    d.dtype == DiscountType.percentage
    ? (f.isArabic
          ? ltr(formatRate(discountRate(d)))
          : formatRate(discountRate(d)))
    : f.fmtMoney(discountRate(d));

/// The export's Value cell: a percentage as 0–100, a fixed amount in EGP.
num discountExportValue(Discount d) => d.dtype == DiscountType.percentage
    ? fractionToPercent(discountRate(d))
    : piastresToEgp(discountRate(d));

/// The table's global search (TanStack `includesString`): a case-insensitive
/// substring of the raw English name, the type code or the legacy integer
/// value; the query is not trimmed, an empty one matches everything.
bool discountMatches(Discount d, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  return d.name.toLowerCase().contains(q) ||
      d.dtype.toLowerCase().contains(q) ||
      '${d.value}'.contains(q);
}

/// The value box as the form opens on [d]: a percentage as 0–100, a fixed
/// amount in EGP; a new discount opens on 0.
String discountValueText(Discount? d) {
  if (d == null) return '0';
  final rate = discountRate(d);
  return jsNumberString(
    d.dtype == DiscountType.fixed
        ? piastresToEgp(rate)
        : fractionToPercent(rate),
  );
}

/// The form's red lines, as i18n keys (null = fine).
typedef DiscountErrors = ({String? name, String? value});

/// The form's checks: the zod schema (`discountSchema`) and the browser's own
/// `min`/`max`/`step` checks on the number box, which the web leaves to the
/// browser's bubble (OFFR-DSC-030). Blank counts as 0.
DiscountErrors validateDiscount({
  required String name,
  required String dtype,
  required String value,
}) {
  final v = jsNumber(value);
  String? valueError;
  if (v.isNaN || v < 0) {
    valueError = 'discounts.valueNegative';
  } else if (dtype == DiscountType.percentage && v > maxPercent) {
    valueError = 'discounts.percentRange';
  } else if (v.isInfinite || (v / valueStep) != (v / valueStep).truncate()) {
    valueError = 'discounts.valueStep';
  }
  return (
    name: name.isEmpty ? 'common.requiredField' : null,
    value: valueError,
  );
}

/// What Save sends as `value`: a percentage as a fraction (14 → 0.14), a
/// fixed amount in piastres (50 → 5000).
double discountWireValue(String dtype, String value) {
  final v = jsNumber(value);
  return dtype == DiscountType.fixed
      ? egpToPiastres(v).toDouble()
      : percentToFraction(v).toDouble();
}

/// The kinds the backend's AppError writes before its sentence.
final RegExp _serverKindPrefix = RegExp(
  r'^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
  r'Service unavailable|Database error): ',
);

/// A failure in words (the web's `getErrorMessage`, OFFR-ALL-004): a coded
/// refusal the tables know → its sentence; an uncoded 429 → "Too many
/// requests…"; an uncoded 403 → "You don't have permission to perform this
/// action."; else the server's sentence without its kind prefix.
String discountErrorText(Object? error, Translator t) {
  if (error is ApiException) {
    final code = error.code;
    if (code != null && t.exists('errors.codes.$code')) {
      final details = error.details;
      final vars = details is Map && details['vars'] is Map
          ? (details['vars'] as Map).cast<String, Object?>()
          : const <String, Object?>{};
      return t('errors.codes.$code', args: vars);
    }
    if (code == null && error.status == 429) {
      return t('errors.tooManyRequests');
    }
    if (code == null && error.status == 403) return t('errors.unauthorized');
    final text = error.message.replaceFirst(_serverKindPrefix, '');
    if (text.isNotEmpty) return text;
  }
  return errorMessage(error, t);
}
