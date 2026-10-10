// Payroll (`/staff/payroll`): the page's header, banners, steps, stats,
// payslips table and its states (TEAM-PAY-001 … -023, -062/-063 and the
// area-wide rows the page carries).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show SkeletonBlock;
import 'package:dashboard_team/src/payroll/payroll_logic.dart' show SlipRow;
import 'package:dashboard_team/src/payroll/payroll_steps.dart';
import 'package:dashboard_team/src/payroll/payslip_sheet.dart';
import 'package:dashboard_team/src/shared/staff_query.dart'
    show staffRevisionsProvider;
import 'package:flutter_test/flutter_test.dart';

import 'payroll_support.dart';

void main() {
  testWidgets('TEAM-PAY-001 refused without payroll rights; asks nothing', (
    tester,
  ) async {
    final h = await pumpPayroll(tester, persona: Persona.manager);
    expect(pageText(h.t('dawam.payrollNoAccess')), findsOneWidget);
    expect(h.server.callsTo(currentT), isEmpty);
  });

  testWidgets(
    'TEAM-PAY-002/004/012/020 open month: period, phase, steps, stats, estimates',
    (tester) async {
      final h = await pumpPayroll(tester);
      expect(pageText('01 Oct 2026 → 31 Oct 2026'), findsOneWidget);
      expect(pageText('Open'), findsOneWidget);
      expect(pageText('Live, changes with every punch'), findsOneWidget);
      expect(
        inPage(
          find.textContaining(
            h.t('dawamOps.payNextApprove'),
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      final steps = find.byKey(PayrollSteps.currentStepKey);
      expect(
        find.descendant(of: steps, matching: find.text('Estimate')),
        findsOneWidget,
      );
      // The server's totals, not a sum made here.
      final cur = (h.server.callsTo(currentT).length);
      expect(cur, 1);
      expect(pageText('Net pay'), findsOneWidget);
      expect(pageText('EGP 165,187.72'), findsOneWidget);
      expect(pageText('15'), findsOneWidget);
      expect(pageText('Paid 0 of 15'), findsNothing);
      // Columns and the live estimate in the Paid column.
      for (final c in ['NAME', 'SALARY', 'OVERTIME', 'NET', 'PAID']) {
        expect(pageText(c), findsOneWidget, reason: c);
      }
      expect(pageText('Estimate'), findsWidgets);
      expect(
        inPage(find.widgetWithText(DashButton, 'Mark paid')),
        findsNothing,
      );
      // Pay lists and the CSV wait for approval.
      expect(pageText('Pay lists (bank, wallet, cash)'), findsNothing);
      expect(pageText('CSV'), findsNothing);
    },
  );

  testWidgets('TEAM-PAY-003 / TEAM-ALL-016 the rules-first banner', (
    tester,
  ) async {
    final h = await pumpPayroll(
      tester,
      edit: (db) {
        for (final r in db['attendance_settings'].rows.toList()) {
          db['attendance_settings'].update(r['id']! as String, {
            'rules_saved_at': null,
          });
        }
      },
    );
    expect(pageText(h.t('dawam.rulesFirstTitle')), findsOneWidget);
    await h.tap(inPage(find.widgetWithText(DashButton, 'Set the rules')));
    expect(h.location.path, '/staff/rules');
  });

  testWidgets('TEAM-ALL-016 no banner once the rules are saved', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    expect(pageText(h.t('dawam.rulesFirstTitle')), findsNothing);
  });

  testWidgets(
    'TEAM-PAY-005/006 a missing salary blocks approval and lists the names',
    (tester) async {
      final h = await pumpPayroll(
        tester,
        edit: (db) => db['employees'].update(SeedIds.employee('adham'), {
          'base_salary_piastres': null,
        }),
      );
      expect(
        pageText(h.t('dawam.salaryMissingTitle', count: 1)),
        findsOneWidget,
      );
      expect(inPage(find.textContaining('Adham Reda.')), findsOneWidget);
      expect(pageText('Not set'), findsOneWidget);
      expect(
        inPage(
          find.textContaining(
            h.t('dawamOps.payNextBlocked'),
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      final approve = tester.widget<DashButton>(
        inPage(find.widgetWithText(DashButton, 'Approve payroll')),
      );
      expect(approve.onPressed, isNull);
      expect(approve.tooltip, h.t('dawamOps.approveBlocked'));
      await h.tap(
        inPage(find.widgetWithText(DashButton, 'Set salaries on Employees')),
      );
      expect(h.location.path, '/staff/employees');
    },
  );

  testWidgets(
    'TEAM-PAY-006 approve: days ahead + totals, POST generate, refreshed',
    (tester) async {
      final h = await pumpPayroll(tester);
      await h.tap(inPage(find.widgetWithText(DashButton, 'Approve payroll')));
      expect(find.text(h.t('dawam.approveTitle')), findsOneWidget);
      expect(
        find.textContaining(h.t('dawam.approveDaysAhead', count: 24)),
        findsOneWidget,
      );
      expect(
        find.textContaining('15 people, EGP 165,187.72 net in total.'),
        findsOneWidget,
      );
      final before = h.server.callsTo(currentT).length;
      await confirm(h, 'Approve payroll');
      expect(
        h.server.callsTo(generateT).single.path,
        '/staff/payroll/periods/${currentPeriodId(h.db!)}/generate',
      );
      await h.expectToast('Payroll approved');
      expect(h.server.callsTo(currentT).length, before + 1);
      expect(pageText('Approved'), findsWidgets);
      expect(pageText('Paid 0 of 15'), findsOneWidget);
      expect(
        inPage(
          find.textContaining(
            h.t('dawamOps.payNextPayFirst'),
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      expect(pageText(h.t('dawam.payLists')), findsOneWidget);
      expect(pageText('CSV'), findsOneWidget);
    },
  );

  testWidgets('TEAM-PAY-006 a cancelled confirm sends nothing', (tester) async {
    final h = await pumpPayroll(tester);
    await h.tap(inPage(find.widgetWithText(DashButton, 'Approve payroll')));
    await confirm(h, 'Cancel');
    expect(h.server.callsTo(generateT), isEmpty);
  });

  testWidgets('TEAM-PAY-006 a refused approval toasts the coded words', (
    tester,
  ) async {
    final s = payrollServer();
    s.server.fail(
      'POST',
      generateT,
      MockResponse.error(
        409,
        'No salary is set for Adham Reda.',
        code: 'SALARY_MISSING',
        vars: {
          'names': ['Adham Reda'],
        },
      ),
    );
    final h = await pumpPayroll(tester, s: s);
    await h.tap(inPage(find.widgetWithText(DashButton, 'Approve payroll')));
    await confirm(h, 'Approve payroll');
    await h.expectToast(
      h.t('errors.codes.SALARY_MISSING', args: {'names': 'Adham Reda'}),
    );
    expect(pageText('Open'), findsOneWidget);
  });

  testWidgets(
    'TEAM-PAY-021 / TEAM-MNY-032 mark paid: first-payment words, PATCH, pill',
    (tester) async {
      final h = await pumpPayroll(tester);
      await approveMonth(h);
      await h.tap(inPage(find.widgetWithText(DashButton, 'Mark paid')).first);
      expect(topText('Mark Adham Reda paid'), findsOneWidget);
      expect(
        inTop(find.textContaining('EGP 7,500.00 to Adham Reda')),
        findsOneWidget,
      );
      expect(
        inTop(find.textContaining(h.t('dawamOps.markPaidFirst'))),
        findsOneWidget,
      );
      await h.tap(inTop(find.text('Bank transfer')));
      await press(h, 'Mark paid');
      expect(lastBody(h, paidT), {'method': 'bank'});
      await h.expectToast('Marked paid');
      // Paid by hand: the month can't be reopened any more (TEAM-PAY-007),
      // and the paid row moves behind the unpaid ones (off page 1).
      expect(pageText('Reopen'), findsNothing);
      expect(pageText('Adham Reda'), findsNothing);
      expect(pageText('Paid 1 of 15'), findsOneWidget);
    },
  );

  testWidgets('TEAM-MNY-032 the method follows a refetch until picked; a '
      'pick survives one', (tester) async {
    final s = payrollServer();
    final h = await pumpPayroll(tester, s: s);
    await approveMonth(h);
    await h.tap(inPage(find.widgetWithText(DashButton, 'Mark paid')).first);
    String method() => tester
        .widget<DashSegmentedControl<String>>(
          inTop(find.byType(DashSegmentedControl<String>)),
        )
        .value;
    final adham = SeedIds.employee('adham');
    expect(method(), 'cash');
    s.db['employees'].update(adham, {'pay_method': 'wallet'});
    h.container.read(staffRevisionsProvider.notifier).invalidateEmployees();
    await h.settle();
    expect(method(), 'wallet');
    await h.tap(inTop(find.text('Bank transfer')));
    s.db['employees'].update(adham, {'pay_method': 'cash'});
    h.container.read(staffRevisionsProvider.notifier).invalidateEmployees();
    await h.settle();
    expect(method(), 'bank');
    await press(h, 'Mark paid');
    expect(lastBody(h, paidT), {'method': 'bank'});
    await h.flushTimers();
  });

  testWidgets('TEAM-PAY-021 the second payment reads the later wording', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    await approveMonth(h);
    await h.tap(inPage(find.widgetWithText(DashButton, 'Mark paid')).first);
    await press(h, 'Mark paid');
    await h.flushTimers();
    await h.tap(inPage(find.widgetWithText(DashButton, 'Mark paid')).first);
    expect(
      inTop(find.textContaining(h.t('dawam.markPaidHint'))),
      findsOneWidget,
    );
  });

  testWidgets(
    'TEAM-PAY-007 / TEAM-MNY-037 reopen: reason required, PATCH draft',
    (tester) async {
      final h = await pumpPayroll(tester);
      await approveMonth(h);
      await h.tap(inPage(find.widgetWithText(DashButton, 'Reopen')));
      expect(topText(h.t('dawam.reopenTitle')), findsOneWidget);
      await press(h, 'Reopen');
      expect(topText('A reason is needed'), findsOneWidget);
      expect(h.server.callsTo(statusT), isEmpty);
      await type<DashTextField>(h, 'Reason', 'Forgot the Eid bonus');
      await press(h, 'Reopen');
      expect(lastBody(h, statusT), {
        'status': 'draft',
        'reason': 'Forgot the Eid bonus',
      });
      await h.expectToast('Payroll reopened');
      expect(pageText('Open'), findsOneWidget);
    },
  );

  testWidgets(
    'TEAM-PAY-008 / TEAM-ALL-024 pay lists: three sheets, nets above zero',
    (tester) async {
      final h = await pumpPayroll(tester);
      await approveMonth(h);
      await h.tap(inPage(find.text(h.t('dawam.payLists'))));
      await h.settle();
      expect(h.exports.built, hasLength(1));
      final spec = h.exports.built.single;
      expect(spec.sheets.map((s) => s.name), [
        'Bank transfer',
        'Mobile wallet',
        'Cash',
      ]);
      expect(spec.sheets.map((s) => s.title), [
        'Bank transfers',
        'Mobile wallets',
        'Cash envelopes',
      ]);
      expect(
        h.files.saved.single.filename,
        startsWith('Madar-Payroll-Transfers-'),
      );
      await h.expectToast(h.t('excel.done', count: 15));
    },
  );

  testWidgets('TEAM-ALL-024 nothing to pay: "Nothing to export", no file', (
    tester,
  ) async {
    final s = payrollServer();
    final h = await pumpPayroll(tester, s: s);
    await approveMonth(h);
    for (final p in s.db['payslips'].rows.toList()) {
      s.db['payslips'].update(p['id']! as String, {'net_piastres': 0});
    }
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    await h.tap(inPage(find.text(h.t('dawam.payLists'))));
    await h.expectToast(h.t('excel.nothingToExport'));
    expect(h.files.saved, isEmpty);
  });

  testWidgets('TEAM-PAY-009 CSV: the server\'s file as payroll-<start>.csv', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    await approveMonth(h);
    await h.tap(inPage(find.widgetWithText(DashButton, 'CSV')));
    expect(h.server.callsTo(csvT), hasLength(1));
    expect(h.files.saved.single.filename, 'payroll-2026-10-01.csv');
  });

  testWidgets('TEAM-PAY-009 a failed CSV toasts', (tester) async {
    final s = payrollServer();
    s.server.fail('GET', csvT, MockResponse.error(500, 'boom'));
    final h = await pumpPayroll(tester, s: s);
    await approveMonth(h);
    await h.tap(inPage(find.widgetWithText(DashButton, 'CSV')));
    await h.expectToast(h.refusalWords(MockResponse.error(500, 'boom')));
    expect(h.files.saved, isEmpty);
  });

  testWidgets(
    'TEAM-PAY-010/011 an older month to settle: banner, open it, act, back',
    (tester) async {
      final h = await pumpPayroll(tester, edit: septemberUnpaid);
      final title = inPage(find.textContaining("isn't fully paid yet"));
      expect(title, findsOneWidget);
      expect(
        inPage(
          find.textContaining(
            h.t('dawam.unsettledApproved', args: {'paid': 12, 'people': 15}),
          ),
        ),
        findsOneWidget,
      );
      await h.tap(inPage(find.widgetWithText(DashButton, 'Open it')));
      expect(h.server.callsTo(payslipsT).single.path, contains(septemberId()));
      expect(
        inPage(find.textContaining("You're looking at an earlier month")),
        findsOneWidget,
      );
      expect(title, findsNothing);
      expect(
        pageText('${dateOf(h, '2026-09-01')} → ${dateOf(h, '2026-09-30')}'),
        findsOneWidget,
      );
      expect(pageText('Paid 12 of 15'), findsOneWidget);
      // Its own actions, by its own id.
      await h.tap(inPage(find.widgetWithText(DashButton, 'Mark paid')).first);
      await press(h, 'Mark paid');
      expect(
        h.server.callsTo(paidT).single.path,
        contains('/periods/${septemberId()}/'),
      );
      await h.flushTimers();
      await h.tap(
        inPage(find.widgetWithText(DashButton, 'Back to this month')),
      );
      expect(pageText('01 Oct 2026 → 31 Oct 2026'), findsOneWidget);
    },
  );

  testWidgets('TEAM-PAY-010/011 a never-approved older month: its preview', (
    tester,
  ) async {
    final h = await pumpPayroll(
      tester,
      edit: (db) => septemberUnpaid(db, unpaid: 0, status: 'draft'),
    );
    expect(pageText(h.t('dawam.unsettledDraft')), findsNothing);
    expect(
      inPage(find.textContaining(h.t('dawam.unsettledDraft'))),
      findsOneWidget,
    );
    await h.tap(inPage(find.widgetWithText(DashButton, 'Open it')));
    expect(h.server.callsTo(previewT).single.path, contains(septemberId()));
    expect(
      inPage(find.widgetWithText(DashButton, 'Approve payroll')),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-PAY-010 no banner when every older month is paid', (
    tester,
  ) async {
    await pumpPayroll(tester);
    expect(inPage(find.widgetWithText(DashButton, 'Open it')), findsNothing);
  });

  testWidgets('TEAM-PAY-013 / TEAM-ALL-021 tabs; the tab resets on leaving', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    for (final tab in [
      'Payslips',
      'Bonuses & deductions',
      'Salary advances',
      'Expense advances',
      'History',
    ]) {
      expect(pageText(tab), findsOneWidget, reason: tab);
    }
    await h.tap(pageText('History'));
    expect(pageText('September 2026'), findsOneWidget);
    await h.go('/staff/employees');
    await h.go(payrollPath);
    expect(pageText('NAME'), findsOneWidget);
    expect(pageText('September 2026'), findsNothing);
  });

  testWidgets('TEAM-PAY-022 loading: skeleton, never the empty words', (
    tester,
  ) async {
    final s = payrollServer();
    final gate = s.server.hold('GET', currentT);
    final h = await pumpPayroll(tester, s: s);
    expect(pageText(h.t('dawam.noPayslips')), findsNothing);
    expect(inPage(find.byType(SkeletonBlock)), findsWidgets);
    gate.release();
    await h.settle();
    expect(pageText('Adham Reda'), findsOneWidget);
  });

  testWidgets(
    'TEAM-PAY-002/022 error: "Couldn\'t load payroll" + Retry asks again',
    (tester) async {
      final s = payrollServer();
      s.server.fail('GET', currentT, MockResponse.error(500, 'boom'));
      final h = await pumpPayroll(tester, s: s);
      expect(pageText(h.t('dawam.payrollLoadError')), findsOneWidget);
      expect(pageText(h.t('dawam.payrollSubtitle')), findsOneWidget);
      await h.tap(inPage(find.widgetWithText(DashButton, 'Retry')));
      expect(h.server.callsTo(currentT), hasLength(2));
      expect(pageText('Adham Reda'), findsOneWidget);
    },
  );

  testWidgets('TEAM-PAY-022 empty: "Nobody on payroll yet"', (tester) async {
    final h = await pumpPayroll(
      tester,
      edit: (db) {
        for (final e in db['employees'].rows.toList()) {
          db['employees'].update(e['id']! as String, {'on_payroll': false});
        }
      },
    );
    expect(pageText(h.t('dawam.noPayslips')), findsOneWidget);
    expect(pageText(h.t('dawam.noPayslipsHint')), findsOneWidget);
  });

  testWidgets(
    'TEAM-ALL-008/010/022 Refresh asks again; a failed refresh keeps the rows and toasts',
    (tester) async {
      final s = payrollServer();
      final h = await pumpPayroll(tester, s: s);
      await h.tap(inPage(find.bySemanticsLabel('Refresh')));
      expect(h.server.callsTo(currentT), hasLength(2));
      s.server.fail(
        'GET',
        currentT,
        MockResponse.error(429, 'Too many requests'),
      );
      await h.tap(inPage(find.bySemanticsLabel('Refresh')));
      expect(pageText('Adham Reda'), findsOneWidget);
      expect(pageText(h.t('dawam.payrollLoadError')), findsNothing);
      await h.expectToast(h.t('errors.tooManyRequests'));
    },
  );

  testWidgets('TEAM-ALL-009 back after 30 s refetches; sooner does not', (
    tester,
  ) async {
    final s = payrollServer();
    final h = await pumpPayroll(tester, s: s);
    await background(tester, h);
    expect(h.server.callsTo(currentT), hasLength(1));
    s.db.clock.advance(const Duration(seconds: 31));
    await background(tester, h);
    expect(h.server.callsTo(currentT), hasLength(2));
  });

  testWidgets('TEAM-PAY-023 a row opens that person\'s payslip', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    await openSlip(h, 'Ali Hassan');
    expect(find.byType(PayslipSheet), findsOneWidget);
    expect(topText('Ali Hassan'), findsOneWidget);
    expect(topText(h.t('dawam.estimateHint')), findsOneWidget);
  });

  testWidgets('TEAM-PAY-062 phone: cards, 2×2 stats, full-screen payslip', (
    tester,
  ) async {
    final h = await pumpPayroll(tester, size: DashSize.phone);
    final net = tester.getTopLeft(pageText('Net pay'));
    final people = tester.getTopLeft(pageText('People'));
    final deductions = tester.getTopLeft(pageText('Deductions').first);
    expect(people.dy, net.dy);
    expect(deductions.dy, greaterThan(net.dy));
    expect(pageText('NAME'), findsNothing);
    await openSlip(h, 'Ali Hassan');
    expect(topText(h.t('dawam.estimateHint')), findsOneWidget);
    final sheet = tester.getSize(find.byType(PayslipSheet));
    expect(sheet.width, DashSize.phone.size.width);
  });

  testWidgets(
    'TEAM-PAY-063 names come from the payslip, else the active list',
    (tester) async {
      final s = payrollServer(edit: septemberUnpaid);
      // A server whose payslips lost two names: Ali is still active, Adham
      // left (no longer on the active list).
      s.server.on('GET', payslipsT, (req) {
        final out = <Map<String, Object?>>[];
        for (final r in s.db['payslips'].rows) {
          if (r['payroll_period_id'] != req.param('id')) continue;
          final e = s.db['employees'].find(r['employee_id']! as String);
          final unnamed = {SeedIds.employee('ali'), SeedIds.employee('adham')};
          final name = unnamed.contains(r['employee_id']) ? null : e?['name'];
          out.add({
            for (final kv in r.entries)
              if (!kv.key.startsWith('_')) kv.key: kv.value,
            'employee_name': name,
          });
        }
        return MockResponse.ok(out);
      });
      s.db['employees'].update(SeedIds.employee('adham'), {
        'employment_status': 'terminated',
      });
      final h = await pumpPayroll(tester, s: s);
      await h.tap(inPage(find.widgetWithText(DashButton, 'Open it')));
      final table = tester.widget<DashDataTable<SlipRow>>(
        inPage(find.byType(DashDataTable<SlipRow>)),
      );
      final names = {for (final r in table.rows) r.employeeId: r.name};
      expect(names[SeedIds.employee('ali')], 'Ali Hassan');
      expect(names[SeedIds.employee('adham')], '—');
    },
  );

  testWidgets('TEAM-ALL-020 pages of 10; the Columns menu lists Name only', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    expect(pageText('Page 1 of 2'), findsOneWidget);
    await h.tap(inPage(find.bySemanticsLabel(h.t('common.next'))).last);
    expect(pageText('Page 2 of 2'), findsOneWidget);
    await h.tap(inPage(find.text('Columns')));
    expect(find.text('Name').hitTestable(), findsOneWidget);
    expect(find.text('Salary').hitTestable(), findsNothing);
  });
}
