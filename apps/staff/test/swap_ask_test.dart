// E2E bug S9 (Youssef, AR, Pixel 7): Omar asked Youssef to swap. Youssef's
// Shifts tab went red ("Bad state: No element"): the card read Omar's shift
// from Youssef's own picture, where it isn't. The ask shows both sides
// (from the ids when a shift isn't in the picture) and can be agreed to,
// in Arabic and English.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('a colleague\'s swap ask shows and can be agreed · $lang', (
      t,
    ) async {
      String? theirs;
      await pumpApp(
        t,
        lang: lang,
        who: 'e1',
        tab: 2,
        core: (f) => f.edit = (v) {
          final swap = (v['requests'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .firstWhere((r) => r['kind'] == 'swap');
          final mine = swap['shift'] as String; // e1's own shift
          final day = mine.split('|')[1];
          theirs = 'e4|$day|zE';
          // e4 asks me: THEIR shift first, mine second; theirs is not in
          // my picture (a colleague's roster isn't mine to see).
          swap
            ..['emp'] = 'e4'
            ..['peer'] = 'e1'
            ..['shift'] = theirs
            ..['shift2'] = mine
            ..['status'] = 'awaitingPeer';
          (v['shifts'] as List<dynamic>).removeWhere((s) => s['id'] == theirs);
        },
      );
      await frames(t, 30);
      expect(t.takeException(), isNull);
      final store = testContainer.read(dawamProvider);
      expect(store.shifts.where((s) => s.id == theirs), isEmpty);
      final asker = name(store.emp('e4'));
      expect(
        find.text(tr('staff.wants_to_swap', {'name': asker})),
        findsOneWidget,
      );
      final day = dayLabel(DateTime.parse(theirs!.split('|')[1]));
      expect(find.textContaining(day), findsWidgets);
      await t.tap(find.text(tr('staff.agree')));
      await frames(t);
      expect(lastAct(), {'action': 'peer_answer', 'req': 'w|w1', 'yes': true});
      await finish(t);
    });
  }
}
