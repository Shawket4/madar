// D8 (FINAL device check): declining an advance (or any request) needs a
// reason, and the person who asked sees it afterwards — the row of a declined
// request says why (the server's decision_note), ahead of their own note so
// the line's cut never hides it. It was parsed and never shown.
import 'package:feature_dawam_requests/src/requests_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

void main() {
  setUp(() {
    words = (k) => const {'staff.decline_reason': 'Reason: {note}'}[k] ?? k;
  });

  Req advance(ReqStatus status) =>
      Req(
          'v|1',
          ReqKind.salaryAdvance,
          'me',
          DateTime(2026, 9, 25),
          status: status,
        )
        ..amount = 50000
        ..note = 'School fees';
  String? nameOf(String id) => null;

  test('a declined request says why, before my own note', () {
    final r = advance(ReqStatus.rejected)..decisionNote = 'Not before payday';
    final meta = reqMeta(r, 'me', nameOf);
    expect(meta, contains('Reason: Not before payday'));
    expect(
      meta.indexOf('Reason: Not before payday'),
      lessThan(meta.indexOf('School fees')),
    );
  });

  test('no reason, or not declined: nothing added', () {
    expect(
      reqMeta(advance(ReqStatus.rejected), 'me', nameOf),
      isNot(contains('Reason')),
    );
    expect(
      reqMeta(advance(ReqStatus.rejected)..decisionNote = '  ', 'me', nameOf),
      isNot(contains('Reason')),
    );
    expect(
      reqMeta(
        advance(ReqStatus.approved)..decisionNote = 'Paid in two',
        'me',
        nameOf,
      ),
      isNot(contains('Reason')),
    );
    expect(
      reqMeta(advance(ReqStatus.pending), 'me', nameOf),
      isNot(contains('Reason')),
    );
  });

  // POLISH: a row with words in it (my note, a reason) may wrap; one that
  // says only when keeps one line.
  test('a row that carries words may wrap; the others keep one line', () {
    expect(
      reqMetaLines(advance(ReqStatus.rejected)..decisionNote = 'Not yet'),
      greaterThan(1),
    );
    expect(reqMetaLines(advance(ReqStatus.pending)), greaterThan(1));
    expect(reqMetaLines(advance(ReqStatus.rejected)..note = ''), 1);
    expect(reqMetaLines(advance(ReqStatus.pending)..note = ' '), 1);
    expect(
      reqMetaLines(
        advance(ReqStatus.cancelled)
          ..note = ''
          ..cancelledBy = 'manager',
      ),
      greaterThan(1),
    );
  });
}
