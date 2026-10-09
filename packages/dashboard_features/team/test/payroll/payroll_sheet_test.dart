// The payslip sheet (TEAM-PAY-030 … -037) and the money dialogs it opens
// (TEAM-MNY-010/017 from a person's payslip, -034, -035, -038).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/payroll/payslip_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payroll_support.dart';

const String waiveT = '/staff/payroll/deductions/{id}/waive';
const String unwaiveT = '/staff/payroll/deductions/{id}/unwaive';
const String overrideT = '/staff/payroll/deductions/{id}/override';
const String deleteDeductionT = '/staff/payroll/deductions/{id}';

Finder inSheet(Finder f) =>
    find.descendant(of: find.byType(PayslipSheet), matching: f);

Finder sheetButton(String label) => inSheet(find.bySemanticsLabel(label));

/// A large approved deduction for Adham (salary 7,500): it carries.
void bigDeduction(MockDb db) {
  final t = db[TeamTables.adjustments];
  final cups = t.rows.firstWhere(
    (r) => r['reason'] == 'Two broken espresso cups.',
  );
  t.insert({
    ...cups,
    'id': mockUuid('adjustment:adham-till'),
    'employee_id': SeedIds.employee('adham'),
    'employee_name': 'Adham Reda',
    'amount_piastres': 2000000,
    'value_piastres': 2000000,
    'reason': 'Till short at closing.',
  }, timestamps: false);
}

void main() {
  testWidgets(
    'TEAM-PAY-030/031 header and lines: salary, rule lines, signed money',
    (tester) async {
      final h = await pumpPayroll(tester);
      await openSlip(h, 'Ali Hassan');
      expect(topText('Ali Hassan'), findsOneWidget);
      expect(topText(h.t('dawam.estimateHint')), findsOneWidget);
      expect(topText('Salary'), findsOneWidget);
      expect(topText('EGP 9,000.00'), findsWidgets);
      expect(topText(h.t('dawam.ruleLine')), findsWidgets);
      expect(inTop(find.textContaining('−EGP')), findsWidgets);
      expect(topText('Net'), findsOneWidget);
      expect(topText('EGP 8,978.37'), findsOneWidget);
    },
  );

  testWidgets(
    'TEAM-PAY-032 / TEAM-MNY-034 waive a rule line: reason, PATCH, struck',
    (tester) async {
      final h = await pumpPayroll(tester);
      await openSlip(h, 'Ali Hassan');
      await h.tap(sheetButton('Waive').first);
      expect(inTop(find.textContaining('Waive "')), findsOneWidget);
      expect(topText(h.t('dawam.waiveHint')), findsOneWidget);
      await press(h, 'Waive');
      expect(topText('A reason is needed'), findsOneWidget);
      await type<DashTextField>(h, 'Reason', 'Bus strike that morning');
      await press(h, 'Waive');
      expect(lastBody(h, waiveT), {'reason': 'Bus strike that morning'});
      await h.expectToast('Deduction waived');
      // The sheet shows the payslip as it is now (TEAM-PAY-023).
      expect(
        inSheet(find.text('Waived: Bus strike that morning')),
        findsOneWidget,
      );
      expect(sheetButton('Undo the waiver'), findsOneWidget);
      expect(topText('EGP 9,000.00'), findsWidgets);
    },
  );

  testWidgets('TEAM-PAY-033 / TEAM-MNY-035 undo a waiver, never a second waiver', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    await openSlip(h, 'Ali Hassan');
    final waivable = sheetButton('Waive').evaluate().length;
    await h.tap(sheetButton('Waive').first);
    await type<DashTextField>(h, 'Reason', 'Bus strike');
    await press(h, 'Waive');
    await h.flushTimers();
    expect(sheetButton('Waive'), findsNWidgets(waivable - 1));
    await h.tap(sheetButton('Undo the waiver'));
    expect(inTop(find.textContaining('Undo the waiver on "')), findsOneWidget);
    await type<DashTextField>(h, 'Reason', 'Strike was the day after');
    await press(h, 'Undo the waiver');
    expect(lastBody(h, unwaiveT), {'reason': 'Strike was the day after'});
    await h.expectToast('Waiver undone');
    expect(sheetButton('Waive'), findsNWidgets(waivable));
  });

  testWidgets(
    'TEAM-PAY-032 / TEAM-MNY-038 override: prefilled figure, zero allowed',
    (tester) async {
      final h = await pumpPayroll(tester);
      await openSlip(h, 'Ali Hassan');
      await h.tap(sheetButton('Override').first);
      expect(inTop(find.textContaining('Override "')), findsOneWidget);
      final box = find.descendant(
        of: field<DashMoneyField>('New amount (EGP)'),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(box).controller.text,
        isNotEmpty,
      );
      await h.enterText(field<DashMoneyField>('New amount (EGP)'), '0');
      await type<DashTextField>(h, 'Reason', 'Covered by the shift swap');
      await press(h, 'Override');
      expect(lastBody(h, overrideT), {
        'amount_piastres': 0,
        'reason': 'Covered by the shift swap',
      });
      await h.expectToast('Deduction overridden');
    },
  );

  testWidgets('TEAM-PAY-034 delete a manual line: confirm, DELETE, toast', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    await openSlip(h, 'Laila Ehab');
    expect(topText(h.t('dawam.manualLine')), findsOneWidget);
    await h.tap(sheetButton('Delete'));
    expect(find.text('Delete "Two broken espresso cups."?'), findsOneWidget);
    await confirm(h, 'Delete');
    expect(h.server.callsTo(deleteDeductionT, method: 'DELETE'), hasLength(1));
    await h.expectToast('Line deleted');
    expect(topText(h.t('dawam.manualLine')), findsNothing);
  });

  testWidgets('TEAM-PAY-034 rule lines are never deletable', (tester) async {
    final h = await pumpPayroll(tester);
    await openSlip(h, 'Ali Hassan');
    expect(sheetButton('Delete'), findsNothing);
  });

  testWidgets('TEAM-PAY-035 carry: badge in the table, hint in the sheet', (
    tester,
  ) async {
    final h = await pumpPayroll(tester, edit: bigDeduction);
    expect(inPage(find.textContaining('carries EGP')), findsOneWidget);
    await openSlip(h, 'Adham Reda');
    expect(
      inTop(find.textContaining('Deductions went past what was earned')),
      findsOneWidget,
    );
    expect(topText('EGP 0.00'), findsWidgets);
  });

  testWidgets('TEAM-PAY-036 Download PDF saves the payslip', (tester) async {
    final h = await pumpPayroll(tester);
    await openSlip(h, 'Ali Hassan');
    await h.tap(inTop(find.widgetWithText(DashButton, 'Download PDF')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await h.settle();
    final f = h.files.saved.single;
    expect(f.filename, 'payslip-2026-10-01-ali-hassan.pdf');
    expect(f.bytes.take(4), '%PDF'.codeUnits);
  });

  testWidgets(
    'TEAM-PAY-037 / TEAM-MNY-010/017 Bonus for this person: fixed, POST, toast',
    (tester) async {
      final h = await pumpPayroll(tester);
      await openSlip(h, 'Ali Hassan');
      await h.tap(inTop(find.widgetWithText(DashButton, 'Bonus')));
      expect(topText(h.t('dawam.addPayLine')), findsOneWidget);
      expect(topText(h.t('dawam.addPayLineHint')), findsOneWidget);
      expect(topText('Pick an employee'), findsNothing);
      await h.enterText(field<DashMoneyField>('Amount (EGP)'), '300');
      await type<DashTextField>(h, 'Reason', 'Covered the Friday rush');
      await press(h, 'Save');
      expect(lastBody(h, linesT, 'POST'), {
        'employee_id': SeedIds.employee('ali'),
        'kind': 'bonus',
        'reason': 'Covered the Friday rush',
        'recurring': false,
        'amount_piastres': 30000,
        'percent_of_base': null,
        'effective_date': '2026-10-01',
      });
      await h.expectToast('Pay line added');
    },
  );

  testWidgets('TEAM-PAY-037 Deduction: an amount only, never a percent', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    await openSlip(h, 'Ali Hassan');
    await h.tap(inTop(find.widgetWithText(DashButton, 'Deduction')));
    expect(topText('% of salary'), findsNothing);
    await h.enterText(field<DashMoneyField>('Amount (EGP)'), '50');
    await type<DashTextField>(h, 'Reason', 'Lost apron');
    await press(h, 'Save');
    final body = lastBody(h, linesT, 'POST');
    expect(body['kind'], 'deduction');
    expect(body['amount_piastres'], 5000);
    expect(body['percent_of_base'], isNull);
  });

  testWidgets('TEAM-PAY-030/032/037 approved: frozen, nothing to change', (
    tester,
  ) async {
    final h = await pumpPayroll(tester);
    await approveMonth(h);
    await openSlip(h, 'Ali Hassan');
    expect(topText(h.t('dawam.frozenHint')), findsOneWidget);
    expect(sheetButton('Waive'), findsNothing);
    expect(sheetButton('Override'), findsNothing);
    expect(inTop(find.widgetWithText(DashButton, 'Bonus')), findsNothing);
    expect(
      inTop(find.widgetWithText(DashButton, 'Download PDF')),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-PAY-032/034/037 read only: no waive, no add, no delete', (
    tester,
  ) async {
    final s = payrollServer();
    answerAuthz(s.server, const ['hr.payroll.read']);
    final h = await pumpPayroll(tester, s: s);
    await openSlip(h, 'Laila Ehab');
    expect(sheetButton('Delete'), findsNothing);
    expect(inTop(find.widgetWithText(DashButton, 'Deduction')), findsNothing);
    await h.tap(find.bySemanticsLabel('Close').last);
    await openSlip(h, 'Ali Hassan');
    expect(sheetButton('Waive'), findsNothing);
    expect(inTop(find.widgetWithText(DashButton, 'Bonus')), findsNothing);
  });

  testWidgets('TEAM-PAY-034/037 bonuses only: Bonus yes, deductions no', (
    tester,
  ) async {
    final s = payrollServer();
    answerAuthz(s.server, const ['hr.payroll.read', 'hr.adjustments.create']);
    final h = await pumpPayroll(tester, s: s);
    await openSlip(h, 'Laila Ehab');
    expect(inTop(find.widgetWithText(DashButton, 'Bonus')), findsOneWidget);
    expect(inTop(find.widgetWithText(DashButton, 'Deduction')), findsNothing);
    // A manual DEDUCTION needs the deductions right to delete.
    expect(sheetButton('Delete'), findsNothing);
  });

  testWidgets('TEAM-MNY-034 a refused waiver keeps the dialog open', (
    tester,
  ) async {
    final s = payrollServer();
    final refusal = MockResponse.error(
      409,
      'That month is paid.',
      code: 'PERIOD_CLOSED',
      vars: {'paid': true},
    );
    s.server.fail('PATCH', waiveT, refusal);
    final h = await pumpPayroll(tester, s: s);
    await openSlip(h, 'Ali Hassan');
    await h.tap(sheetButton('Waive').first);
    await type<DashTextField>(h, 'Reason', 'x');
    await press(h, 'Waive');
    await h.expectToast(h.t('errors.codes.PERIOD_CLOSED_paid'));
    expect(inTop(find.textContaining('Waive "')), findsOneWidget);
  });
}
