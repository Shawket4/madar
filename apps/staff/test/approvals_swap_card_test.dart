// E2E roster (iPhone, Karim, 24 Sep): the Approvals card of a swap both
// colleagues agreed to named the ASKER twice ("Omar Khaled's Sat 26 Sep ⇄
// Omar Khaled's Sat 26 Sep — both agreed"), so the manager couldn't see who
// the other person was. The card names the asker's side, then the
// colleague's, in Arabic and English.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('a swap to approve names both people · $lang', (t) async {
      late String day;
      await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 1,
        core: (f) => f.edit = (v) {
          final shifts = (v['shifts'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          // A date on which e1 works the morning and e4 the evening.
          day = shifts
              .where((s) => s['emp'] == 'e1' && s['tpl'] == 'zM')
              .map((s) => s['date'] as String)
              .firstWhere(
                (d) => shifts.any(
                  (s) => s['emp'] == 'e4' && s['tpl'] == 'zE' && s['date'] == d,
                ),
              );
          (v['requests'] as List<dynamic>).add({
            'amount': 0,
            'can_decide': true,
            'created': '2026-09-23T06:00:00+03:00',
            'decided_by': null,
            'decision_note': null,
            'emp': 'e1',
            'from': day,
            'half': false,
            'id': 'w|w9',
            'installments': 1,
            'kind': 'swap',
            'leave_half': null,
            'minutes': 0,
            'month_open': true,
            'note': '',
            'paid': null,
            'paid_default': null,
            'peer': 'e4',
            'shift': 'e1|$day|zM',
            'shift2': 'e4|$day|zE',
            'status': 'pending',
            'time': null,
            'time2': null,
            'to': null,
            'to_owner': false,
            'tpl': null,
          });
          // The core puts it in the manager's queue.
          (v['inbox'] as List<dynamic>).add('w|w9');
        },
      );
      await frames(t, 30);
      final store = testContainer.read(dawamProvider);
      final asker = name(store.emp('e1'));
      final colleague = name(store.emp('e4'));
      final d = dayLabel(DateTime.parse(day));
      expect(
        find.text(
          tr('staff.s_s_both_agreed', {
            'name': asker,
            'date': d,
            'name2': colleague,
            'date2': d,
          }),
        ),
        findsOneWidget,
        reason: 'the asker, then the colleague',
      );
      await finish(t);
    });
  }
}
