// The phone rule against madar-shared's vectors (a verbatim copy of the
// web's `src/lib/phone_vectors.json`) and the web's own display/input cases.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_sell/src/shared/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vectors =
      json.decode(File('test/shared/phone_vectors.json').readAsStringSync())
          as Map<String, Object?>;

  test('every valid vector canonicalises to its expected form', () {
    for (final v in (vectors['valid']! as List).cast<List<Object?>>()) {
      expect(canonicalPhone(v[0]! as String), v[1], reason: '${v[0]}');
    }
  });

  test('every invalid vector is refused', () {
    for (final v in (vectors['invalid']! as List).cast<String>()) {
      expect(canonicalPhone(v), isNull, reason: v);
      expect(isValidPhone(v), isFalse, reason: v);
    }
  });

  test('display and input forms (phone.test.ts)', () {
    expect(formatPhoneDisplay('201001234567'), '+20 100 123 4567');
    expect(formatPhoneDisplay('01001234567'), '+20 100 123 4567');
    expect(formatPhoneDisplay('966512345678'), '+966512345678');
    expect(formatPhoneDisplay('20221234567'), '+20221234567');
    expect(formatPhoneDisplay('n/a'), 'n/a');
    expect(formatPhoneDisplay(''), '');
    expect(formatPhoneDisplay(null), '');
    expect(formatPhoneInput('201001234567'), '01001234567');
    expect(formatPhoneInput('966512345678'), '+966512345678');
    expect(samePhone('01001234567', '+20 100 123 4567'), isTrue);
    expect(samePhone('abc', 'abc'), isFalse);
  });
}
