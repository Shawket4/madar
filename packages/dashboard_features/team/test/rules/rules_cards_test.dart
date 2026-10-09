// The Rules page's cards below the ladder (TEAM-RUL-020/021 the preview,
// 025 pay basis, 026 policies, 030…038 the Dawam rules), on the seeded
// mock: 26 working days, an 8-hour shift, EGP 12,000; the ladder 15–30 min
// → 30 minutes of pay, 31–60 → 0.25 day, 61+ → 0.5 day.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/rules/rules_cards.dart';
import 'package:dashboard_team/src/rules/rules_dawam_card.dart';
import 'package:dashboard_team/src/rules/rules_preview_card.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rules_support.dart';

Finder result() => find.byKey(RulesPreviewKeys.result);
Finder inResult(String s) =>
    find.descendant(of: result(), matching: find.text(s));
Finder segmented(DashHarness h, String labelKey) => find.byWidgetPredicate(
  (w) => w is DashSegmentedControl<String> && w.semanticLabel == h.t(labelKey),
);

void main() {
  testWidgets('TEAM-RUL-020 the preview card: its words and its three inputs '
      '(20 min, EGP 12,000, 8 h by default)', (tester) async {
    final h = await pumpRules(tester);
    expect(pageText('Try the ladder'), findsOneWidget);
    expect(pageText(h.t('staff.ladderPreviewHint')), findsOneWidget);
    expect(shown(tester, RulesPreviewKeys.late), '20');
    expect(shown(tester, RulesPreviewKeys.salary), contains('12,000'));
    expect(shown(tester, RulesPreviewKeys.shift), '8');
    for (final p in ['5 min', '20 min', '45 min']) {
      expect(pageText(p), findsWidgets, reason: p);
    }
  });

  testWidgets('TEAM-RUL-021 the verdict: rung 1 docks EGP 28.85 at 20 min; '
      'nothing before the first rung; on time at 0', (tester) async {
    final h = await pumpRules(tester);
    // 1,200,000 × 30 / (26 × 480) = 2,884.6 → 2,885.
    expect(inResult('rung 1: docks EGP 28.85'), findsOneWidget);
    await typeIn(h, RulesPreviewKeys.late, '45');
    // 1,200,000 × 0.25 / 26 = 11,538.5 → EGP 115.38.
    expect(inResult('rung 2: docks EGP 115.38'), findsOneWidget);
    await typeIn(h, RulesPreviewKeys.late, '5');
    expect(inResult(h.t('staff.previewNoRung')), findsOneWidget);
    await typeIn(h, RulesPreviewKeys.late, '0');
    expect(inResult(h.t('staff.previewOnTime')), findsOneWidget);
    // One sample per rung, from its first minute.
    expect(
      find.descendant(
        of: find.byKey(RulesPreviewKeys.sample(2)),
        matching: find.text('EGP 230.77'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-RUL-021 a different salary or shift reprices every rung; '
      'the working days come from the form', (tester) async {
    final h = await pumpRules(tester);
    await typeIn(h, RulesPreviewKeys.salary, '6000');
    // 600,000 × 30 / (26 × 480) = 1,442.3.
    expect(inResult('rung 1: docks EGP 14.42'), findsOneWidget);
    await typeIn(h, RulesPreviewKeys.shift, '6');
    // 600,000 × 30 / (26 × 360) = 1,923.1.
    expect(inResult('rung 1: docks EGP 19.23'), findsOneWidget);
    await typeIn(h, RulesKeys.workingDays, '20');
    // 600,000 × 30 / (20 × 360) = 2,500.
    expect(inResult('rung 1: docks EGP 25.00'), findsOneWidget);
  });

  testWidgets('TEAM-RUL-025 pay basis: the three fields, the absence example, '
      'and each field\'s check', (tester) async {
    final h = await pumpRules(tester);
    expect(pageText('Pay basis'), findsOneWidget);
    expect(shown(tester, RulesKeys.workingDays), '26');
    expect(shown(tester, RulesKeys.absenceDays), '1');
    expect(shown(tester, RulesKeys.autoBuffer), '60');
    // 1,200,000 / 26 = 46,153.8 → EGP 461.54.
    expect(
      pageText('An absence docks about EGP 461.54 on the example salary.'),
      findsOneWidget,
    );
    await typeIn(h, RulesKeys.absenceDays, '0.5');
    expect(
      pageText('An absence docks about EGP 230.77 on the example salary.'),
      findsOneWidget,
    );
    await typeIn(h, RulesKeys.workingDays, '0');
    expect(pageText(h.t('staff.workingDaysPositive')), findsOneWidget);
    await typeIn(h, RulesKeys.autoBuffer, '-15');
    expect(pageText(h.t('staff.autoBufferRange')), findsOneWidget);
    expect(find.text(h.t('staff.rulesFixFirst')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-026 policies: the fence line, and the paid-permission '
      'switch marks the form unsaved', (tester) async {
    final h = await pumpRules(tester);
    expect(pageText(h.t('staff.fenceAlwaysOn')), findsOneWidget);
    expect(pageText(h.t('staff.excusedPaidHint')), findsOneWidget);
    expect(tester.widget<DashSwitch>(find.byKey(RulesKeys.excused)).value,
        isTrue);
    await tapKey(h, RulesKeys.excused);
    expect(tester.widget<DashSwitch>(find.byKey(RulesKeys.excused)).value,
        isFalse);
    expect(find.text(h.t('staff.rulesUnsaved')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-030 the Dawam card: "Overtime is off" only while it '
      'is off; three overtime choices', (tester) async {
    final h = await pumpRules(tester);
    expect(pageText('Overtime, holidays and pay'), findsOneWidget);
    expect(find.textContaining(h.t('dawam.setupOtOff')), findsNothing);
    expect(find.textContaining(h.t('dawam.rulesHintRates')), findsOneWidget);
    final ot = segmented(h, 'dawam.overtime');
    expect(tester.widget<DashSegmentedControl<String>>(ot).value, 'approval');
    await tester.ensureVisible(ot);
    await h.tap(find.descendant(of: ot, matching: find.text('Off')));
    expect(find.textContaining(h.t('dawam.setupOtOff')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-031 the rates and their "1 h pays" hints; the night '
      'hint shows the window', (tester) async {
    final h = await pumpRules(tester);
    expect(pageText('1 h pays 1.35 h'), findsOneWidget);
    expect(pageText('1 h pays 2 h'), findsOneWidget);
    expect(find.textContaining('1 h pays 1.7 h · 10:00 PM'), findsOneWidget);
    await typeIn(h, RulesDawamKeys.number('otDay'), '1.5');
    expect(pageText('1 h pays 1.5 h'), findsOneWidget);
  });

  testWidgets('TEAM-RUL-032/037 business only: the advance cap, the pay '
      'period start and gender; a branch hides them', (tester) async {
    final h = await pumpRules(tester);
    expect(find.byKey(RulesDawamKeys.number('advanceCap')), findsOneWidget);
    expect(find.byKey(RulesDawamKeys.number('periodStartDay')), findsOneWidget);
    expect(pageText(h.t('dawam.genderHint')), findsOneWidget);
    expect(
      tester.widget<DashSegmentedControl<String>>(segmented(h, 'dawam.genderTitle')).enabled,
      isTrue,
    );
    await pickIn(h, RulesKeys.scope, 'Maadi');
    expect(find.byKey(RulesDawamKeys.number('advanceCap')), findsNothing);
    expect(find.byKey(RulesDawamKeys.number('periodStartDay')), findsNothing);
    expect(pageText(h.t('dawam.genderHint')), findsNothing);
  });

  testWidgets('TEAM-RUL-033/034 half-day leave and the night window', (
    tester,
  ) async {
    final h = await pumpRules(tester);
    final half = segmented(h, 'dawam.halfDayLeave');
    expect(tester.widget<DashSegmentedControl<String>>(half).value,
        'half_shift');
    await tester.ensureVisible(half);
    await h.tap(find.descendant(of: half, matching: find.text('The whole day')));
    expect(tester.widget<DashSegmentedControl<String>>(half).value,
        'whole_day');
    expect(pageText(h.t('dawam.nightUnconfirmed')), findsOneWidget);
    await typeIn(h, RulesDawamKeys.nightEnd, '05:00');
    expect(find.textContaining('10:00 PM – 05:00 AM'), findsOneWidget);
  });

  testWidgets('TEAM-RUL-035 cover pay: two choices for the business, three '
      'for a branch (following the business picked)', (tester) async {
    final h = await pumpRules(tester);
    expect(find.byKey(RulesDawamKeys.cover(coverBusiness)), findsNothing);
    expect(pageText(h.t('dawam.coverPayMinuteHint')), findsOneWidget);
    expect(pageText(h.t('dawam.coverPayBlockHint')), findsOneWidget);
    await pickIn(h, RulesKeys.scope, 'Maadi');
    expect(find.byKey(RulesDawamKeys.cover(coverBusiness)), findsOneWidget);
    expect(pageText(h.t('dawam.coverPayBusinessHint')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-036 the labour limits and orders per person', (
    tester,
  ) async {
    final h = await pumpRules(tester);
    expect(pageText(h.t('dawam.limitsHint')), findsOneWidget);
    expect(shown(tester, RulesDawamKeys.number('limitDay')), '12');
    expect(shown(tester, RulesDawamKeys.number('limitWeek')), '60');
    expect(shown(tester, RulesDawamKeys.number('ordersPerStaff')), '25');
    expect(pageText(h.t('dawam.ordersPerStaffHint')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-038 the Dawam card\'s checks: one message under it', (
    tester,
  ) async {
    final h = await pumpRules(tester);
    Future<void> expectProblem(String key, String field, String text) async {
      await typeIn(h, RulesDawamKeys.number(field), text);
      expect(pageText(h.t(key)), findsOneWidget, reason: key);
    }

    await expectProblem('dawam.rulesRateLow', 'otNight', '0.9');
    await typeIn(h, RulesDawamKeys.number('otNight'), '1.7');
    await expectProblem('dawam.rulesCapRange', 'advanceCap', '120');
    await typeIn(h, RulesDawamKeys.number('advanceCap'), '50');
    await expectProblem('dawam.rulesStartDay', 'periodStartDay', '30');
    await typeIn(h, RulesDawamKeys.number('periodStartDay'), '1');
    await expectProblem('dawam.rulesLimitRange', 'limitWeek', '200');
    await typeIn(h, RulesDawamKeys.number('limitWeek'), '60');
    await expectProblem('dawam.rulesOrdersPerStaff', 'ordersPerStaff', '0');
    await typeIn(h, RulesDawamKeys.number('ordersPerStaff'), '25');
    expect(find.text(h.t('staff.rulesFixFirst')), findsNothing);
  });

  testWidgets('TEAM-RUL-001 a viewer (manager) is not refused', (
    tester,
  ) async {
    final h = await pumpRules(tester, persona: Persona.manager);
    expect(pageText('Overtime, holidays and pay'), findsOneWidget);
    expect(h.server.callsTo(settingsT).last.status, 200);
  });
}
