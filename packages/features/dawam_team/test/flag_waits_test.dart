// Minor #33: a flag's deduction over the manager's limit waits for the
// owner; the sheet says so instead of closing as if it were done.
import 'package:feature_dawam_team/src/team_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

void main() {
  test('a pending flag deduction waits for the owner', () {
    expect(
      flagDeductionWaits((
        id: 'f|f1',
        status: ReqStatus.pending,
        toOwner: true,
      )),
      isTrue,
    );
    expect(flagDeductionWaits(null), isFalse, reason: 'within the limit');
    expect(
      flagDeductionWaits((
        id: 'q|1',
        status: ReqStatus.pending,
        toOwner: false,
      )),
      isFalse,
      reason: 'another answer',
    );
  });
}
