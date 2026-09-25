// E2E posnotif X-41: a shift with its own times (18:45–22:45 on a block
// whose default is 16:00–00:00) showed "8h 00m" on the running card and ran
// its progress bar against 8 hours. The card measures the shift it shows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();

  for (final lang in ['en', 'ar']) {
    testWidgets(
      'a running shift with its own times shows its own length · $lang',
      (t) async {
        await pumpApp(
          t,
          lang: lang,
          who: 'e1',
          core: (c) => c.edit = (v) {
            // The fixture's own today (it is written on the day it runs).
            final today = (v['now'] as String).substring(0, 10);
            for (final s in v['shifts'] as List<dynamic>) {
              final m = s as Map<String, dynamic>;
              if (m['id'] == 'e1|$today|zM') {
                // 09:00–11:00 on a block that runs 08:00–16:00 by default.
                m['start'] = 540;
                m['end'] = 660;
                m['edited'] = true;
                m['in_at'] = '${today}T09:00:00+03:00';
                m['in_method'] = 'till';
              }
            }
          },
        );
        await frames(t, 20);
        expect(
          find.text(mins(120)),
          findsOneWidget,
          reason: 'the shift is 2 h',
        );
        expect(
          find.text(mins(480)),
          findsNothing,
          reason: "the block's default length",
        );
        final bar = t.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        // 30 min into a 2-h shift (the fixture's now is 09:30).
        expect(bar.value, closeTo(0.25, 0.01));
        await finish(t);
      },
    );
  }
}
