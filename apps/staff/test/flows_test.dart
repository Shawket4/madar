// Workflows driven through the real UI: the words are the core's (English
// here), the picture is the core's snapshot, and each test checks the action
// the screen hands the core. What that action does is tested in madar-core
// (`dawam.rs`) and the server (tests/dawam.rs).
import 'package:design_system/design_system.dart';
import 'package:feature_dawam_schedule/feature_dawam_schedule.dart';
import 'package:flutter/gestures.dart';
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
    expect(
      lastAct()['fix'],
      isNotNull,
      reason: 'the punch carries the GPS fix',
    );
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

  testWidgets('a flag deduction carries the reason the manager types (AD-9)', (
    t,
  ) async {
    await pumpApp(t, lang: 'en', who: 'e2', manage: true);
    await tapText(t, 'Youssef Adel · Left mid-shift');
    await t.enterText(
      find.widgetWithText(
        TextField,
        'Reason — the employee sees it on the pay line',
      ),
      'Left for a delivery',
    );
    await tapText(t, 'Deduct');
    expect(lastAct(), {
      'action': 'resolve',
      'flag': 'f1',
      'how': 'deduct',
      'deduct': 5500,
      'reason': 'Left for a delivery',
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
    await t.ensureVisible(inCard('Approve'));
    await frames(t);
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

  /// Sara's card for today on the manager's board.
  Finder todaysCard(DawamStore store) => find.byWidgetPredicate(
    (w) =>
        w is ShiftCard &&
        w.card.shift.emp == 'e1' &&
        sameDay(w.card.shift.date, store.today),
  );

  testWidgets('a shift tapped on the board can be given a day off', (t) async {
    final c = await pumpApp(t, lang: 'en', who: 'e2', manage: true, tab: 2);
    final store = c.read(dawamProvider);
    expect(store.shiftsOn('e1', store.today), isNotEmpty);
    await frames(t); // the phone's board scrolls to today
    await t.tap(todaysCard(store));
    await frames(t);
    expect(find.text('Day off'), findsOneWidget, reason: 'edit sheet opens');
    await tapText(t, 'Day off');
    expect(lastAct(), containsPair('action', 'set_day'));
    expect(lastAct(), containsPair('emp', 'e1'));
    expect(lastAct(), containsPair('tpl', null));
    await finish(t);
  });

  testWidgets('an empty day on the board adds a shift for that person', (
    t,
  ) async {
    await pumpApp(
      t,
      lang: 'en',
      who: 'e2',
      manage: true,
      tab: 2,
      size: const Size(1180, 820),
    );
    await frames(t);
    // Omar has no shifts: every day of his row reads "Off".
    await t.tap(find.text('Off').first);
    await frames(t);
    await tapText(t, 'Add');
    // Beside anything else that day, never replacing it (SC-11).
    expect(lastAct(), containsPair('action', 'add_block'));
    expect(lastAct(), containsPair('emp', 'e2'));
    await finish(t);
  });

  testWidgets('a shift dragged to the next day moves (SC-5)', (t) async {
    final c = await pumpApp(
      t,
      lang: 'ar',
      who: 'e2',
      manage: true,
      tab: 2,
      size: const Size(1180, 820),
    );
    await frames(t);
    final store = c.read(dawamProvider);
    final today = store.today;
    // The next day this week, or the day before on a Friday.
    final other = today.weekday == DateTime.friday
        ? DateTime(today.year, today.month, today.day - 1)
        : DateTime(today.year, today.month, today.day + 1);
    final from = t.getCenter(todaysCard(store));
    final to = Offset(t.getCenter(find.text('${other.day}')).dx, from.dy);
    final g = await t.startGesture(from);
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await g.moveTo(to);
    await t.pump();
    await g.up();
    await frames(t);
    expect(lastAct(), containsPair('action', 'move_shift'));
    expect(lastAct()['shift'], startsWith('e1|'));
    expect(
      lastAct()['day'],
      '${other.year}-${other.month.toString().padLeft(2, '0')}-'
      '${other.day.toString().padLeft(2, '0')}',
    );
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
    final needs = (lastAct()['needs'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
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

  // ── clocking (audit 03 / 06: AT-5, B4, B10, CL-4) ─────────────────────

  for (final lang in ['en', 'ar']) {
    testWidgets('a new phone sees the notice until the server records it · '
        '$lang (AT-5)', (t) async {
      final c = await pumpApp(t, lang: lang, core: (f) => f.accepted = false);
      await t.enterText(find.byType(EditableText), '01001234567');
      await tapText(t, tr('staff.send_code'));
      await t.enterText(find.byType(EditableText), '123456');
      await tapText(t, tr('staff.verify'));
      expect(c.read(dawamProvider).me, 'e1', reason: 'signed in');
      expect(find.text(tr('staff.i_agree')), findsOneWidget, reason: 'notice');
      expect(find.text(tr('staff.clock_in')), findsNothing, reason: 'no tabs');
      expect(
        testCore.acts.where((a) => a['action'] == 'accept_privacy'),
        isEmpty,
        reason: 'nothing accepted for them',
      );
      await tapText(t, tr('staff.i_agree'));
      expect(testCore.acts.first, {'action': 'accept_privacy'});
      expect(find.text(tr('staff.clock_in')), findsOneWidget, reason: 'in');
      await finish(t);
    });

    testWidgets('a session restored on the notice opens at the notice · '
        '$lang (AT-5)', (t) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e1',
        core: (f) => f
          ..restored = 'e1'
          ..accepted = false,
      );
      await frames(t);
      expect(find.text(tr('staff.i_agree')), findsOneWidget);
      expect(find.text(tr('staff.clock_in')), findsNothing);
      await tapText(t, tr('staff.i_agree'));
      expect(find.text(tr('staff.clock_in')), findsOneWidget);
      await finish(t);
    });

    // E2E S11 (QUESTIONS #26): after "I agree", a failure to open the app
    // said nothing and left the notice up. It now says so, offers Try again,
    // and Try again opens the app.
    for (final how in ['lost in transit', 'accepted but the app failed']) {
      testWidgets('a failed "I agree" says so and Try again opens · $how · '
          '$lang (S11)', (t) async {
        await pumpApp(
          t,
          lang: lang,
          who: 'e1',
          core: (f) {
            f
              ..restored = 'e1'
              ..accepted = false;
            if (how == 'lost in transit') {
              f.acceptError = Exception('socket closed');
            } else {
              f.acceptLeavesNotice = true;
            }
          },
        );
        await frames(t);
        await tapText(t, tr('staff.i_agree'));
        expect(find.text(tr('staff.privacy_open_failed')), findsOneWidget);
        expect(find.text(tr('staff.try_again')), findsOneWidget);
        expect(find.text(tr('staff.clock_in')), findsNothing);
        await tapText(t, tr('staff.try_again'));
        expect(find.text(tr('staff.clock_in')), findsOneWidget);
        await finish(t);
      });
    }

    testWidgets('Home says where you are from a fresh reading · $lang '
        '(06 B4)', (t) async {
      await pumpApp(t, lang: lang, who: 'e1');
      await frames(t);
      final noted = testCore.acts.where((a) => a['action'] == 'note_fix');
      expect(noted, isNotEmpty, reason: 'a reading is taken when Home opens');
      expect(noted.last['fix'], containsPair('latitude', 30.0609));
      // No fresh reading: "not known yet", never "inside".
      expect(find.text(tr('staff.fence_unknown')), findsOneWidget);
      final branch = lang == 'ar' ? 'Zamalek' : 'Zamalek';
      for (final (state, distance) in [('inside', 150), ('outside', 612)]) {
        testCore.fences = {
          'b1': {'state': state, 'distance_m': distance, 'radius': 200},
        };
        testContainer.read(dawamProvider).sync();
        await frames(t);
        expect(
          find.text(
            tr('staff.fence_$state', {
              'name': branch,
              'distance': distance,
              'radius': 200,
            }),
          ),
          findsOneWidget,
          reason: '$state $distance',
        );
        expect(find.textContaining('$distance'), findsWidgets);
      }
      await finish(t);
    });
  }

  testWidgets('the typed deduction survives the store changing (06 B10)', (
    t,
  ) async {
    await pumpApp(t, lang: 'en', who: 'e2', manage: true);
    await tapText(t, 'Youssef Adel · Left mid-shift');
    // The amount, above the reason the employee reads.
    final fields = find.byType(EditableText);
    final field = fields.at(fields.evaluate().length - 2);
    await t.enterText(field, '123');
    await frames(t);
    // The 2-minute poll, a push, a ping: the store notifies meanwhile.
    testContainer.read(dawamProvider).sync();
    await frames(t);
    expect(t.widget<EditableText>(field).controller.text, '123');
    await tapText(t, 'Deduct');
    expect(lastAct(), containsPair('deduct', 12300));
    await finish(t);
  });

  testWidgets('background tracking follows the shift (CL-4, CL-17)', (t) async {
    await pumpApp(
      t,
      lang: 'en',
      who: 'e1',
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
    expect(testCore.trackingCalls, [true], reason: 'on shift: started once');
    testContainer.read(dawamProvider).sync();
    await frames(t);
    expect(testCore.trackingCalls, [true], reason: 'not again while on');
    testCore.edit = null; // clocked out
    testContainer.read(dawamProvider).sync();
    await frames(t);
    expect(testCore.trackingCalls, [
      true,
      false,
    ], reason: 'stopped at clock-out');
    await finish(t);
  });
}
