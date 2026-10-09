// Driven tests of the Requests inbox's forms: approve with the pay
// question (TEAM-REQ-020…023), cancel (TEAM-REQ-031) and New request
// (TEAM-REQ-040…048).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show formatProvider;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/approvals/approvals_dialogs.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/requests/requests_dialogs.dart';
import 'package:dashboard_team/src/shared/staff_query.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'requests_support.dart';

const String _youssef = 'Renewing my national ID';
const String _salma = "My sister's wedding";
const String _farida = "Doctor's appointment.";

Finder _listed(String option) => find
    .descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('DashOptionList'),
      ),
      matching: find.text(option),
    )
    .last;

/// The text box of the field labelled [label] in the open dialog.
Finder _box(String label) => find.descendant(
  of: inSurface(find.widgetWithText(DashTextField, label)),
  matching: find.byType(EditableText),
);

Finder _save() => inSurface(find.widgetWithText(DashButton, 'Save'));

Finder _optionList() => find.byWidgetPredicate(
  (w) => w.runtimeType.toString().startsWith('DashOptionList'),
);

Future<void> _pick(DashHarness h, String shows, String option) async {
  await h.tap(surfaceText(shows).first);
  await h.tester.scrollUntilVisible(
    find.descendant(of: _optionList(), matching: find.text(option)),
    100,
    scrollable: find
        .descendant(of: _optionList(), matching: find.byType(Scrollable))
        .last,
  );
  await h.tap(_listed(option));
}

/// Day [n] of the calendar the [i]th date field opens.
Future<void> _pickDay(DashHarness h, int i, String n) async {
  await h.tap(inSurface(find.byType(DashDateField)).at(i));
  await h.tap(find.text(n).hitTestable().last);
}

Future<void> _typeTime(DashHarness h, int i, String text) async {
  await h.enterText(
    find.descendant(
      of: inSurface(find.byType(DashTimeField)).at(i),
      matching: find.byType(EditableText),
    ),
    text,
  );
  await h.tester.testTextInput.receiveAction(TextInputAction.done);
  await h.settle();
}

int _posts(DashHarness h) => h.server.callsTo(listT, method: 'POST').length;

Future<DashHarness> _openNew(WidgetTester tester, {Srv? s}) async {
  final h = await pumpRequests(tester, s: s);
  await h.tap(pageText('New request'));
  return h;
}

String _d(DashHarness h, String iso) =>
    h.container.read(formatProvider).fmtDate(iso);

void main() {
  // ── approve with pay ────────────────────────────────────────────────────

  testWidgets('TEAM-REQ-020/023 leave: "Paid leave" starts on and is always '
      'sent; "Decision saved", the dialog closes', (tester) async {
    final h = await pumpRequests(tester);
    await h.tap(approveIn(_salma));
    expect(surfaceText('Approve request'), findsOneWidget);
    expect(
      surfaceText(
        'Salma Nabil · ${_d(h, '2026-10-12')} → ${_d(h, '2026-10-13')}',
      ),
      findsOneWidget,
    );
    expect(surfaceText(h.t('staff.paidLeaveSwitch')), findsOneWidget);
    expect(surfaceText(h.t('staff.paidLeaveHint')), findsOneWidget);
    expect(
      tester.widget<DashSwitch>(inSurface(find.byType(DashSwitch))).value,
      isTrue,
    );
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Approve')));
    expect(lastBody(h, decideT), {
      'status': 'approved',
      'is_paid': true,
      'note': null,
    });
    await h.expectToast(h.t('staff.decisionSaved'));
    expect(find.byType(ApproveWithPayDialog), findsNothing);
    expect(pageHas(_salma), findsNothing);
  });

  testWidgets('TEAM-REQ-020/023 a permission starts from the rule and sends '
      'no pay unless the switch is touched', (tester) async {
    final h = await pumpRequests(
      tester,
      edit: (db) => db[TeamTables.requests].insert(
        requestRow(
          id: 'rq-x',
          employeeKey: 'laila',
          kind: 'excuse',
          onDate: day(2),
          fromTime: '12:00:00',
          toTime: '13:00:00',
          reason: 'Bank errand',
          paidDefault: false,
        ),
      ),
    );
    await h.tap(approveIn('Bank errand'));
    expect(surfaceText(h.t('staff.paidTime')), findsOneWidget);
    expect(surfaceText(h.t('staff.paidTimeHint')), findsOneWidget);
    expect(surfaceText(h.t('staff.ruleSaysUnpaid')), findsOneWidget);
    expect(
      tester.widget<DashSwitch>(inSurface(find.byType(DashSwitch))).value,
      isFalse,
    );
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Approve')));
    expect(lastBody(h, decideT), {'status': 'approved', 'note': null});
    await h.flushTimers();

    await h.tap(approveIn(_farida));
    expect(surfaceText(h.t('staff.ruleSaysPaid')), findsNothing);
    await h.tap(inSurface(find.byType(DashSwitch)));
    await h.enterText(_box('Note'), 'Only this once');
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Approve')));
    expect(lastBody(h, decideT), {
      'status': 'approved',
      'is_paid': false,
      'note': 'Only this once',
    });
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-020 the dialog is the web\'s sm:max-w-md (448)', (
    tester,
  ) async {
    final h = await pumpRequests(tester);
    await h.tap(approveIn(_salma));
    expect(tester.getSize(find.byType(ApproveWithPayDialog)).width, 448);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });

  testWidgets('TEAM-REQ-020 closed mid-save: the list still reads again once '
      'the PATCH lands', (tester) async {
    final s = requestsServer();
    final gate = s.server.hold('PATCH', decideT);
    final h = await pumpRequests(tester, s: s);
    await h.tap(approveIn(_salma));
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Approve')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.byType(ApproveWithPayDialog), findsNothing);
    final lists = gets(h);
    gate.release();
    await h.settle();
    expect(patches(h), 1);
    expect(gets(h), lists + 1);
    expect(pageHas(_salma), findsNothing);
  });

  testWidgets('TEAM-REQ-020 a refresh that changes paid_default moves the '
      'switch until the approver touches it', (tester) async {
    final s = requestsServer(
      edit: (db) => db[TeamTables.requests].insert(
        requestRow(
          id: 'rq-x',
          employeeKey: 'laila',
          kind: 'excuse',
          onDate: day(2),
          fromTime: '12:00:00',
          toTime: '13:00:00',
          reason: 'Bank errand',
          paidDefault: false,
        ),
      ),
    );
    final h = await pumpRequests(tester, s: s);
    bool paid() =>
        tester.widget<DashSwitch>(inSurface(find.byType(DashSwitch))).value;
    Future<void> refresh() async {
      h.container.read(staffRevisionsProvider.notifier).invalidateStaff();
      await h.settle();
    }

    await h.tap(approveIn('Bank errand'));
    expect(paid(), isFalse);
    s.db[TeamTables.requests].update('rq-x', {'paid_default': true});
    await refresh();
    expect(paid(), isTrue, reason: 'untouched: follows the server');
    await h.tap(inSurface(find.byType(DashSwitch)));
    expect(paid(), isFalse);
    await refresh();
    expect(paid(), isFalse, reason: 'touched: the approver\'s choice stays');
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Approve')));
    expect(lastBody(h, decideT), {
      'status': 'approved',
      'is_paid': false,
      'note': null,
    });
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-021 leave over a day already worked says so', (
    tester,
  ) async {
    final h = await pumpRequests(
      tester,
      edit: (db) => db[TeamTables.requests].insert(
        requestRow(
          id: 'rq-w',
          employeeKey: 'laila',
          kind: 'leave',
          onDate: day(-2),
          endDate: day(-1),
          reason: 'Was sick',
          workedDates: [day(-2)],
        ),
      ),
    );
    await h.tap(approveIn('Was sick'));
    expect(
      surfaceText(
        h.t(
          'staff.leaveOverPunches',
          args: {'name': 'Laila Ehab', 'dates': _d(h, day(-2))},
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-REQ-022 a note too long says so; Cancel sends nothing', (
    tester,
  ) async {
    final h = await pumpRequests(tester);
    await h.tap(approveIn(_salma));
    await h.enterText(_box('Note'), 'x' * 501);
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Approve')));
    expect(surfaceText(h.t('staff.noteTooLong')), findsOneWidget);
    expect(patches(h), 0);
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Cancel')));
    expect(find.byType(ApproveWithPayDialog), findsNothing);
    expect(patches(h), 0);
  });

  // ── cancel ──────────────────────────────────────────────────────────────

  testWidgets('TEAM-REQ-031 cancel someone else\'s: "Why" is required; then '
      '"Request cancelled"', (tester) async {
    final h = await pumpRequests(tester);
    final id = requestOf(tester, _youssef).id;
    await h.tap(cancelIn(_youssef));
    expect(surfaceText(h.t('staff.cancelRequestTitle')), findsOneWidget);
    expect(
      surfaceText(
        'Youssef Samir · ${h.t('staff.windowLate', args: {'date': _d(h, day(1)), 'time': '08:30 AM'})}',
      ),
      findsOneWidget,
    );
    final confirm = inSurface(
      find.widgetWithText(DashButton, 'Cancel request'),
    );
    await h.tap(confirm);
    expect(surfaceText(h.t('staff.cancelNoteRequired')), findsOneWidget);
    expect(patches(h), 0);
    await h.enterText(_box('Why'), 'x' * 501);
    expect(surfaceText(h.t('staff.noteTooLong')), findsOneWidget);
    await h.enterText(_box('Why'), '  Shop closed that day  ');
    await h.tap(confirm);
    expect(lastBody(h, decideT), {
      'status': 'cancelled',
      'note': 'Shop closed that day',
    });
    expect(lastDecidePath(h), '/staff/requests/$id/decision');
    await h.expectToast(h.t('staff.requestCancelled'));
    expect(find.byType(CancelRequestDialog), findsNothing);
  });

  testWidgets('TEAM-REQ-031 one\'s own pending request goes without a reason; '
      'Back sends nothing', (tester) async {
    final h = await pumpRequests(
      tester,
      persona: Persona.manager,
      edit: (db) => db[TeamTables.requests].insert(
        requestRow(
          id: 'rq-own',
          employeeKey: 'karim',
          kind: 'late_arrival',
          onDate: day(2),
          toTime: '10:00:00',
          reason: 'Bank first',
        ),
      ),
    );
    await h.tap(cancelIn('Bank first'));
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Back')));
    expect(patches(h), 0);
    await h.tap(cancelIn('Bank first'));
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Cancel request')));
    expect(lastBody(h, decideT), {'status': 'cancelled', 'note': null});
    expect(lastDecidePath(h), '/staff/requests/rq-own/decision');
    await h.expectToast(h.t('staff.requestCancelled'));
  });

  testWidgets('TEAM-REQ-031/TEAM-ALL-019 an approved request\'s cancel the '
      'server refuses for want of a reason: its own words', (tester) async {
    final s = requestsServer();
    final h = await pumpRequests(tester, s: s);
    await h.tap(pageText('Approved'));
    s.server.fail(
      'PATCH',
      decideT,
      MockResponse.error(
        400,
        'Say why this approved request is cancelled',
        code: 'CANCEL_REASON_REQUIRED',
        vars: {'status': 'approved'},
      ),
    );
    await h.tap(cancelIn('Family visit in Tanta'));
    await h.enterText(_box('Why'), 'Changed');
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Cancel request')));
    expect(
      find.text(h.t('errors.codes.CANCEL_REASON_REQUIRED_approved')),
      findsWidgets,
    );
    expect(find.byType(CancelRequestDialog), findsOneWidget);
    await h.flushTimers();
  });

  // ── new request ─────────────────────────────────────────────────────────

  testWidgets('TEAM-REQ-040/041/042 New request: filed as pending, a late '
      'arrival today by 14:00; five kinds; Save waits for a person', (
    tester,
  ) async {
    final h = await _openNew(tester);
    expect(surfaceText('New request'), findsOneWidget);
    expect(surfaceText(h.t('staff.newRequestHint')), findsOneWidget);
    expect(
      h.server
          .callsTo(employeesT)
          .any((c) => c.query['employment_status']?.single == 'active'),
      isTrue,
    );
    expect(surfaceText('Late arrival'), findsOneWidget);
    expect(surfaceText('Arriving by'), findsOneWidget);
    expect(
      tester.widget<DashTimeField>(inSurface(find.byType(DashTimeField))).value,
      '14:00',
    );
    expect(
      tester.widget<DashDateField>(inSurface(find.byType(DashDateField))).value,
      DateTime.parse(day()),
    );
    expect(tester.widget<DashButton>(_save()).onPressed, isNull);
    await h.tap(surfaceText('Late arrival'));
    for (final k in [
      'Leave',
      'Late arrival',
      'Early departure',
      'Permission',
      'Mission',
    ]) {
      expect(_listed(k), findsOneWidget, reason: k);
    }
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w.runtimeType.toString().startsWith('DashOptionList'),
        ),
        matching: find.text('Correction'),
      ),
      findsNothing,
    );
    await h.tap(_listed('Late arrival'));
    await _pick(h, 'Pick an employee', 'Laila Ehab');
    expect(tester.widget<DashButton>(_save()).onPressed, isNotNull);
  });

  testWidgets('TEAM-REQ-043 leave: half a day picks its half; one\'s own '
      'leave approved as filed asks paid or unpaid', (tester) async {
    final h = await _openNew(tester);
    await _pick(h, 'Late arrival', 'Leave');
    await _pick(h, 'Pick an employee', 'Nour El-Sayed');
    expect(surfaceText(h.t('staff.leavePayQuestion')), findsOneWidget);
    await h.tap(inSurface(find.byType(DashSwitch)));
    await h.tap(surfaceText('Second half'));
    await h.tap(_save());
    expect(surfaceText(h.t('staff.payChoiceNeeded')), findsOneWidget);
    expect(_posts(h), 0);
    await h.tap(surfaceText('Unpaid'));
    expect(surfaceText(h.t('staff.payChoiceNeeded')), findsNothing);
    await h.tap(_save());
    expect(lastBody(h, listT, 'POST'), {
      'employee_id': emp('nour'),
      'kind': 'leave',
      'on_date': day(),
      'end_date': null,
      'from_time': null,
      'to_time': null,
      'is_half_day': true,
      'leave_half': 'second',
      'is_paid': false,
      'title': null,
      'reason': null,
    });
    await h.expectToast(h.t('staff.requestFiledApproved'));
    expect(find.byType(NewRequestDialog), findsNothing);
  });

  testWidgets('TEAM-REQ-043 someone else\'s leave: no pay question (their '
      'approver chooses)', (tester) async {
    final h = await _openNew(tester);
    await _pick(h, 'Late arrival', 'Leave');
    await _pick(h, 'Pick an employee', 'Laila Ehab');
    expect(surfaceText(h.t('staff.leavePayQuestion')), findsNothing);
    await h.tap(_save());
    expect(lastBody(h, listT, 'POST'), isNot(contains('is_paid')));
    await h.expectToast(h.t('staff.requestFiled'));
  });

  testWidgets('TEAM-REQ-044 a mission needs a title or a note; a title of '
      'over 200 says so', (tester) async {
    final h = await _openNew(tester);
    await _pick(h, 'Late arrival', 'Mission');
    await _pick(h, 'Pick an employee', 'Laila Ehab');
    await h.tap(_save());
    expect(surfaceText(h.t('staff.missionNeedsText')), findsOneWidget);
    await h.enterText(_box('Title (optional)'), 'x' * 201);
    expect(surfaceText(h.t('staff.titleTooLong')), findsOneWidget);
    await h.enterText(_box('Title (optional)'), '');
    await h.enterText(_box('Reason'), 'At the roastery');
    await h.tap(_save());
    final body = lastBody(h, listT, 'POST');
    expect(
      (body['title'], body['reason'], body['end_date']),
      (null, 'At the roastery', day()),
    );
    await h.expectToast(h.t('staff.requestFiled'));
  });

  testWidgets('TEAM-REQ-045 span kinds show From and To; To follows From until '
      'set by hand and never sits before it', (tester) async {
    // ponytail: the kit's calendar popover overflows when 220–360 px are
    // left under its field (kit candidate); a taller window keeps it whole.
    final h = await _openNew(tester);
    tester.view.physicalSize = const Size(1440, 1400) * DashSize.pixelRatio;
    await h.settle();
    expect(surfaceText('Date'), findsOneWidget);
    await _pick(h, 'Late arrival', 'Leave');
    expect(surfaceText('From'), findsOneWidget);
    expect(surfaceText('To'), findsOneWidget);
    DateTime? end() => tester
        .widget<DashDateField>(inSurface(find.byType(DashDateField)).at(1))
        .value;
    await _pickDay(h, 0, '12');
    expect(end(), DateTime(2026, 10, 12));
    await _pickDay(h, 1, '14');
    await _pickDay(h, 0, '13');
    expect(end(), DateTime(2026, 10, 14), reason: 'set by hand: it stays');
    await _pickDay(h, 0, '16');
    expect(end(), DateTime(2026, 10, 16), reason: 'never before From');
    await _pickDay(h, 1, '10');
    await _pick(h, 'Pick an employee', 'Laila Ehab');
    await h.tap(_save());
    expect(surfaceText(h.t('staff.endBeforeStart')), findsOneWidget);
    expect(_posts(h), 0);
  });

  testWidgets('TEAM-REQ-046 times by kind; a time cleared says "Pick a time"; '
      'a permission past midnight is explained', (tester) async {
    final h = await _openNew(tester);
    await _pick(h, 'Late arrival', 'Early departure');
    expect(surfaceText('Leaving at'), findsOneWidget);
    await _pick(h, 'Early departure', 'Permission');
    expect(surfaceText('From'), findsOneWidget);
    expect(surfaceText('To'), findsOneWidget);
    expect(surfaceText(h.t('staff.excuseMidnightHint')), findsOneWidget);
    await _pick(h, 'Pick an employee', 'Laila Ehab');
    await _typeTime(h, 1, '');
    await h.tap(_save());
    expect(surfaceText(h.t('staff.timeNeeded')), findsOneWidget);
    expect(_posts(h), 0);
    await _typeTime(h, 1, '1:30 AM');
    await h.tap(_save());
    final body = lastBody(h, listT, 'POST');
    expect((body['from_time'], body['to_time']), ('12:00:00', '01:30:00'));
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-047 a reason over 500 says so', (tester) async {
    final h = await _openNew(tester);
    await _pick(h, 'Pick an employee', 'Laila Ehab');
    await h.enterText(_box('Reason'), 'x' * 501);
    await h.tap(_save());
    expect(surfaceText(h.t('staff.reasonTooLong')), findsOneWidget);
    expect(_posts(h), 0);
  });

  testWidgets('TEAM-REQ-048 a late arrival filed: the web\'s body, "Request '
      'filed", the list reads again', (tester) async {
    final h = await _openNew(tester);
    final lists = gets(h);
    await _pick(h, 'Pick an employee', 'Laila Ehab');
    await h.enterText(_box('Reason'), ' Bank appointment ');
    await h.tap(_save());
    expect(lastBody(h, listT, 'POST'), {
      'employee_id': emp('laila'),
      'kind': 'late_arrival',
      'on_date': day(),
      'end_date': null,
      'from_time': null,
      'to_time': '14:00:00',
      'title': null,
      'reason': 'Bank appointment',
    });
    await h.expectToast(h.t('staff.requestFiled'));
    expect(find.byType(NewRequestDialog), findsNothing);
    expect(gets(h), lists + 1);
    expect(pageHas('Bank appointment'), findsOneWidget);
  });

  testWidgets('TEAM-REQ-048 refused: the server\'s words, the form stays', (
    tester,
  ) async {
    final s = requestsServer();
    final refusal = MockResponse.error(
      409,
      'You already have a request like this for that time.',
      code: 'OVERLAPPING_REQUEST',
    );
    s.server.fail('POST', listT, refusal);
    final h = await _openNew(tester, s: s);
    await _pick(h, 'Pick an employee', 'Laila Ehab');
    await h.tap(_save());
    expect(find.text(h.t('errors.codes.OVERLAPPING_REQUEST')), findsWidgets);
    expect(find.byType(NewRequestDialog), findsOneWidget);
    await h.flushTimers();
  });
}
