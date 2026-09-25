// H2-11: the owner's Payroll tab approved the month and deleted a manual pay
// line without waiting for the server: a refusal came as a stray toast, and
// a success said nothing. Both now wait: the server's words on a refusal,
// what happened on a success, in the phone's language.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

/// The owner's Manage side: Team, Approvals, Schedule, Payroll.
const _payrollTab = 3;

final _refusal = DawamError(
  'This month is already approved.',
  'الشهر ده اتعمد خلاص.',
);

Future<void> _tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await frames(t);
}

void main() {
  useCoreWords();
  setUpAll(initializeDateFormatting);

  for (final lang in ['en', 'ar']) {
    testWidgets('approving the month waits and says so · $lang', (t) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e3',
        manage: true,
        tab: _payrollTab,
        size: const Size(1180, 820),
      );
      await frames(t);
      await _tapText(t, tr('staff.pay_out'));
      Future<void> approve() async {
        await _tapText(t, tr('staff.approve_payroll'));
        await _tapText(t, tr('staff.approve_payroll_confirm'));
      }

      testCore.refuse = _refusal;
      await approve();
      expect(lastAct(), {'action': 'approve_payroll'});
      expect(find.text(loc(_refusal)), findsOneWidget);

      testCore.refuse = null;
      await approve();
      expect(find.text(tr('staff.approved_payslips_frozen')), findsWidgets);
      await finish(t);
    });

    testWidgets('deleting a manual line waits and says so · $lang', (t) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e3',
        manage: true,
        tab: _payrollTab,
        size: const Size(1180, 820),
        core: (f) => f.edit = (v) {
          for (final s in v['slips'] as List<dynamic>) {
            if ((s as Map<String, dynamic>)['emp'] != 'e4') continue;
            (s['lines'] as List<dynamic>).add({
              'amount': -20000,
              'ar': 'كسر كوباية',
              'date': null,
              'en': 'Broke a glass',
              'key': 'd|a1',
              'manual': 'a|deduction|a1',
              'rule': false,
              'waived': false,
            });
          }
        },
      );
      await frames(t);
      final store = testContainer.read(dawamProvider);
      Future<void> delete() async {
        await _tapText(t, name(store.emp('e4')));
        await _tapText(t, isAr ? 'كسر كوباية' : 'Broke a glass');
        await _tapText(t, tr('staff.delete'));
      }

      testCore.refuse = _refusal;
      await delete();
      expect(lastAct(), {'action': 'delete_adj', 'adj': 'a|deduction|a1'});
      expect(find.text(loc(_refusal)), findsOneWidget);
      await t.tapAt(const Offset(10, 10)); // close the slip
      await frames(t);

      testCore.refuse = null;
      await delete();
      expect(find.text(tr('staff.line_deleted')), findsOneWidget);
      await finish(t);
    });
  }
}
