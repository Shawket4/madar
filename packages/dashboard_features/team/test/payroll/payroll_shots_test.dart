// The Payroll screenshot matrix: the default page at every size in
// {en light, ar dark}; every other state, sheet and dialog at
// desktop-en-light and phone-ar-light.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payroll_support.dart';

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpPayroll(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          edit: septemberUnpaid,
        );
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [(DashSize.desktop, 'en'), (DashSize.phone, 'ar')]) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(WidgetTester tester, {Srv? s}) =>
        pumpPayroll(tester, size: size, locale: lang, s: s);

    testWidgets('loading, $tag', (tester) async {
      final s = payrollServer();
      final gate = s.server.hold('GET', currentT);
      final h = await open(tester, s: s);
      await h.shot('payroll/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = payrollServer();
      s.server.fail('GET', currentT, MockResponse.error(500, 'boom'));
      final h = await open(tester, s: s);
      await h.shot('payroll/failed');
    });

    testWidgets('refused, $tag', (tester) async {
      final h = await pumpPayroll(
        tester,
        persona: Persona.manager,
        size: size,
        locale: lang,
      );
      await h.shot('payroll/refused');
    });

    testWidgets('approved, $tag', (tester) async {
      final h = await open(tester);
      await approveMonth(h);
      await shootPage(h, 'approved');
    });

    testWidgets('approve confirm, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inPage(find.widgetWithText(DashButton, h.t('dawam.approve'))));
      await h.shot('payroll/approve-confirm');
    });

    testWidgets('payslip sheet, $tag', (tester) async {
      final h = await open(tester);
      await openSlip(h, 'Ali Hassan');
      await h.shot('payroll/payslip');
    });

    testWidgets('pay-line dialog, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(pageText(h.t('dawam.payLines')));
      await h.tap(inPage(find.widgetWithText(DashButton, h.t('dawam.addPayLine'))));
      await h.shot('payroll/pay-line');
    });

    testWidgets('mark paid dialog, $tag', (tester) async {
      final h = await open(tester);
      await approveMonth(h);
      await h.tap(inPage(find.widgetWithText(DashButton, h.t('dawam.markPaid'))).first);
      await h.shot('payroll/mark-paid');
    });

    for (final (tab, name) in [
      ('dawam.payLines', 'lines'),
      ('dawam.salaryAdvances', 'advances'),
      ('dawam.expenseAdvances', 'expenses'),
      ('dawam.history', 'history'),
    ]) {
      testWidgets('$name tab, $tag', (tester) async {
        final h = await open(tester);
        await h.tap(pageText(h.t(tab)));
        await shootPage(h, name);
      });
    }

    testWidgets('advance review and expense dialogs, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(pageText(h.t('dawam.salaryAdvances')));
      await h.tap(inPage(find.widgetWithText(DashButton, h.t('dawam.review'))).first);
      await h.shot('payroll/review-advance');
    });

    testWidgets('expense dialog, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(pageText(h.t('dawam.expenseAdvances')));
      await h.tap(inPage(find.widgetWithText(DashButton, h.t('dawam.logExpense'))));
      await h.shot('payroll/log-expense');
    });

    testWidgets('history sheet, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(pageText(h.t('dawam.history')));
      await h.tap(inPage(find.textContaining('2026')).first);
      await h.shot('payroll/history-sheet');
    });
  }
}
