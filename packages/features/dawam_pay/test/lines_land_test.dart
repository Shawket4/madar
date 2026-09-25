// Minor #27: with this month's payroll approved, a new pay line silently went
// to a closed month (PERIOD_CLOSED). It lands in the first open month, and the
// sheet says which before it is added.
import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  tearDown(() => currentLang = 'en');

  test('a new pay line names the month it lands in', () {
    words = coreWord;
    final land = (from: DateTime(2026, 10, 26), to: DateTime(2026, 11, 25));
    expect(
      linesLandWords(land),
      'Lands in the ${dayMonth(land.from)} – ${dayMonth(land.to)} pay: '
      "this month's is approved.",
    );
    expect(linesLandWords(null), isNull, reason: 'this month is open');
    currentLang = 'ar';
    words = (k) => coreWord(k, arabic: true);
    expect(linesLandWords(land), contains(dayMonth(land.to)));
    expect(linesLandWords(land), isNot(contains('{')));
  });
}
