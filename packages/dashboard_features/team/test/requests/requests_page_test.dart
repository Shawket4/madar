// Driven tests of the Requests inbox (`/staff/requests`): one per
// TEAM-REQ row of the list and its decisions, plus the area-wide TEAM-ALL
// rows the page carries. The forms are in requests_dialogs_test.dart.
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/approvals/approvals_dialogs.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/requests/requests_page.dart';
import 'package:dashboard_team/src/requests/requests_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'requests_support.dart';

const String _youssef = 'Renewing my national ID';
const String _salma = "My sister's wedding";
const String _farida = "Doctor's appointment.";

Finder _inSidebar(String text) =>
    find.descendant(of: find.byType(DashSidebar), matching: find.text(text));

Finder _listed(String option) => find
    .descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('DashOptionList'),
      ),
      matching: find.text(option),
    )
    .last;

List<StaffRequest> _shown(WidgetTester tester) => [
  for (final r in tester.widgetList<RequestRow>(
    inPage(find.byType(RequestRow)),
  ))
    r.request,
];

MockResponse _stale() => MockResponse.error(
  409,
  'This request was already decided: approved',
  code: 'REQUEST_ALREADY_DECIDED',
  vars: {'status': 'approved'},
);

void main() {
  // ── header and filters ──────────────────────────────────────────────────

  testWidgets('TEAM-REQ-001 header: title, what approving does, Refresh and '
      'New request', (tester) async {
    final h = await pumpRequests(tester);
    expect(pageText('Requests'), findsWidgets);
    expect(pageText(h.t('staff.requestsSubtitle')), findsOneWidget);
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(pageText('New request'), findsOneWidget);
  });

  testWidgets('TEAM-REQ-001 refusal: New request only with hr.leave.create', (
    tester,
  ) async {
    final h = await pumpRequests(tester, persona: Persona.manager);
    expect(rowCount(), greaterThan(0));
    expect(pageText('New request'), findsNothing);
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(h.server.callsTo('/staff/requests', method: 'POST'), isEmpty);
  });

  testWidgets('TEAM-REQ-002 status: Pending first, then each status and All', (
    tester,
  ) async {
    final h = await pumpRequests(tester);
    expect(lastQuery(h), {
      'status': ['pending'],
    });
    expect(_shown(tester).map((r) => r.status).toSet(), {'pending'});
    await h.tap(pageText('Approved'));
    expect(lastQuery(h), {
      'status': ['approved'],
    });
    expect(_shown(tester).map((r) => r.status).toSet(), {'approved'});
    await h.tap(pageText('Cancelled'));
    expect(_shown(tester).map((r) => r.status).toSet(), {'cancelled'});
    await h.tap(pageText(h.t('dawam.all')));
    expect(lastQuery(h), isEmpty);
    expect(
      _shown(tester).map((r) => r.status).toSet(),
      containsAll(['pending', 'approved', 'rejected', 'cancelled']),
    );
  });

  testWidgets('TEAM-REQ-003 kind: every kind, Correction included', (
    tester,
  ) async {
    final h = await pumpRequests(tester);
    await h.tap(pageText('All kinds'));
    for (final k in [
      'Leave',
      'Late arrival',
      'Early departure',
      'Permission',
      'Mission',
      'Correction',
    ]) {
      expect(_listed(k), findsOneWidget, reason: k);
    }
    await h.tap(_listed('Mission'));
    expect(lastQuery(h), {
      'kind': ['mission'],
      'status': ['pending'],
    });
    expect(_shown(tester).map((r) => r.kind).toSet(), {'mission'});
  });

  // ── states ──────────────────────────────────────────────────────────────

  testWidgets('TEAM-REQ-004 loading: four skeleton rows, never "nothing"', (
    tester,
  ) async {
    final s = requestsServer();
    final gate = s.server.hold('GET', listT);
    final h = await pumpRequests(tester, s: s);
    expect(inPage(find.byType(RequestsSkeleton)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RequestsSkeleton),
        matching: find.byType(DashSkeleton),
      ),
      findsNWidgets(12),
    );
    expect(pageText(h.t('dawamOps.noPendingTitle')), findsNothing);
    gate.release();
    await h.settle();
    expect(inPage(find.byType(RequestsSkeleton)), findsNothing);
    expect(rowCount(), greaterThan(0));
  });

  testWidgets('TEAM-REQ-005 error: what failed, why, and Retry asks again', (
    tester,
  ) async {
    final s = requestsServer();
    final boom = MockResponse.error(500, 'The database is busy');
    s.server.fail('GET', listT, boom, times: null);
    final h = await pumpRequests(tester, s: s);
    expect(pageText(h.t('staff.requestsLoadError')), findsOneWidget);
    expect(pageHas(h.refusalWords(boom)), findsOneWidget);
    expect(rowCount(), 0);
    final before = gets(h);
    s.server.clearFailures();
    await h.tap(inPage(find.text('Retry')));
    expect(gets(h), before + 1);
    expect(rowCount(), greaterThan(0));
  });

  testWidgets('TEAM-REQ-006 nothing pending: "Nothing is waiting", not "no '
      'match"', (tester) async {
    final h = await pumpRequests(
      tester,
      edit: (db) =>
          db[TeamTables.requests].removeWhere((r) => r['status'] == 'pending'),
    );
    expect(pageText(h.t('dawamOps.noPendingTitle')), findsOneWidget);
    expect(pageText(h.t('dawamOps.noPendingHint')), findsOneWidget);
    expect(pageText(h.t('staff.noRequestsTitle')), findsNothing);
  });

  testWidgets('TEAM-REQ-007 no match: says so, and "Show what\'s pending" '
      'resets both filters', (tester) async {
    final h = await pumpRequests(tester);
    await h.tap(pageText('Rejected'));
    await h.tap(pageText('All kinds'));
    await h.tap(_listed('Correction'));
    expect(pageText(h.t('staff.noRequestsTitle')), findsOneWidget);
    expect(pageText(h.t('staff.noRequestsHint')), findsOneWidget);
    await h.tap(pageText(h.t('dawamOps.showPending')));
    expect(pageText('All kinds'), findsOneWidget);
    expect(_shown(tester).map((r) => r.status).toSet(), {'pending'});
    expect(_shown(tester).map((r) => r.kind).toSet().length, greaterThan(1));
  });

  // ── rows ────────────────────────────────────────────────────────────────

  testWidgets('TEAM-REQ-010 a row: the kind\'s glyph, name, kind and the '
      'status pill in its tone', (tester) async {
    final h = await pumpRequests(tester);
    expect(inRow(_youssef, find.text('Youssef Samir')), findsOneWidget);
    expect(inRow(_youssef, find.text('Late arrival')), findsOneWidget);
    expect(
      inRow(
        _youssef,
        find.byWidgetPredicate((w) => w is DashIcon && w.name == 'timer'),
      ),
      findsOneWidget,
    );
    final pill = tester.widget<DashStatusPill>(
      inRow(_youssef, find.byType(DashStatusPill)),
    );
    expect((pill.label, pill.tone), ('Pending', DashTone.warning));
    expect(
      inRow(
        _salma,
        find.byWidgetPredicate(
          (w) => w is DashIcon && w.name == 'calendar-off',
        ),
      ),
      findsOneWidget,
    );
    await h.tap(pageText(h.t('dawam.all')));
    for (final (text, label, tone) in [
      ('Family visit in Tanta', 'Approved', DashTone.success),
      ('Football match', 'Rejected', DashTone.danger),
      ('Moving flats', 'Cancelled', DashTone.neutral),
    ]) {
      final p = tester.widget<DashStatusPill>(
        inRow(text, find.byType(DashStatusPill)),
      );
      expect((p.label, p.tone), (label, tone), reason: text);
    }
  });

  testWidgets('TEAM-REQ-011 meta: window, title, reason, who decided and '
      'their note, who cancelled and why', (tester) async {
    final h = await pumpRequests(
      tester,
      edit: (db) => db[TeamTables.requests].insertAll([
        requestRow(
          id: 'rq-cx',
          employeeKey: 'laila',
          kind: 'leave',
          onDate: day(9),
          status: 'cancelled',
          reason: 'Trip off',
          decidedByName: 'Nour El-Sayed',
          decisionNote: 'Enjoy',
          cancelledBy: SeedIds.user('laila'),
          cancelNote: 'Plans changed',
        ),
        requestRow(
          id: 'rq-cy',
          employeeKey: 'ali',
          kind: 'leave',
          onDate: day(10),
          status: 'cancelled',
          reason: 'Visit gone',
          cancelledBy: SeedIds.user('nobody'),
          cancelNote: 'No longer needed',
        ),
      ]),
    );
    await h.tap(pageText(h.t('dawam.all')));
    final f = h.container.read(formatProvider);
    String metaOf(String text) => tester
        .widgetList<Text>(inRow(text, find.byType(Text)))
        .map((w) => (w.data ?? '').replaceAll(RegExp('[\u2068\u2069]'), ''))
        .firstWhere((s) => s.contains(text));
    expect(
      metaOf('Family visit in Tanta'),
      contains('Decided by Nour El-Sayed'),
    );
    expect(
      metaOf('Football match'),
      endsWith(
        'Decided by Nour El-Sayed · Two of us are already off that afternoon.',
      ),
    );
    // The server names the canceller; else the employee linked to them.
    expect(metaOf('Moving flats'), endsWith('Cancelled by Ziad Amr'));
    expect(
      metaOf('Trip off'),
      '${f.fmtDate(day(9))} · Trip off · Decided by Nour El-Sayed · Enjoy · '
      'Cancelled by Laila Ehab: Plans changed',
    );
    expect(
      metaOf('Visit gone'),
      endsWith('Visit gone · Cancelled: No longer needed'),
    );
    // A mission's title says what it is.
    await h.tap(pageText('Pending'));
    expect(
      metaOf('Choosing next month'),
      contains('Supplier visit · Choosing'),
    );
  });

  testWidgets('TEAM-REQ-012 badges: unpaid, the half of a half day, yours, '
      'for the owner, a closed month', (tester) async {
    final h = await pumpRequests(
      tester,
      persona: Persona.manager,
      edit: (db) => db[TeamTables.requests].insertAll([
        requestRow(
          id: 'rq-u',
          employeeKey: 'laila',
          kind: 'excuse',
          onDate: day(2),
          fromTime: '12:00:00',
          toTime: '13:00:00',
          reason: 'Unpaid hour',
          isPaid: false,
        ),
        requestRow(
          id: 'rq-h1',
          employeeKey: 'laila',
          kind: 'leave',
          onDate: day(3),
          isHalfDay: true,
          leaveHalf: 'first',
          reason: 'Morning off',
        ),
        requestRow(
          id: 'rq-h2',
          employeeKey: 'adham',
          kind: 'leave',
          onDate: day(3),
          isHalfDay: true,
          leaveHalf: 'second',
          reason: 'Afternoon off',
        ),
        requestRow(
          id: 'rq-h0',
          employeeKey: 'mariam',
          kind: 'leave',
          onDate: day(3),
          isHalfDay: true,
          reason: 'Some half',
        ),
        requestRow(
          id: 'rq-own',
          employeeKey: 'karim',
          kind: 'late_arrival',
          onDate: day(1),
          toTime: '10:00:00',
          reason: 'Bank first',
        ),
        requestRow(
          id: 'rq-old',
          employeeKey: 'laila',
          kind: 'late_arrival',
          onDate: '2026-09-20',
          toTime: '10:00:00',
          reason: 'Old late note',
        ),
      ]),
    );
    expect(inRow('Unpaid hour', find.text('unpaid')), findsOneWidget);
    expect(
      inRow('Morning off', find.text(h.t('staff.halfFirst'))),
      findsOneWidget,
    );
    expect(
      inRow('Afternoon off', find.text(h.t('staff.halfSecond'))),
      findsOneWidget,
    );
    expect(
      inRow('Some half', find.text(h.t('staff.halfDayUnsaid'))),
      findsOneWidget,
    );
    expect(
      inRow('Bank first', find.text(h.t('staff.yourRequest'))),
      findsOneWidget,
    );
    expect(
      inRow('Bank first', find.text(h.t('staff.toOwner'))),
      findsOneWidget,
    );
    expect(
      inRow('Old late note', find.text(h.t('staff.monthClosedRejectOnly'))),
      findsOneWidget,
    );
    expect(inRow(_youssef, find.text(h.t('staff.yourRequest'))), findsNothing);
  });

  testWidgets('TEAM-REQ-013 the window, kind by kind; times on the 12-hour '
      'clock; a correction says a time it already set once', (tester) async {
    final h = await pumpRequests(
      tester,
      edit: (db) => db[TeamTables.requests].insertAll([
        requestRow(
          id: 'rq-e',
          employeeKey: 'laila',
          kind: 'early_departure',
          onDate: day(2),
          fromTime: '16:30:00',
          reason: 'Leaving early',
        ),
        requestRow(
          id: 'rq-c',
          employeeKey: 'ali',
          kind: 'correction',
          onDate: day(-1),
          fromTime: '09:00:00',
          toTime: '17:45:00',
          reason: 'Forgot to punch',
          recordCheckInAt: DateTime.utc(2026, 10, 7, 6, 12),
          recordCheckOutAt: DateTime.utc(2026, 10, 7, 14, 45),
        ),
        requestRow(
          id: 'rq-hd',
          employeeKey: 'adham',
          kind: 'leave',
          onDate: day(4),
          isHalfDay: true,
          leaveHalf: 'first',
          reason: 'Half off',
        ),
      ]),
    );
    expect(
      pageHas(
        '${h.t('staff.windowLate', args: {'date': _d(h, day(1)), 'time': '08:30 AM'})} · ',
      ),
      findsOneWidget,
    );
    expect(pageHas('· leaving at 04:30 PM ·'), findsOneWidget);
    expect(pageHas('· 12:00 PM–01:00 PM ·'), findsOneWidget);
    // 09:12 → 09:00 changes; 17:45 is already the punch: said once.
    expect(
      pageHas('· in 09:12 AM → 09:00 AM · out 05:45 PM ·'),
      findsOneWidget,
    );
    expect(pageHas('${_d(h, day(4))} · half day'), findsOneWidget);
    expect(
      pageHas('${_d(h, '2026-10-12')} → ${_d(h, '2026-10-13')}'),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-REQ-014 a decision only where the server allows it; '
      'never a manager\'s own', (tester) async {
    final h = await pumpRequests(
      tester,
      persona: Persona.manager,
      edit: (db) => db[TeamTables.requests].insertAll([
        requestRow(
          id: 'rq-no',
          employeeKey: 'laila',
          kind: 'late_arrival',
          onDate: day(1),
          toTime: '10:00:00',
          reason: 'Not mine to decide',
          canDecide: false,
        ),
        requestRow(
          id: 'rq-own',
          employeeKey: 'karim',
          kind: 'late_arrival',
          onDate: day(2),
          toTime: '10:00:00',
          reason: 'My own request',
        ),
      ]),
    );
    for (final text in ['Not mine to decide', 'My own request']) {
      expect(approveIn(text), findsNothing, reason: text);
      expect(rejectIn(text), findsNothing, reason: text);
    }
    expect(approveIn(_youssef), findsOneWidget);
    expect(rejectIn(_youssef), findsOneWidget);
    expect(h.server.callsTo(listT).last.status, 200);
  });

  testWidgets('TEAM-REQ-015 what approving means, under a decidable row', (
    tester,
  ) async {
    final h = await pumpRequests(
      tester,
      edit: (db) => db[TeamTables.requests].insert(
        requestRow(
          id: 'rq-old',
          employeeKey: 'laila',
          kind: 'late_arrival',
          onDate: '2026-09-20',
          toTime: '10:00:00',
          reason: 'Old late note',
        ),
      ),
    );
    expect(
      inRow(
        _youssef,
        find.text(h.t('dawamOps.meansLate', args: {'time': '08:30 AM'})),
      ),
      findsOneWidget,
    );
    expect(
      inRow(_salma, find.text(h.t('dawamOps.meansLeave'))),
      findsOneWidget,
    );
    expect(
      inRow(_farida, find.text(h.t('dawamOps.meansExcuse'))),
      findsOneWidget,
    );
    expect(
      inRow('Choosing next month', find.text(h.t('dawamOps.meansMission'))),
      findsOneWidget,
    );
    // A closed month offers Reject only, so approving is not explained.
    expect(
      inRow('Old late note', find.textContaining('Approving:')),
      findsNothing,
    );
  });

  // ── decisions ───────────────────────────────────────────────────────────

  testWidgets('TEAM-REQ-016/TEAM-ALL-026 approve a late arrival in one '
      'click: "Decision saved", everything under /staff read again', (
    tester,
  ) async {
    final h = await pumpRequests(tester);
    final lists = gets(h);
    final people = gets(h, employeesT);
    await h.tap(approveIn(_youssef));
    expect(lastBody(h, decideT), {'status': 'approved'});
    await h.expectToast(h.t('staff.decisionSaved'));
    expect(gets(h), lists + 1);
    expect(gets(h, employeesT), greaterThan(people));
    expect(pageHas(_youssef), findsNothing);
  });

  testWidgets('TEAM-REQ-016 a double tap sends once: the row\'s buttons wait', (
    tester,
  ) async {
    final s = requestsServer();
    final h = await pumpRequests(tester, s: s);
    final gate = s.server.hold('PATCH', decideT);
    await h.tap(approveIn(_youssef));
    expect(tester.widget<DashButton>(approveIn(_youssef)).onPressed, isNull);
    expect(tester.widget<DashIconButton>(rejectIn(_youssef)).onPressed, isNull);
    await h.tap(approveIn(_youssef));
    gate.release();
    await h.settle();
    expect(patches(h), 1);
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-016/TEAM-ALL-015 decided by someone else first: the '
      'words, and the list reads again', (tester) async {
    final s = requestsServer();
    final h = await pumpRequests(tester, s: s);
    final lists = gets(h);
    s.server.fail('PATCH', decideT, _stale());
    await h.tap(approveIn(_youssef));
    expect(find.textContaining('already decided'), findsWidgets);
    expect(gets(h), lists + 1);
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-017 approving leave, a permission or an early '
      'departure asks the pay question first', (tester) async {
    final h = await pumpRequests(
      tester,
      edit: (db) => db[TeamTables.requests].insert(
        requestRow(
          id: 'rq-e',
          employeeKey: 'laila',
          kind: 'early_departure',
          onDate: day(2),
          fromTime: '16:30:00',
          reason: 'Leaving early',
        ),
      ),
    );
    for (final text in [_salma, _farida, 'Leaving early']) {
      await h.tap(approveIn(text));
      expect(find.byType(ApproveWithPayDialog), findsOneWidget, reason: text);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
    }
    expect(patches(h), 0);
  });

  testWidgets('TEAM-REQ-018 reject: its own warning, an optional reason sent '
      'as the note (empty → null)', (tester) async {
    final h = await pumpRequests(tester);
    await h.tap(rejectIn(_youssef));
    expect(
      surfaceText(
        h.t('staff.rejectRequestTitle', args: {'name': 'Youssef Samir'}),
      ),
      findsOneWidget,
    );
    expect(surfaceText(h.t('staff.rejectRequestHint')), findsOneWidget);
    await h.tap(inSurface(find.text('Reject')).last);
    expect(lastBody(h, decideT), {'status': 'rejected', 'note': null});
    await h.expectToast(h.t('staff.decisionSaved'));
    expect(find.byType(RejectReasonDialog), findsNothing);

    await h.tap(rejectIn(_farida));
    await h.enterText(
      inSurface(find.byType(EditableText)),
      'Too busy that day',
    );
    await h.tap(inSurface(find.text('Reject')).last);
    expect(lastBody(h, decideT), {
      'status': 'rejected',
      'note': 'Too busy that day',
    });
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-018 a stale reject: the words, the list reads again, '
      'the dialog stays', (tester) async {
    final s = requestsServer();
    final h = await pumpRequests(tester, s: s);
    final lists = gets(h);
    s.server.fail('PATCH', decideT, _stale());
    await h.tap(rejectIn(_youssef));
    await h.tap(inSurface(find.text('Reject')).last);
    expect(find.textContaining('already decided'), findsWidgets);
    expect(find.byType(RejectReasonDialog), findsOneWidget);
    expect(gets(h), lists + 1);
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-024 a mission over worked days warns first; backing '
      'out sends nothing; none worked approves in one click', (tester) async {
    final h = await pumpRequests(
      tester,
      edit: (db) => db[TeamTables.requests].insertAll([
        requestRow(
          id: 'rq-m1',
          employeeKey: 'laila',
          kind: 'mission',
          onDate: day(-2),
          title: 'Roastery visit',
          reason: 'Tasting day',
          workedDates: [day(-2)],
        ),
        requestRow(
          id: 'rq-m2',
          employeeKey: 'ali',
          kind: 'mission',
          onDate: day(3),
          title: 'Expo',
          reason: 'Cairo coffee expo',
          workedDates: const [],
        ),
      ]),
    );
    await h.tap(approveIn('Tasting day'));
    expect(
      inConfirm(
        find.text(
          h.t('staff.missionOverPunchesTitle', args: {'name': 'Laila Ehab'}),
        ),
      ),
      findsOneWidget,
    );
    expect(inConfirm(find.textContaining(_d(h, day(-2)))), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(patches(h), 0);
    await h.tap(approveIn('Tasting day'));
    await h.tap(inConfirm(find.text('Approve')));
    expect(lastBody(h, decideT), {'status': 'approved'});
    await h.flushTimers();
    final reads = gets(h, attendanceT);
    await h.tap(approveIn('Cairo coffee expo'));
    expect(confirmCard(), findsNothing);
    expect(patches(h), 2);
    expect(gets(h, attendanceT), reads, reason: 'the server named the days');
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-024 an older server names no days: the mission\'s '
      'attendance is read first', (tester) async {
    final h = await pumpRequests(tester);
    final tarek = requestOf(tester, 'Choosing next month');
    await h.tap(approveIn('Choosing next month'));
    final read = h.server.callsTo(attendanceT).last.query;
    expect(read, {
      'employee_id': [tarek.employeeId],
      'from': [tarek.onDate],
      'to': [tarek.endDate ?? tarek.onDate],
    });
    if (confirmCard().evaluate().isNotEmpty) {
      await h.tap(inConfirm(find.text('Approve')));
    }
    expect(lastBody(h, decideT), {'status': 'approved'});
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-030 Cancel offered on pending and approved, never on '
      'an approved correction or approved time in a closed month', (
    tester,
  ) async {
    final h = await pumpRequests(
      tester,
      edit: (db) => db[TeamTables.requests].insertAll([
        requestRow(
          id: 'rq-ac',
          employeeKey: 'ali',
          kind: 'correction',
          onDate: day(-1),
          fromTime: '09:00:00',
          status: 'approved',
          reason: 'Punch fixed',
        ),
        requestRow(
          id: 'rq-aold',
          employeeKey: 'ali',
          kind: 'late_arrival',
          onDate: '2026-09-15',
          toTime: '10:00:00',
          status: 'approved',
          reason: 'Old approved',
        ),
      ]),
    );
    expect(cancelIn(_youssef), findsOneWidget);
    await h.tap(pageText(h.t('dawam.all')));
    expect(cancelIn('Family visit in Tanta'), findsOneWidget);
    expect(cancelIn('Punch fixed'), findsNothing);
    expect(cancelIn('Old approved'), findsNothing);
    expect(cancelIn('Football match'), findsNothing);
    expect(cancelIn('Moving flats'), findsNothing);
  });

  testWidgets('TEAM-REQ-049 a closed month refused reads in Arabic', (
    tester,
  ) async {
    final s = requestsServer();
    final h = await pumpRequests(tester, s: s, locale: 'ar');
    s.server.fail(
      'PATCH',
      decideT,
      MockResponse.error(
        409,
        "That month's payroll is approved",
        code: 'PERIOD_CLOSED',
        vars: {'date': day(1), 'paid': false},
      ),
    );
    await h.tap(approveIn(_youssef));
    expect(find.text(h.t('errors.codes.PERIOD_CLOSED')), findsWidgets);
    expect(find.textContaining("payroll is approved"), findsNothing);
    await h.flushTimers();
  });

  testWidgets('TEAM-REQ-050 phone: the words keep the width, the pill and '
      'buttons sit under them', (tester) async {
    await pumpRequests(tester, size: DashSize.phone);
    final name = tester.getRect(inRow(_youssef, find.text('Youssef Samir')));
    final approve = tester.getRect(approveIn(_youssef));
    final pill = tester.getRect(inRow(_youssef, find.byType(DashStatusPill)));
    expect(approve.top, greaterThan(name.bottom));
    expect(pill.top, greaterThan(name.bottom));
    await pumpRequests(tester, size: DashSize.tablet);
    final n2 = tester.getRect(inRow(_youssef, find.text('Youssef Samir')));
    final a2 = tester.getRect(approveIn(_youssef));
    expect(a2.left, greaterThan(n2.right));
  });

  // ── area-wide ───────────────────────────────────────────────────────────

  testWidgets('TEAM-ALL-001/002 the Requests leaf shows with hr.leave.read, '
      'hidden without', (tester) async {
    final h = await pumpRequests(tester);
    expect(_inSidebar('Requests'), findsOneWidget);
    final s = requestsServer();
    answerAuthz(s.server, const ['hr.attendance.read']);
    await pumpRequests(tester, s: s);
    expect(_inSidebar('Requests'), findsNothing);
    expect(h.location.path, requestsPath);
  });

  testWidgets('TEAM-ALL-005 module off: the module refusal, nothing asked', (
    tester,
  ) async {
    final s = requestsServer(
      edit: (db) => db['orgs'].update(SeedIds.sabahOrg, {
        'modules': ['pos'],
      }),
    );
    final h = await pumpRequests(tester, s: s);
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(page, findsNothing);
    expect(h.server.callsTo(listT), isEmpty);
  });

  testWidgets('TEAM-ALL-007/014 no in-page guard: without hr.leave.read the '
      'list says the refusal in the reader\'s words', (tester) async {
    final h = await pumpRequests(tester, persona: Persona.limited);
    expect(pageText('Requests'), findsWidgets);
    expect(pageText(h.t('staff.requestsLoadError')), findsOneWidget);
    expect(pageText(h.t('errors.unauthorized')), findsOneWidget);
    expect(h.server.callsTo(listT).last.status, 403);
    expect(pageText('New request'), findsNothing);
  });

  testWidgets('TEAM-ALL-008 Refresh asks again what the page shows, and '
      'spins while it does', (tester) async {
    final s = requestsServer();
    final h = await pumpRequests(tester, s: s);
    final lists = gets(h);
    final people = gets(h, employeesT);
    final gate = s.server.hold('GET', listT);
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(inPage(find.bySemanticsLabel('Refreshing…')), findsOneWidget);
    gate.release();
    await h.settle();
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(gets(h), lists + 1);
    expect(gets(h, employeesT), greaterThan(people));
  });

  testWidgets('TEAM-ALL-009 back to the app after 30 s reads again; sooner '
      'does not', (tester) async {
    final h = await pumpRequests(tester);
    final before = gets(h);
    void resume() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    h.server.clock.advance(const Duration(seconds: 10));
    resume();
    await h.settle();
    expect(gets(h), before);
    h.server.clock.advance(const Duration(seconds: 30));
    resume();
    await h.settle();
    expect(gets(h), before + 1);
  });

  testWidgets('TEAM-ALL-010/022 a failed refresh keeps the rows and says so '
      'once', (tester) async {
    final s = requestsServer();
    final h = await pumpRequests(tester, s: s);
    s.server.fail(
      'GET',
      listT,
      MockResponse.error(429, 'Too many requests'),
      times: null,
    );
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(rowOf(_youssef), findsOneWidget);
    expect(pageText(h.t('staff.requestsLoadError')), findsNothing);
    await h.expectToast(h.t('errors.tooManyRequests'));
  });

  testWidgets('TEAM-ALL-013 Arabic: Latin digits in the dates and times', (
    tester,
  ) async {
    await pumpRequests(tester, locale: 'ar', dark: true);
    final meta = tester
        .widgetList<Text>(inRow(_youssef, find.byType(Text)))
        .map((w) => w.data ?? '')
        .firstWhere((s) => s.contains(_youssef));
    expect(meta, contains('08:30'));
    expect(RegExp('[٠-٩]').hasMatch(meta), isFalse);
  });

  testWidgets('TEAM-ALL-018 the scope bar\'s branch is not sent', (
    tester,
  ) async {
    final h = await pumpRequests(tester);
    await h.tap(find.text('All branches'));
    await h.tap(find.text('Zamalek').hitTestable());
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(
      h.server.callsTo(listT).every((c) => !c.query.containsKey('branch_id')),
      isTrue,
    );
  });

  testWidgets('TEAM-ALL-021 filters live in the page, not the URL; leaving '
      'resets them; Escape closes a dialog sending nothing', (tester) async {
    final h = await pumpRequests(tester);
    await h.tap(pageText('Approved'));
    expect(h.location.query, isEmpty);
    await h.tap(cancelIn('Family visit in Tanta'));
    expect(find.byType(DashSurface), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.byType(DashSurface), findsNothing);
    expect(patches(h), 0);
    await h.go('/staff/approvals');
    await h.go(requestsPath);
    expect(_shown(tester).map((r) => r.status).toSet(), {'pending'});
  });

  testWidgets('TEAM-ALL-023 the list read: a 403 once, a 500 twice, a 429 '
      'four times', (tester) async {
    Future<int> asks(MockResponse answer) async {
      final s = requestsServer();
      s.server.fail('GET', listT, answer, times: null);
      final c = ProviderContainer(
        retry: webRetry,
        overrides: [
          transportProvider.overrideWithValue(s.server),
          orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
        ],
      );
      final sub = c.listen(
        requestsListProvider((status: 'approved', kind: null)),
        (_, _) {},
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      sub.close();
      c.dispose();
      return s.server.callsTo(listT).length;
    }

    expect(await asks(MockResponse.denied('hr.leave.read')), 1);
    expect(await asks(MockResponse.error(500, 'boom')), 2);
    expect(await asks(MockResponse.error(429, 'Slow down')), 4);
  });
}

String _d(DashHarness h, String iso) =>
    h.container.read(formatProvider).fmtDate(iso);
