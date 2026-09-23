// Workflows driven through the real UI: the words are the core's (English
// here), the picture is the core's snapshot, and each test checks the action
// the screen hands the core. What that action does is tested in madar-core
// (`dawam.rs`) and the server (tests/dawam.rs).
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await frames(t);
}

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  testWidgets('sign in with the WhatsApp code, agree, clock in', (t) async {
    final c = await pumpApp(t, lang: 'en');
    await t.enterText(find.byType(EditableText), '01001234567');
    await tapText(t, 'Send code');
    await t.enterText(find.byType(EditableText), '123456');
    await tapText(t, 'Verify');
    await tapText(t, 'I agree');
    expect(c.read(dawamProvider).me, 'e1');
    await tapText(t, 'Clock in');
    expect(lastAct()['action'], 'clock_in');
    expect(lastAct()['shift'], startsWith('e1|'));
    expect(lastAct()['fix'], isNotNull, reason: 'the punch carries the GPS fix');
    await finish(t);
  });

  testWidgets('an unknown number is refused (RO-1)', (t) async {
    await pumpApp(t, lang: 'en');
    await t.enterText(find.byType(EditableText), '01111111111');
    await tapText(t, 'Send code');
    expect(find.textContaining("isn't registered"), findsOneWidget);
    await finish(t);
  });

  testWidgets('a manager deducts for leaving mid-shift (CL-6, CL-7)', (
    t,
  ) async {
    await pumpApp(t, lang: 'en', who: 'e2', manage: true);
    await tapText(t, 'Youssef Adel · Left mid-shift');
    await tapText(t, 'Deduct');
    expect(lastAct(), {
      'action': 'resolve',
      'flag': 'f1',
      'how': 'deduct',
      'deduct': 5500, // the server's suggestion, as typed (nearest 5 EGP)
    });
    await finish(t);
  });

  testWidgets('approving a leave as unpaid asks the core for exactly that', (
    t,
  ) async {
    await pumpApp(t, lang: 'en', who: 'e2', manage: true, tab: 1);
    final card = find.ancestor(
      of: find.textContaining('Family wedding'),
      matching: find.byType(MadarCard),
    );
    Finder inCard(String text) =>
        find.descendant(of: card, matching: find.text(text));
    await t.tap(inCard('Unpaid'));
    await frames(t);
    await t.tap(inCard('Approve'));
    await frames(t);
    expect(lastAct(), containsPair('action', 'decide'));
    expect(lastAct(), containsPair('req', 'q|q1'));
    expect(lastAct(), containsPair('approve', true));
    expect(lastAct(), containsPair('paid', false));
    await finish(t);
  });

  testWidgets('a shift tapped on the calendar can be given a day off', (
    t,
  ) async {
    final c = await pumpApp(t, lang: 'en', who: 'e2', manage: true, tab: 2);
    final store = c.read(dawamProvider);
    expect(store.shiftsOn('e1', store.today), isNotEmpty);
    // kalender staggers simultaneous shifts; tap the corner that shows.
    await t.tapAt(t.getTopLeft(find.text('Sara').first) + const Offset(3, 3));
    await frames(t);
    expect(find.text('Day off'), findsOneWidget, reason: 'edit sheet opens');
    await tapText(t, 'Day off');
    expect(lastAct(), containsPair('action', 'set_day'));
    expect(lastAct(), containsPair('emp', 'e1'));
    expect(lastAct(), containsPair('tpl', null));
    await finish(t);
  });

  testWidgets('refused "Always" location clocks in with tracking off (CL-5)', (
    t,
  ) async {
    await pumpApp(t, lang: 'en', who: 'e1');
    testCore.always = false;
    await tapText(t, 'Clock in');
    expect(lastAct()['action'], 'clock_in');
    expect(lastAct()['tracking_off'], isTrue);
    await finish(t);
  });

  testWidgets('a manager sets the coverage grid (SC-13)', (t) async {
    await pumpApp(t, lang: 'en', who: 'e2', manage: true, tab: 2);
    await tapText(t, 'Coverage needs');
    await tapText(t, 'Save');
    expect(lastAct()['action'], 'set_coverage');
    final needs = (lastAct()['needs'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(needs.single, {
      'day_of_week': 6,
      'band_start': '12:00:00',
      'band_end': '15:00:00',
      'staff': 2,
    });
    await finish(t);
  });

  testWidgets('language and theme come from the shared pickers', (t) async {
    final c = await pumpApp(t, lang: 'en', who: 'e1');
    await t.tap(find.byType(MadarAvatar).first);
    await frames(t);
    await tapText(t, 'Dark');
    expect(
      t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tapText(t, 'العربية');
    expect(c.read(localeProvider), 'ar');
    expect(find.text('الرئيسية'), findsWidgets);
    await finish(t);
  });
}
