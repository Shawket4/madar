// The Payroll tabs (TEAM-PAY-040 … -061) and the money dialogs they open
// (TEAM-MNY-001, -010 … -017, -020, -030 … -033, -036, -039 … -041).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show orgIdProvider, transportProvider, webRetry;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/payroll/payroll_data.dart';
import 'package:dashboard_team/src/payroll/payroll_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payroll_support.dart';

const String decideT = '/staff/adjustments/{kind}/{id}/decision';
const String stopT = '/staff/adjustments/{kind}/{id}/stop';
const String recordT = '/staff/advances/record';
const String reviewT = '/staff/advances/{id}/review';
const String expenseT = '/staff/expense-advances/{id}';

Future<DashHarness> onTab(
  WidgetTester tester,
  String tab, {
  Srv? s,
  Persona persona = Persona.owner,
}) async {
  final h = await pumpPayroll(tester, s: s, persona: persona);
  await h.tap(pageText(tab));
  return h;
}

Finder rowOf(String key) => find.byKey(ValueKey(key));

/// The row (keyed `<prefix>-…`) holding [text].
Finder rowWith(String prefix, String text) => find
    .ancestor(
      of: inPage(find.textContaining(text)),
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('$prefix-'),
      ),
    )
    .first;

Finder inRow(Finder row, Finder f) => find.descendant(of: row, matching: f);

/// Picks [option] in the topmost surface's select labelled [label].
Future<void> pick(DashHarness h, String label, String option) async {
  await h.tap(field<DashSelectField<String>>(label));
  await h.tap(find.text(option).hitTestable().last);
}

/// A second pending line in Sabah (Omar's), beside Hassan's.
void secondPending(MockDb db) {
  final t = db[TeamTables.adjustments];
  final hassan = t.rows.firstWhere(
    (r) => (r['reason'] as String).startsWith('Kept the kitchen running'),
  );
  t.insert({
    ...hassan,
    'id': mockUuid('adjustment:omar-doubles'),
    'employee_id': SeedIds.employee('omar'),
    'employee_name': 'Omar Khaled',
    'reason': 'Covered two doubles.',
  }, timestamps: false);
}

/// A recurring approved pay line with no end yet (Salma's meal allowance).
void mealAllowance(MockDb db) {
  final t = db[TeamTables.adjustments];
  final salma = t.rows.firstWhere(
    (r) => r['reason'] == 'Best mystery-shopper score in September.',
  );
  t.update(salma['id']! as String, {
    'recurring': true,
    'ends_on': null,
    'reason': 'Meal allowance',
  });
}

void main() {
  group('Bonuses & deductions', () {
    testWidgets(
      'TEAM-PAY-040/042 rows: kind, rule source, reason, date, value, status',
      (tester) async {
        final h = await onTab(tester, 'Bonuses & deductions');
        final hassan = rowWith('payline', 'Kept the kitchen running');
        expect(inRow(hassan, find.text('Hassan Ibrahim')), findsOneWidget);
        expect(inRow(hassan, find.text('Bonus')), findsOneWidget);
        expect(
          inRow(hassan, find.textContaining(dateOf(h, '2026-10-01'))),
          findsOneWidget,
        );
        expect(pageText(h.t('dawam.addPayLine')), findsOneWidget);
        expect(pageText('Rule · late'), findsWidgets);
        expect(pageText('Waiting for the owner'), findsWidgets);
        expect(pageText('Counts'), findsWidgets);
        expect(pageText('EGP 1,500.00'), findsOneWidget);
        expect(pageText('−EGP 250.00'), findsOneWidget);
      },
    );

    testWidgets('TEAM-PAY-041 error + Retry, loading, empty', (tester) async {
      final s = payrollServer();
      s.server.fail(
        'GET',
        linesT,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await onTab(tester, 'Bonuses & deductions', s: s);
      expect(pageText(h.t('dawam.payLinesLoadError')), findsOneWidget);
      final before = h.server.callsTo(linesT).length;
      s.server.clearFailures();
      await h.tap(inPage(find.widgetWithText(DashButton, 'Retry')));
      expect(h.server.callsTo(linesT), hasLength(before + 1));
      expect(pageText(h.t('dawam.payLinesLoadError')), findsNothing);
    });

    testWidgets('TEAM-PAY-041 empty: "No bonuses or deductions"', (
      tester,
    ) async {
      final s = payrollServer(
        edit: (db) => db[TeamTables.adjustments].removeWhere((_) => true),
      );
      final gate = s.server.hold('GET', linesT);
      final h = await onTab(tester, 'Bonuses & deductions', s: s);
      expect(pageText(h.t('dawam.noPayLines')), findsNothing);
      gate.release();
      await h.settle();
      expect(pageText(h.t('dawam.noPayLines')), findsOneWidget);
      expect(pageText(h.t('dawam.noPayLinesHint')), findsOneWidget);
    });

    testWidgets(
      'TEAM-PAY-043 / TEAM-MNY-033 approve a pending line; reject with why',
      (tester) async {
        final s = payrollServer(edit: secondPending);
        final h = await onTab(tester, 'Bonuses & deductions', s: s);
        final pending = rowWith('payline', 'Kept the kitchen running');
        await h.tap(inRow(pending, find.widgetWithText(DashButton, 'Approve')));
        expect(lastBody(h, decideT), {'approve': true});
        await h.expectToast('Decision saved');
        expect(inRow(pending, find.text('Counts')), findsOneWidget);
        final reem = rowWith('payline', 'Covered two doubles');
        await h.tap(inRow(reem, find.bySemanticsLabel('Reject')));
        expect(topText("Reject Omar Khaled's line?"), findsOneWidget);
        expect(topText(h.t('dawam.rejectWhyHint')), findsOneWidget);
        expect(topText(h.t('dawamOps.reasonSeen')), findsOneWidget);
        await press(h, 'Reject');
        expect(topText('A reason is needed'), findsOneWidget);
        await type<DashTextField>(h, 'Reason', 'Training is part of the job');
        await press(h, 'Reject');
        expect(lastBody(h, decideT), {
          'approve': false,
          'reason': 'Training is part of the job',
        });
        await h.expectToast('Decision saved');
        expect(
          inRow(
            reem,
            find.textContaining('Rejected: Training is part of the job'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('TEAM-PAY-043 without hr.payroll.run: no Approve or Reject', (
      tester,
    ) async {
      final s = payrollServer();
      answerAuthz(s.server, const ['hr.payroll.read', 'hr.adjustments.create']);
      final h = await onTab(tester, 'Bonuses & deductions', s: s);
      expect(inPage(find.widgetWithText(DashButton, 'Approve')), findsNothing);
      expect(inPage(find.bySemanticsLabel('Reject')), findsNothing);
      expect(pageText(h.t('dawam.addPayLine')), findsOneWidget);
    });

    testWidgets('TEAM-PAY-040 without either add right: no add button', (
      tester,
    ) async {
      final s = payrollServer();
      answerAuthz(s.server, const ['hr.payroll.read']);
      final h = await onTab(tester, 'Bonuses & deductions', s: s);
      expect(pageText(h.t('dawam.addPayLine')), findsNothing);
    });

    testWidgets(
      'TEAM-PAY-044 / TEAM-MNY-036 stop a monthly line: reason, POST, until',
      (tester) async {
        final s = payrollServer(edit: mealAllowance);
        final h = await onTab(tester, 'Bonuses & deductions', s: s);
        expect(pageText('monthly'), findsOneWidget);
        await h.tap(inPage(find.widgetWithText(DashButton, 'Stop')));
        expect(topText('Stop "Meal allowance"?'), findsOneWidget);
        await type<DashTextField>(h, 'Reason', 'Moved to the canteen plan');
        await press(h, 'Stop');
        expect(lastBody(h, stopT), {'reason': 'Moved to the canteen plan'});
        await h.expectToast('Stopped from next month');
        expect(inPage(find.textContaining('monthly until')), findsOneWidget);
        expect(inPage(find.widgetWithText(DashButton, 'Stop')), findsNothing);
      },
    );

    testWidgets(
      'TEAM-MNY-036 a stop refused for want of a reason, in its words',
      (tester) async {
        final s = payrollServer(edit: mealAllowance);
        s.server.fail(
          'POST',
          stopT,
          MockResponse.error(400, 'Say why', code: 'REASON_REQUIRED'),
        );
        final h = await onTab(tester, 'Bonuses & deductions', s: s);
        await h.tap(inPage(find.widgetWithText(DashButton, 'Stop')));
        await type<DashTextField>(h, 'Reason', ' x ');
        await press(h, 'Stop');
        await h.expectToast(h.t('errors.codes.REASON_REQUIRED_stopLine'));
      },
    );

    testWidgets(
      'TEAM-MNY-010/011/012/013/014/015/016/041 the pay-line form: fields, rules, never yourself',
      (tester) async {
        final s = payrollServer(edit: (db) => linkOwner(db, 'ali'));
        final h = await onTab(tester, 'Bonuses & deductions', s: s);
        await h.tap(
          inPage(find.widgetWithText(DashButton, h.t('dawam.addPayLine'))),
        );
        expect(topText(h.t('dawam.addPayLineHint')), findsOneWidget);
        await press(h, 'Save');
        expect(topText('Pick an employee'), findsWidgets);
        expect(topText('Type an amount'), findsOneWidget);
        expect(topText('A reason is needed'), findsOneWidget);
        expect(h.server.callsTo(linesT, method: 'POST'), isEmpty);
        // Never the signed-in person (Ali's row is the owner's here).
        await h.tap(field<DashSelectField<String>>('Employee'));
        expect(find.text('Adham Reda').hitTestable(), findsWidgets);
        expect(find.text('Ali Hassan').hitTestable(), findsNothing);
        await h.tap(find.text('Adham Reda').hitTestable().last);
        // Bonus by percent (a deduction is always an amount).
        expect(topText('Amount'), findsOneWidget);
        await h.tap(topText('% of salary'));
        expect(field<DashNumberField>('Percent'), findsOneWidget);
        await h.tap(topText('Deduction'));
        expect(topText('% of salary'), findsNothing);
        await h.tap(topText('Bonus'));
        await h.enterText(field<DashNumberField>('Percent'), '10');
        await type<DashTextField>(h, 'Reason', 'Ramadan');
        expect(topText(h.t('dawam.reasonShown')), findsOneWidget);
        expect(topText(h.t('dawam.monthHint')), findsOneWidget);
        expect(topText('Counts in the month of'), findsOneWidget);
        await h.tap(
          find.descendant(
            of: field<DashSwitchField>('Every month'),
            matching: find.byType(DashSwitch),
          ),
        );
        expect(topText('Every month from'), findsOneWidget);
        expect(topText(h.t('dawam.everyMonthHint')), findsOneWidget);
        await press(h, 'Save');
        expect(lastBody(h, linesT, 'POST'), {
          'employee_id': SeedIds.employee('adham'),
          'kind': 'bonus',
          'reason': 'Ramadan',
          'recurring': true,
          'amount_piastres': null,
          'percent_of_base': 10.0,
          'effective_date': '2026-10-01',
        });
        await h.expectToast('Pay line added');
      },
    );

    testWidgets('TEAM-MNY-017 a line over the limit waits: the info toast', (
      tester,
    ) async {
      final s = payrollServer();
      final h = await onTab(tester, 'Bonuses & deductions', s: s);
      final cups = s.db[TeamTables.adjustments].rows.firstWhere(
        (r) => r['reason'] == 'Two broken espresso cups.',
      );
      s.server.fail(
        'POST',
        linesT,
        MockResponse.ok({...cups, 'status': 'pending'}),
      );
      await h.tap(
        inPage(find.widgetWithText(DashButton, h.t('dawam.addPayLine'))),
      );
      await pick(h, 'Employee', 'Adham Reda');
      await h.enterText(field<DashMoneyField>('Amount (EGP)'), '5000');
      await type<DashTextField>(h, 'Reason', 'Big win');
      await press(h, 'Save');
      await h.expectToast(h.t('dawam.payLinePending'));
    });

    testWidgets(
      'TEAM-MNY-017 / TEAM-ALL-019 refusals worded for pay lines and month forms',
      (tester) async {
        final s = payrollServer();
        s.server.fail(
          'POST',
          linesT,
          MockResponse.error(
            409,
            'closed',
            code: 'PERIOD_CLOSED',
            vars: {'paid': false},
          ),
        );
        final h = await onTab(tester, 'Bonuses & deductions', s: s);
        await h.tap(
          inPage(find.widgetWithText(DashButton, h.t('dawam.addPayLine'))),
        );
        await pick(h, 'Employee', 'Adham Reda');
        await h.enterText(field<DashMoneyField>('Amount (EGP)'), '50');
        await type<DashTextField>(h, 'Reason', 'x');
        await press(h, 'Save');
        await h.expectToast(h.t('errors.codes.PERIOD_CLOSED_month'));
        // The form stays open.
        expect(topText(h.t('dawam.addPayLineHint')), findsOneWidget);
        s.server.fail(
          'POST',
          linesT,
          MockResponse.error(400, 'why', code: 'REASON_REQUIRED'),
        );
        await press(h, 'Save');
        await h.expectToast(h.t('errors.codes.REASON_REQUIRED_payLine'));
      },
    );

    testWidgets('TEAM-MNY-001 the month follows the payroll answer', (
      tester,
    ) async {
      final h = await onTab(tester, 'Bonuses & deductions');
      await approveMonth(h);
      await h.tap(
        inPage(find.widgetWithText(DashButton, h.t('dawam.addPayLine'))),
      );
      // October is approved: the first open month is November.
      expect(topText('November 2026'), findsOneWidget);
    });

    testWidgets('TEAM-MNY-001 without payroll read: today\'s month', (
      tester,
    ) async {
      final s = payrollServer();
      answerAuthz(s.server, const ['hr.payroll.run', 'hr.adjustments.create']);
      final h = await onTab(tester, 'Bonuses & deductions', s: s);
      await h.tap(
        inPage(find.widgetWithText(DashButton, h.t('dawam.addPayLine'))),
      );
      expect(topText('October 2026'), findsOneWidget);
    });
  });

  group('Salary advances', () {
    testWidgets(
      'TEAM-PAY-050/051 / TEAM-MNY-040 rows: meta, cap note, left, status, Review',
      (tester) async {
        final h = await onTab(tester, 'Salary advances');
        expect(pageText(h.t('dawam.recordAdvance')), findsOneWidget);
        final omar = rowOf('advance-${TeamSeedIds.advance('omar')}');
        expect(
          inRow(omar, find.textContaining('over 3 installments')),
          findsOneWidget,
        );
        expect(inRow(omar, find.text('Pending')), findsOneWidget);
        expect(
          inRow(omar, find.widgetWithText(DashButton, 'Review')),
          findsOneWidget,
        );
        final mariam = rowOf('advance-${TeamSeedIds.advance('mariam')}');
        expect(inRow(mariam, find.textContaining(' left')), findsOneWidget);
        expect(
          inRow(mariam, find.widgetWithText(DashButton, 'Review')),
          findsNothing,
        );
        expect(inPage(find.textContaining(' cap')), findsWidgets);
        expect(inPage(find.textContaining('Owes ')), findsWidgets);
      },
    );

    testWidgets(
      'TEAM-MNY-040 someone who may not pass the cap reads "only the owner"',
      (tester) async {
        final s = payrollServer();
        answerAuthz(
          s.server,
          const ['hr.payroll.read', 'hr.payroll.run', 'hr.advances.decide'],
          everywhere: const ['hr.payroll.read'],
        );
        final h = await onTab(tester, 'Salary advances', s: s);
        final over = h.t('dawam.overCapOwner');
        final within = h.t('dawam.withinCap');
        expect(
          inPage(find.text(over)).evaluate().length +
              inPage(find.text(within)).evaluate().length,
          greaterThan(0),
        );
        expect(pageText(h.t('dawam.overCap')), findsNothing);
      },
    );

    testWidgets('TEAM-PAY-050 error + Retry; empty', (tester) async {
      final s = payrollServer(
        edit: (db) => db[TeamTables.advances].removeWhere((_) => true),
      );
      s.server.fail(
        'GET',
        advancesT,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await onTab(tester, 'Salary advances', s: s);
      expect(pageText(h.t('dawam.advancesLoadError')), findsOneWidget);
      s.server.clearFailures();
      await h.tap(inPage(find.widgetWithText(DashButton, 'Retry')));
      expect(pageText(h.t('dawam.noAdvances')), findsOneWidget);
      expect(pageText(h.t('dawam.noAdvancesHint')), findsOneWidget);
    });

    testWidgets(
      'TEAM-PAY-050 without hr.advances.decide: no record, no review',
      (tester) async {
        final s = payrollServer();
        answerAuthz(s.server, const ['hr.payroll.read']);
        final h = await onTab(tester, 'Salary advances', s: s);
        expect(pageText(h.t('dawam.recordAdvance')), findsNothing);
        expect(inPage(find.widgetWithText(DashButton, 'Review')), findsNothing);
      },
    );

    testWidgets(
      'TEAM-MNY-020/041 record an advance: everyone active, 1 to 24, POST',
      (tester) async {
        final s = payrollServer(edit: (db) => linkOwner(db, 'ali'));
        final h = await onTab(tester, 'Salary advances', s: s);
        await h.tap(
          inPage(find.widgetWithText(DashButton, h.t('dawam.recordAdvance'))),
        );
        expect(topText(h.t('dawam.recordAdvanceHint')), findsOneWidget);
        await press(h, 'Save');
        expect(topText('Type an amount'), findsOneWidget);
        expect(h.server.callsTo(recordT), isEmpty);
        // The signed-in person is offered here (the server decides).
        await h.tap(field<DashSelectField<String>>('Employee'));
        expect(find.text('Ali Hassan').hitTestable(), findsWidgets);
        await h.tap(find.text('Adham Reda').hitTestable().last);
        await h.enterText(field<DashMoneyField>('Amount (EGP)'), '1200');
        await h.enterText(field<DashNumberField>('Monthly installments'), '30');
        await press(h, 'Save');
        expect(h.server.callsTo(recordT), isEmpty);
        await h.enterText(field<DashNumberField>('Monthly installments'), '3');
        await press(h, 'Save');
        expect(lastBody(h, recordT), {
          'employee_id': SeedIds.employee('adham'),
          'amount_piastres': 120000,
          'installments': 3,
          'reason': null,
        });
        await h.expectToast('Advance recorded');
      },
    );

    testWidgets('TEAM-MNY-039 review: prefilled, only what changed is sent', (
      tester,
    ) async {
      final h = await onTab(tester, 'Salary advances');
      final omar = rowOf('advance-${TeamSeedIds.advance('omar')}');
      await h.tap(inRow(omar, find.widgetWithText(DashButton, 'Review')));
      expect(topText("Approve Omar Khaled's advance"), findsOneWidget);
      await h.enterText(field<DashNumberField>('Monthly installments'), '6');
      await type<DashTextField>(h, 'Note', 'Six is easier on him');
      await press(h, 'Approve');
      expect(lastBody(h, reviewT), {
        'approve': true,
        'amount_piastres': null,
        'installments': 6,
        'note': 'Six is easier on him',
      });
      await h.expectToast('Decision saved');
    });

    testWidgets('TEAM-MNY-039 Enter in a field submits the form, as the '
        "web's form does", (tester) async {
      final h = await onTab(tester, 'Salary advances');
      final omar = rowOf('advance-${TeamSeedIds.advance('omar')}');
      await h.tap(inRow(omar, find.widgetWithText(DashButton, 'Review')));
      await h.enterText(field<DashNumberField>('Monthly installments'), '6');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(lastBody(h, reviewT)['installments'], 6);
      await h.expectToast('Decision saved');
    });

    testWidgets('TEAM-MNY-039 the review form follows a refetch until edited; '
        'an edit survives one', (tester) async {
      final s = payrollServer();
      final h = await onTab(tester, 'Salary advances', s: s);
      final id = TeamSeedIds.advance('omar');
      await h.tap(
        inRow(rowOf('advance-$id'), find.widgetWithText(DashButton, 'Review')),
      );
      int? amount() => tester
          .widget<DashMoneyField>(field<DashMoneyField>('Amount (EGP)'))
          .value;
      double? installments() => tester
          .widget<DashNumberField>(
            field<DashNumberField>('Monthly installments'),
          )
          .value;
      s.db[TeamTables.advances].update(id, {
        'amount_piastres': 240000,
        'installments': 4,
      });
      h.container.invalidate(payrollAdvancesProvider);
      await h.settle();
      expect(amount(), 240000);
      expect(installments(), 4);
      await h.enterText(field<DashNumberField>('Monthly installments'), '6');
      s.db[TeamTables.advances].update(id, {
        'amount_piastres': 300000,
        'installments': 2,
      });
      h.container.invalidate(payrollAdvancesProvider);
      await h.settle();
      expect(amount(), 240000);
      await press(h, 'Approve');
      // The amount the approver saw differs from the request now: sent.
      expect(lastBody(h, reviewT)['amount_piastres'], 240000);
      expect(lastBody(h, reviewT)['installments'], 6);
      await h.flushTimers();
    });
  });

  group('Expense advances', () {
    testWidgets(
      'TEAM-PAY-055/056 the log: note, rows, till tag correctable by the owner',
      (tester) async {
        final h = await onTab(tester, 'Expense advances');
        expect(pageText(h.t('dawam.expenseNever')), findsOneWidget);
        expect(pageText(h.t('dawam.logExpense')), findsOneWidget);
        expect(h.server.callsTo(expensesT).last.query['branch_id'], isNull);
        final karim = rowOf(
          'expense-${TeamSeedIds.expenseAdvance('karim-milk')}',
        );
        expect(
          inRow(karim, find.textContaining('Till pay-out')),
          findsOneWidget,
        );
        expect(inRow(karim, find.text('EGP 1,200.00')), findsOneWidget);
        expect(
          inRow(karim, find.widgetWithText(DashButton, 'Correct the tag')),
          findsOneWidget,
        );
        final dina = rowOf(
          'expense-${TeamSeedIds.expenseAdvance('dina-plumber')}',
        );
        expect(
          inRow(dina, find.widgetWithText(DashButton, 'Correct the tag')),
          findsNothing,
        );
      },
    );

    testWidgets('TEAM-PAY-056 not the right everywhere: no tag correction', (
      tester,
    ) async {
      final s = payrollServer();
      answerAuthz(
        s.server,
        const ['hr.payroll.read', 'hr.payroll.run', 'hr.expense_advances.log'],
        everywhere: const ['hr.payroll.read'],
      );
      final h = await onTab(tester, 'Expense advances', s: s);
      expect(pageText(h.t('dawam.correctTag')), findsNothing);
      expect(pageText(h.t('dawam.logExpense')), findsOneWidget);
    });

    testWidgets('TEAM-PAY-055 / TEAM-ALL-018 the scope bar\'s branch is sent', (
      tester,
    ) async {
      final h = await onTab(tester, 'Expense advances');
      expect(h.server.callsTo(expensesT).last.query['branch_id'], isNull);
      await h.tap(find.text('All branches'));
      await h.tap(find.text('Zamalek').hitTestable());
      expect(h.server.callsTo(expensesT).last.query['branch_id'], [
        SeedIds.zamalek,
      ]);
    });

    testWidgets('TEAM-PAY-055 error + Retry; empty "Nothing logged"', (
      tester,
    ) async {
      final s = payrollServer(
        edit: (db) => db[TeamTables.expenseAdvances].removeWhere((_) => true),
      );
      s.server.fail(
        'GET',
        expensesT,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await onTab(tester, 'Expense advances', s: s);
      expect(pageText(h.t('dawam.expensesLoadError')), findsOneWidget);
      s.server.clearFailures();
      await h.tap(inPage(find.widgetWithText(DashButton, 'Retry')));
      expect(pageText(h.t('dawam.noExpenses')), findsOneWidget);
    });

    testWidgets(
      'TEAM-MNY-030 log an expense advance: required fields, safe default, POST',
      (tester) async {
        final h = await onTab(tester, 'Expense advances');
        await h.tap(
          inPage(find.widgetWithText(DashButton, h.t('dawam.logExpense'))),
        );
        expect(topText(h.t('dawam.logExpenseHint')), findsOneWidget);
        await press(h, 'Save');
        expect(topText('Say what it\'s for'), findsOneWidget);
        expect(topText('Pick a branch'), findsWidgets);
        await pick(h, 'Employee', 'Adham Reda');
        await h.enterText(field<DashMoneyField>('Amount (EGP)'), '350');
        await type<DashTextField>(h, "What it's for", 'Cleaning supplies');
        await pick(h, 'Handed over at', 'Maadi');
        await press(h, 'Save');
        final body = lastBody(h, expensesT, 'POST');
        expect(body['employee_id'], SeedIds.employee('adham'));
        expect(body['amount_piastres'], 35000);
        expect(body['purpose'], 'Cleaning supplies');
        expect(body['via'], 'safe');
        expect(body['given_on'], '2026-10-08');
        expect(body['branch_id'], SeedIds.maadi);
        await h.expectToast('Expense advance logged');
      },
    );

    testWidgets(
      'TEAM-MNY-031 correct a till tag: reassign (someone else) or clear',
      (tester) async {
        final h = await onTab(tester, 'Expense advances');
        final id = TeamSeedIds.expenseAdvance('karim-milk');
        await h.tap(
          inRow(
            rowOf('expense-$id'),
            find.widgetWithText(DashButton, 'Correct the tag'),
          ),
        );
        expect(topText("Correct Karim Adel's till tag"), findsOneWidget);
        await pick(h, 'Employee', 'Karim Adel');
        await type<DashTextField>(h, 'Reason', 'Wrong person tagged');
        await press(h, 'Save');
        expect(topText(h.t('dawam.pickSomeoneElse')), findsOneWidget);
        await pick(h, 'Employee', 'Adham Reda');
        await press(h, 'Save');
        expect(lastBody(h, expenseT, 'PATCH'), {
          'employee_id': SeedIds.employee('adham'),
          'reason': 'Wrong person tagged',
        });
        await h.expectToast(h.t('dawam.tagReassigned'));
      },
    );

    testWidgets('TEAM-MNY-031 clear the tag: DELETE with the reason', (
      tester,
    ) async {
      final h = await onTab(tester, 'Expense advances');
      final id = TeamSeedIds.expenseAdvance('karim-milk');
      await h.tap(
        inRow(
          rowOf('expense-$id'),
          find.widgetWithText(DashButton, 'Correct the tag'),
        ),
      );
      await h.tap(topText(h.t('dawam.clearTag')));
      expect(topText('Pick an employee'), findsNothing);
      await type<DashTextField>(h, 'Reason', 'Shop money, not a person');
      await press(h, 'Save');
      final call = h.server.callsTo(expenseT, method: 'DELETE').single;
      expect(call.query['reason'], ['Shop money, not a person']);
      await h.expectToast(h.t('dawam.tagCleared'));
    });
  });

  group('History', () {
    testWidgets('TEAM-PAY-060 rows: name, dates, net, phase', (tester) async {
      final h = await onTab(tester, 'History');
      expect(pageText('September 2026'), findsOneWidget);
      expect(pageText('August 2026'), findsOneWidget);
      expect(
        inPage(
          find.textContaining(
            '${dateOf(h, '2026-09-01')} → ${dateOf(h, '2026-09-30')}',
          ),
        ),
        findsOneWidget,
      );
      expect(inPage(find.textContaining('Not fully paid yet')), findsNothing);
      expect(pageText('Paid'), findsWidgets);
    });

    testWidgets(
      'TEAM-PAY-061 / TEAM-PAY-063 a settled month opens its frozen payslips',
      (tester) async {
        final h = await onTab(tester, 'History');
        await h.tap(pageText('September 2026'));
        expect(find.byType(HistorySheet), findsOneWidget);
        expect(topText(h.t('dawam.frozenHint')), findsOneWidget);
        expect(topText('Adham Reda'), findsOneWidget);
        expect(topText('Cash'), findsWidgets);
        expect(
          h.server.callsTo(payslipsT).single.path,
          contains(septemberId()),
        );
      },
    );

    testWidgets('TEAM-PAY-061 the sheet\'s error + Retry', (tester) async {
      final s = payrollServer();
      s.server.fail(
        'GET',
        payslipsT,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await onTab(tester, 'History', s: s);
      await h.tap(pageText('September 2026'));
      expect(topText(h.t('dawam.payslipsLoadError')), findsOneWidget);
      s.server.clearFailures();
      await h.tap(inTop(find.widgetWithText(DashButton, 'Retry')));
      expect(topText('Adham Reda'), findsOneWidget);
    });

    testWidgets('TEAM-PAY-060/061 an unsettled month opens in the page', (
      tester,
    ) async {
      final s = payrollServer(edit: septemberUnpaid);
      final h = await onTab(tester, 'History', s: s);
      expect(inPage(find.textContaining('Not fully paid yet')), findsOneWidget);
      await h.tap(pageText('September 2026'));
      expect(find.byType(HistorySheet), findsNothing);
      expect(
        inPage(find.textContaining("You're looking at an earlier month")),
        findsOneWidget,
      );
      expect(pageText('NAME'), findsOneWidget);
    });

    testWidgets('TEAM-PAY-060 empty: "No earlier months yet"', (tester) async {
      final s = payrollServer(
        edit: (db) => db[TeamTables.payrollPeriods].removeWhere(
          (p) => (p['start_date']! as String).compareTo('2026-10') < 0,
        ),
      );
      final h = await onTab(tester, 'History', s: s);
      expect(pageText(h.t('dawam.noHistory')), findsOneWidget);
      expect(pageText(h.t('dawam.noHistoryHint')), findsOneWidget);
    });

    testWidgets('TEAM-ALL-008 an open History sheet\'s read spins Refresh', (
      tester,
    ) async {
      final h = await onTab(tester, 'History');
      await h.tap(pageText('August 2026'));
      final gate = h.server.hold('GET', payslipsT);
      h.container.invalidate(
        payrollOlderSlipsProvider((
          id: TeamSeedIds.period('sabah', '2026-08'),
          draft: false,
        )),
      );
      await h.settle();
      expect(
        find.bySemanticsLabel('Refreshing…', skipOffstage: false),
        findsOneWidget,
      );
      gate.release();
      await h.settle();
      expect(
        find.bySemanticsLabel('Refreshing…', skipOffstage: false),
        findsNothing,
      );
    });
  });

  testWidgets('TEAM-ALL-008 the active tab\'s list spins Refresh', (
    tester,
  ) async {
    final h = await onTab(tester, 'Salary advances');
    final gate = h.server.hold('GET', advancesT);
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(inPage(find.bySemanticsLabel('Refreshing…')), findsOneWidget);
    gate.release();
    await h.settle();
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
  });

  testWidgets('TEAM-ALL-022/023 one 500 on a refresh is retried, never an '
      'error a toast would show', (tester) async {
    final s = payrollServer();
    final c = ProviderContainer(
      retry: webRetry,
      overrides: [
        transportProvider.overrideWithValue(s.server),
        orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
      ],
    );
    addTearDown(c.dispose);

    Future<void> check<T>(String path, FutureProvider<T> read) async {
      final seen = <AsyncValue<T>>[];
      final sub = c.listen(read, (_, next) => seen.add(next));
      await tester.pump(const Duration(milliseconds: 300));
      expect(sub.read().hasValue, isTrue, reason: path);
      final before = s.server.callsTo(path).length;
      s.server.fail('GET', path, MockResponse.error(500, 'boom'));
      c.invalidate(read);
      await tester.pump(const Duration(milliseconds: 300));
      // Failed once, data still on screen, Riverpod retrying: no toast.
      expect(sub.read().hasValue, isTrue, reason: path);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(sub.read().hasError, isFalse, reason: path);
      // `listenStaffRefreshFailure` toasts only `hasError && !retrying`.
      for (final v in seen) {
        expect(v.hasError && !v.retrying, isFalse, reason: path);
      }
      expect(seen.any((v) => v.hasError && v.retrying), isTrue, reason: path);
      expect(s.server.callsTo(path).length, before + 2, reason: path);
      sub.close();
    }

    await check(advancesT, payrollAdvancesProvider);
    final slips = payrollOlderSlipsProvider((id: septemberId(), draft: false));
    await check(payslipsT, slips);
  });
}
