// The Schedule's dialogs and cards: the day editor (TEAM-SCH-040…050), the
// coverage needs (055…058), the preferences dialog (060…062) and the
// fairness card (065…067), driven on the real shell and the seeded mock.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show formatProvider, ltr;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/schedule/coverage_card.dart';
import 'package:dashboard_team/src/schedule/fairness_card.dart';
import 'package:dashboard_team/src/shared/refresh_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_support.dart';

/// Opens [name]'s day [day] (0 = Saturday) of this week.
Future<DashHarness> openDay(
  WidgetTester tester,
  String name,
  int day, {
  Persona persona = Persona.owner,
  void Function(MockDb db)? edit,
  Srv? s,
  DashSize size = DashSize.desktop,
  String locale = 'en',
}) async {
  final h = await pumpSchedule(
    tester,
    persona: persona,
    edit: edit,
    s: s,
    size: size,
    locale: locale,
  );
  await h.tap(dayCellOf(h, name, day));
  expect(surface(), findsOneWidget);
  return h;
}

Finder surfaceButton(String label) =>
    inSurface(find.widgetWithText(DashButton, label));

bool on(WidgetTester tester, Finder f) =>
    tester.widget<DashButton>(f.first).onPressed != null;

/// Types [text] into the [i]th time box of the open dialog and commits it.
Future<void> typeTime(DashHarness h, int i, String text) async {
  final box = find.descendant(
    of: inSurface(find.byType(DashTimeField)).at(i),
    matching: find.byType(EditableText),
  );
  await h.enterText(box, text);
  await h.tester.testTextInput.receiveAction(TextInputAction.done);
  await h.settle();
}

Future<void> pickIn(DashHarness h, Key select, String option) async {
  await h.tap(find.byKey(select));
  await h.tap(find.textContaining(option).hitTestable().last);
}

/// A day set at Zamalek for [key] on [date] of [blocks] (`[block, start,
/// end]`).
void setDay(MockDb db, String key, String date, List<List<String?>> blocks) =>
    db['roster_day_sets'].put({
      'id': '${emp(key)}|$date',
      'employee_id': emp(key),
      'on_date': date,
      'blocks': [
        for (final b in blocks)
          {
            'work_shift_id': b[0],
            'start_time': b[1],
            'end_time': b[2],
            'branch_id': SeedIds.zamalek,
          },
      ],
    });

void main() {
  // ── the day editor ───────────────────────────────────────────────────

  testWidgets('TEAM-SCH-040 the day editor: the title, the hint (published: '
      'they are told), the day\'s shifts', (tester) async {
    final h = await openDay(tester, 'Adham Reda', 0);
    expect(inSurface(plainHas('Adham Reda, 03 Oct 2026')), findsWidgets);
    expect(
      surfaceText(
        '${h.t('dawam.dayEditorHint')} ${h.t('dawamOps.toldPublished')}',
      ),
      findsOneWidget,
    );
    expect(inSurface(find.text('Morning')), findsOneWidget);
    expect(find.byKey(const Key('day-elsewhere')), findsNothing);
  });

  testWidgets('TEAM-SCH-040 a draft week says nothing about telling; a rest '
      'day lists "Off"', (tester) async {
    final h = await pumpSchedule(tester);
    await h.tap(pressable('Next week'));
    await h.tap(dayCell('Adham Reda', 9));
    expect(surfaceText(h.t('dawam.dayEditorHint')), findsOneWidget);
    expect(surfaceText('Off'), findsOneWidget);
  });

  testWidgets('TEAM-SCH-040 shifts at another branch are said, never listed', (
    tester,
  ) async {
    final h = await openDay(
      tester,
      'Adham Reda',
      2,
      edit: (db) {
        db['employees'].find(emp('adham'))!['branch_ids'] = [
          SeedIds.zamalek,
          SeedIds.maadi,
        ];
        db['roster_day_sets'].put({
          'id': '${emp('adham')}|${wd(2)}',
          'employee_id': emp('adham'),
          'on_date': wd(2),
          'blocks': [
            {
              'work_shift_id': morningId,
              'start_time': null,
              'end_time': null,
              'branch_id': SeedIds.maadi,
            },
          ],
        });
      },
    );
    expect(
      surfaceText(
        h.t('dawamOps.alsoElsewhere', args: {'shifts': 'Morning (Maadi)'}),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-041 a shift item: times past midnight, Edited, '
      'Changed after publishing, its three actions', (tester) async {
    await openDay(tester, 'Laila Ehab', 4);
    expect(inSurface(plainHas('16:00–00:00')), findsWidgets);
    expect(inSurface(find.text('+1 day')), findsOneWidget);
    expect(inSurface(find.text('Edited')), findsOneWidget);
    expect(inSurface(find.text('Changed after publishing')), findsOneWidget);
    for (final l in [
      'Times of Evening',
      'Give Evening to someone else',
      'Take Evening off this day',
    ]) {
      expect(inSurface(pressable(l)), findsOneWidget, reason: l);
    }
  });

  testWidgets('TEAM-SCH-042 take one shift of a split day off: the rest sent '
      'back, toast, closed', (tester) async {
    final h = await openDay(tester, 'Youssef Samir', 2);
    await h.tap(inSurface(pressable('Take Evening off this day')));
    final put = calls(h, daysT, 'PUT').single;
    expect(bodyOf(put), {
      'employee_id': emp('youssef'),
      'on_date': wd(2),
      'shifts': [
        {'work_shift_id': morningId, 'start_time': null, 'end_time': null},
      ],
      'branch_id': SeedIds.zamalek,
    });
    await h.expectToast('Day changed');
    expect(find.byType(DashSurface), findsNothing);
    expect(
      find.descendant(
        of: dayCell('Youssef Samir', 2),
        matching: find.text('Hours a day'),
      ),
      findsNothing,
    );
  });

  testWidgets('TEAM-SCH-043 new times for this date: PUT, toast, stays open '
      'and shows Edited', (tester) async {
    final h = await openDay(tester, 'Adham Reda', 0);
    await h.tap(inSurface(pressable('Times of Morning')));
    await typeTime(h, 0, '08:00');
    await typeTime(h, 1, '16:00');
    await h.tap(surfaceButton('Save times'));
    final put = calls(h, timesT, 'PUT').single;
    expect(bodyOf(put), {
      'employee_id': emp('adham'),
      'on_date': wd(0),
      'work_shift_id': morningId,
      'start_time': '08:00:00',
      'end_time': '16:00:00',
    });
    await h.expectToast('Times saved for this day');
    expect(surface(), findsOneWidget);
    expect(inSurface(find.text('Edited')), findsOneWidget);
    expect(inSurface(plainHas('08:00–16:00')), findsWidgets);
  });

  testWidgets('TEAM-SCH-043 a clash with the other shift is said and blocks '
      'Save', (tester) async {
    final h = await openDay(tester, 'Youssef Samir', 2);
    await h.tap(inSurface(pressable('Times of Morning')));
    await typeTime(h, 1, '18:00');
    expect(
      inSurface(
        find.text(
          h.t(
            'dawamOps.clashTimes',
            args: {'with': 'Evening ${ltr('15:00–23:00')}'},
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(on(tester, surfaceButton('Save times')), isFalse);
    expect(calls(h, timesT, 'PUT'), isEmpty);
  });

  testWidgets('TEAM-SCH-044 back to the shift\'s own times: PUT nulls, toast, '
      'stays open', (tester) async {
    final h = await openDay(tester, 'Laila Ehab', 4);
    await h.tap(inSurface(pressable('Times of Evening')));
    await h.tap(surfaceButton("Use the shift's times"));
    final put = calls(h, timesT, 'PUT').single;
    expect(bodyOf(put), {
      'employee_id': emp('laila'),
      'on_date': wd(4),
      'work_shift_id': eveningId,
      'start_time': null,
      'end_time': null,
    });
    await h.expectToast("Back to the shift's own times");
    expect(surface(), findsOneWidget);
    expect(inSurface(find.text('Edited')), findsNothing);
  });

  testWidgets('TEAM-SCH-044 no own times: no "Use the shift\'s times"', (
    tester,
  ) async {
    final h = await openDay(tester, 'Adham Reda', 0);
    await h.tap(inSurface(pressable('Times of Morning')));
    expect(surfaceButton("Use the shift's times"), findsNothing);
    expect(h.location.path, schedulePath);
  });

  testWidgets('TEAM-SCH-045 give a shift to someone else: POST move, toast, '
      'closed, the receiver\'s warnings toasted', (tester) async {
    final h = await openDay(tester, 'Adham Reda', 0);
    await h.tap(inSurface(pressable('Give Morning to someone else')));
    expect(surfaceText('Give it to'), findsOneWidget);
    expect(on(tester, surfaceButton('Move')), isFalse);
    // Laila is off the Friday before: only the day's own limits warn.
    await pickIn(h, const Key('day-give-to'), 'Laila Ehab');
    await h.tap(surfaceButton('Move'));
    expect(bodyOf(calls(h, moveT, 'POST').single), {
      'employee_id': emp('adham'),
      'to_employee_id': emp('laila'),
      'on_date': wd(0),
      'work_shift_id': morningId,
    });
    expect(find.text('Shift moved'), findsWidgets);
    expect(find.text('Hours a day: 16h of 12h. Only a warning.'), findsWidgets);
    await h.flushTimers();
    expect(find.byType(DashSurface), findsNothing);
  });

  testWidgets('TEAM-SCH-045 the colleague already works then: said, Move '
      'waits', (tester) async {
    final h = await openDay(tester, 'Adham Reda', 0);
    await h.tap(inSurface(pressable('Give Morning to someone else')));
    await pickIn(h, const Key('day-give-to'), 'Karim Adel');
    expect(inSurface(find.byKey(const Key('day-clash'))), findsOneWidget);
    expect(surfaceHas('Karim Adel already works Morning'), findsOneWidget);
    expect(on(tester, surfaceButton('Move')), isFalse);
  });

  testWidgets('TEAM-SCH-046 add a shift that runs that day: PUT the day with '
      'it, toast, its warnings', (tester) async {
    final h = await openDay(tester, 'Adham Reda', 0);
    await pickIn(h, const Key('day-add-shift'), 'Evening');
    await h.tap(surfaceButton('Add'));
    expect(bodyOf(calls(h, daysT, 'PUT').single)['shifts'], [
      {'work_shift_id': morningId, 'start_time': null, 'end_time': null},
      {'work_shift_id': eveningId, 'start_time': null, 'end_time': null},
    ]);
    expect(find.text('Day changed'), findsWidgets);
    expect(find.text('Hours a day: 16h of 12h. Only a warning.'), findsWidgets);
    await h.flushTimers();
    expect(find.byType(DashSurface), findsNothing);
  });

  testWidgets('TEAM-SCH-046 an overlapping block is marked, said and refused '
      'before sending', (tester) async {
    final h = await openDay(
      tester,
      'Adham Reda',
      0,
      edit: (db) => setDay(db, 'adham', wd(0), [
        [morningId, '07:00:00', '16:00:00'],
      ]),
    );
    await h.tap(find.byKey(const Key('day-add-shift')));
    expect(find.text('overlaps Morning').hitTestable(), findsOneWidget);
    await h.tap(find.textContaining('Evening').hitTestable().last);
    expect(inSurface(find.byKey(const Key('day-clash'))), findsOneWidget);
    expect(on(tester, surfaceButton('Add')), isFalse);
  });

  testWidgets('TEAM-SCH-046 every block already on the day: "No other shift '
      'runs that day"', (tester) async {
    final h = await openDay(tester, 'Youssef Samir', 2);
    expect(surfaceText(h.t('dawam.noShiftThatDay')), findsOneWidget);
    expect(on(tester, surfaceButton('Add')), isFalse);
  });

  testWidgets('TEAM-SCH-047 the note: limits warn, overlaps are refused', (
    tester,
  ) async {
    final h = await openDay(tester, 'Adham Reda', 0);
    expect(surfaceText(h.t('dawam.dayEditorWarn')), findsOneWidget);
  });

  testWidgets('TEAM-SCH-048 a date with its own set goes back to the pattern: '
      'DELETE, toast, closed', (tester) async {
    final h = await openDay(tester, 'Mariam Fathy', 6);
    expect(surfaceText(h.t('dawam.backToPatternHint')), findsOneWidget);
    await h.tap(surfaceButton('Back to pattern'));
    final del = calls(h, daysT, 'DELETE').single;
    expect(del.query, {
      'employee_id': [emp('mariam')],
      'on_date': [wd(6)],
      'branch_id': [SeedIds.zamalek],
    });
    await h.expectToast('Back on the standing pattern');
    expect(find.byType(DashSurface), findsNothing);
    expect(
      find.descendant(
        of: dayCell('Mariam Fathy', 6),
        matching: find.text('Evening'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-048 a pattern day says it follows the pattern', (
    tester,
  ) async {
    final h = await openDay(tester, 'Adham Reda', 0);
    expect(surfaceText('Follows the standing pattern'), findsOneWidget);
    expect(surfaceButton('Back to pattern'), findsNothing);
    expect(h.location.path, schedulePath);
  });

  testWidgets('TEAM-SCH-049 day off with shifts: confirm naming them, then '
      'an empty day', (tester) async {
    final h = await openDay(tester, 'Adham Reda', 0);
    await h.tap(surfaceButton('Day off'));
    expect(
      inConfirm(plainHas('Give Adham Reda the day off on 03 Oct 2026?')),
      findsWidgets,
    );
    expect(
      inConfirm(
        find.text(
          '${h.t('dawamOps.dayOffHint', args: {'shifts': 'Morning'})} '
          '${h.t('dawamOps.toldPublished')}',
        ),
      ),
      findsOneWidget,
    );
    await h.tap(inConfirm(find.text('Day off')));
    expect(bodyOf(calls(h, daysT, 'PUT').single)['shifts'], isEmpty);
    await h.expectToast('Day changed');
    expect(
      find.descendant(
        of: dayCell('Adham Reda', 0),
        matching: find.text('Day off'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-049 a day with no shifts: no confirm', (tester) async {
    final h = await openDay(tester, 'Adham Reda', 2);
    await h.tap(surfaceButton('Day off'));
    expect(confirm(), findsNothing);
    expect(calls(h, daysT, 'PUT'), hasLength(1));
    await h.flushTimers();
  });

  testWidgets('TEAM-SCH-050 a refusal toasts its words, the dialog stays; '
      'buttons wait while busy', (tester) async {
    final s = scheduleServer();
    final refusal = MockResponse.error(
      409,
      'Morning on 2026-10-05 and Evening on 2026-10-05 overlap.',
      code: 'SHIFTS_OVERLAP',
      vars: {'a': 'Morning', 'b': 'Evening', 'date': wd(2)},
    );
    s.server.fail('PUT', daysT, refusal);
    final h = await openDay(tester, 'Adham Reda', 0, s: s);
    await pickIn(h, const Key('day-add-shift'), 'Evening');
    await h.tap(surfaceButton('Add'));
    expect(
      find.textContaining(
        h.t('errors.codes.SHIFTS_OVERLAP_named').split('{{').first,
      ),
      findsWidgets,
    );
    await h.flushTimers();
    expect(surface(), findsOneWidget);

    final gate = h.server.hold('PUT', daysT);
    await h.tap(surfaceButton('Add'));
    expect(on(tester, surfaceButton('Day off')), isFalse);
    gate.release();
    await h.settle();
    await h.flushTimers();
  });

  testWidgets('TEAM-SCH-050 (phone) the day editor is a centred card in '
      'Arabic', (tester) async {
    final h = await openDay(
      tester,
      'Adham Reda',
      0,
      size: DashSize.phone,
      locale: 'ar',
    );
    expect(surfaceText(h.t('dawam.dayEditorWarn')), findsOneWidget);
    expectPhoneDialog(tester);
  });

  // ── coverage needs ───────────────────────────────────────────────────

  Future<DashHarness> openCoverage(
    WidgetTester tester, {
    Srv? s,
    Persona persona = Persona.owner,
  }) async {
    final h = await pumpSchedule(tester, s: s, persona: persona);
    await h.tap(inPage(find.widgetWithText(DashButton, 'Coverage needs')));
    return h;
  }

  Finder inCoverage(Finder f) =>
      find.descendant(of: find.byType(CoverageCard), matching: f);

  DashTextInput cellAt(WidgetTester tester, int dow, int hour) =>
      tester.widget<DashTextInput>(find.byKey(ValueKey('coverage-$dow-$hour')));

  testWidgets('TEAM-SCH-056/057 POS-derived needs: the sales words, hours '
      'from 06:00, Saturday first, greyed figures in empty cells', (
    tester,
  ) async {
    final h = await openCoverage(tester);
    expect(
      inCoverage(find.text(h.t('dawam.coveragePos', args: {'n': 25}))),
      findsOneWidget,
    );
    expect(inCoverage(plainHas('06:00')), findsWidgets);
    expect(inCoverage(plainHas('05:00')), findsNothing);
    final sat = tester.getCenter(inCoverage(find.text('Sat'))).dx;
    final fri = tester.getCenter(inCoverage(find.text('Fri'))).dx;
    expect(sat, lessThan(fri));
    expect(cellAt(tester, 6, 8).value, '');
    expect(cellAt(tester, 6, 8).placeholder, '1');
    expect(cellAt(tester, 6, 6).placeholder, isNull);
    expect(cellAt(tester, 6, 8).semanticLabel, 'Sat 08:00');
  });

  testWidgets('TEAM-SCH-056 typed needs: the grid words', (tester) async {
    final s = scheduleServer(
      edit: (db) => db['coverage_needs'].insert({
        'org_id': SeedIds.sabahOrg,
        'branch_id': SeedIds.zamalek,
        'day_of_week': 6,
        'band_start': '05:00:00',
        'band_end': '07:00:00',
        'staff': 2,
        'department_id': null,
      }, timestamps: false),
    );
    final h = await openCoverage(tester, s: s);
    expect(inCoverage(find.text(h.t('dawam.coverageGrid'))), findsOneWidget);
    expect(cellAt(tester, 6, 5).value, '2');
    expect(inCoverage(plainHas('05:00')), findsWidgets);
  });

  testWidgets('TEAM-SCH-056 a Dawam-only org: the pattern words', (
    tester,
  ) async {
    final s2 = scheduleServer(
      edit: (db) {
        final org = db['orgs'].find(SeedIds.sabahOrg)!;
        org['modules'] = ['dawam'];
      },
    );
    final h2 = await openCoverage(tester, s: s2);
    expect(
      inCoverage(find.text(h2.t('dawam.coveragePattern'))),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-056 coverage loading: a skeleton', (tester) async {
    final s = scheduleServer();
    final gate = s.server.hold('GET', coverageT);
    final h = await openCoverage(tester, s: s);
    expect(find.byKey(const Key('coverage-skeleton')), findsOneWidget);
    gate.release();
    await h.settle();
  });

  testWidgets('TEAM-SCH-056 coverage failed: the error, Retry', (tester) async {
    final s2 = scheduleServer();
    // Every try fails: the toggle's touch warms the read first.
    s2.server.fail(
      'GET',
      coverageT,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h2 = await openCoverage(tester, s: s2);
    expect(inPage(find.text(h2.t('dawam.coverageLoadError'))), findsOneWidget);
    s2.server.clearFailures();
    await h2.tap(inPage(find.text('Retry')));
    expect(find.byKey(const Key('coverage-card')), findsOneWidget);
  });

  testWidgets('TEAM-SCH-058 save: the whole list, department needs kept, '
      'equal hours merged; toast; coverage and /staff refetched', (
    tester,
  ) async {
    final s = scheduleServer(
      edit: (db) => db['coverage_needs'].insert({
        'org_id': SeedIds.sabahOrg,
        'branch_id': SeedIds.zamalek,
        'day_of_week': 1,
        'band_start': '09:00:00',
        'band_end': '12:00:00',
        'staff': 1,
        'department_id': 'dept-kitchen',
      }, timestamps: false),
    );
    final h = await openCoverage(tester, s: s);
    await h.enterText(find.byKey(const ValueKey('coverage-6-9')), '3');
    await h.enterText(find.byKey(const ValueKey('coverage-6-10')), '3');
    final cov = calls(h, coverageT).length;
    final sg = calls(h, suggestionsT).length;
    await h.tap(find.byKey(const Key('coverage-save')));
    final put = calls(h, coverageT, 'PUT').single;
    expect(bodyOf(put), {
      'branch_id': SeedIds.zamalek,
      'needs': [
        {
          'band_end': '12:00:00',
          'band_start': '09:00:00',
          'day_of_week': 1,
          'department_id': 'dept-kitchen',
          'staff': 1,
        },
        {
          'band_end': '11:00:00',
          'band_start': '09:00:00',
          'day_of_week': 6,
          'department_id': null,
          'staff': 3,
        },
      ],
    });
    await h.expectToast('Coverage needs saved');
    expect(calls(h, coverageT).length, cov + 1);
    expect(calls(h, suggestionsT).length, sg + 1);
  });

  testWidgets('TEAM-SCH-058 a refused save toasts and keeps the typed grid', (
    tester,
  ) async {
    final s = scheduleServer();
    s.server.fail('PUT', coverageT, MockResponse.error(400, 'Bad band'));
    final h = await openCoverage(tester, s: s);
    await h.enterText(find.byKey(const ValueKey('coverage-0-9')), '2');
    await h.tap(find.byKey(const Key('coverage-save')));
    await h.expectToast(h.refusalWords(MockResponse.error(400, 'Bad band')));
    expect(cellAt(tester, 0, 9).value, '2');
  });

  testWidgets('TEAM-SCH-058 a refresh re-seeds an untouched grid; after a '
      'keystroke it does not', (tester) async {
    final h = await openCoverage(tester);
    void need(int dow, String from, String to, int staff) =>
        h.db!['coverage_needs'].insert({
          'org_id': SeedIds.sabahOrg,
          'branch_id': SeedIds.zamalek,
          'day_of_week': dow,
          'band_start': from,
          'band_end': to,
          'staff': staff,
          'department_id': null,
        }, timestamps: false);
    final refresh = inPage(find.byType(DawamRefreshButton));
    expect(cellAt(tester, 6, 9).value, '');
    need(6, '09:00:00', '10:00:00', 2);
    await h.tap(refresh);
    expect(cellAt(tester, 6, 9).value, '2');
    await h.enterText(find.byKey(const ValueKey('coverage-0-9')), '3');
    need(1, '09:00:00', '10:00:00', 4);
    await h.tap(refresh);
    expect(cellAt(tester, 1, 9).value, '');
    expect(cellAt(tester, 0, 9).value, '3');
  });

  // ── preferences ──────────────────────────────────────────────────────

  Future<DashHarness> openPrefs(
    WidgetTester tester,
    String name, {
    Srv? s,
    String locale = 'en',
    DashSize size = DashSize.desktop,
  }) async {
    final h = await pumpSchedule(tester, s: s, locale: locale, size: size);
    await h.tap(inGrid(pressable(h.t('dawam.prefsOf', args: {'name': name}))));
    return h;
  }

  testWidgets('TEAM-SCH-060 the preferences dialog: who set them, the time, '
      'the days Saturday first', (tester) async {
    final h = await openPrefs(tester, 'Hassan Ibrahim');
    expect(surfaceText("Hassan Ibrahim's preferences"), findsOneWidget);
    expect(surfaceText(h.t('dawam.prefsByManager')), findsOneWidget);
    expect(
      tester
          .widget<DashSelect<String>>(find.byKey(const Key('prefs-time')))
          .value,
      'evening',
    );
    final sat = tester.getCenter(find.byKey(const ValueKey('prefs-day-6'))).dx;
    final fri = tester.getCenter(find.byKey(const ValueKey('prefs-day-5'))).dx;
    expect(sat, lessThan(fri));
    expect(surfaceButton('Save'), findsOneWidget);
    expect(find.byKey(const Key('prefs-note')), findsOneWidget);
  });

  testWidgets('TEAM-SCH-060 without hr.staff.edit: read-only, no note, no '
      'Save', (tester) async {
    final s = scheduleServer();
    answerAuthz(s.server, ['hr.schedule.read', 'hr.schedule.edit']);
    final h = await openPrefs(tester, 'Adham Reda', s: s);
    expect(surfaceText(h.t('dawam.prefsByEmployee')), findsOneWidget);
    expect(
      tester
          .widget<DashSelect<String>>(find.byKey(const Key('prefs-time')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<DashChoiceChip>(find.byKey(const ValueKey('prefs-day-0')))
          .enabled,
      isFalse,
    );
    expect(find.byKey(const Key('prefs-note')), findsNothing);
    expect(surfaceButton('Save'), findsNothing);
    await h.tap(surfaceButton('Close'));
    expect(find.byType(DashSurface), findsNothing);
  });

  testWidgets('TEAM-SCH-060 a refresh that lands before any edit re-seeds '
      'the dialog; after an edit it does not', (tester) async {
    final h = await openPrefs(tester, 'Hassan Ibrahim');
    String? time() => tester
        .widget<DashSelect<String>>(find.byKey(const Key('prefs-time')))
        .value;
    Future<void> refresh(String prefTime) async {
      h.db!['employees'].update(emp('hassan'), {'pref_time': prefTime});
      // Back in the app after 30 s: the week is asked again.
      h.server.clock.advance(const Duration(seconds: 31));
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await h.settle();
    }

    expect(time(), 'evening');
    await refresh('morning');
    expect(time(), 'morning');
    await h.tap(find.byKey(const ValueKey('prefs-day-0')));
    await refresh('evening');
    expect(time(), 'morning');
  });

  testWidgets('TEAM-SCH-061 save: PUT, toast, closed, the grid line follows', (
    tester,
  ) async {
    final h = await openPrefs(tester, 'Adham Reda');
    await h.tap(find.byKey(const Key('prefs-time')));
    await h.tap(find.text('Prefers evenings').hitTestable().last);
    await h.tap(find.byKey(const ValueKey('prefs-day-0')));
    await h.enterText(find.byKey(const Key('prefs-note')), ' Studies Sundays ');
    await h.tap(surfaceButton('Save'));
    final put = calls(h, prefsT, 'PUT').single;
    expect(put.path, '/staff/employees/${emp('adham')}/preferences');
    expect(bodyOf(put), {
      'pref_time': 'evening',
      'cant_work_days': [0],
      'note': 'Studies Sundays',
    });
    await h.expectToast('Preferences saved; they were told');
    expect(find.byType(DashSurface), findsNothing);
    expect(
      inGrid(
        find.text("Prefers evenings · Can't work: Sun · set by a manager"),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-061 a note over 300 characters is refused before '
      'sending', (tester) async {
    final h = await openPrefs(tester, 'Adham Reda');
    await h.enterText(find.byKey(const Key('prefs-note')), 'x' * 301);
    await h.tap(surfaceButton('Save'));
    expect(surfaceText('At most 300 characters'), findsOneWidget);
    expect(calls(h, prefsT, 'PUT'), isEmpty);
  });

  testWidgets('TEAM-SCH-061 no preference sends nulls', (tester) async {
    final h = await openPrefs(tester, 'Hassan Ibrahim');
    await h.tap(find.byKey(const Key('prefs-time')));
    await h.tap(find.text('No preference').hitTestable().last);
    await h.tap(surfaceButton('Save'));
    expect(bodyOf(calls(h, prefsT, 'PUT').single), {
      'pref_time': null,
      'cant_work_days': <int>[],
      'note': null,
    });
    await h.flushTimers();
  });

  testWidgets('TEAM-SCH-062 the change log: by whom and when, what', (
    tester,
  ) async {
    final h = await openPrefs(tester, 'Hassan Ibrahim');
    expect(surfaceText('By Karim Adel'), findsOneWidget);
    expect(surfaceText('By the employee'), findsOneWidget);
    expect(
      surfaceText(h.container.read(formatProvider).fmtDate('2026-09-20')),
      findsOneWidget,
    );
    expect(
      surfaceText('Prefers evenings · Closes the kitchen this month'),
      findsOneWidget,
    );
    expect(calls(h, prefsLogT).single.path, contains(emp('hassan')));
  });

  testWidgets('TEAM-SCH-062 no change yet', (tester) async {
    final h2 = await openPrefs(tester, 'Adham Reda');
    expect(surfaceText('No changes yet.'), findsOneWidget);
    expect(h2.location.path, schedulePath);
  });

  testWidgets('TEAM-SCH-062 the log failed: the server\'s words', (
    tester,
  ) async {
    final s3 = scheduleServer();
    // Every try fails: the button's touch warms the log first.
    s3.server.fail(
      'GET',
      prefsLogT,
      MockResponse.error(500, 'Log down'),
      times: null,
    );
    await openPrefs(tester, 'Adham Reda', s: s3);
    expect(surfaceHas('Log down'), findsOneWidget);
    expect(surfaceText('No changes yet.'), findsNothing);
  });

  // ── fairness ─────────────────────────────────────────────────────────

  Finder inFair(Finder f) =>
      find.descendant(of: find.byType(FairnessCard), matching: f);

  testWidgets('TEAM-SCH-065 the owner sees the nights by gender and the '
      'decisions line', (tester) async {
    final h = await pumpSchedule(tester);
    await h.scrollUntilVisible(find.byType(FairnessCard));
    expect(inFair(find.text('Night shifts, fairly')), findsOneWidget);
    for (final w in [
      'Gender',
      'People',
      'Prefer evenings',
      'Shifts',
      'Night shifts',
    ]) {
      expect(inFair(find.text(w)), findsWidgets, reason: w);
    }
    expect(inFair(find.text('Female')), findsOneWidget);
    expect(inFair(find.text('Male')), findsOneWidget);
    expect(
      inFair(
        find.text('Managers accepted 7 of 14 suggestions in the last 4 weeks.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-065 a manager sees no fairness card', (tester) async {
    final h2 = await pumpSchedule(tester, persona: Persona.manager);
    expect(find.byType(FairnessCard), findsNothing);
    expect(calls(h2, fairnessT), isEmpty);
    expect(calls(h2, auditsT), isEmpty);
  });

  testWidgets('TEAM-SCH-065 learning frozen: the line says so', (tester) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) {
        for (var i = 0; i < 6; i++) {
          db['suggestion_decisions'].put({
            'id': '${SeedIds.heliopolis}|x-$i',
            'branch_id': SeedIds.heliopolis,
            'suggestion_id': 'x-$i',
            'accept': false,
            'by_default': false,
            'decided_at': DateTime.utc(2026, 10, 7).toIso8601String(),
          });
        }
      },
    );
    await h.scrollUntilVisible(find.byType(FairnessCard));
    expect(
      inFair(find.textContaining(h.t('dawam.learningFrozen'))),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-065 fairness loading: a skeleton', (tester) async {
    final s = scheduleServer();
    final gate = s.server.hold('GET', fairnessT);
    final h = await pumpSchedule(tester, s: s);
    expect(inFair(find.byType(DashSkeleton)), findsOneWidget);
    gate.release();
    await h.settle();
  });

  testWidgets('TEAM-SCH-065 fairness failed: the server\'s words', (
    tester,
  ) async {
    final s2 = scheduleServer();
    s2.server.fail('GET', fairnessT, MockResponse.error(500, 'No figures'));
    final h2 = await pumpSchedule(tester, s: s2);
    expect(
      inFair(find.text(h2.refusalWords(MockResponse.error(500, 'No figures')))),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-066 branch by branch: gap, accepted, by the default, '
      'the state pills', (tester) async {
    final h = await pumpSchedule(tester);
    await h.scrollUntilVisible(find.byType(FairnessCard));
    final table = find.byKey(const Key('fairness-branches'));
    Finder inTable(Finder f) => find.descendant(of: table, matching: f);
    expect(inTable(find.text('Branch')), findsOneWidget);
    expect(inTable(find.text('Zamalek')), findsOneWidget);
    expect(inTable(plainHas('3/10')), findsWidgets);
    expect(inTable(find.text('Learning paused')), findsOneWidget);
    expect(h.location.path, schedulePath);
  });

  testWidgets('TEAM-SCH-067 the monthly audits: gap and pill', (tester) async {
    final h = await pumpSchedule(tester);
    await h.scrollUntilVisible(find.byType(FairnessCard));
    final audits = find.byKey(const Key('fairness-audits'));
    Finder inAudits(Finder f) => find.descendant(of: audits, matching: f);
    expect(inAudits(find.text('gap 26 points')), findsOneWidget);
    expect(inAudits(find.text('Over 20 points')), findsNWidgets(2));
    expect(inAudits(find.text('Within 20 points')), findsNWidgets(2));
  });

  testWidgets('TEAM-SCH-067 no audit yet', (tester) async {
    final h2 = await pumpSchedule(
      tester,
      edit: (db) => db['fairness_audits'].removeWhere((_) => true),
    );
    await h2.scrollUntilVisible(find.byType(FairnessCard));
    expect(inFair(find.text(h2.t('dawam.noAudits'))), findsOneWidget);
  });

  testWidgets('TEAM-SCH-067 the audits failed: the server\'s words', (
    tester,
  ) async {
    final s3 = scheduleServer();
    s3.server.fail('GET', auditsT, MockResponse.error(500, 'No audits'));
    final h3 = await pumpSchedule(tester, s: s3);
    await h3.scrollUntilVisible(find.byType(FairnessCard));
    expect(
      inFair(find.text(h3.refusalWords(MockResponse.error(500, 'No audits')))),
      findsOneWidget,
    );
  });
}
