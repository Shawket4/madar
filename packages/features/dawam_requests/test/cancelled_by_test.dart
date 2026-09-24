// RQ-F6: a request someone else cancelled says who and why, from the
// cancel's own fields (cancelled_by / cancel_note) — never from decided_by,
// which stays the approver's.
import 'package:feature_dawam_requests/src/requests_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

void main() {
  setUp(() {
    words = (k) =>
        const {'staff.cancelled_by_name': 'Cancelled by {name}'}[k] ?? k;
  });

  Req req(ReqStatus status) =>
      Req('q|1', ReqKind.leave, 'me', DateTime(2026, 9, 22), status: status);
  String nameOf(String id) =>
      const {'karim': 'Karim Mostafa', 'omar': 'Omar Khaled'}[id] ?? id;

  test('cancelled by someone else: who and why', () {
    final r = req(ReqStatus.cancelled)
      ..decidedBy = 'karim'
      ..decisionNote = 'Get well'
      ..cancelledBy = 'omar'
      ..cancelNote = 'She came in after all';
    expect(
      cancelledWords(r, 'me', nameOf),
      'Cancelled by Omar Khaled · She came in after all',
    );
  });

  test('the approver is never shown as the canceller', () {
    final r = req(ReqStatus.cancelled)
      ..decidedBy = 'karim'
      ..decisionNote = 'Get well';
    expect(cancelledWords(r, 'me', nameOf), isNull);
  });

  test('my own cancel, or a live request, says nothing', () {
    expect(
      cancelledWords(
        req(ReqStatus.cancelled)..cancelledBy = 'me',
        'me',
        nameOf,
      ),
      isNull,
    );
    expect(
      cancelledWords(
        req(ReqStatus.approved)..cancelledBy = 'omar',
        'me',
        nameOf,
      ),
      isNull,
    );
  });

  test('no note: just who', () {
    final r = req(ReqStatus.cancelled)..cancelledBy = 'omar';
    expect(cancelledWords(r, 'me', nameOf), 'Cancelled by Omar Khaled');
  });
}
