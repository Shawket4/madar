// E2E roster (Karim, iPad Air 11" portrait, 24 Sep): the Schedule board's
// bar put the week's range, the status pill and every action on one row; with
// "This week", "Coverage needs" and "Suggestions · 1" the range was squeezed to
// nothing ("OVERFLOWED BY 0.247 PIXELS") and the manager could not see which
// week he was editing. On a tablet the range keeps its room and the actions
// wrap below it, in Arabic and English, for a draft week (Publish) too.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('the week range keeps its room on an iPad · $lang', (t) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 2,
        size: const Size(820, 1180),
      );
      await frames(t, 30);
      final ws = weekStart(c.read(dawamProvider).today);
      // Two weeks on: a draft (Publish week) away from this week ("This week").
      for (var i = 0; i < 2; i++) {
        await t.tap(
          find
              .byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == tr('staff.next'),
              )
              .first,
        );
        await frames(t);
      }
      final shown = DateTime(ws.year, ws.month, ws.day + 14);
      final end = DateTime(shown.year, shown.month, shown.day + 6);
      final range = find.text('${dayMonth(shown)} – ${dayMonth(end)}');
      expect(range, findsOneWidget);
      expect(
        t.getSize(range).width,
        greaterThan(100),
        reason: 'the range is readable',
      );
      final errors = <Object>[];
      for (Object? e = t.takeException(); e != null; e = t.takeException()) {
        errors.add(e);
      }
      expect(errors, isEmpty, reason: 'no overflow in the bar');
      await finish(t);
    });
  }
}
