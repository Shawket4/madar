// FINAL device check (run B, C2): taking back my claim on an open shift
// toasted "Cancelled" while its row then read "Withdrawn". The toast says
// what the row says: the claim was withdrawn. POLISH: so does the question
// before it, "Withdraw this claim?" / "Withdraw". Any other request of mine
// taken back is still cancelled, in the question and the toast.
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

/// The owner-free side: Home, Timesheet, Shifts, Requests, Pay.
const _requests = 3;

Map<String, dynamic> _request(String id, String kind) => {
  'amount': 0,
  'can_decide': null,
  'cancel_note': null,
  'cancelled_by': null,
  'cancelled_by_name': null,
  'created': '2026-09-25T09:00:00+03:00',
  'decided_by': null,
  'decision_note': null,
  'emp': 'e1',
  'from': '2026-09-29',
  'half': false,
  'id': id,
  'installments': 1,
  'kind': kind,
  'leave_half': null,
  'minutes': 0,
  'month_open': true,
  'note': '',
  'paid': null,
  'paid_default': null,
  'peer': null,
  'shift': kind == 'openShift' ? 'open|os1' : null,
  'shift2': null,
  'status': 'pending',
  'time': null,
  'time2': null,
  'to': null,
  'to_owner': false,
  'tpl': null,
  'within_cap': null,
  'worked': <String>[],
};

void main() {
  useCoreWords();
  setUpAll(() async {
    await loadFonts();
    await initializeDateFormatting();
  });

  for (final lang in ['en', 'ar']) {
    for (final (kind, label, title, button, toast) in [
      (
        'openShift',
        'staff.kind_open_shift',
        'staff.withdraw_this_claim',
        'staff.withdraw',
        'staff.claim_withdrawn',
      ),
      (
        'mission',
        'staff.kind_mission',
        'staff.cancel_this_request',
        'staff.cancel_request',
        'staff.cancelled',
      ),
    ]) {
      testWidgets('taking back a pending $kind says $toast · $lang', (t) async {
        await pumpApp(
          t,
          lang: lang,
          who: 'e1',
          tab: _requests,
          core: (f) => f.edit = (v) {
            (v['requests'] as List<dynamic>).add(_request('x|1', kind));
          },
        );
        await frames(t);
        final row = find.descendant(
          of: find.byType(MadarListRow),
          matching: find.text(tr(label)),
        );
        await t.ensureVisible(row.first);
        await t.tap(row.first);
        await frames(t);
        expect(find.text(tr(title)), findsOneWidget, reason: tr(title));
        expect(find.text(tr(button)), findsOneWidget, reason: tr(button));
        await t.tap(find.text(tr(button)).last);
        await frames(t);
        expect(lastAct(), {'action': 'cancel', 'req': 'x|1'});
        expect(testContainer.read(toastProvider)?.text, tr(toast));
        if (kind == 'openShift') {
          // The row's word for it, in both languages.
          expect(
            tr('staff.claim_withdrawn'),
            contains(lang == 'en' ? 'withdrawn' : tr('staff.withdrawn')),
          );
          expect(find.text(tr('staff.cancel_this_request')), findsNothing);
        }
        await finish(t);
      });
    }
  }
}
