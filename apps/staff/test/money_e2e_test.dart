// Money bugs the E2E campaign found in the real app (dawam-fix/e2e/campaign/
// REPORT-money.md), each pinned here first:
//
//  CB1  a bonus/deduction over the manager's limit said "Added" although the
//       server parked it for the owner (AD-5);
//  CB3  the owner's payroll listed and counted people the server left out of
//       the run (not on payroll, owner decision 2 / PAY-9);
//  CB4  a waived line never said "Waived" (AD-8);
//  CB5  the owner's 0-net payslip, settled by the server with the method
//       'none', read "Paid · Cash" and hid Reopen (PAY-6, PAY-7, D16);
//  CB6  stopping an every-month line sent no reason, which the server
//       refuses, and the refusal was swallowed: nothing happened (AD-3, AD-9);
//  CB2  the toast (and the keyboard's Done bar) sat above the Navigator with
//       no Material: its words took the fallback style's yellow underline.
import 'dart:async';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

import 'support.dart';

/// The owner's Manage side: Team, Approvals, Schedule, Payroll.
const _payrollTab = 3;

/// The real Plex faces (as sheets_test): the test font's square glyphs are
/// far wider than real text and would overflow rows that fit on a phone.
Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File(
        '../../packages/design_system/assets/fonts/$family-$cut.ttf',
      );
      if (file.existsSync()) {
        loader.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await loader.load();
  }
}

void main() {
  useCoreWords();
  setUpAll(_loadFonts);

  testWidgets(
    'CB1: a line over the limit is said to wait for the owner, never "Added"',
    (t) async {
      final c = await pumpApp(t, lang: 'en', who: 'e2', manage: true);
      final store = c.read(dawamProvider);
      Future<void> add(String amount) async {
        unawaited(
          adjustmentSheet(
            t.element(find.byType(MadarShellScaffold)),
            emp: 'e1',
          ),
        );
        await frames(t);
        await t.tap(find.text(tr('staff.deduction')).last);
        await frames(t);
        final fields = find.byType(EditableText);
        await t.enterText(fields.at(0), amount);
        await t.enterText(fields.last, 'broken cups');
        await t.tap(find.text(tr('staff.add')).last);
        await frames(t);
      }

      // The server parked it: pending, for the owner.
      testCore.filed = {
        'id': 'a|deduction|d1',
        'status': 'pending',
        'to_owner': false,
      };
      await add('1000.01');
      expect(lastAct()['action'], 'add_adjustment');
      expect(
        find.text(tr('staff.added')),
        findsNothing,
        reason: 'a pending line is not added yet',
      );
      expect(
        find.text(
          tr('staff.over_waits_for_the_owner_before', {
            'amount': egp(store.managerDeductLimit),
          }),
        ),
        findsWidgets,
        reason: 'the toast says it waits for the owner',
      );
      await frames(t, 80);

      // Within the limit: counted at once, "Added".
      testCore.filed = {
        'id': 'a|deduction|d2',
        'status': 'approved',
        'to_owner': false,
      };
      await add('50');
      expect(find.text(tr('staff.added')), findsOneWidget);
      await finish(t);
    },
  );

  testWidgets('CB3: payroll lists and counts only the people the server paid', (
    t,
  ) async {
    final c = await pumpApp(
      t,
      lang: 'en',
      who: 'e3',
      manage: true,
      tab: _payrollTab,
    );
    await frames(t);
    final store = c.read(dawamProvider);
    // e3 (the owner) is visible but the server sent no slip for her.
    expect(store.visibleEmps.map((e) => e.id), contains('e3'));
    expect(
      find.ancestor(
        of: find.text(name(store.emp('e3'))),
        matching: find.byType(MadarListRow),
      ),
      findsNothing,
      reason: 'not in the run → not listed',
    );
    expect(
      find.text('4'),
      findsWidgets,
      reason: 'People = the server\'s 4 slips',
    );
    expect(find.text('0/4'), findsOneWidget);
    await finish(t);
  });

  testWidgets('CB4: a waived line says Waived', (t) async {
    await pumpApp(
      t,
      lang: 'en',
      who: 'e1',
      tab: 4,
      core: (f) => f.edit = (v) {
        final slip = (v['slips'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((s) => s['frozen'] != true);
        (slip['lines'] as List).add({
          'key': 'd|w1',
          'en': 'Late by 17 minutes',
          'ar': 'تأخير 17 دقيقة',
          'amount': -3125,
          'rule': true,
          'waived': true,
          'date': '2026-09-24',
        });
      },
    );
    await frames(t);
    final line = find.textContaining('Late by 17 minutes');
    await t.scrollUntilVisible(
      line,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(tr('staff.waived_short')), findsOneWidget);
    await finish(t);
  });

  testWidgets(
    'CB5: the server-settled 0-net payslip reads "Nothing to pay" and Reopen stays',
    (t) async {
      await pumpApp(
        t,
        lang: 'en',
        who: 'e3',
        manage: true,
        tab: _payrollTab,
        core: (f) => f.edit = (v) {
          v['period']['status'] = 'approved';
          v['period']['paid_by'] = {'e5': 'none'};
          for (final s in (v['slips'] as List).cast<Map<String, dynamic>>()) {
            s['frozen'] = true;
            if (s['emp'] == 'e5') s['net'] = 0;
          }
          // Only the current period's frozen slips (drop the old one).
          v['slips'] = (v['slips'] as List)
              .where((s) => s['start'] == v['period']['start'])
              .toList();
        },
      );
      await frames(t);
      await t.ensureVisible(find.text(tr('staff.pay_out')));
      await t.tap(find.text(tr('staff.pay_out')));
      await frames(t);
      expect(
        find.text(tr('staff.paid_with_method', {'method': tr('staff.cash')})),
        findsNothing,
        reason: 'nobody was paid cash',
      );
      expect(find.text(tr('staff.nothing_to_pay')), findsWidgets);
      await t.scrollUntilVisible(
        find.text(tr('staff.reopen_payroll')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(tr('staff.reopen_payroll')),
        findsOneWidget,
        reason:
            'a 0-net slip settled by the server never blocks reopening (D16)',
      );
      await finish(t);
    },
  );

  testWidgets('CB6: stopping an every-month line asks why and sends it', (
    t,
  ) async {
    await pumpApp(
      t,
      lang: 'en',
      who: 'e3',
      manage: true,
      tab: _payrollTab,
      core: (f) => f.edit = (v) {
        (v['adjustments'] as List).add({
          'amount': 30000,
          'at': '2026-09-24T12:00:00+03:00',
          'bonus': true,
          'by': 'e3',
          'emp': 'e1',
          'id': 'a|bonus|m1',
          'pct': null,
          'period': '2026-09-24',
          'reason': 'Meal allowance',
          'recurring': true,
          'status': 'active',
          'value': 30000,
          'waived': false,
        });
      },
    );
    await frames(t);
    await t.tap(find.text(tr('staff.adjustments')));
    await frames(t);
    final row = find.textContaining('Meal allowance');
    await t.ensureVisible(row.first);
    await t.tap(row.first);
    await frames(t);
    // No reason: refused on the phone, nothing sent.
    final n = testCore.acts.length;
    await t.tap(find.text(tr('staff.stop')).last);
    await frames(t);
    expect(find.text(tr('staff.a_reason_is_required')), findsWidgets);
    expect(testCore.acts.length, n);
    await t.enterText(find.byType(EditableText).last, 'moved to a meal card');
    await t.tap(find.text(tr('staff.stop')).last);
    await frames(t);
    expect(lastAct(), {
      'action': 'stop_adj',
      'adj': 'a|bonus|m1',
      'reason': 'moved to a meal card',
    });
    await finish(t);
  });

  testWidgets('CB2: a toast is not underlined (no fallback text style)', (
    t,
  ) async {
    final c = await pumpApp(t, lang: 'en', who: 'e1');
    await frames(t);
    c.read(toastProvider.notifier).show('Added', tone: ChipTone.success);
    await frames(t);
    final e = t.element(find.text('Added'));
    final style = DefaultTextStyle.of(e).style.merge((e.widget as Text).style);
    expect(
      style.decoration,
      anyOf(isNull, TextDecoration.none),
      reason: 'the yellow double underline of a Text with no Material',
    );
    await frames(t, 120);
    await finish(t);
  });
}
