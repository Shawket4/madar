// E2E bug S2 (Youssef, EN, Pixel 7): on shift, Home's tracking line read
// "Location on —…": the sentence that says how often the location is
// checked was cut to one line beside the battery and the pill. It must be
// readable in full on a phone, in Arabic and English.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(() async {
    await initializeDateFormatting();
    await loadFonts();
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('the tracking line is whole on a phone · $lang', (t) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e1',
        size: const Size(360, 780),
        core: (f) => f.edit = (v) {
          final id = (v['my_now'] as List<dynamic>).first as String;
          v['active_shift'] = id;
          for (final s
              in (v['shifts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
            if (s['id'] == id) s['in_at'] = '${s['date']}T09:02:00+03:00';
          }
        },
      );
      await frames(t);
      final line = find.text(tr('staff.location_on_checked_every_15_min'));
      await t.ensureVisible(line);
      await frames(t, 5);
      expect(line, findsOneWidget);
      final p = t.renderObject<RenderParagraph>(line);
      expect(
        p.didExceedMaxLines,
        isFalse,
        reason: 'cut off: ${p.text.toPlainText()}',
      );
      expect(find.text(tr('staff.tracking_on')), findsOneWidget);
      expect(
        find.textContaining('%'),
        findsWidgets,
        reason: 'the battery stays',
      );
      await finish(t);
    });
  }
}
