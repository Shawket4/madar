// RQ-F6: a request someone else cancelled says who and why, from the
// cancel's own fields (cancelled_by / cancel_note) — never from decided_by,
// which stays the approver's. The row's one line leads with it (E2E: the
// words sat after the filer's own note and were cut off), and a canceller
// the phone doesn't know (the owner, outside the branch) still reads right.
import 'package:feature_dawam_requests/src/requests_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

void main() {
  setUp(() {
    words = (k) =>
        const {
          'staff.cancelled_by_name': 'Cancelled by {name}',
          'staff.cancelled_by_manager': 'Cancelled by a manager',
        }[k] ??
        k;
  });

  Req req(ReqStatus status) =>
      Req('q|1', ReqKind.leave, 'me', DateTime(2026, 9, 22), status: status)
        ..from = DateTime(2026, 9, 23)
        ..note = 'Sick';
  String? nameOf(String id) =>
      const {'karim': 'Karim Mostafa', 'omar': 'Omar Khaled'}[id];

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

  test(
    'a canceller the phone does not know: the server name, else a manager',
    () {
      final r = req(ReqStatus.cancelled)
        ..cancelledBy = 'owner'
        ..cancelNote = 'Came in';
      expect(
        cancelledWords(r, 'me', nameOf),
        'Cancelled by a manager · Came in',
      );
      r.cancelledByName = 'Tasbeeh';
      expect(cancelledWords(r, 'me', nameOf), 'Cancelled by Tasbeeh · Came in');
    },
  );

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

  test("the row's line leads with the cancel, before my own note", () {
    final r = req(ReqStatus.cancelled)
      ..cancelledBy = 'omar'
      ..cancelNote = 'Came in';
    final meta = reqMeta(r, 'me', nameOf);
    expect(
      meta.indexOf('Cancelled by Omar Khaled'),
      lessThan(meta.indexOf('Sick')),
    );
    expect(reqMeta(req(ReqStatus.pending), 'me', nameOf), endsWith('Sick'));
  });
}
