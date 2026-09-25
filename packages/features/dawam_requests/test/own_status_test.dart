// Addendum 2 (RQ-5): a manager's own pending request or claim reads
// "Waiting for the owner" in his Requests, never "Pending" as if his own
// manager had it; anyone else's reads as before.
import 'package:feature_dawam_requests/src/requests_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  setUp(() => words = coreWord);

  Req req({required bool toOwner, ReqStatus status = ReqStatus.pending}) =>
      Req('o|x', ReqKind.openShift, 'me', DateTime(2026, 9, 22), status: status)
        ..toOwner = toOwner;

  test('my own item that the owner decides says so', () {
    expect(
      reqStatus(req(toOwner: true), 'me').label,
      coreWord('staff.waiting_for_the_owner'),
    );
    expect(
      reqStatus(req(toOwner: false), 'me').label,
      coreWord('staff.pending'),
    );
    expect(
      reqStatus(req(toOwner: true, status: ReqStatus.approved), 'me').label,
      coreWord('staff.approved'),
    );
    expect(
      reqStatus(req(toOwner: true), 'someone else').label,
      coreWord('staff.pending'),
    );
  });

  test('a manager claiming a shift is told the owner decides', () {
    expect(
      claimSentWords(Role.manager),
      coreWord('staff.claimed_waiting_for_the_owner'),
    );
    expect(
      claimSentWords(Role.employee),
      coreWord('staff.claimed_waiting_for_the_manager'),
    );
  });
}
