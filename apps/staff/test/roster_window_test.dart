// The manager's board and the dates it holds (H2, owner bug 1): every edit
// waits for the server and says what it made of it, in the phone's language;
// a week past the phone's window is asked for and never edited blind; and a
// week reads Published when the server says so, shifts or none.
import 'package:design_system/design_system.dart';
import 'package:feature_dawam_schedule/feature_dawam_schedule.dart';
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

String ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime plus(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

const tablet = Size(1180, 820);

final refusal = DawamError(
  'Brunch and Morning overlap on that day.',
  'البرنش والصباحي متداخلين في اليوم ده.',
);

Future<void> openCard(WidgetTester t, Shift s) async {
  t.widget<RosterBoard>(find.byType(RosterBoard)).onTapCard(s);
  await frames(t);
}

Future<void> nextWeek(WidgetTester t) async {
  final next = find.byWidgetPredicate(
    (w) => w is MadarGlyphTile && w.semanticLabel == tr('staff.next'),
  );
  await t.tap(next.first);
  await frames(t);
}

Future<DawamStore> board(WidgetTester t, String lang) async {
  final c = await pumpApp(
    t,
    lang: lang,
    who: 'e2',
    manage: true,
    tab: 2,
    size: tablet,
  );
  await frames(t);
  return c.read(dawamProvider);
}

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('an Add waits for the server: refused, the sheet stays with '
        'its words; taken, it says so and closes · $lang', (t) async {
      final store = await board(t, lang);
      final friday = plus(weekStart(store.today), 6);
      final title = tr('staff.add_to', {'date': dayLabel(friday)});
      t.widget<RosterBoard>(find.byType(RosterBoard)).onTapEmpty('e2', friday);
      await frames(t);
      await tapText(t, 'Brunch');

      testCore.refuse = refusal;
      await tapText(t, tr('staff.add'));
      expect(lastAct()['action'], 'add_block');
      expect(find.text(loc(refusal)), findsOneWidget, reason: 'the words');
      expect(find.text(title), findsOneWidget, reason: 'the sheet stays');

      testCore.refuse = null;
      await tapText(t, tr('staff.add'));
      expect(find.text(tr('staff.added')), findsOneWidget);
      expect(find.text(title), findsNothing, reason: 'closed once taken');
      await finish(t);
    });

    testWidgets('an edit on a shift waits for the server too · $lang', (
      t,
    ) async {
      final store = await board(t, lang);
      final day = plus(store.today, 3);
      final evening = store
          .shiftsOn('e1', day)
          .firstWhere((s) => s.tpl == 'zE');

      testCore.refuse = refusal;
      await openCard(t, evening);
      await tapText(t, tr('staff.remove_this_shift'));
      expect(lastAct(), {
        'action': 'remove_block',
        'shift': evening.id,
        'branch': 'b1',
      });
      expect(find.text(loc(refusal)), findsOneWidget);
      expect(
        find.text(tr('staff.remove_this_shift')),
        findsOneWidget,
        reason: 'the sheet stays open on a refusal',
      );

      testCore.refuse = null;
      await tapText(t, tr('staff.remove_this_shift'));
      expect(find.text(tr('staff.day_saved')), findsOneWidget);
      expect(find.text(tr('staff.remove_this_shift')), findsNothing);

      // Dropped on the open row: posted, and the board says so.
      t.widget<RosterBoard>(find.byType(RosterBoard)).onDrop!(
        evening,
        null,
        evening.date,
      );
      await frames(t);
      expect(lastAct(), {
        'action': 'assign',
        'shift': evening.id,
        'emp': null,
        'branch': 'b1',
      });
      expect(find.text(tr('staff.open_shift_posted')), findsOneWidget);
      await finish(t);
    });

    testWidgets('a week past the phone\'s window is asked for, and never '
        'edited blind · $lang', (t) async {
      final store = await board(t, lang);
      final ws = weekStart(store.today);
      final far = plus(ws, 28);
      // The core holds this week, four back and three ahead.
      testCore.edit = (v) => v['loaded'] = [
        [ymd(plus(ws, -28)), ymd(plus(ws, 27))],
      ];
      await store.refresh();
      await frames(t);
      for (var i = 0; i < 4; i++) {
        await nextWeek(t);
      }
      expect(lastAct(), {
        'action': 'view_range',
        'from': ymd(far),
        'to': ymd(plus(far, 6)),
      });
      // The core could not bring it: the board says so, and an Add there
      // is not offered on a week the phone doesn't hold.
      final words = tr('staff.week_couldnt_load');
      expect(find.text(words), findsOneWidget);
      expect(find.text(tr('staff.draft')), findsNothing);
      expect(find.text(tr('staff.publish_week')), findsNothing);
      t.widget<RosterBoard>(find.byType(RosterBoard)).onTapEmpty('e2', far);
      await frames(t);
      expect(
        find.text(tr('staff.add_to', {'date': dayLabel(far)})),
        findsNothing,
      );
      expect(find.text(words), findsNWidgets(2), reason: 'and the toast');

      // Once the core holds it, the week is the board's like any other.
      testCore.edit = (v) => v['loaded'] = [
        [ymd(plus(ws, -28)), ymd(plus(ws, 27))],
        [ymd(far), ymd(plus(far, 6))],
      ];
      await store.viewRange(far, plus(far, 6));
      await frames(t, 60);
      expect(find.text(words), findsNothing);
      t.widget<RosterBoard>(find.byType(RosterBoard)).onTapEmpty('e2', far);
      await frames(t);
      expect(
        find.text(tr('staff.add_to', {'date': dayLabel(far)})),
        findsOneWidget,
      );
      await finish(t);
    });

    testWidgets('my calendar page past the window is asked for, and says '
        'why it is empty until it comes · $lang', (t) async {
      final c = await pumpApp(t, lang: lang, who: 'e1', tab: 2);
      await frames(t);
      final store = c.read(dawamProvider);
      final ws = weekStart(store.today);
      testCore.edit = (v) => v['loaded'] = [
        [ymd(plus(ws, -28)), ymd(plus(ws, 89))],
      ];
      await store.refresh();
      final from = plus(ws, 91);
      final to = plus(from, 34);
      t.widget<ShiftCalendar>(find.byType(ShiftCalendar)).onRangeChanged!(
        from,
        to,
      );
      await frames(t);
      expect(lastAct(), {
        'action': 'view_range',
        'from': ymd(from),
        'to': ymd(to),
      });
      expect(find.text(tr('staff.week_couldnt_load')), findsOneWidget);
      await finish(t);
    });

    testWidgets('a coverage band shows once the server takes it · $lang', (
      t,
    ) async {
      await board(t, lang);
      await tapText(t, tr('staff.coverage_needs'));
      testCore.refuse = refusal;
      await tapText(t, tr('common.save'));
      expect(lastAct()['action'], 'set_coverage');
      expect(find.text(loc(refusal)), findsOneWidget);
      expect(find.text('12:00 – 15:00'), findsNothing, reason: 'not taken');
      testCore.refuse = null;
      await tapText(t, tr('common.save'));
      expect(find.text(tr('staff.coverage_saved')), findsOneWidget);
      expect(find.text('12:00 – 15:00'), findsOneWidget);
      await finish(t);
    });

    testWidgets('a week the server published reads Published, shifts or '
        'none · $lang', (t) async {
      final store = await board(t, lang);
      final ws = weekStart(store.today);
      final empty = plus(ws, 14);
      expect(
        store.shifts.where(
          (s) => !s.date.isBefore(empty) && s.date.isBefore(plus(empty, 7)),
        ),
        isEmpty,
        reason: 'a week with no shift in it',
      );
      testCore.edit = (v) => v['published_weeks'] = ['b1|${ymd(empty)}'];
      await store.refresh();
      await nextWeek(t);
      await nextWeek(t);
      expect(find.text(tr('staff.published')), findsOneWidget);
      expect(find.text(tr('staff.publish_week')), findsNothing);
      await finish(t);
    });
  }
}
