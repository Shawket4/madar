// Requests and approvals against the rules backend (phase B), driven
// through the real UI in Arabic and English. Each test checks the action
// the screen hands the core; what the core sends the server is tested in
// madar-core (`dawam.rs`), and what the server does in tests/dawam_rules.rs.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

import 'support.dart';

/// The owner-free side of the app: Home, Timesheet, Shifts, Requests, Pay.
const _timesheet = 1;
const _requests = 3;

/// Manager side: Team, Approvals, Schedule.
const _approvals = 1;

void main() {
  useCoreWords();
  setUpAll(() async {
    await loadFonts();
    await initializeDateFormatting();
  });

  for (final lang in ['en', 'ar']) {
    String w(String key) => coreWord(key, arabic: lang == 'ar');

    Future<void> tapText(WidgetTester t, String text) async {
      final f = find.text(text).last;
      await t.ensureVisible(f);
      await t.tap(f);
      await frames(t);
    }

    Finder cardWith(String text) => find.ancestor(
      of: find.textContaining(text),
      matching: find.byType(MadarCard),
    );

    Future<void> tapIn(WidgetTester t, Finder card, String text) async {
      final f = find.descendant(of: card, matching: find.text(text));
      await t.ensureVisible(f);
      await frames(t, 4);
      await t.tap(f);
      await frames(t);
    }

    Future<void> openKind(WidgetTester t, String key) async {
      await pumpApp(t, lang: lang, who: 'e1', tab: _requests);
      // The kind's tile, above any request of that kind in the list.
      await t.tap(find.text(w(key)).first);
      await frames(t);
    }

    group(lang, () {
      // RQ-8: a half day says which half; RQ-5: the words after sending
      // are the server's answer, never the filer's role. Sara is an
      // employee: the old screen told her "Sent to your manager" even when
      // the server approved it.
      testWidgets('a half day sends its half, and the server says approved', (
        t,
      ) async {
        await openKind(t, 'staff.kind_leave');
        testCore.filed = {
          'id': 'q|n1',
          'status': 'approved',
          'to_owner': false,
        };
        await tapText(t, w('staff.half_day'));
        await tapText(t, w('staff.second_half'));
        await tapText(t, w('staff.send'));
        expect(lastAct()['action'], 'file');
        expect(lastAct()['kind'], 'leave');
        expect(lastAct()['half'], isTrue);
        expect(lastAct()['leave_half'], 'second');
        // The list already shows two approved requests; the third is the toast.
        expect(find.text(w('staff.approved')), findsNWidgets(3));
        expect(find.text(w('staff.sent_to_your_manager')), findsNothing);
        await finish(t);
      });

      testWidgets('a full day names no half; a manager’s goes to the owner', (
        t,
      ) async {
        await openKind(t, 'staff.kind_leave');
        testCore.filed = {'id': 'q|n2', 'status': 'pending', 'to_owner': true};
        await tapText(t, w('staff.send'));
        expect(lastAct()['half'], isFalse);
        expect(lastAct().containsKey('leave_half'), isFalse);
        expect(find.text(w('staff.sent_to_the_owner')), findsOneWidget);
        await finish(t);
      });

      // B5 / 06-B12: an excuse may end after midnight. The old sheet
      // refused any end at or before the start and never sent it.
      testWidgets('an excuse past midnight is sent, marked the next day', (
        t,
      ) async {
        await openKind(t, 'staff.kind_excuse');
        // From 23:00 (the default end, 13:00, is now earlier on the clock).
        await t.tap(find.text(w('staff.from')).last);
        await frames(t);
        await t.tap(find.byIcon(Icons.keyboard_outlined));
        await frames(t);
        final fields = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );
        await t.enterText(fields.first, '11');
        await t.enterText(fields.last, '00');
        await frames(t, 4);
        final ok = MaterialLocalizations.of(
          t.element(find.byType(Dialog)),
        ).okButtonLabel;
        await t.tap(find.text(ok));
        await frames(t);
        expect(
          find.textContaining(w('staff.ends_the_next_day')),
          findsOneWidget,
        );
        await tapText(t, w('staff.send'));
        expect(lastAct()['kind'], 'excuse');
        expect((lastAct()['time'], lastAct()['time2']), (23 * 60, 13 * 60));
        await finish(t);
      });

      // §3: a mission's note is its title; the sheet asks for it.
      testWidgets('a mission asks where you will be, and sends it', (t) async {
        await openKind(t, 'staff.kind_mission');
        expect(find.text(w('staff.where_you_ll_be')), findsOneWidget);
        await t.enterText(find.byType(EditableText).last, 'Obour market');
        await tapText(t, w('staff.send'));
        expect(lastAct()['kind'], 'mission');
        expect(lastAct()['note'], 'Obour market');
        await finish(t);
      });

      // AT-7: cancelling an approved request says why, and the sheet sends
      // the reason. RQ-8: the row says which half.
      testWidgets('cancelling an approved half day asks why', (t) async {
        await pumpApp(t, lang: lang, who: 'e1', tab: _requests);
        final row = find.textContaining('Sister');
        expect(
          find.textContaining(w('staff.half_day_second_suffix').trim()),
          findsWidgets,
        );
        await t.ensureVisible(row);
        await t.tap(row);
        await frames(t);
        expect(find.text(w('staff.why_cancel')), findsOneWidget);
        await t.enterText(find.byType(EditableText).last, 'Plans changed');
        await tapText(t, w('staff.cancel_request'));
        expect(lastAct(), {
          'action': 'cancel',
          'req': 'q|q8',
          'note': 'Plans changed',
        });
        await finish(t);
      });

      // RQ-7: an early departure's pay is decided, starting from the rule
      // (`paidDefault`); the old card had no toggle and sent unpaid.
      testWidgets('an early departure starts from the rule and can flip', (
        t,
      ) async {
        await pumpApp(t, lang: lang, who: 'e2', manage: true, tab: _approvals);
        final card = cardWith('Pharmacy');
        expect(
          find.descendant(of: card, matching: find.text(w('staff.unpaid'))),
          findsOneWidget,
        );
        await tapIn(t, card, w('staff.approve'));
        expect(lastAct(), containsPair('req', 'q|q6'));
        expect(lastAct(), containsPair('paid', true));
        await finish(t);
      });

      testWidgets('an early departure approved unpaid says so', (t) async {
        await pumpApp(t, lang: lang, who: 'e2', manage: true, tab: _approvals);
        final card = cardWith('Pharmacy');
        await tapIn(t, card, w('staff.unpaid'));
        await tapIn(t, card, w('staff.approve'));
        expect(lastAct(), containsPair('paid', false));
        await finish(t);
      });

      // RQ-7: a late arrival has no pay to decide.
      testWidgets('a late arrival is approved without a pay answer', (t) async {
        await pumpApp(t, lang: lang, who: 'e2', manage: true, tab: _approvals);
        final card = cardWith('Exam');
        expect(
          find.descendant(of: card, matching: find.text(w('staff.unpaid'))),
          findsNothing,
        );
        await tapIn(t, card, w('staff.approve'));
        expect(lastAct(), containsPair('req', 'q|q3'));
        expect(lastAct().containsKey('paid'), isFalse);
        await finish(t);
      });

      // 06 TAB-Approvals: the advance is shown to the piastre and sent only
      // when the approver changed it (approving 500.50 unchanged sent 501).
      testWidgets('an advance approved unchanged sends no amount', (t) async {
        await pumpApp(t, lang: lang, who: 'e2', manage: true, tab: _approvals);
        final card = cardWith('Rent');
        final field = find.descendant(
          of: card,
          matching: find.byType(EditableText),
        );
        expect(t.widget<EditableText>(field).controller.text, '500.50');
        await tapIn(t, card, w('staff.approve'));
        expect(lastAct(), containsPair('req', 'v|v2'));
        expect(lastAct().containsKey('amount'), isFalse);
        await finish(t);
      });

      testWidgets('an advance the approver edits sends the new amount', (
        t,
      ) async {
        await pumpApp(t, lang: lang, who: 'e2', manage: true, tab: _approvals);
        final card = cardWith('Rent');
        await t.enterText(
          find.descendant(of: card, matching: find.byType(EditableText)),
          '400',
        );
        await tapIn(t, card, w('staff.approve'));
        expect(lastAct(), containsPair('amount', 40000));
        await finish(t);
      });

      // §3: a correction proposes only what changed. Yesterday's punches
      // are both there: an untouched form proposes neither (the core then
      // says to change one), where the old form re-sent both.
      testWidgets('a correction sends only the times that changed', (t) async {
        final c = await pumpApp(t, lang: lang, who: 'e1', tab: _timesheet);
        final store = c.read(dawamProvider);
        final yesterday = store.shifts.firstWhere(
          (s) => s.emp == 'e1' && s.inAt != null && s.outAt != null,
        );
        expect(yesterday.monthOpen, isTrue);
        await t.tap(find.textContaining(hm(yesterday.inAt!)).first);
        await frames(t);
        await tapText(t, w('staff.fix_this_shift'));
        await tapText(t, w('staff.send_to_manager'));
        expect(lastAct()['kind'], 'correction');
        expect(lastAct()['shift'], yesterday.id);
        expect(lastAct().containsKey('time'), isFalse);
        expect(lastAct().containsKey('time2'), isFalse);
        await finish(t);
      });

      testWidgets('a missing punch is proposed at the rostered time', (
        t,
      ) async {
        final c = await pumpApp(t, lang: lang, who: 'e1', tab: _timesheet);
        final store = c.read(dawamProvider);
        final today = store.shifts.firstWhere(
          (s) => s.emp == 'e1' && sameDay(s.date, store.today),
        );
        expect(today.inAt, isNull);
        await t.tap(find.textContaining(shiftWindow(today)).first);
        await frames(t);
        await tapText(t, w('staff.fix_this_shift'));
        await tapText(t, w('staff.send_to_manager'));
        expect(lastAct()['time'], today.template.start);
        expect(lastAct()['time2'], today.template.end);
        await finish(t);
      });

      // E2E bug S10 (Youssef, EN, tablet): a block with its own times
      // (00:47–03:22 on the rota) proposed the template's 16:00 in the fix.
      testWidgets('a missing punch is proposed at the shift\'s own times', (
        t,
      ) async {
        final c = await pumpApp(
          t,
          lang: lang,
          who: 'e1',
          tab: _timesheet,
          core: (f) => f.edit = (v) {
            for (final s
                in (v['shifts'] as List<dynamic>)
                    .cast<Map<String, dynamic>>()) {
              if (s['emp'] == 'e1' && s['in_at'] == null) {
                s['start'] = 47; // 00:47
                s['end'] = 202; // 03:22
                s['edited'] = true;
              }
            }
          },
        );
        final store = c.read(dawamProvider);
        final today = store.shifts.firstWhere(
          (s) => s.emp == 'e1' && sameDay(s.date, store.today),
        );
        expect((today.start, today.end), (47, 202));
        await t.tap(find.textContaining(shiftWindow(today)).first);
        await frames(t);
        await tapText(t, w('staff.fix_this_shift'));
        await tapText(t, w('staff.send_to_manager'));
        expect(lastAct()['time'], 47, reason: 'the shift\'s own start');
        expect(lastAct()['time2'], 202, reason: 'the shift\'s own end');
        await finish(t);
      });
    });
  }
}
