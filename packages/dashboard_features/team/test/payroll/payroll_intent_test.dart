// Intent warming on the Payroll page: the mouse resting on a tab, an
// "Open it" banner button or a History row starts that exact read, and the
// press then asks the server nothing more.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payroll_support.dart';

void main() {
  testWidgets('tabs, "Open it" and History rows warm their reads; the press '
      'asks nothing more', (tester) async {
    final h = await pumpPayroll(tester, edit: septemberUnpaid);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    Future<void> rest(Finder f) async {
      await mouse.moveTo(tester.getCenter(f));
      await tester.pump(const Duration(milliseconds: 120));
      await h.settle();
    }

    for (final (tab, read) in [
      ('Bonuses & deductions', linesT),
      ('Salary advances', advancesT),
      ('Expense advances', expensesT),
    ]) {
      expect(h.server.callsTo(read), isEmpty, reason: tab);
      await rest(pageText(tab));
      expect(h.server.callsTo(read), hasLength(1), reason: '$tab warmed');
      await h.tap(pageText(tab));
      expect(h.server.callsTo(read), hasLength(1), reason: '$tab from cache');
    }

    await h.tap(pageText('Payslips'));
    expect(h.server.callsTo(payslipsT), isEmpty);
    await rest(pageText('Open it'));
    expect(h.server.callsTo(payslipsT), hasLength(1));
    await h.tap(pageText('Open it'));
    expect(h.server.callsTo(payslipsT), hasLength(1));
    await h.tap(pageText('Back to this month'));

    // A settled month's sheet (August) from History.
    await h.tap(pageText('History'));
    final before = h.server.callsTo(payslipsT).length;
    await rest(pageText('August 2026'));
    expect(h.server.callsTo(payslipsT), hasLength(before + 1));
    await h.tap(pageText('August 2026'));
    expect(h.server.callsTo(payslipsT), hasLength(before + 1));
  });
}
