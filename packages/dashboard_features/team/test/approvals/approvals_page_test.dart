// Driven tests of /staff/approvals: one per TEAM-APR row (+ the TEAM-ALL rows
// the page carries), row ids first in each name.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/approvals/approvals_data.dart';
import 'package:dashboard_team/src/approvals/approvals_dialogs.dart';
import 'package:dashboard_team/src/payroll/money_dialogs.dart';
import 'package:dashboard_team/src/approvals/approvals_page.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'approvals_support.dart';

const _lists = [requestsT, advancesT, swapsT, claimsT, payLinesT];

Map<String, int> _counts(DashHarness h) => {
  for (final t in [..._lists, attendanceT])
    t: h.server.callsTo(t, method: 'GET').length,
};

Map<String, Object?> _body(DashHarness h, String template) =>
    (h.server.callsTo(template, method: 'PATCH').last.body! as Map)
        .cast<String, Object?>();

int _patches(DashHarness h, String template) =>
    h.server.callsTo(template, method: 'PATCH').length;

Finder _inSidebar(String text) =>
    find.descendant(of: find.byType(DashSidebar), matching: find.text(text));

Future<void> _resume(WidgetTester tester, DashHarness h) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await h.settle();
}

void main() {
  // ── gating ───────────────────────────────────────────────────────────────

  testWidgets('TEAM-APR-001 / TEAM-ALL-007 refused for someone who may decide '
      'nothing: its own title and words, nothing requested', (tester) async {
    final h = await pumpApprovals(tester, persona: Persona.limited);
    expect(find.text(h.t('common.restrictedTitle')), findsOneWidget);
    expect(find.text(h.t('dawam.approvalsNoAccess')), findsOneWidget);
    expect(page, findsNothing);
    for (final t in _lists) {
      expect(h.server.callsTo(t), isEmpty, reason: t);
    }
  });

  testWidgets('TEAM-APR-002 / TEAM-ALL-002 only the lists this person may '
      'decide are asked for and shown; the nav leaf shows for them', (
    tester,
  ) async {
    final s = approvalsServer();
    answerAuthz(s.server, const ['hr.schedule.edit']);
    final h = await pumpApprovals(tester, s: s);
    expect(h.server.callsTo(swapsT), hasLength(1));
    expect(h.server.callsTo(claimsT), hasLength(1));
    for (final t in [
      requestsT,
      advancesT,
      payLinesT,
      attendanceT,
      employeesT,
    ]) {
      expect(h.server.callsTo(t), isEmpty, reason: t);
    }
    final types = {
      for (final r in tester.widgetList<PendingRow>(
        inPage(find.byType(PendingRow)),
      ))
        r.item.type,
    };
    expect(types, {PendingType.swap, PendingType.claim});
    expect(_inSidebar(h.t('nav.approvals')), findsOneWidget);
  });

  testWidgets('TEAM-ALL-002 the Approvals leaf is hidden from someone who may '
      'decide nothing', (tester) async {
    final s = approvalsServer();
    answerAuthz(s.server, const ['hr.leave.read', 'hr.staff.read']);
    final h = await pumpApprovals(tester, s: s, path: '/staff/employees');
    h.allowUnmatched = true;
    expect(_inSidebar(h.t('nav.approvals')), findsNothing);
  });

  // ── header, sections, states ─────────────────────────────────────────────

  testWidgets('TEAM-APR-003 header: title, description and Refresh; no rules '
      'banner', (tester) async {
    final h = await pumpApprovals(tester);
    expect(pageText(h.t('dawam.approvals')), findsOneWidget);
    expect(pageText(h.t('dawam.approvalsSubtitle')), findsOneWidget);
    expect(inPage(find.byTooltip(h.t('common.refresh'))), findsOneWidget);
    expect(pageText(h.t('dawam.rulesFirstTitle')), findsNothing);
  });

  testWidgets('TEAM-APR-004 the section filter counts what each shows', (
    tester,
  ) async {
    final h = await pumpApprovals(tester);
    int n(PendingType t) => tester
        .widgetList<PendingRow>(inPage(find.byType(PendingRow)))
        .where((r) => r.item.type == t)
        .length;
    final requests = n(PendingType.request);
    final money = n(PendingType.advance) + n(PendingType.payLine);
    final all = rowCount();
    final shifts = all - requests - money;
    expect(pageText('${h.t('dawam.all')} ($all)'), findsOneWidget);
    expect(pageText('${h.t('staff.requests')} ($requests)'), findsOneWidget);
    expect(pageText('${h.t('dawam.money')} ($money)'), findsOneWidget);
    await h.tap(pageText('${h.t('dawam.shifts')} ($shifts)'));
    expect(rowCount(), shifts);
    await h.tap(pageText('${h.t('dawam.money')} ($money)'));
    expect(rowCount(), money);
    expect(
      tester
          .widgetList<PendingRow>(inPage(find.byType(PendingRow)))
          .every((r) => r.item.section == ApprovalSection.money),
      isTrue,
    );
  });

  testWidgets('TEAM-APR-005 / TEAM-ALL-010 one list failing says so in its '
      'place; the rest still show, and Retry asks only that list', (
    tester,
  ) async {
    final s = approvalsServer();
    s.server.fail(
      'GET',
      advancesT,
      MockResponse.denied('hr.advances.decide'),
      times: null,
    );
    final h = await pumpApprovals(tester, s: s);
    final title = h.t(
      'dawam.sectionLoadError',
      args: {'section': h.t('dawam.salaryAdvances')},
    );
    expect(pageText(title), findsOneWidget);
    expect(pageText(h.t('errors.unauthorized')), findsOneWidget);
    expect(rowOfType(PendingType.swap), findsOneWidget);
    expect(rowOfType(PendingType.advance), findsNothing);
    final before = _counts(h);
    s.server.clearFailures();
    await h.tap(inPage(find.text(h.t('common.retry'))));
    expect(h.server.callsTo(advancesT).length, before[advancesT]! + 1);
    for (final t in [requestsT, swapsT, claimsT, payLinesT, attendanceT]) {
      expect(h.server.callsTo(t).length, before[t], reason: t);
    }
    expect(pageText(title), findsNothing);
    expect(rowOfType(PendingType.advance), findsWidgets);
  });

  testWidgets('TEAM-APR-006 loading: one skeleton, never "nothing waiting"', (
    tester,
  ) async {
    final s = approvalsServer();
    final gate = s.server.hold('GET', swapsT);
    final h = await pumpApprovals(tester, s: s);
    expect(inPage(find.byType(DashSkeleton)), findsOneWidget);
    expect(pageText(h.t('dawam.nothingWaiting')), findsNothing);
    expect(inPage(find.byType(PendingRow)), findsNothing);
    gate.release();
    await h.settle();
    expect(inPage(find.byType(DashSkeleton)), findsNothing);
    expect(inPage(find.byType(PendingRow)), findsWidgets);
  });

  testWidgets('TEAM-APR-006 empty: the inbox words', (tester) async {
    final h = await pumpApprovals(tester, edit: emptyQueue);
    expect(pageText(h.t('dawam.nothingWaiting')), findsOneWidget);
    expect(pageText(h.t('dawam.nothingWaitingHint')), findsOneWidget);
    expect(pageText('${h.t('dawam.all')} (0)'), findsOneWidget);
  });

  testWidgets('TEAM-APR-007 a row: who, kind, detail, what approving does, '
      'Approve and Reject; newest first, nothing decided', (tester) async {
    final h = await pumpApprovals(tester);
    final items = [
      for (final r in tester.widgetList<PendingRow>(
        inPage(find.byType(PendingRow)),
      ))
        r.item,
    ];
    for (var i = 1; i < items.length; i++) {
      expect(items[i - 1].at.compareTo(items[i].at), greaterThanOrEqualTo(0));
    }
    expect(items.map((i) => i.key).toSet(), hasLength(items.length));
    final swap = rowOfType(PendingType.swap);
    final it = itemOf(tester, swap);
    for (final text in [it.who, h.t('dawam.swap'), h.t('dawamOps.meansSwap')]) {
      expect(
        find.descendant(of: swap, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(approveOf(swap), findsOneWidget);
    expect(rejectOf(swap), findsOneWidget);
    // Decided rows never show.
    final decided = h.db![TeamTables.swaps].rows
        .where((r) => r['status'] != 'pending')
        .map((r) => 'w|${r['id']}');
    for (final k in decided) {
      expect(items.any((i) => i.key == k), isFalse);
    }
  });

  testWidgets('TEAM-APR-025 phone: Reject is a glyph with its word as its '
      'label; nothing overflows', (tester) async {
    final h = await pumpApprovals(tester, size: DashSize.phone);
    final swap = rowOfType(PendingType.swap);
    final reject = tester.widget<DashIconButton>(
      find.descendant(of: swap, matching: find.byType(DashIconButton)),
    );
    expect(reject.semanticLabel, h.t('common.reject'));
    expect(
      find.descendant(of: swap, matching: find.text(h.t('common.reject'))),
      findsNothing,
    );
  });

  // ── the one-click runner ─────────────────────────────────────────────────

  testWidgets('TEAM-APR-008 a decision goes once however fast it is tapped; '
      'every button waits meanwhile', (tester) async {
    final s = approvalsServer();
    final gate = s.server.hold('PATCH', decideClaimT);
    final h = await pumpApprovals(tester, s: s);
    final claim = rowOfType(PendingType.claim);
    await h.tap(approveOf(claim));
    await tester.tap(approveOf(claim));
    await h.settle();
    expect(_patches(h, decideClaimT), 1);
    for (final b in tester.widgetList<DashButton>(
      approveOf(find.byType(PendingRow)),
    )) {
      expect(b.onPressed, isNull);
    }
    gate.release();
    await h.settle();
    expect(_patches(h, decideClaimT), 1);
    await h.expectToast(h.t('staff.decisionSaved'));
  });

  testWidgets('TEAM-APR-009/010 / TEAM-APR-018 a one-click approval leaves at '
      'once, says "Decision saved" and refreshes /staff', (tester) async {
    final s = approvalsServer();
    final h = await pumpApprovals(tester, s: s);
    final it = itemOf(tester, rowOfType(PendingType.swap));
    final before = _counts(h);
    final gate = s.server.hold('GET', swapsT);
    await h.tap(approveOf(rowOfType(PendingType.swap)));
    expect(_body(h, decideSwapT), {'approve': true});
    // Gone while the refetch is still in flight.
    expect(rowOfType(PendingType.swap), findsNothing);
    gate.release();
    await h.settle();
    await h.expectToast(h.t('staff.decisionSaved'));
    expect(pageHas(it.who), findsNothing);
    for (final t in _lists) {
      expect(h.server.callsTo(t).length, greaterThan(before[t]!), reason: t);
    }
  });

  testWidgets('TEAM-APR-010 / TEAM-APR-020 approving a claim says each labour '
      'limit it passes, and blocks nothing', (tester) async {
    final s = approvalsServer();
    s.server.fail(
      'PATCH',
      decideClaimT,
      MockResponse.ok({
        'status': 'approved',
        'warnings': [
          {
            'date': day(3),
            'employee_id': emp('laila'),
            'kind': 'day_hours',
            'minutes': 600,
            'limit_minutes': 540,
          },
        ],
      }),
    );
    final h = await pumpApprovals(tester, s: s);
    final claims = h.server.callsTo(claimsT).single;
    expect(claims.query, {
      'from': [day(-366)],
      'to': [day(366)],
    });
    await h.tap(approveOf(rowOfType(PendingType.claim)));
    expect(_body(h, decideClaimT), {'approve': true});
    final warn = h.t(
      'dawam.limitWarning',
      args: {
        'limit': h.t('dawam.warn_day_hours'),
        'minutes': '10h',
        'cap': '9h',
      },
    );
    expect(find.text(warn), findsOneWidget);
    await h.expectToast(h.t('staff.decisionSaved'));
  });

  testWidgets('TEAM-APR-010 / TEAM-ALL-014 a refused decision keeps the item '
      'and says why in the reader\'s words', (tester) async {
    final s = approvalsServer();
    s.server.fail(
      'PATCH',
      decideClaimT,
      MockResponse.error(
        403,
        "You can't approve your own claim.",
        code: 'OWN_CLAIM',
      ),
    );
    final h = await pumpApprovals(tester, s: s);
    final before = _counts(h);
    await h.tap(approveOf(rowOfType(PendingType.claim)));
    await h.expectToast(h.t('errors.codes.OWN_CLAIM'));
    expect(rowOfType(PendingType.claim), findsOneWidget);
    expect(_counts(h), before, reason: 'not stale: nothing re-read');
  });

  testWidgets('TEAM-ALL-015 a decision someone made first says so and '
      'refreshes the queue', (tester) async {
    final s = approvalsServer();
    s.server.fail(
      'PATCH',
      decideClaimT,
      MockResponse.error(
        404,
        'No claim waiting here.',
        code: 'NO_CLAIM_WAITING',
      ),
    );
    final h = await pumpApprovals(tester, s: s);
    final before = _counts(h);
    await h.tap(approveOf(rowOfType(PendingType.claim)));
    await h.expectToast(h.t('errors.codes.NO_CLAIM_WAITING'));
    expect(h.server.callsTo(claimsT).length, before[claimsT]! + 1);
  });

  // ── requests ─────────────────────────────────────────────────────────────

  testWidgets('TEAM-APR-011 only requests the caller may decide: never one the '
      'server says not, never their own', (tester) async {
    final h = await pumpApprovals(
      tester,
      edit: (db) {
        db[TeamTables.requests]
          ..insert(
            requestRow(
              id: 'rq-no',
              employeeKey: 'laila',
              kind: 'late_arrival',
              onDate: day(1),
              toTime: '10:00:00',
              reason: 'Not mine to decide',
              canDecide: false,
            ),
          )
          ..insert(
            requestRow(
              id: 'rq-own',
              employeeKey: 'laila',
              kind: 'late_arrival',
              onDate: day(1),
              toTime: '10:00:00',
              reason: 'My own request',
              isOwn: true,
            ),
          )
          ..insert(
            requestRow(
              id: 'rq-ok',
              employeeKey: 'laila',
              kind: 'correction',
              onDate: day(-1),
              fromTime: '09:00:00',
              reason: 'Forgot to clock in',
              title: 'Clock-in missed',
            ),
          );
      },
    );
    expect(pageHas('Not mine to decide'), findsNothing);
    expect(pageHas('My own request'), findsNothing);
    final row = rowOf('Forgot to clock in');
    expect(
      find.descendant(
        of: row,
        matching: find.text(h.t('dawam.kindCorrection')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining('Clock-in missed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text(h.t('dawamOps.meansCorrection')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-APR-011 a manager is never offered a request of an '
      'employee linked to them', (tester) async {
    final h = await pumpApprovals(
      tester,
      edit: (db) {
        final e = db['employees'].rows.firstWhere(
          (e) => e['id'] == emp('laila'),
        );
        db['employees'].update(e['id']! as String, {'user_id': SeedIds.owner});
        db[TeamTables.requests].insert(
          requestRow(
            id: 'rq-linked',
            employeeKey: 'laila',
            kind: 'late_arrival',
            onDate: day(1),
            toTime: '10:00:00',
            reason: 'Linked to me',
          ),
        );
      },
    );
    expect(
      h.server.callsTo(employeesT).where((c) => c.query.isEmpty),
      isNotEmpty,
    );
    expect(pageHas('Linked to me'), findsNothing);
  });

  testWidgets(
    'TEAM-APR-012 a late arrival is approved in one click with no pay '
    'question',
    (tester) async {
      final h = await pumpApprovals(tester);
      await h.tap(approveIn('Renewing my national ID'));
      expect(_body(h, decideRequestT), {'status': 'approved'});
      await h.expectToast(h.t('staff.decisionSaved'));
    },
  );

  testWidgets('TEAM-APR-012 / TEAM-APR-026 leave asks paid or not; unpaid is '
      'sent; the row leaves on the refetch, not before', (tester) async {
    final s = approvalsServer();
    final h = await pumpApprovals(tester, s: s);
    await h.tap(approveIn(h.t('staff.kindLeave')));
    expect(inSurface(find.text(h.t('staff.approveRequest'))), findsOneWidget);
    await h.tap(inSurface(find.byType(DashSwitch)));
    final gate = s.server.hold('GET', requestsT);
    await h.tap(inSurface(find.text(h.t('common.approve'))));
    expect(_body(h, decideRequestT), {
      'status': 'approved',
      'is_paid': false,
      'note': null,
    });
    expect(find.byType(ApproveWithPayDialog), findsNothing);
    expect(
      pageHas("My sister's wedding"),
      findsWidgets,
      reason: 'not hidden locally',
    );
    gate.release();
    await h.settle();
    await h.expectToast(h.t('staff.decisionSaved'));
    expect(pageHas("My sister's wedding"), findsNothing);
  });

  testWidgets(
    'TEAM-APR-012 an excuse starts from the rule and leaves it to the '
    'rule unless changed',
    (tester) async {
      final h = await pumpApprovals(
        tester,
        edit: (db) {
          onlyPending(db, const {});
          db[TeamTables.requests].insert(
            requestRow(
              id: 'rq-ex',
              employeeKey: 'laila',
              kind: 'excuse',
              onDate: day(-1),
              fromTime: '12:00:00',
              toTime: '13:00:00',
              reason: 'Bank errand',
              paidDefault: false,
            ),
          );
        },
      );
      await h.tap(approveIn('Bank errand'));
      expect(
        tester.widget<DashSwitch>(inSurface(find.byType(DashSwitch))).value,
        isFalse,
      );
      expect(surfaceText(h.t('staff.ruleSaysUnpaid')), findsOneWidget);
      await h.tap(inSurface(find.text(h.t('common.approve'))));
      expect(_body(h, decideRequestT), {'status': 'approved', 'note': null});
      await h.expectToast(h.t('staff.decisionSaved'));
    },
  );

  testWidgets('TEAM-APR-026 a refused dialog decision stays open with the '
      'server\'s words', (tester) async {
    final s = approvalsServer();
    final h = await pumpApprovals(tester, s: s);
    s.server.fail(
      'PATCH',
      decideRequestT,
      MockResponse.error(422, 'Leave balance is used up.'),
    );
    await h.tap(approveIn(h.t('staff.kindLeave')));
    await h.tap(inSurface(find.text(h.t('common.approve'))));
    await h.expectToast(
      h.refusalWords(MockResponse.error(422, 'Leave balance is used up.')),
    );
    expect(find.byType(ApproveWithPayDialog), findsOneWidget);
  });

  testWidgets('TEAM-APR-012 a mission over a worked day warns first; backing '
      'out sends and says nothing', (tester) async {
    final h = await pumpApprovals(
      tester,
      edit: (db) => db[TeamTables.requests].insert(
        requestRow(
          id: 'rq-m',
          employeeKey: 'laila',
          kind: 'mission',
          onDate: day(-1),
          title: 'Roastery visit',
          reason: 'Tasting day',
          workedDates: [day(-1)],
        ),
      ),
    );
    final row = rowOf('Tasting day');
    expect(itemOf(tester, row).batchable, isFalse);
    await h.tap(approveOf(row));
    expect(find.byType(DashConfirmDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(_patches(h, decideRequestT), 0);
    expect(rowOf('Tasting day'), findsOneWidget);
    await h.tap(approveOf(rowOf('Tasting day')));
    await h.tap(inConfirm(find.text(h.t('common.approve'))));
    expect(_body(h, decideRequestT), {'status': 'approved'});
    await h.expectToast(h.t('staff.decisionSaved'));
  });

  testWidgets('TEAM-APR-013 rejecting a request: its own warning, an optional '
      'reason sent as the note (empty → null)', (tester) async {
    final h = await pumpApprovals(tester);
    await h.tap(rejectIn('Renewing my national ID'));
    expect(
      surfaceText(
        h.t(
          'dawam.rejectTitle',
          args: {'name': 'Youssef Samir', 'kind': h.t('staff.kindLateArrival')},
        ),
      ),
      findsOneWidget,
    );
    expect(surfaceText(h.t('staff.rejectRequestHint')), findsOneWidget);
    await h.tap(inSurface(find.text(h.t('common.reject'))).last);
    expect(_body(h, decideRequestT), {'status': 'rejected', 'note': null});
    await h.expectToast(h.t('staff.decisionSaved'));

    await h.tap(rejectIn(h.t('staff.kindLeave')));
    await h.enterText(
      inSurface(find.byType(DashTextField)),
      'Too busy that week',
    );
    await h.tap(inSurface(find.text(h.t('common.reject'))).last);
    expect(_body(h, decideRequestT), {
      'status': 'rejected',
      'note': 'Too busy that week',
    });
    await h.flushTimers();
  });

  testWidgets('TEAM-APR-013 a request in a closed month offers Reject only', (
    tester,
  ) async {
    final h = await pumpApprovals(
      tester,
      edit: (db) => db[TeamTables.requests].insert(
        requestRow(
          id: 'rq-c',
          employeeKey: 'laila',
          kind: 'late_arrival',
          onDate: '2026-09-20',
          toTime: '10:00:00',
          reason: 'Old late note',
          monthClosed: true,
        ),
      ),
    );
    final row = rowOf('Old late note');
    expect(approveOf(row), findsNothing);
    expect(rejectOf(row), findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.text(h.t('staff.monthClosedRejectOnly')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-ALL-019 a reason the server needs on a rejection is worded '
      'for declining', (tester) async {
    final s = approvalsServer();
    final h = await pumpApprovals(tester, s: s);
    s.server.fail(
      'PATCH',
      decideRequestT,
      MockResponse.error(400, 'Say why.', code: 'REASON_REQUIRED'),
    );
    await h.tap(rejectIn('Renewing my national ID'));
    await h.tap(inSurface(find.text(h.t('common.reject'))).last);
    await h.expectToast(h.t('errors.codes.REASON_REQUIRED_decline'));
    expect(find.byType(ReasonDialog), findsOneWidget);
  });

  // ── money ────────────────────────────────────────────────────────────────

  testWidgets(
    'TEAM-APR-014 an advance: amount, installments, cap note; Approve '
    'reviews it and sends the changed installments only',
    (tester) async {
      final h = await pumpApprovals(tester);
      final row = rowOf("My mother's eye operation");
      expect(
        find.descendant(of: row, matching: find.text(h.t('dawam.withinCap'))),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(h.t('dawamOps.meansAdvance')),
        ),
        findsOneWidget,
      );
      await h.tap(approveOf(row));
      expect(find.byType(ReviewAdvanceDialog), findsOneWidget);
      await h.enterText(inSurface(find.byType(DashNumberField)), '4');
      await h.tap(inSurface(find.text(h.t('common.approve'))));
      expect(_body(h, reviewAdvanceT), {
        'approve': true,
        'amount_piastres': null,
        'installments': 4,
        'note': null,
      });
      await h.expectToast(h.t('staff.decisionSaved'));
    },
  );

  testWidgets('TEAM-APR-014 an advance over the cap is reject-only for someone '
      'who may not pass the cap', (tester) async {
    final s = approvalsServer();
    answerAuthz(s.server, const ['hr.advances.decide'], everywhere: const []);
    final h = await pumpApprovals(tester, s: s);
    final row = rowOf('Deposit on a new flat');
    expect(
      find.descendant(of: row, matching: find.text(h.t('dawam.overCapOwner'))),
      findsOneWidget,
    );
    expect(approveOf(row), findsNothing);
    expect(approveOf(rowOf("My mother's eye operation")), findsOneWidget);
  });

  testWidgets('TEAM-APR-015 an advance is rejected only with a reason', (
    tester,
  ) async {
    final h = await pumpApprovals(tester);
    await h.tap(rejectIn("My mother's eye operation"));
    expect(surfaceText(h.t('dawam.rejectWhyHint')), findsOneWidget);
    await h.tap(inSurface(find.text(h.t('common.reject'))).last);
    expect(surfaceText(h.t('dawam.reasonRequired')), findsOneWidget);
    expect(_patches(h, reviewAdvanceT), 0);
    await h.enterText(inSurface(find.byType(DashTextField)), 'Owes too much');
    await h.tap(inSurface(find.text(h.t('common.reject'))).last);
    expect(_body(h, reviewAdvanceT), {
      'approve': false,
      'reason': 'Owes too much',
    });
    await h.expectToast(h.t('staff.decisionSaved'));
  });

  testWidgets('TEAM-APR-016/017 a pay line over the limit: one-click approve, '
      'never batched; rejected only with a reason', (tester) async {
    final h = await pumpApprovals(tester);
    final row = rowOfType(PendingType.payLine);
    final it = itemOf(tester, row);
    expect(it.batchable, isFalse);
    expect(
      find.descendant(of: row, matching: find.byType(DashCheckbox)),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.text(h.t('dawamOps.meansBonus'))),
      findsOneWidget,
    );
    await h.tap(rejectOf(row));
    await h.tap(inSurface(find.text(h.t('common.reject'))).last);
    expect(surfaceText(h.t('dawam.reasonRequired')), findsOneWidget);
    await h.enterText(inSurface(find.byType(DashTextField)), 'Over budget');
    await h.tap(inSurface(find.text(h.t('common.reject'))).last);
    final id = (it.source as dynamic).id as String;
    expect(
      h.server.callsTo(decideAdjustmentT, method: 'PATCH').last.path,
      '/staff/adjustments/bonus/$id/decision',
    );
    expect(_body(h, decideAdjustmentT), {
      'approve': false,
      'reason': 'Over budget',
    });
    await h.flushTimers();
  });

  testWidgets('TEAM-APR-016 approving a pay line is one click', (tester) async {
    final h = await pumpApprovals(tester);
    await h.tap(approveOf(rowOfType(PendingType.payLine)));
    expect(_body(h, decideAdjustmentT), {'approve': true});
    await h.expectToast(h.t('staff.decisionSaved'));
  });

  // ── shifts ───────────────────────────────────────────────────────────────

  testWidgets('TEAM-APR-019 a swap is rejected only after confirming', (
    tester,
  ) async {
    final h = await pumpApprovals(tester);
    final it = itemOf(tester, rowOfType(PendingType.swap));
    await h.tap(rejectOf(rowOfType(PendingType.swap)));
    expect(
      inConfirm(
        find.text(
          h.t('dawam.rejectTitle', args: {'name': it.who, 'kind': it.kind}),
        ),
      ),
      findsOneWidget,
    );
    expect(inConfirm(find.text(h.t('dawam.rejectHint'))), findsOneWidget);
    expect(_patches(h, decideSwapT), 0);
    await h.tap(inConfirm(find.text(h.t('common.reject'))));
    expect(_body(h, decideSwapT), {'approve': false});
    await h.expectToast(h.t('staff.decisionSaved'));
  });

  testWidgets('TEAM-APR-020 rejecting a claim confirms, then decides', (
    tester,
  ) async {
    final h = await pumpApprovals(tester);
    await h.tap(rejectOf(rowOfType(PendingType.claim)));
    await h.tap(inConfirm(find.text(h.t('common.reject'))));
    expect(_body(h, decideClaimT), {'approve': false});
    await h.expectToast(h.t('staff.decisionSaved'));
  });

  testWidgets('TEAM-APR-021/022 covers and overtime: every pending one however '
      'old; approve and reject in one click', (tester) async {
    final h = await pumpApprovals(tester);
    final att = h.server.callsTo(attendanceT).map((c) => c.query).toList();
    expect(
      att,
      containsAll([
        {
          'cover_status': ['pending'],
        },
        {
          'overtime_status': ['pending'],
        },
      ]),
    );
    final cover = rowOfType(PendingType.cover);
    expect(
      find.descendant(
        of: cover,
        matching: find.text(h.t('dawamOps.meansCover')),
      ),
      findsOneWidget,
    );
    await h.tap(approveOf(cover));
    expect(_body(h, decideCoverT), {'approve': true});
    await h.expectToast(h.t('staff.decisionSaved'));
    await h.tap(rejectOf(rowOfType(PendingType.overtime, index: 0)));
    await h.tap(inConfirm(find.text(h.t('common.reject'))));
    expect(_body(h, decideOvertimeT), {'approve': false});
    await h.expectToast(h.t('staff.decisionSaved'));
  });

  testWidgets('TEAM-APR-021/022 a cover or overtime in a closed month is '
      'reject-only and points to next month', (tester) async {
    final h = await pumpApprovals(
      tester,
      edit: (db) {
        final t = db[TeamTables.attendance];
        final ot = t.rows.firstWhere((r) => r['overtime_status'] == 'pending');
        final cv = t.rows.firstWhere((r) => r['cover_status'] == 'pending');
        t.update(ot['id']! as String, {'business_date': '2026-09-28'});
        t.update(cv['id']! as String, {'business_date': '2026-09-27'});
      },
    );
    for (final type in [PendingType.cover, PendingType.overtime]) {
      final row = find.byWidgetPredicate(
        (w) => w is PendingRow && w.item.type == type && w.item.rejectOnly,
      );
      expect(row, findsOneWidget, reason: '$type');
      expect(approveOf(row), findsNothing);
      expect(
        find.descendant(
          of: row,
          matching: find.text(h.t('dawam.closedMonthNextLine')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(h.t('staff.monthClosedRejectOnly')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byType(DashCheckbox)),
        findsNothing,
      );
    }
  });

  // ── the batch ────────────────────────────────────────────────────────────

  testWidgets('TEAM-APR-023 the batch bar: select-all of the eligible, a hint '
      'until something is ticked, a checkbox only on eligible rows', (
    tester,
  ) async {
    final h = await pumpApprovals(tester);
    final n = batchCount(tester);
    expect(n, greaterThan(1));
    expect(pageText(h.t('dawamOps.selectAll', count: n)), findsOneWidget);
    expect(pageText(h.t('dawamOps.pickToBatch')), findsOneWidget);
    expect(
      tester
          .widget<DashButton>(
            inPage(
              find.widgetWithText(DashButton, h.t('dawamOps.approveSelected')),
            ),
          )
          .onPressed,
      isNull,
    );
    final swap = rowOfType(PendingType.swap);
    final it = itemOf(tester, swap);
    await h.tap(
      find.descendant(
        of: swap,
        matching: find.bySemanticsLabel(
          h.t('dawamOps.selectItem', args: {'name': it.who, 'kind': it.kind}),
        ),
      ),
    );
    expect(pageText(h.t('dawamOps.approveCount', count: 1)), findsOneWidget);
    expect(pageText(h.t('dawamOps.pickToBatch')), findsNothing);
    expect(
      find.descendant(
        of: rowOfType(PendingType.advance),
        matching: find.byType(DashCheckbox),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'TEAM-APR-024 approving together: confirm, one call each in turn, '
    'what failed says why and stays',
    (tester) async {
      final s = approvalsServer();
      final h = await pumpApprovals(tester, s: s);
      final n = batchCount(tester);
      final swap = itemOf(tester, rowOfType(PendingType.swap));
      s.server.fail(
        'PATCH',
        decideSwapT,
        MockResponse.error(
          403,
          "You can't approve a swap you're part of.",
          code: 'OWN_SWAP',
        ),
      );
      await h.tap(
        inPage(find.bySemanticsLabel(h.t('dawamOps.selectAll', count: n))),
      );
      await h.tap(inPage(find.text(h.t('dawamOps.approveCount', count: n))));
      expect(
        inConfirm(find.text(h.t('dawamOps.bulkTitle', count: n))),
        findsOneWidget,
      );
      expect(
        inConfirm(find.textContaining(h.t('dawamOps.bulkHint'))),
        findsOneWidget,
      );
      await h.tap(inConfirm(find.text(h.t('dawamOps.approveCount', count: n))));
      final patches = [
        decideRequestT,
        decideSwapT,
        decideClaimT,
        decideCoverT,
        decideOvertimeT,
      ].map((t) => _patches(h, t)).fold<int>(0, (a, b) => a + b);
      expect(patches, n);
      expect(find.text(h.t('dawamOps.bulkDone', count: n - 1)), findsOneWidget);
      final why = h.t('errors.codes.OWN_SWAP');
      expect(
        find.text(
          h.t(
            'dawamOps.bulkFailed',
            args: {'first': '${swap.who}: $why'},
            count: 1,
          ),
        ),
        findsOneWidget,
      );
      expect(rowOfType(PendingType.swap), findsOneWidget);
      expect(batchCount(tester), 1);
      await h.flushTimers();
    },
  );

  // ── area-wide ────────────────────────────────────────────────────────────

  testWidgets('TEAM-ALL-008 Refresh asks every shown list again', (
    tester,
  ) async {
    final h = await pumpApprovals(tester);
    final before = _counts(h);
    await h.tap(inPage(find.byTooltip(h.t('common.refresh'))));
    for (final t in [..._lists, attendanceT]) {
      expect(h.server.callsTo(t).length, greaterThan(before[t]!), reason: t);
    }
  });

  testWidgets('TEAM-ALL-009 back after 30 s re-reads the lists; sooner does '
      'nothing', (tester) async {
    final h = await pumpApprovals(tester);
    final before = _counts(h);
    h.server.clock.advance(const Duration(seconds: 10));
    await _resume(tester, h);
    expect(_counts(h), before);
    h.server.clock.advance(const Duration(seconds: 30));
    await _resume(tester, h);
    expect(h.server.callsTo(swapsT).length, before[swapsT]! + 1);
  });

  testWidgets('TEAM-ALL-010/022 a failed refresh keeps the rows and says so', (
    tester,
  ) async {
    final s = approvalsServer();
    final h = await pumpApprovals(tester, s: s);
    s.server.fail('GET', swapsT, MockResponse.error(500, 'down'), times: null);
    await h.tap(inPage(find.byTooltip(h.t('common.refresh'))));
    expect(rowOfType(PendingType.swap), findsOneWidget);
    expect(
      pageText(
        h.t('dawam.sectionLoadError', args: {'section': h.t('dawam.swap')}),
      ),
      findsNothing,
    );
    expect(
      find.text(h.refusalWords(MockResponse.error(500, 'down'))),
      findsOneWidget,
    );
    await h.flushTimers();
  });

  testWidgets('TEAM-ALL-018 the lists ignore the scope branch', (tester) async {
    final h = await pumpApprovals(tester, persona: Persona.manager);
    for (final t in [..._lists, attendanceT]) {
      for (final c in h.server.callsTo(t)) {
        expect(c.query.containsKey('branch_id'), isFalse, reason: t);
      }
    }
  });

  testWidgets('TEAM-ALL-021 Escape closes a dialog and sends nothing', (
    tester,
  ) async {
    final h = await pumpApprovals(tester);
    await h.tap(approveIn(h.t('staff.kindLeave')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.byType(ApproveWithPayDialog), findsNothing);
    expect(_patches(h, decideRequestT), 0);
  });

  testWidgets('intent: pointing at a mission\'s Approve warms its worked-days '
      'read; pressing asks nothing more', (tester) async {
    final h = await pumpApprovals(tester);
    final row = rowOfType(PendingType.request, index: 0);
    final mission = find.byWidgetPredicate(
      (w) => w is PendingRow && w.item.approveMode == ApproveMode.mission,
    );
    expect(mission, findsOneWidget, reason: '$row');
    final r = itemOf(tester, mission).source as dynamic;
    bool days(MockCall c) => c.query['employee_id']?.single == r.employeeId;
    expect(h.server.callsTo(attendanceT).where(days), isEmpty);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.ensureVisible(approveOf(mission));
    await h.settle();
    await mouse.moveTo(tester.getCenter(approveOf(mission)));
    await h.settle();
    expect(h.server.callsTo(attendanceT).where(days), hasLength(1));
    await h.tap(approveOf(mission));
    expect(h.server.callsTo(attendanceT).where(days), hasLength(1));
    if (find.byType(DashConfirmDialog).evaluate().isNotEmpty) {
      await h.tap(inConfirm(find.text(h.t('common.approve'))));
    }
    expect(_body(h, decideRequestT), {'status': 'approved'});
    await h.expectToast(h.t('staff.decisionSaved'));
  });
}
