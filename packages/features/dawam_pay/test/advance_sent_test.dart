// Minor #34: an employee already over the advance cap may still ask; the
// answer says only the owner can approve it.
import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  setUp(() => words = coreWord);

  test('an advance over the cap says only the owner can approve it', () {
    expect(
      advanceSentWords((id: 'v|v9', status: ReqStatus.pending, toOwner: true)),
      "Sent. It's over your advance cap, so only the owner can approve this.",
    );
    expect(
      advanceSentWords((id: 'v|v9', status: ReqStatus.pending, toOwner: false)),
      coreWord('staff.sent_to_your_manager'),
    );
  });
}
