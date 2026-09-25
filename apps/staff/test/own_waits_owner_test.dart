// Addendum 2 (owner's Android test, RQ-5): Karim, a manager, claimed an open
// shift; his view said "waiting for the manager" though it goes to the
// owner, and it vanished from his Approvals. His own pending items show
// there read-only, "Waiting for the owner", with nothing to decide.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('my own request waits for the owner, read-only · $lang', (
      t,
    ) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 1,
        core: (f) => f.edit = (v) {
          (v['requests'] as List<dynamic>).add({
            'amount': 0,
            'created': '2026-09-23T06:00:00+03:00',
            'emp': 'e2',
            'from': '2026-09-30',
            'half': false,
            'id': 'q|mine',
            'installments': 1,
            'kind': 'leave',
            'minutes': 0,
            'month_open': true,
            'note': 'Wedding',
            'status': 'pending',
            'to': '2026-09-30',
            'to_owner': true,
          });
          v['waiting_owner'] = ['q|mine'];
        },
      );
      await frames(t, 30);
      final card = find.byKey(const ValueKey('owner|q|mine'));
      await t.dragUntilVisible(
        card,
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      await frames(t);
      expect(
        find.descendant(
          of: card,
          matching: find.text(tr('staff.waiting_for_the_owner')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text(tr('staff.approve'))),
        findsNothing,
        reason: 'nothing for me to decide',
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('Wedding')),
        findsOneWidget,
      );
      await finish(t);
    });
  }
}
