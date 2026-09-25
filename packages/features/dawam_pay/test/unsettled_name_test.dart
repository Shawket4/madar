// A5: the unsettled-month banner names a calendar month ("Aug 2026") when
// the pay period is exactly one, otherwise its dates (26 Jul – 25 Aug).
import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  tearDown(() => currentLang = 'en');

  test('a calendar month by its name, anything else by its dates', () {
    words = coreWord;
    expect(periodName(DateTime(2026, 8), DateTime(2026, 8, 31)), 'Aug 2026');
    expect(periodName(DateTime(2026, 2), DateTime(2026, 2, 28)), 'Feb 2026');
    expect(
      periodName(DateTime(2026, 7, 26), DateTime(2026, 8, 25)),
      '${dayMonth(DateTime(2026, 7, 26))} – ${dayMonth(DateTime(2026, 8, 25))}',
    );
    expect(
      periodName(DateTime(2026, 8), DateTime(2026, 8, 30)),
      contains('–'),
      reason: 'a day short is not the month',
    );
    currentLang = 'ar';
    words = (k) => coreWord(k, arabic: true);
    expect(periodName(DateTime(2026, 8), DateTime(2026, 8, 31)), 'أغسطس 2026');
  });
}
