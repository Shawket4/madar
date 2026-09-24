// E2E clocking (area brief): Home greeted "Good evening, Youssef" at 3:10 PM.
// English has an afternoon (12:00–16:59); Arabic says «مساء الخير» from
// noon. The greeting follows the branch's clock (the snapshot's `now`),
// never the phone's zone.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(() async {
    await initializeDateFormatting();
    await loadFonts();
  });

  const en = ['Good morning', 'Good afternoon', 'Good evening'];
  const cases = {
    '09:00': ('Good morning', 'صباح الخير'),
    '11:59': ('Good morning', 'صباح الخير'),
    '12:00': ('Good afternoon', 'مساء الخير'),
    '14:20': ('Good afternoon', 'مساء الخير'),
    '16:59': ('Good afternoon', 'مساء الخير'),
    '17:00': ('Good evening', 'مساء الخير'),
    '21:30': ('Good evening', 'مساء الخير'),
  };
  for (final c in cases.entries) {
    for (final lang in ['en', 'ar']) {
      testWidgets('Home greets by the branch clock at ${c.key} · $lang', (
        t,
      ) async {
        await pumpApp(
          t,
          lang: lang,
          who: 'e1',
          core: (f) =>
              f.edit = (v) => v['now'] = '2026-09-24T${c.key}:00+03:00',
        );
        await frames(t);
        final want = lang == 'en' ? c.value.$1 : c.value.$2;
        expect(
          find.textContaining(want),
          findsOneWidget,
          reason: 'at ${c.key}',
        );
        if (lang == 'en') {
          for (final other in en.where((g) => g != want)) {
            expect(
              find.textContaining(other),
              findsNothing,
              reason: 'at ${c.key}',
            );
          }
        }
        await finish(t);
      });
    }
  }
}
