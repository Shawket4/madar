// H2-P1: after the month rolled over, an older month still a draft (or
// approved with someone unpaid) could not be approved or paid from the app:
// every action named the current month. The owner's Payroll tab says which
// older month isn't fully paid yet and opens it with its own actions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

const _payrollTab = 3;

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
    testWidgets('an older unpaid month opens with its actions · $lang', (
      t,
    ) async {
      await pumpApp(
        t,
        lang: lang,
        who: 'e3',
        manage: true,
        tab: _payrollTab,
        size: const Size(1180, 820),
        core: (f) => f.edit = (v) {
          (v['history'] as List<dynamic>).add({
            'end': '2026-07-25',
            'id': 'p0',
            'paid_by': <String, dynamic>{},
            'start': '2026-06-26',
            'status': 'open',
          });
          final slip = Map<String, dynamic>.of(
            (v['slips'] as List<dynamic>).first as Map<String, dynamic>,
          );
          (v['slips'] as List<dynamic>).add({
            ...slip,
            'start': '2026-06-26',
            'end': '2026-07-25',
            'frozen': false,
            'net': 777700,
          });
          v['unsettled'] = [
            {
              'id': 'p0',
              'start': '2026-06-26',
              'end': '2026-07-25',
              'status': 'open',
              'net': 777700,
              'paid_count': 0,
              'people': 1,
            },
          ];
        },
      );
      await frames(t);
      final older =
          '${dayMonth(DateTime(2026, 6, 26))} – ${dayMonth(DateTime(2026, 7, 25))}';
      final banner = tr('staff.unsettled_title', {'period': older});
      expect(find.text(banner), findsOneWidget);
      await _tapText(t, banner);
      expect(find.text(older), findsWidgets, reason: 'that month is open');
      await _tapText(t, tr('staff.pay_out'));
      await _tapText(t, tr('staff.approve_payroll'));
      await _tapText(t, tr('staff.approve_payroll_confirm'));
      expect(lastAct(), {'action': 'approve_payroll', 'period': 'p0'});
      await _tapText(t, tr('staff.back_to_this_month'));
      expect(find.text(banner), findsOneWidget, reason: 'back on this month');
      await finish(t);
    });
  }

  testWidgets('no older month to settle: no banner', (t) async {
    await pumpApp(
      t,
      lang: 'en',
      who: 'e3',
      manage: true,
      tab: _payrollTab,
      size: const Size(1180, 820),
    );
    await frames(t);
    expect(find.textContaining("isn't fully paid yet"), findsNothing);
    await finish(t);
  });
}
