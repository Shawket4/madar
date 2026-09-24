// A push that arrives with the app open on Android (the OS draws nothing
// there) shows as a toast in the server's words, and its action opens the
// same screen a tapped notification would.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:madar_staff/shell.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

void main() {
  useCoreWords();
  setUpAll(() async {
    await initializeDateFormatting();
    await loadFonts();
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('a foreground push shows a toast that opens Pay ($lang)', (
      tester,
    ) async {
      final c = await pumpApp(tester, lang: lang, who: 'e1');
      await tester.pumpAndSettle();
      const text = 'Dawam · A deduction was added: Late (50.00 EGP)';
      c.read(foregroundPushProvider).value = (
        text: text,
        key: 'staff.n_deduction_added',
      );
      await tester.pump();
      expect(find.text(text), findsOneWidget);
      final view = find.text(tr('staff.push_view'));
      expect(view, findsOneWidget);
      await tester.tap(view);
      await tester.pumpAndSettle();
      final store = c.read(dawamProvider);
      expect(
        c.read(shellProvider).tab,
        shellTabs(store, manage: false).indexOf('pay'),
      );
      expect(find.text(text), findsNothing, reason: 'the toast closed');
      await finish(tester);
    });
  }

  testWidgets('a foreground push without a screen shows no action', (
    tester,
  ) async {
    final c = await pumpApp(tester, lang: 'en', who: 'e1');
    await tester.pumpAndSettle();
    c.read(foregroundPushProvider).value = (text: 'Dawam · hello', key: null);
    await tester.pump();
    expect(find.text('Dawam · hello'), findsOneWidget);
    expect(find.text(tr('staff.push_view')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Dawam · hello'), findsNothing, reason: '2.6 s toast');
    await finish(tester);
  });
}
