// E2E bug S5 (Omar, EN, Pixel 7): a swap Omar asked for, in a week not yet
// published to him, showed on Shifts as a card that said only "Swap this
// shift" with a cancel button — not which day, shift or colleague. The
// card names both sides from the request itself, in Arabic and English.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('my pending swap says which one · $lang', (t) async {
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
          // Its week isn't published to me: neither shift is in my picture.
          (v['shifts'] as List<dynamic>).removeWhere(
            (s) => s['id'] == swap['shift'] || s['id'] == swap['shift2'],
          );
        },
      );
      await frames(t, 30);
      await openSwaps(t);
      final store = testContainer.read(dawamProvider);
      final r = store.reqs.firstWhere((r) => r.kind == ReqKind.swap);
      expect(store.shifts.where((s) => s.id == r.shift), isEmpty);
      final day = dayLabel(DateTime.parse(r.shift!.split('|')[1]));
      final peer = name(store.emp(r.peer!));
      expect(find.textContaining(day), findsWidgets, reason: 'the day');
      expect(find.textContaining(peer), findsWidgets, reason: 'the colleague');
      expect(find.textContaining('⇄'), findsOneWidget);
      await finish(t);
    });
  }
}
