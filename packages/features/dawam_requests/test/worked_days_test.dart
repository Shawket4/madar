// Minor #16: a mission approved over a day the person already clocked in was
// approved blind. The card warns: the punches stay, the day is paid as a
// mission with no penalty.
import 'package:feature_dawam_requests/src/approvals_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  tearDown(() => currentLang = 'en');

  Req req(ReqKind kind, List<DateTime> worked) =>
      Req('q|1', kind, 'e4', DateTime(2026, 9, 22))
        ..from = DateTime(2026, 9, 23)
        ..to = DateTime(2026, 9, 24)
        ..worked = worked;

  test('a mission over a worked day warns the approver', () {
    words = coreWord;
    final day = DateTime(2026, 9, 23);
    final text = workedWarning(req(ReqKind.mission, [day]), 'Omar');
    expect(text, contains('Omar'));
    expect(text, contains(dayLabel(day)));
    expect(text, contains('mission'));
    expect(
      workedWarning(req(ReqKind.leave, [day]), 'Omar'),
      contains(dayLabel(day)),
    );
    expect(workedWarning(req(ReqKind.mission, const []), 'Omar'), isNull);
    expect(workedWarning(req(ReqKind.excuse, [day]), 'Omar'), isNull);
    currentLang = 'ar';
    words = (k) => coreWord(k, arabic: true);
    final ar = workedWarning(req(ReqKind.mission, [day]), 'عمر')!;
    expect(ar, contains('عمر'));
    expect(ar, isNot(contains('{')));
  });
}
