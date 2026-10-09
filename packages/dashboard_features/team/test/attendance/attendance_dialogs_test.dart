// Add record (TEAM-ATT-023…033) and Correct record (TEAM-ATT-035…037),
// driven through the real shell on the mock server, with the area-wide rows
// they carry (coded refusals, the time field, invalidation, Escape).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/attendance/attendance_dialogs.dart';
import 'package:dashboard_team/src/shared/staff_query.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'attendance_support.dart';

final String morning = TeamSeedIds.workShift('sabah', 'morning');

List<MockCall> posts(DashHarness h) => h.server.callsTo(listT, method: 'POST');

List<MockCall> patches(DashHarness h) =>
    h.server.callsTo(recordT, method: 'PATCH');

Map<String, Object?> bodyOf(MockCall c) => (c.body! as Map).cast();

Future<void> openAdd(DashHarness h) async {
  await h.tap(pageText('Add record'));
  expect(find.byType(AttendanceAddDialog), findsOneWidget);
}

/// Opens a select in the dialog by what it shows, and picks [option].
Future<void> pick(DashHarness h, String shows, String option) async {
  await h.tap(surfaceText(shows).first);
  final list = find.byType(DashOptionList<String>);
  await h.tester.scrollUntilVisible(
    find.descendant(of: list, matching: find.text(option)),
    100,
    scrollable: find
        .descendant(of: list, matching: find.byType(Scrollable))
        .last,
  );
  await h.tap(listed(option));
}

/// [option] in the open option list.
Finder listed(String option) => find
    .descendant(
      of: find.byType(DashOptionList<String>),
      matching: find.text(option),
    )
    .last;

/// Picks day [n] of the calendar the trigger showing [shows] opens, [back]
/// months before the one it shows.
Future<void> pickDay(
  DashHarness h,
  Finder trigger,
  String n, {
  int back = 0,
}) async {
  await h.tap(trigger);
  for (var i = 0; i < back; i++) {
    await h.tap(find.bySemanticsLabel('Previous').hitTestable().last);
  }
  await h.tap(find.text(n).hitTestable().last);
}

/// The [i]th punch's (0 In, 1 Out) day trigger and time box (the Add
/// dialog's own Date comes first there).
Finder dayOf(int i) => find.descendant(
  of: inSurface(find.byType(AttendanceDateTimeField)).at(i),
  matching: find.byType(DashDateField),
);

Finder timeBox(int i) => find.descendant(
  of: inSurface(find.byType(DashTimeField)).at(i),
  matching: find.byType(EditableText),
);

Future<void> typeTime(DashHarness h, int i, String text) async {
  await h.enterText(timeBox(i), text);
  await h.tester.testTextInput.receiveAction(TextInputAction.done);
  await h.settle();
}

String timeShown(WidgetTester tester, int i) =>
    tester.widget<EditableText>(timeBox(i)).controller.text;

Future<void> typeReason(DashHarness h, String text) => h.enterText(
  find.descendant(
    of: find.ancestor(
      of: surfaceText(h.t('staff.reason')),
      matching: find.byType(DashTextField),
    ),
    matching: find.byType(EditableText),
  ),
  text,
);

Finder save() => inSurface(find.widgetWithText(DashButton, 'Save'));

bool saveEnabled(WidgetTester tester) =>
    tester.widget<DashButton>(save()).onPressed != null;

/// One late record of Laila's yesterday at Zamalek, 09:02–17:00 Cairo.
MockRow lailaRow() => recordRow(
  id: 'r-laila',
  employeeKey: 'laila',
  date: day(-1),
  status: 'late',
  workShiftId: morning,
  workShiftName: 'Morning',
  inAt: cairo(day(-1), '09:02'),
  outAt: cairo(day(-1), '17:00'),
  inMethod: 'mobile_gps',
  outMethod: 'mobile_gps',
  late: 2,
  worked: 478,
  scheduledStart: cairo(day(-1), '07:00'),
  scheduledEnd: cairo(day(-1), '15:00'),
);

void main() {
  // ── Add record ──────────────────────────────────────────────────────────

  testWidgets('TEAM-ATT-023 Add record: title and words; reads the active '
      'people and the shifts; opens empty every time', (tester) async {
    final h = await pumpAttendance(tester);
    await openAdd(h);
    expect(surfaceText('Add record'), findsOneWidget);
    expect(surfaceText(h.t('staff.addRecordHint')), findsOneWidget);
    expect(
      h.server
          .callsTo(employeesT)
          .where((c) => c.query['employment_status']?.first == 'active'),
      isNotEmpty,
    );
    expect(h.server.callsTo('/staff/work-shifts'), isNotEmpty);
    await typeReason(h, 'Left over');
    await h.tap(inSurface(find.text('Cancel')));
    expect(find.byType(AttendanceAddDialog), findsNothing);
    await openAdd(h);
    expect(
      tester
          .widget<DashTextField>(
            find.ancestor(
              of: surfaceText('Reason'),
              matching: find.byType(DashTextField),
            ),
          )
          .value,
      '',
    );
    expect(posts(h), isEmpty);
  });

  testWidgets('TEAM-ATT-024/032 Save with nothing picked says "Pick an '
      'employee" and "Say why", and sends nothing', (tester) async {
    final h = await pumpAttendance(tester);
    await openAdd(h);
    await h.tap(save());
    expect(surfaceText('Pick an employee'), findsWidgets);
    expect(surfaceText('Say why'), findsOneWidget);
    expect(surfaceText('Why this record exists'), findsOneWidget);
    expect(posts(h), isEmpty);
  });

  testWidgets('TEAM-ATT-024 only active people are offered', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) =>
          db['employees'].find(emp('ziad'))!['employment_status'] = 'suspended',
    );
    await openAdd(h);
    await h.tap(surfaceText('Pick an employee'));
    expect(find.text('Mariam Fathy').hitTestable(), findsOneWidget);
    expect(find.text('Ziad Amr').hitTestable(), findsNothing);
  });

  testWidgets('TEAM-ATT-025/033 one branch in scope: its branch, never '
      'asked; the record is saved on the branch\'s clock with a derived '
      'status, toasted, and the list refetched', (tester) async {
    final h = await pumpAttendance(tester);
    await h.tap(find.text('All branches'));
    await h.tap(find.text('Zamalek').hitTestable());
    final lists = pageListCalls(h).length;
    final summaries = h.server.callsTo(summaryT).length;
    await openAdd(h);
    await pick(h, 'Pick an employee', 'Nour El-Sayed');
    expect(surfaceText('Branch'), findsNothing);
    await pickDay(h, inSurface(find.byType(DashDateFormField)), '6');
    await pickDay(h, dayOf(0), '6');
    await typeTime(h, 0, '930');
    await typeReason(h, 'The app missed the day');
    await h.tap(save());
    expect(bodyOf(posts(h).single), {
      'branch_id': SeedIds.zamalek,
      'business_date': '2026-10-06',
      'check_in_at': '2026-10-06T06:30:00.000Z',
      'check_out_at': null,
      'employee_id': emp('nour'),
      'reason': 'The app missed the day',
      'status': null,
      'work_shift_id': null,
    });
    await h.expectToast('Record added');
    expect(find.byType(AttendanceAddDialog), findsNothing);
    expect(pageListCalls(h).length, lists + 1);
    expect(h.server.callsTo(summaryT).length, summaries + 1);
    await h.enterText(inPage(find.byType(DashSearchInput)), 'nour');
    await h.settle();
    expect(tableText('Nour El-Sayed'), findsOneWidget);
    expect(tableText('entered by hand'), findsOneWidget);
  });

  testWidgets('TEAM-ATT-025 All branches: a one-branch person\'s branch is '
      'used; someone at several picks among theirs, "Pick a branch" until '
      'then', (tester) async {
    final h = await pumpAttendance(tester);
    await openAdd(h);
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    expect(surfaceText('Branch'), findsNothing);
    await typeReason(h, 'Missed');
    await h.tap(save());
    expect(bodyOf(posts(h).single)['branch_id'], SeedIds.zamalek);
    await h.flushTimers();

    await openAdd(h);
    await pick(h, 'Pick an employee', 'Nour El-Sayed');
    expect(surfaceText('Branch'), findsOneWidget);
    await typeReason(h, 'Covered at Maadi');
    await h.tap(save());
    expect(surfaceText('Pick a branch'), findsNWidgets(2));
    expect(posts(h), hasLength(1));
    await h.tap(surfaceText('Pick a branch').first);
    for (final b in ['Heliopolis', 'Maadi', 'New Cairo', 'Zamalek']) {
      expect(find.text(b).hitTestable(), findsWidgets, reason: b);
    }
    await h.tap(find.text('Maadi').hitTestable().last);
    await h.tap(save());
    expect(bodyOf(posts(h).last)['branch_id'], SeedIds.maadi);
    await h.flushTimers();
  });

  testWidgets('TEAM-ATT-026/027 the date defaults to today; "From the '
      'times" by default (sent as null), or one of the five', (tester) async {
    final h = await pumpAttendance(tester);
    await openAdd(h);
    expect(
      tester
          .widget<DashDateFormField>(inSurface(find.byType(DashDateFormField)))
          .value,
      DateTime(2026, 10, 8),
    );
    expect(surfaceText('From the times'), findsOneWidget);
    await h.tap(surfaceText('From the times'));
    for (final s in ['Present', 'Late', 'Half day', 'Absent', 'On leave']) {
      expect(find.text(s).hitTestable(), findsWidgets, reason: s);
    }
    await h.tap(find.text('Absent').hitTestable().last);
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    await typeReason(h, 'No show');
    await h.tap(save());
    final b = bodyOf(posts(h).single);
    expect(b['status'], 'absent');
    expect(b['business_date'], day());
    await h.flushTimers();
  });

  testWidgets('TEAM-ATT-028 Work shift: Unscheduled, the record branch\'s '
      'blocks and business-wide ones only', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) {
        final base = db['work_shifts'].rows.firstWhere(
          (r) => r['org_id'] == SeedIds.sabahOrg,
        );
        db['work_shifts']
          ..insert({
            ...base,
            'id': 'ws-zamalek',
            'name': 'Zamalek late',
            'branch_id': SeedIds.zamalek,
          })
          ..insert({
            ...base,
            'id': 'ws-maadi',
            'name': 'Maadi brunch',
            'branch_id': SeedIds.maadi,
          });
      },
    );
    await openAdd(h);
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    await h.tap(surfaceText('Unscheduled'));
    for (final s in ['Morning', 'Evening', 'Zamalek late']) {
      expect(find.text(s).hitTestable(), findsOneWidget, reason: s);
    }
    expect(find.text('Maadi brunch').hitTestable(), findsNothing);
    await h.tap(find.text('Zamalek late').hitTestable());
    await typeReason(h, 'Late block');
    await h.tap(save());
    expect(bodyOf(posts(h).single)['work_shift_id'], 'ws-zamalek');
    await h.flushTimers();
  });

  testWidgets('TEAM-ATT-029 / TEAM-ALL-025 times on the branch clock, named '
      'under them; typed as said (9:30p, Arabic digits); out before in '
      'refused; half-typed sends nothing', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) =>
          db['branches'].find(SeedIds.zamalek)!['timezone'] = 'Asia/Tokyo',
    );
    await openAdd(h);
    expect(
      surfaceText("Times are the branch's clock (Africa/Cairo)."),
      findsOneWidget,
    );
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    expect(
      surfaceText("Times are the branch's clock (Asia/Tokyo)."),
      findsOneWidget,
    );
    await pickDay(h, dayOf(0), '8');
    await typeTime(h, 0, '9:30p');
    expect(timeShown(tester, 0), '09:30 PM');
    await pickDay(h, dayOf(1), '8');
    await typeTime(h, 1, '٩:٠٠ ص');
    expect(timeShown(tester, 1), '09:00 AM');
    await typeReason(h, 'Night');
    await h.tap(save());
    expect(surfaceText('Out must be after in'), findsOneWidget);
    expect(posts(h), isEmpty);
    await typeTime(h, 1, '11:45 pm');
    expect(surfaceText('Out must be after in'), findsNothing);
    await h.tap(save());
    final b = bodyOf(posts(h).single);
    expect(b['check_in_at'], '2026-10-08T12:30:00.000Z'); // 21:30 Tokyo
    expect(b['check_out_at'], '2026-10-08T14:45:00.000Z');
    await h.flushTimers();
  });

  testWidgets('TEAM-ATT-029 a day with no time yet is not a punch: nothing '
      'is sent for it', (tester) async {
    final h = await pumpAttendance(tester);
    await openAdd(h);
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    await pickDay(h, dayOf(0), '8');
    await typeReason(h, 'Day only');
    await h.tap(save());
    expect(bodyOf(posts(h).single)['check_in_at'], isNull);
    await h.flushTimers();
  });

  testWidgets('TEAM-ALL-025 an unreadable time says so and blocks Save', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    await openAdd(h);
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    await pickDay(h, dayOf(0), '8');
    await typeTime(h, 0, 'soon');
    expect(
      surfaceText(h.t('inputs.timeUnreadable', args: {'text': 'soon'})),
      findsOneWidget,
    );
    await typeReason(h, 'x');
    await h.tap(save());
    expect(posts(h), isEmpty);
    expect(find.byType(AttendanceAddDialog), findsOneWidget);
  });

  testWidgets('TEAM-ATT-030 a colleague covers the picked shift: the note, '
      'and Save off once an In is typed; asks the day and 40 after', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    await openAdd(h);
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    await pickDay(h, inSurface(find.byType(DashDateFormField)), '7');
    expect(
      h.server
          .callsTo(listT)
          .where(
            (c) =>
                c.query['from']?.first == day(-1) &&
                c.query['to']?.first == '2026-11-16' &&
                c.query.length == 2,
          ),
      isNotEmpty,
    );
    expect(
      surfaceText(h.t('dawam.coveredByHint', args: {'name': 'Youssef Samir'})),
      findsNothing,
    );
    await pick(h, 'Unscheduled', 'Morning');
    expect(
      surfaceText(h.t('dawam.coveredByHint', args: {'name': 'Youssef Samir'})),
      findsOneWidget,
    );
    expect(saveEnabled(tester), isTrue);
    await pickDay(h, dayOf(0), '7');
    await typeTime(h, 0, '7');
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('TEAM-ATT-031 a day in an approved month: the note, Save off', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    await openAdd(h);
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    expect(surfaceText(h.t('staff.dayMonthClosed')), findsNothing);
    await pickDay(h, inSurface(find.byType(DashDateFormField)), '20', back: 1);
    expect(surfaceText(h.t('staff.dayMonthClosed')), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('TEAM-ATT-033 / TEAM-ALL-014 a refusal toasts its words in the '
      'person\'s language and keeps the dialog open', (tester) async {
    final s = attendanceServer();
    s.server.fail(
      'POST',
      listT,
      MockResponse.error(
        409,
        'This employee already has a record for that day and shift',
        code: 'RECORD_EXISTS',
      ),
    );
    final h = await pumpAttendance(tester, s: s, locale: 'ar');
    await h.tap(pageText('إضافة سجل'));
    await pick(h, 'اختر موظفًا', 'Mariam Fathy');
    await typeReason(h, 'سبب');
    await h.tap(inSurface(find.widgetWithText(DashButton, 'حفظ')));
    await h.expectToast(h.t('errors.codes.RECORD_EXISTS'));
    expect(find.byType(AttendanceAddDialog), findsOneWidget);
  });

  testWidgets('TEAM-ATT-033 the server\'s own refusal: a check-in on a '
      'covered shift reads with the coverer\'s name', (tester) async {
    final s = attendanceServer();
    s.server.fail(
      'POST',
      listT,
      MockResponse.error(
        409,
        'Youssef Samir is covering this shift.',
        code: 'SHIFT_COVERED',
        vars: {'coverer_name': 'Youssef Samir'},
      ),
    );
    final h = await pumpAttendance(tester, s: s);
    await openAdd(h);
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    await typeReason(h, 'x');
    await h.tap(save());
    await h.expectToast(
      h.t(
        'errors.codes.SHIFT_COVERED',
        args: {'coverer_name': 'Youssef Samir'},
      ),
    );
  });

  testWidgets('TEAM-ATT-033 / TEAM-ALL-026 a dialog closed mid-save still '
      'refreshes the records', (tester) async {
    final h = await pumpAttendance(tester);
    final lists = pageListCalls(h).length;
    await openAdd(h);
    await pick(h, 'Pick an employee', 'Mariam Fathy');
    await typeReason(h, 'x');
    final gate = h.server.hold('POST', listT);
    await h.tap(save());
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.byType(AttendanceAddDialog), findsNothing);
    gate.release();
    await h.settle();
    expect(pageListCalls(h).length, lists + 1);
  });

  testWidgets('TEAM-ALL-021 Escape closes the dialog, sending nothing', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    await openAdd(h);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.byType(AttendanceAddDialog), findsNothing);
    expect(posts(h), isEmpty);
  });

  // ── Correct record ──────────────────────────────────────────────────────

  testWidgets('TEAM-ATT-035 Correct: title, who and which day, the stamps on '
      'the RECORD\'s branch clock, the status and the reason', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) {
        db['branches'].find(SeedIds.zamalek)!['timezone'] = 'Asia/Tokyo';
        onlyRecords(db, [lailaRow()]);
      },
    );
    await h.tap(inPage(find.bySemanticsLabel('Correct')));
    expect(surfaceText('Correct record'), findsOneWidget);
    expect(surfaceText('Laila Ehab · ${day(-1)}'), findsOneWidget);
    // 06:02Z is 15:02 in Tokyo.
    expect(timeShown(tester, 0), '03:02 PM');
    expect(timeShown(tester, 1), '11:00 PM');
    expect(
      surfaceText("Times are the branch's clock (Asia/Tokyo)."),
      findsOneWidget,
    );
    expect(surfaceText('Late'), findsOneWidget);
    await h.tap(surfaceText('Late'));
    for (final s in ['Present', 'Half day', 'Absent', 'On leave']) {
      expect(find.text(s).hitTestable(), findsWidgets, reason: s);
    }
    expect(find.text('From the times').hitTestable(), findsNothing);
  });

  testWidgets('TEAM-ATT-037 / TEAM-ALL-026 Correct sends only what changed; '
      'toasts, closes and refreshes /staff/attendance…', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) => onlyRecords(db, [lailaRow()]),
    );
    final lists = pageListCalls(h).length;
    final summaries = h.server.callsTo(summaryT).length;
    await h.tap(inPage(find.bySemanticsLabel('Correct')));
    expect(timeShown(tester, 0), '09:02 AM');
    await h.tap(save());
    expect(surfaceText('Say why'), findsOneWidget);
    expect(surfaceText('Why this is being changed'), findsOneWidget);
    expect(patches(h), isEmpty);
    await typeTime(h, 1, '6:30 pm');
    await typeReason(h, 'Forgot to clock out');
    await h.tap(save());
    final call = patches(h).single;
    expect(call.path, '/staff/attendance/r-laila');
    expect(bodyOf(call), {
      'check_in_at': null,
      'check_out_at': '${day(-1)}T15:30:00.000Z',
      'reason': 'Forgot to clock out',
      'status': null,
    });
    await h.expectToast('Record corrected');
    expect(find.byType(AttendanceCorrectDialog), findsNothing);
    expect(pageListCalls(h).length, lists + 1);
    expect(h.server.callsTo(summaryT).length, summaries + 1);
    expect(tableText('corrected'), findsOneWidget);
  });

  testWidgets('TEAM-ATT-035/037 an out before the in is refused; a new status '
      'alone is sent alone', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) => onlyRecords(db, [lailaRow()]),
    );
    await h.tap(inPage(find.bySemanticsLabel('Correct')));
    await typeTime(h, 1, '8');
    await typeReason(h, 'x');
    await h.tap(save());
    expect(surfaceText('Out must be after in'), findsOneWidget);
    expect(patches(h), isEmpty);
    await typeTime(h, 1, '5p');
    await pick(h, 'Late', 'Present');
    await h.tap(save());
    expect(bodyOf(patches(h).single), {
      'check_in_at': null,
      'check_out_at': null,
      'reason': 'x',
      'status': 'present',
    });
    await h.flushTimers();
  });

  testWidgets('TEAM-ATT-036 a covered shift: the note, and Save off once a '
      'NEW In is typed', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) => records(db).insert(
        recordRow(
          id: 'r-mariam',
          employeeKey: 'mariam',
          date: day(-1),
          status: 'absent',
          workShiftId: morning,
          workShiftName: 'Morning',
        ),
      ),
    );
    await h.enterText(inPage(find.byType(DashSearchInput)), 'mariam');
    await h.settle();
    await h.tap(
      find.descendant(
        of: find
            .ancestor(
              of: tableText('Covered by Youssef Samir'),
              matching: find.byType(Row),
            )
            .at(1),
        matching: find.bySemanticsLabel('Correct'),
      ),
    );
    expect(surfaceText('Mariam Fathy · ${day(-1)}'), findsOneWidget);
    expect(
      surfaceText(h.t('dawam.coveredByHint', args: {'name': 'Youssef Samir'})),
      findsOneWidget,
    );
    await typeReason(h, 'He came in');
    expect(saveEnabled(tester), isTrue);
    await pickDay(h, dayOf(0), '7');
    await typeTime(h, 0, '9:30');
    expect(saveEnabled(tester), isFalse);
    expect(patches(h), isEmpty);
  });

  testWidgets('TEAM-ATT-037 a closed month refused by the server toasts its '
      'words', (tester) async {
    final s = attendanceServer(edit: (db) => onlyRecords(db, [lailaRow()]));
    s.server.fail(
      'PATCH',
      recordT,
      MockResponse.error(
        409,
        "That month is paid — a correction dated ${day(-1)} can't change it.",
        code: 'PERIOD_CLOSED',
        vars: {'date': day(-1), 'paid': true},
      ),
    );
    final h = await pumpAttendance(tester, s: s);
    await h.tap(inPage(find.bySemanticsLabel('Correct')));
    await typeReason(h, 'x');
    await pick(h, 'Late', 'Present');
    await h.tap(save());
    await h.expectToast(h.t('errors.codes.PERIOD_CLOSED_paid'));
    expect(find.byType(AttendanceCorrectDialog), findsOneWidget);
  });

  testWidgets('TEAM-ATT-035 a background refresh re-seeds the form until it '
      'is edited', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) => onlyRecords(db, [lailaRow()]),
    );
    await h.tap(inPage(find.bySemanticsLabel('Correct')));
    expect(timeShown(tester, 1), '05:00 PM');
    records(h.db!).find('r-laila')!['check_out_at'] = cairo(day(-1), '17:45');
    h.container.read(staffRevisionsProvider.notifier).refetch();
    await h.settle();
    expect(timeShown(tester, 1), '05:45 PM');
    await typeReason(h, 'Fix');
    records(h.db!).find('r-laila')!['check_out_at'] = cairo(day(-1), '18:00');
    h.container.read(staffRevisionsProvider.notifier).refetch();
    await h.settle();
    expect(timeShown(tester, 1), '05:45 PM');
    await pick(h, 'Late', 'Present');
    await h.tap(save());
    // The diff is against what was seeded, not the newer server value.
    expect(bodyOf(patches(h).single)['check_out_at'], isNull);
    await h.flushTimers();
  });
}
