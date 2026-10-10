// The rules the web runs in the browser (`util.ts` discountSchema and its
// `discount-schema.test.ts`, `tax-rate.ts`, the table's global filter), and
// this unit's i18n supplement.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_api/dashboard_api.dart' show Discount;
import 'package:dashboard_catalog_offers/src/discounts/discounts_data.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

String? _valueError(String dtype, String value) =>
    validateDiscount(name: 'Staff', dtype: dtype, value: value).value;

Discount _d(String name, String dtype, num rate, int legacy) => Discount(
  createdAt: DateTime.utc(2026),
  dtype: dtype,
  id: name,
  isActive: true,
  name: name,
  nameTranslations: const {'ar': 'خصم'},
  orgId: 'org',
  updatedAt: DateTime.utc(2026),
  value: legacy,
  valueRate: rate.toDouble(),
);

void main() {
  group('OFFR-DSC-029 a discount can never be configured to go negative '
      '(discount-schema.test.ts)', () {
    test('refuses a percentage over 100, and says what the limit means', () {
      expect(_valueError('percentage', '150'), 'discounts.percentRange');
    });
    test('allows exactly 100%', () {
      expect(_valueError('percentage', '100'), isNull);
    });
    test('refuses a negative value of either type', () {
      expect(_valueError('percentage', '-1'), 'discounts.valueNegative');
      expect(_valueError('fixed', '-1'), 'discounts.valueNegative');
    });
    test('allows a fixed amount larger than 100 EGP', () {
      expect(_valueError('fixed', '200'), isNull);
      expect(_valueError('fixed', '100000'), isNull);
    });
    test('allows zero', () {
      expect(_valueError('percentage', '0'), isNull);
      expect(_valueError('fixed', '0'), isNull);
    });
  });

  test('OFFR-DSC-028/030 blank is 0; junk reads negative; off the 0.5 step '
      'is refused', () {
    expect(_valueError('percentage', ''), isNull);
    expect(_valueError('percentage', '-'), 'discounts.valueNegative');
    expect(_valueError('percentage', '12.3'), 'discounts.valueStep');
    expect(_valueError('fixed', '10.25'), 'discounts.valueStep');
    expect(_valueError('percentage', '12.5'), isNull);
    expect(_valueError('percentage', '101'), 'discounts.percentRange');
    expect(
      validateDiscount(name: '', dtype: 'fixed', value: '1').name,
      'common.requiredField',
    );
    expect(
      validateDiscount(name: ' ', dtype: 'fixed', value: '1').name,
      isNull,
      reason: 'the rule is only "not empty"',
    );
  });

  test('4.1 rates: fractionToPercent, percentToFraction, formatRate', () {
    expect(fractionToPercent(0.14), 14);
    expect(fractionToPercent(0.125), 12.5);
    expect(fractionToPercent(0.123456), 12.3456);
    expect(fractionToPercent(null), 0);
    expect(percentToFraction(14), 0.14);
    expect(percentToFraction(12.5), 0.125);
    expect(percentToFraction(33.3333333), 0.333333);
    expect(formatRate(0.125), '12.5%');
    expect(formatRate(1), '100%');
    expect(formatRate(0.14), '14%');
  });

  test('OFFR-DSC-033 the wire value: a fraction, or piastres', () {
    expect(discountWireValue('percentage', '14'), 0.14);
    expect(discountWireValue('fixed', '50'), 5000);
    expect(discountWireValue('fixed', '19.99'), 1999);
    expect(discountWireValue('percentage', ''), 0);
  });

  test('OFFR-DSC-025 the box opens on 0–100 or EGP', () {
    expect(discountValueText(null), '0');
    expect(discountValueText(_d('A', 'percentage', 0.125, 13)), '12.5');
    expect(discountValueText(_d('B', 'fixed', 5000, 5000)), '50');
    expect(discountValueText(_d('C', 'fixed', 1025, 1025)), '10.25');
  });

  test('OFFR-DSC-012 the Value column', () {
    const f = DashFormat();
    expect(discountValueLabel(_d('A', 'percentage', 0.125, 13), f), '12.5%');
    expect(discountValueLabel(_d('B', 'fixed', 5000, 5000), f), 'EGP 50.00');
    const ar = DashFormat(lang: 'ar');
    expect(
      discountValueLabel(_d('A', 'percentage', 0.125, 13), ar),
      ltr('12.5%'),
    );
  });

  test('OFFR-DSC-007 the export\'s Value cell', () {
    expect(discountExportValue(_d('A', 'percentage', 0.125, 13)), 12.5);
    expect(discountExportValue(_d('B', 'fixed', 5000, 5000)), 50);
  });

  test('OFFR-DSC-041 the search: name, type code, legacy value; untrimmed; '
      'never the Arabic name', () {
    final d = _d('Corporate: Vodafone', 'percentage', 0.125, 13);
    expect(discountMatches(d, ''), isTrue);
    expect(discountMatches(d, 'VODA'), isTrue);
    expect(discountMatches(d, 'PERCENT'), isTrue);
    expect(discountMatches(d, '13'), isTrue);
    expect(discountMatches(d, '12.5'), isFalse);
    expect(discountMatches(d, ' vodafone'), isTrue);
    expect(discountMatches(d, 'vodafone '), isFalse);
    expect(discountMatches(d, 'خصم'), isFalse);
  });

  test('the supplement words exist in English and Arabic', () {
    Map<String, Object?> read(String lang) =>
        (json.decode(
                  File('assets/i18n/discounts.$lang.json').readAsStringSync(),
                )
                as Map)
            .cast<String, Object?>();
    final en = read('en');
    final ar = read('ar');
    expect(en.keys.toSet(), ar.keys.toSet());
    expect(en['discounts.valueStep'], isA<String>());
    expect(ar['discounts.valueStep'], contains('0.5'));
  });
}
