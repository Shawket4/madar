// Workflows driven through the real UI: the words are the core's (English
// here), the state is the mock core, the widgets are the features'.
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
    await tapText(t, 'Sara Ahmed');
    await t.enterText(find.byType(EditableText), '123456');
    await tapText(t, 'Verify');
    await tapText(t, 'I agree');
    final store = c.read(dawamProvider);
    expect(store.me, 'e1');
    await tapText(t, 'Clock in');
    expect(store.activeShift, isNotNull);
    expect(find.text('Clock out'), findsOneWidget);
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
    final c = await pumpApp(t, lang: 'en', who: 'e2', manage: true);
    await tapText(t, 'Youssef Adel · Left mid-shift');
    await tapText(t, 'Deduct');
    final store = c.read(dawamProvider);
    final f = store.flags.firstWhere((f) => f.kind == FlagKind.leftMidShift);
    expect(f.deducted, greaterThan(0));
    expect(
      store.slip(f.emp, store.period).lines.any((l) => l.key == 'away:${f.id}'),
      isTrue,
    );
    await finish(t);
  });

  testWidgets('approving a leave as unpaid prices it like an absence', (
    t,
  ) async {
    final c = await pumpApp(t, lang: 'en', who: 'e2', manage: true, tab: 1);
    final store = c.read(dawamProvider);
    final leave = store.inbox.firstWhere((r) => r.kind == ReqKind.leave);
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
    expect(leave.status, ReqStatus.approved);
    expect(leave.paid, isFalse);
    await finish(t);
  });

  testWidgets('a shift tapped on the calendar can be given a day off', (
    t,
  ) async {
    final c = await pumpApp(t, lang: 'en', who: 'e2', manage: true, tab: 2);
    final store = c.read(dawamProvider);
    final today = store.today;
    expect(store.shiftsOn('e1', today), isNotEmpty);
    // kalender staggers simultaneous shifts; tap the corner that shows.
    await t.tapAt(t.getTopLeft(find.text('Sara').first) + const Offset(3, 3));
    await frames(t);
    expect(find.text('Day off'), findsOneWidget, reason: 'edit sheet opens');
    await tapText(t, 'Day off');
    expect(store.shiftsOn('e1', today), isEmpty);
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
