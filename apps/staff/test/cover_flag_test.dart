// E2E clocking (S-208): on a cover flag the only button read "Ignore"
// («تجاهل»), but it confirms the cover — and a confirmed cover is PAID. The
// button says what it does: "Confirm cover", in both languages; other flags
// keep their Ignore.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('a cover flag offers "Confirm cover", not "Ignore" · $lang', (
      t,
    ) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        core: (f) => f.edit = (v) {
          final flags = v['flags'] as List<dynamic>;
          flags.add({
            'at': '2026-09-23T17:30:00+03:00',
            'emp': 'e4',
            'id': 'fc',
            'kind': 'cover',
            'minutes_away': 0,
            'resolution': null,
            'shift': 'e4|2026-09-23|zE',
            'suggested': 0,
          });
          v['open_flags'] = ['fc'];
        },
      );
      await frames(t);
      // The row's title is "<name> · <kind label>"; open it by its kind.
      final label = flagInfo(FlagKind.cover).label;
      final title = find.textContaining(' · $label');
      expect(title, findsOneWidget);
      await t.tap(title);
      await frames(t);
      expect(find.text(tr('staff.ignore')), findsNothing);
      expect(find.text(tr('staff.confirm_cover')), findsOneWidget);
      await t.tap(find.text(tr('staff.confirm_cover')));
      await frames(t);
      expect(testCore.acts.last, {
        'action': 'resolve',
        'flag': 'fc',
        'how': 'confirm',
        'deduct': 0,
      });
      await finish(t);
    });

    // H2-B3: a cover flag is confirmed OR rejected (the server refuses
    // anything else); rejecting was only possible from Approvals.
    testWidgets('a cover flag can be rejected there too · $lang', (t) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        core: (f) => f.edit = (v) {
          (v['flags'] as List<dynamic>).add({
            'at': '2026-09-23T17:30:00+03:00',
            'emp': 'e4',
            'id': 'fc',
            'kind': 'cover',
            'minutes_away': 0,
            'resolution': null,
            'shift': 'e4|2026-09-23|zE',
            'suggested': 0,
          });
          v['open_flags'] = ['fc'];
        },
      );
      await frames(t);
      await t.tap(find.textContaining(' · ${flagInfo(FlagKind.cover).label}'));
      await frames(t);
      expect(find.text(tr('staff.excuse_paid')), findsNothing);
      await t.tap(find.text(tr('staff.reject_cover')));
      await frames(t);
      expect(testCore.acts.last, {
        'action': 'resolve',
        'flag': 'fc',
        'how': 'reject',
        'deduct': 0,
      });
      await finish(t);
    });
  }
}
