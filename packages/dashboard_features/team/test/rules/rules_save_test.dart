// Saving the rules (TEAM-RUL-009, 035, 041…044; TEAM-ALL-014/019/026): what
// each save sends, the confirmation that lists the changes, the refusals,
// and what is asked again afterwards.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/rules/rules_cards.dart';
import 'package:dashboard_team/src/rules/rules_dawam_card.dart';
import 'package:dashboard_team/src/shared/staff_query.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rules_support.dart';

Future<void> save(DashHarness h) => tapKey(h, RulesKeys.save);

/// Answers `/authz/me` with only [caps], held everywhere.
void answerAuthz(MockServer server, List<String> caps) {
  server.on('GET', '/authz/me', (req) {
    final sorted = [...caps]..sort();
    return MockResponse.ok({
      'user_id': req.persona.userId,
      'branch_id': req.q('branch_id'),
      'capabilities': sorted,
      'everywhere': sorted,
      'ask_manager': <String>[],
      'limits': <String, Object?>{},
      'owner': false,
      'platform': false,
      'role_kinds': req.persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    });
  });
}

void main() {
  testWidgets('TEAM-RUL-043/044 the business: the confirmation lists each '
      'change, then one PUT of every rule; "Rules saved"; the reads asked '
      'again', (tester) async {
    final h = await pumpRules(tester);
    final gets = settingsGets(h);
    await typeIn(h, RulesKeys.workingDays, '22');
    await tapKey(h, RulesKeys.excused);
    await save(h);
    expect(find.text('Change the rules for everyone?'), findsOneWidget);
    expect(find.text(h.t('staff.rulesConfirmHint')), findsOneWidget);
    expect(find.text('Working days per month'), findsWidgets);
    expect(find.text('26 → 22'), findsOneWidget);
    expect(find.text('Yes → No'), findsOneWidget);
    await h.tap(find.text('Save the changes'));
    final body = puts(h).single;
    expect(body['working_days_per_month'], 22);
    expect(body['excused_time_paid_default'], false);
    expect(body['gender_mode'], 'soft');
    expect(body.containsKey('branch_id'), isFalse);
    expect(body['late_deduction_tiers'], hasLength(3));
    expect(body['night_start'], '22:00:00');
    await h.expectToast('Rules saved');
    expect(settingsGets(h), gets + 1);
    expect(shown(tester, RulesKeys.workingDays), '22');
    expect(find.text(h.t('staff.rulesAllSaved')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-043 Cancel sends nothing; the edit stays', (
    tester,
  ) async {
    final h = await pumpRules(tester);
    await typeIn(h, RulesKeys.workingDays, '22');
    await save(h);
    await h.tap(find.text('Cancel').last);
    expect(puts(h), isEmpty);
    expect(shown(tester, RulesKeys.workingDays), '22');
  });

  testWidgets('TEAM-RUL-043 the ladder reads "3 rungs → 3 rungs (edited)"; '
      'a night time on the 12-hour clock', (tester) async {
    final h = await pumpRules(tester);
    await typeIn(h, RulesKeys.tierAmount(0), '20');
    await save(h);
    expect(find.text('3 rungs → 3 rungs (edited)'), findsOneWidget);
    await h.tap(find.text('Cancel').last);
    await tapKey(h, RulesKeys.tierRemove(2));
    await typeIn(h, RulesDawamKeys.nightStart, '23:00');
    await save(h);
    expect(find.text('3 rungs → 2 rungs'), findsOneWidget);
    expect(find.text('10:00 PM → 11:00 PM'), findsOneWidget);
    await h.tap(find.text('Cancel').last);
  });

  testWidgets('TEAM-RUL-043 the very first business save asks nothing', (
    tester,
  ) async {
    final h = await pumpRules(tester, edit: neverSaved);
    await save(h);
    expect(find.text('Change the rules for everyone?'), findsNothing);
    final body = puts(h).single;
    expect(body['late_deduction_tiers'], hasLength(4));
    await h.expectToast('Rules saved');
    expect(pageText(h.t('dawam.rulesFirstTitle')), findsNothing);
  });

  testWidgets('TEAM-RUL-044 / TEAM-RUL-037 without hr.roster.settings the '
      'gender mode is off and never sent', (tester) async {
    final s = rulesServer();
    answerAuthz(s.server, ['hr.rules.edit', 'hr.rules.view']);
    final h = await pumpRules(tester, s: s);
    final gender = tester.widget<DashSegmentedControl<String>>(
      find.byWidgetPredicate(
        (w) =>
            w is DashSegmentedControl<String> &&
            w.semanticLabel == h.t('dawam.genderTitle'),
      ),
    );
    expect(gender.enabled, isFalse);
    await typeIn(h, RulesKeys.workingDays, '22');
    await save(h);
    await h.tap(find.text('Save the changes'));
    expect(puts(h).single.containsKey('gender_mode'), isFalse);
    await h.flushTimers();
  });

  testWidgets('TEAM-RUL-044 a branch sends only what it changed, plus the '
      'rules it hands back', (tester) async {
    final h = await pumpRules(tester);
    await pickIn(h, RulesKeys.scope, 'Zamalek · own rules');
    await typeIn(h, RulesKeys.workingDays, '24');
    await h.tap(find.bySemanticsLabel("Use the business's Hours a day"));
    await save(h);
    expect(find.text("Change Zamalek's rules?"), findsOneWidget);
    expect(find.text("Hours a day: back to the business's"), findsOneWidget);
    await h.tap(find.text('Save the changes'));
    expect(puts(h).single, {
      'working_days_per_month': 24,
      'branch_id': SeedIds.zamalek,
      'inherit': ['limit_day_hours'],
    });
    await h.expectToast('Rules saved');
    // The refetch: Hours a day is the business's again.
    expect(find.byKey(RulesKeys.chip('limit_day_hours')), findsNothing);
    expect(
      find.byKey(RulesKeys.chip('working_days_per_month')),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-RUL-042 a branch with nothing changed: "Nothing changed", '
      'no request', (tester) async {
    final h = await pumpRules(tester);
    await pickIn(h, RulesKeys.scope, 'Maadi');
    await save(h);
    await h.expectToast('Nothing changed');
    expect(puts(h), isEmpty);
  });

  testWidgets('TEAM-RUL-035 cover pay: a branch following the business picks '
      'its own (sent even at the same value); back to the business hands it '
      'back', (tester) async {
    final h = await pumpRules(tester);
    await pickIn(h, RulesKeys.scope, 'Maadi');
    expect(find.text(h.t('dawam.coverPayBusiness')), findsOneWidget);
    await tapKey(h, RulesDawamKeys.cover('minute_rate'));
    // The same value it runs on: nothing to list, so nothing to confirm.
    await save(h);
    expect(find.text('Save the changes'), findsNothing);
    expect(puts(h).last, {
      'cover_pay_mode': 'minute_rate',
      'branch_id': SeedIds.maadi,
    });
    await h.flushTimers();
    expect(find.byKey(RulesKeys.chip('cover_pay_mode')), findsOneWidget);
    await tapKey(h, RulesDawamKeys.cover(coverBusiness));
    await save(h);
    expect(find.text("Cover pay: back to the business's"), findsOneWidget);
    await h.tap(find.text('Save the changes'));
    expect(puts(h).last, {
      'branch_id': SeedIds.maadi,
      'inherit': ['cover_pay_mode'],
    });
    await h.flushTimers();
  });

  testWidgets('TEAM-RUL-041 Save with a value the form refuses: the first '
      'problem\'s words, no request', (tester) async {
    final h = await pumpRules(tester);
    await typeIn(h, RulesKeys.workingDays, '0');
    expect(pageText(h.t('staff.workingDaysPositive')), findsOneWidget);
    await save(h);
    await h.expectToast(h.t('staff.workingDaysPositive'));
    expect(puts(h), isEmpty);
  });

  testWidgets('TEAM-RUL-044 / TEAM-ALL-014/019 a refused rule is named by '
      'its page label, in the page\'s language', (tester) async {
    final h = await pumpRules(tester);
    await typeIn(h, RulesKeys.absenceDays, '40');
    await save(h);
    await h.tap(find.text('Save the changes'));
    await h.expectToast('Days docked per absence must be from 0 to 31.');
    await typeIn(h, RulesKeys.absenceDays, '1');
    await typeIn(h, RulesKeys.workingDays, '40');
    await save(h);
    await h.tap(find.text('Save the changes'));
    await h.expectToast(
      'Working days per month must be more than 0 and at most 31.',
    );
    // The form keeps what was typed.
    expect(shown(tester, RulesKeys.workingDays), '40');
  });

  testWidgets('TEAM-ALL-014 in Arabic the refusal reads in Arabic', (
    tester,
  ) async {
    final h = await pumpRules(tester, locale: 'ar');
    await typeIn(h, RulesKeys.absenceDays, '40');
    await save(h);
    await h.tap(find.text(h.t('staff.rulesConfirmSave')));
    await h.expectToast(
      h.t(
        'errors.codes.SETTING_OUT_OF_RANGE',
        args: {'field': h.t('staff.absenceDays'), 'min': 0, 'max': 31},
      ),
    );
  });

  testWidgets('TEAM-RUL-009 Follow the business: confirm, DELETE, "Rules '
      'saved", the chips gone', (tester) async {
    final h = await pumpRules(tester);
    await pickIn(h, RulesKeys.scope, 'Zamalek · own rules');
    await tapKey(h, RulesKeys.follow);
    expect(find.text("Zamalek follows the business's rules?"), findsOneWidget);
    expect(find.text(h.t('staff.rulesFollowBusinessHint')), findsOneWidget);
    await h.tap(find.text('Follow the business').last);
    expect(
      h.server.callsTo(deleteT).single.path,
      '/staff/attendance/settings/branches/${SeedIds.zamalek}',
    );
    await h.expectToast('Rules saved');
    expect(pageText(h.t('staff.rulesBranchNone')), findsOneWidget);
    expect(shown(tester, RulesKeys.autoBuffer), '60');
  });

  testWidgets('TEAM-RUL-009 a refused follow toasts the words; Cancel sends '
      'nothing', (tester) async {
    final s = rulesServer();
    final no = MockResponse.denied('hr.rules.edit');
    s.server.fail('DELETE', deleteT, no);
    final h = await pumpRules(tester, s: s);
    await pickIn(h, RulesKeys.scope, 'Zamalek · own rules');
    await tapKey(h, RulesKeys.follow);
    await h.tap(find.text('Cancel').last);
    expect(h.server.callsTo(deleteT), isEmpty);
    await tapKey(h, RulesKeys.follow);
    await h.tap(find.text('Follow the business').last);
    await h.expectToast(h.t('errors.unauthorized'));
    expect(find.byKey(RulesKeys.chip('limit_day_hours')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-044 / TEAM-ALL-026 leaving mid-save still invalidates '
      '/staff/attendance', (tester) async {
    final s = rulesServer();
    final gate = s.server.hold('PUT', settingsT);
    final h = await pumpRules(tester, s: s);
    await typeIn(h, RulesKeys.workingDays, '22');
    await save(h);
    await h.tap(find.text('Save the changes'));
    final before = h.container
        .read(staffRevisionsProvider)
        .revisionOf('/staff/attendance/settings');
    await h.go('/staff/shifts');
    gate.release();
    await h.settle();
    expect(
      h.container
          .read(staffRevisionsProvider)
          .revisionOf('/staff/attendance/settings'),
      before + 1,
    );
    expect(puts(h), hasLength(1));
  });

  testWidgets('TEAM-RUL-044 Save spins while the PUT is in flight', (
    tester,
  ) async {
    final s = rulesServer();
    final gate = s.server.hold('PUT', settingsT);
    final h = await pumpRules(tester, s: s);
    await typeIn(h, RulesKeys.workingDays, '22');
    await save(h);
    await h.tap(find.text('Save the changes'));
    expect(
      tester.widget<DashButton>(find.byKey(RulesKeys.save)).loading,
      isTrue,
    );
    gate.release();
    await h.settle();
    expect(
      tester.widget<DashButton>(find.byKey(RulesKeys.save)).loading,
      isFalse,
    );
    await h.flushTimers();
  });

  testWidgets('TEAM-ALL-021 Escape closes the confirmation, sending nothing', (
    tester,
  ) async {
    final h = await pumpRules(tester);
    await typeIn(h, RulesKeys.workingDays, '22');
    await save(h);
    expect(find.text('Save the changes'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.text('Save the changes'), findsNothing);
    expect(puts(h), isEmpty);
  });
}
