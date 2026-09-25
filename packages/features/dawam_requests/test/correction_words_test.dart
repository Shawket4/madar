// Minor #43 (app part): on the dashboard an approved correction read
// "out 05:45 PM → 05:45 PM" (the rewritten punch shown as its own before).
// The app names only the proposed times, once each, before and after
// approval.
import 'package:feature_dawam_requests/src/requests_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  setUp(() => words = coreWord);

  test('an approved correction names its time once, with no arrow', () {
    for (final status in [ReqStatus.pending, ReqStatus.approved]) {
      final out =
          Req(
              'q|c',
              ReqKind.correction,
              'e4',
              DateTime(2026, 9, 22),
              status: status,
            )
            ..from = DateTime(2026, 9, 21)
            ..time2 = 17 * 60 + 45;
      final when = reqWhen(out);
      expect(when, isNot(contains('→')));
      expect(RegExp(hmMin(17 * 60 + 45)).allMatches(when), hasLength(1));
    }
  });
}
