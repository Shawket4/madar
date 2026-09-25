// The roster in both languages (Phase B · schedules): the swap names MY
// shift first (06 B2), a requester takes a swap back, and every board edit
// touches one block of a split day (SC-5, SC-11): its own times, remove it,
// give it away, back to the pattern, cancel an open shift, and a block
// offered only on its own days at that day's times. Each test checks the
// action the screen hands the core; what it does is tested in madar-core
// and the server.
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

/// A word on screen whatever its case (section headers and tags may be set
/// in capitals in English).
Finder word(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.toLowerCase() == text.toLowerCase(),
);

/// Open a shift's sheet from the board, as a tap on its card does.
Future<void> openCard(WidgetTester t, Shift s) async {
  t.widget<RosterBoard>(find.byType(RosterBoard)).onTapCard(s);
  await frames(t);
}

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('a swap names my shift, then the colleague\'s · $lang', (
      t,
    ) async {
      final c = await pumpApp(t, lang: lang, who: 'e1', tab: 2);
      await frames(t);
      final store = c.read(dawamProvider);
      final mine = store.shifts.firstWhere(
        (s) => s.emp == 'e1' && s.published && s.startAt.isAfter(store.now),
      );
      t.widget<ShiftCalendar>(find.byType(ShiftCalendar)).onTapShift!(mine);
      await frames(t);
      expect(word(tr('staff.swap_with')), findsOneWidget);
      await tapText(t, name(store.emp('e4')));
      final act = lastAct();
      expect(act['action'], 'ask_swap');
      expect(act['mine'], mine.id, reason: 'MY shift is mine (06 B2)');
      expect(act['theirs'] as String, startsWith('e4|'));
      await finish(t);
    });

    testWidgets('I take back a swap I asked for · $lang', (t) async {
      await pumpApp(t, lang: lang, who: 'e1', tab: 2);
      await frames(t);
      await tapText(t, tr('staff.cancel_swap'));
      expect(lastAct(), {'action': 'cancel', 'req': 'w|w1'});
      await finish(t);
    });

    testWidgets('one shift of a split day is edited alone · $lang', (t) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 2,
        size: tablet,
      );
      await frames(t);
      final store = c.read(dawamProvider);
      final day = plus(store.today, 3);
      final split = store.shiftsOn('e1', day);
      expect(split, hasLength(2), reason: 'the fixture\'s split day');
      final evening = split.firstWhere((s) => s.tpl == 'zE');
      expect(evening.edited && evening.ownDay, isTrue);
      expect(hm(evening.startAt), hm(DateTime(2000, 1, 1, 17)));

      await openCard(t, evening);
      expect(word(tr('staff.edited')), findsWidgets);
      await tapText(t, tr('staff.remove_this_shift'));
      expect(lastAct(), {'action': 'remove_block', 'shift': evening.id});

      await openCard(t, evening);
      await tapText(t, tr('staff.block_times'));
      expect(lastAct(), {'action': 'set_times', 'shift': evening.id});

      await openCard(t, evening);
      await tapText(t, tr('staff.back_to_pattern'));
      expect(lastAct(), {'action': 'reset_day', 'emp': 'e1', 'date': ymd(day)});

      await openCard(t, evening);
      await tapText(t, name(store.emp('e4')));
      expect(lastAct(), {
        'action': 'give_shift',
        'shift': evening.id,
        'to': 'e4',
      });
      await finish(t);
    });

    // E2E roster m1: the board said "Omar Khaled said they can't work Fris."
    // (the short day name with an "s" stuck on).
    testWidgets('a day someone can\'t work is named in full · $lang', (
      t,
    ) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 2,
        size: tablet,
        core: (core) => core.edit = (v) {
          for (final p in v['people'] as List<dynamic>) {
            final m = p as Map<String, dynamic>;
            if (m['id'] == 'e1' || m['id'] == 'e4') {
              m['cant_work'] = [1, 2, 3, 4, 5, 6, 7];
            }
          }
        },
      );
      await frames(t);
      final store = c.read(dawamProvider);
      final day = plus(store.today, 3);
      final evening = store
          .shiftsOn('e1', day)
          .firstWhere((s) => s.tpl == 'zE');
      final w = day.weekday - 1;
      final days = lang == 'en'
          ? const [
              'Mondays',
              'Tuesdays',
              'Wednesdays',
              'Thursdays',
              'Fridays',
              'Saturdays',
              'Sundays',
            ][w]
          : const [
              'الإثنين',
              'الثلاثاء',
              'الأربعاء',
              'الخميس',
              'الجمعة',
              'السبت',
              'الأحد',
            ][w];
      String said(String who) => lang == 'en'
          ? "$who said they can't work on $days."
          : '$who قال مش هيقدر يشتغل أيام $days.';
      await openCard(t, evening);
      expect(find.text(said(name(store.emp('e1')))), findsOneWidget);
      // The colleague she could give it to says so too.
      expect(find.text(said(firstName(store.emp('e4')))), findsOneWidget);
      await finish(t);
    });

    testWidgets('a night past midnight reads "ends next day" · $lang', (
      t,
    ) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 2,
        size: tablet,
      );
      await frames(t);
      final store = c.read(dawamProvider);
      final late = store
          .shiftsOn('e4', plus(store.today, 2))
          .firstWhere((s) => s.tpl == 'zE');
      expect(late.nextDay, isTrue);
      expect(
        late.endAt,
        DateTime(late.date.year, late.date.month, late.date.day + 1, 0, 30),
        reason: 'the server\'s times, not the block\'s',
      );
      await openCard(t, late);
      expect(word(tr('staff.ends_next_day')), findsOneWidget);
      expect(word(tr('staff.edited')), findsOneWidget);
      // A date with its own times can go back to the usual pattern.
      expect(word(tr('staff.back_to_pattern')), findsOneWidget);
      await finish(t);
    });

    testWidgets('an open shift can be taken back · $lang', (t) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 2,
        size: tablet,
      );
      await frames(t);
      final store = c.read(dawamProvider);
      final open = store.shifts.firstWhere((s) => s.id == 'open|o1');
      await openCard(t, open);
      await tapText(t, tr('staff.cancel_open_shift'));
      expect(lastAct(), {'action': 'cancel_open', 'shift': 'open|o1'});
      await finish(t);
    });

    testWidgets('a day off by date change goes back to the pattern · $lang', (
      t,
    ) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 2,
        size: tablet,
      );
      await frames(t);
      final store = c.read(dawamProvider);
      final off = plus(store.today, 6);
      expect(store.isDayOff('e1', off), isTrue);
      expect(store.shiftsOn('e1', off), isEmpty);
      t.widget<RosterBoard>(find.byType(RosterBoard)).onTapEmpty('e1', off);
      await frames(t);
      expect(
        word('${tr('staff.day_off')} · ${tr('staff.changed')}'),
        findsOneWidget,
      );
      await tapText(t, tr('staff.back_to_pattern'));
      expect(lastAct(), {'action': 'reset_day', 'emp': 'e1', 'date': ymd(off)});
      await finish(t);
    });

    testWidgets('a date on the pattern offers no way back to it · $lang', (
      t,
    ) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 2,
        size: tablet,
      );
      await frames(t);
      final store = c.read(dawamProvider);
      await openCard(t, store.shiftsOn('e1', store.today).first);
      expect(word(tr('staff.back_to_pattern')), findsNothing);
      await finish(t);
    });

    testWidgets('a block is offered only on its days · $lang', (t) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 2,
        size: tablet,
      );
      await frames(t);
      final store = c.read(dawamProvider);
      final ws = weekStart(store.today);
      final board = t.widget<RosterBoard>(find.byType(RosterBoard));
      // Brunch is a Friday block: not on Saturday…
      board.onTapEmpty('e2', ws);
      await frames(t);
      expect(find.text('Brunch'), findsNothing);
      await t.tapAt(const Offset(10, 10)); // close the sheet
      await frames(t);
      await finish(t);
    });

    testWidgets('…and on Friday, beside the rest of the day · $lang', (
      t,
    ) async {
      final c = await pumpApp(
        t,
        lang: lang,
        who: 'e2',
        manage: true,
        tab: 2,
        size: tablet,
      );
      await frames(t);
      final store = c.read(dawamProvider);
      final friday = plus(weekStart(store.today), 6);
      t.widget<RosterBoard>(find.byType(RosterBoard)).onTapEmpty('e2', friday);
      await frames(t);
      await tapText(t, 'Brunch');
      await tapText(t, tr('staff.add'));
      expect(lastAct(), {
        'action': 'add_block',
        'emp': 'e2',
        'date': ymd(friday),
        'tpl': 'zB',
      });
      await finish(t);
    });
  }

  testWidgets('one shift gets its own times', (t) async {
    final c = await pumpApp(
      t,
      lang: 'en',
      who: 'e2',
      manage: true,
      tab: 2,
      size: tablet,
    );
    await frames(t);
    final store = c.read(dawamProvider);
    final today = store.shiftsOn('e1', store.today).first;
    await openCard(t, today);
    await tapText(t, tr('staff.change_times'));
    await tapText(t, 'OK'); // from: as it was
    await tapText(t, 'OK'); // to: as it was
    expect(lastAct(), {
      'action': 'set_times',
      'shift': today.id,
      'start': 8 * 60,
      'end': 16 * 60,
    });
    await finish(t);
  });
}
