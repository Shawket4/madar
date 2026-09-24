// E2E clocking (S-043): the owner signed out from Manage > Team and the Maadi
// manager who signed in next on the same phone landed on Manage > Team, not
// her own Home. Whoever signs in next starts on their own Home — after a
// sign-out from the settings sheet and after a forced one (a revoked phone).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:madar_staff/shell.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await frames(t);
}

Future<void> signInAs(WidgetTester t, String phone) async {
  await t.enterText(find.byType(EditableText), phone);
  await tapText(t, 'Send code');
  await t.enterText(find.byType(EditableText), '123456');
  await tapText(t, 'Verify');
  if (find.text('I agree').evaluate().isNotEmpty) await tapText(t, 'I agree');
  await frames(t);
}

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final forced in [false, true]) {
    testWidgets('the next person starts on their own Home · '
        '${forced ? 'forced sign-out' : 'Sign out'}', (t) async {
      final c = await pumpApp(t, lang: 'en', who: 'e2', manage: true);
      await frames(t);
      expect(find.text('Team'), findsWidgets, reason: 'on the Manage side');
      if (forced) {
        c.read(dawamProvider).signOut();
      } else {
        final handle = t.ensureSemantics();
        await t.tap(find.bySemanticsLabel(RegExp('Omar')).first);
        handle.dispose();
        await frames(t);
        await tapText(t, 'Sign out');
        if (find.text('Sign out').evaluate().isNotEmpty) {
          await tapText(t, 'Sign out');
        }
      }
      await frames(t);
      expect(find.text('Send code'), findsOneWidget);
      await signInAs(t, '01003333333');
      expect(c.read(dawamProvider).me, 'e3');
      expect(c.read(shellProvider), (tab: 0, manage: false));
      expect(find.text('Team'), findsNothing, reason: 'Home, not Manage');
      expect(find.text('Home'), findsWidgets);
      await finish(t);
    });
  }
}
