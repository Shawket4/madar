// Minor #19: the swap sheet listed only the 12 soonest colleague shifts,
// so a shift later in the week could not be picked. It lists every
// colleague shift in published weeks at the branch, grouped by day.
import 'package:feature_dawam_schedule/feature_dawam_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  setUp(() {
    tplIndex
      ..clear()
      ..['am'] = Tpl('am', 'b1', 'Morning', 'Morning', 8 * 60, 16 * 60)
      ..['pm'] = Tpl('pm', 'b1', 'Evening', 'Evening', 16 * 60, 24 * 60)
      ..['x'] = Tpl('x', 'b2', 'Other', 'Other', 8 * 60, 16 * 60);
  });

  test('every colleague shift, by day, soonest first', () {
    final now = DateTime(2026, 9, 20, 9);
    final mine = Shift('me|2026-09-21|am', 'me', 'am', DateTime(2026, 9, 21));
    Shift s(String emp, int day, String tpl) =>
        Shift('$emp|2026-09-$day|$tpl', emp, tpl, DateTime(2026, 9, day));
    final shifts = [
      mine,
      // Twenty colleague shifts over ten days: more than the old 12.
      for (var d = 21; d <= 30; d++) ...[
        s('omar', d, 'pm'),
        s('sara', d, 'am'),
      ],
      s('omar', 20, 'am'), // started already
      s('laila', 22, 'x'), // another branch
      Shift('open|o1', null, 'am', DateTime(2026, 9, 23)), // an open shift
      s('ziad', 31, 'am'), // an unpublished week
    ];
    final days = swapChoices(
      shifts,
      mine,
      me: 'me',
      now: now,
      published: (x) => x.emp != 'ziad',
    );
    expect(days.map((d) => d.$1.day), [for (var d = 21; d <= 30; d++) d]);
    expect(days.expand((d) => d.$2), hasLength(20), reason: 'all of them');
    expect(days.first.$2.map((x) => x.emp), [
      'sara',
      'omar',
    ], reason: 'in start order within the day');
  });

  // Minor #23: the swap cards sat above the full-height calendar and
  // scrolled out of sight. They fold into one line that opens them.
  test('waiting swaps fold into one line', () {
    words = coreWord;
    expect(swapsWaitingLine(asks: 0, mine: 0), isNull, reason: 'no line');
    final (title, meta) = swapsWaitingLine(asks: 1, mine: 1)!;
    expect(title, coreWord('staff.swaps_waiting').replaceAll('{count}', '2'));
    expect(meta, coreWord('staff.swaps_to_answer').replaceAll('{count}', '1'));
    expect(swapsWaitingLine(asks: 0, mine: 2)!.$2, isNull);
  });
}
