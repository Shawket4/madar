// E2E roster (Omar, iPhone, 24 Sep): with a swap of his waiting and the
// "not published yet" notice above it, the Shifts tab's Month view had so
// little height that every week row overflowed ("BOTTOM OVERFLOWED BY 15
// PIXELS") and showed only "+1" — no shift could be seen or tapped. The
// calendar keeps a full screen's height; what sits above it scrolls away.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('the month view has room under a swap card · $lang', (t) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e1',
        tab: 2,
        core: (f) => f.edit = (v) {
          final swap = (v['requests'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .firstWhere((r) => r['kind'] == 'swap');
          swap['status'] = 'awaitingPeer';
          // A second one of mine waits for the manager, and next week isn't
          // published yet: two cards and the notice above the calendar, as
          // on Omar's phone.
          (v['requests'] as List<dynamic>).add({
            ...swap,
            'id': 'w|w2',
            'status': 'pending',
          });
          for (final sh
              in (v['shifts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
            if ((sh['date'] as String).compareTo('2026-09-26') >= 0) {
              sh['published'] = false;
            }
          }
        },
      );
      await frames(t, 30);
      expect(
        find.text(tr('staff.swaps_waiting', {'count': 2})),
        findsOneWidget,
        reason: 'two swaps wait, folded into one line (minor #23)',
      );
      expect(
        find.text(tr('staff.not_published_yet_you_ll_get')),
        findsOneWidget,
      );
      await t.ensureVisible(find.text(tr('staff.view_month')));
      await frames(t);
      await t.tap(find.text(tr('staff.view_month')));
      await frames(t, 30);
      final errors = <Object>[];
      for (Object? e = t.takeException(); e != null; e = t.takeException()) {
        errors.add(e);
      }
      expect(errors, isEmpty, reason: 'no overflow in the month view');
      await finish(t);
    });
  }
}
