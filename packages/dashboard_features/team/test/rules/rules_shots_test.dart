// The Rules screenshot matrix: the page at every size in EN light and AR
// dark, then each state and dialog at desktop-en-light and phone-ar-light.
// Writes PNGs only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/src/rules/rules_cards.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rules_support.dart';

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpRules(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    testWidgets('loading and error, ${size.name} $lang', (tester) async {
      final s = rulesServer();
      final gate = s.server.hold('GET', settingsT);
      var h = await pumpRules(tester, s: s, size: size, locale: lang);
      await h.shot('rules/loading');
      gate.release();
      await h.settle();
      final f = rulesServer();
      f.server.fail('GET', settingsT, MockResponse.error(500, 'boom'));
      h = await pumpRules(tester, s: f, size: size, locale: lang);
      await h.shot('rules/error');
    });

    testWidgets('never saved, read-only, ${size.name} $lang', (tester) async {
      var h = await pumpRules(
        tester,
        size: size,
        locale: lang,
        edit: neverSaved,
      );
      await h.shot('rules/never-saved');
      h = await pumpRules(
        tester,
        size: size,
        locale: lang,
        persona: Persona.manager,
      );
      await h.shot('rules/read-only');
    });

    testWidgets('a branch, errors and dialogs, ${size.name} $lang', (
      tester,
    ) async {
      final h = await pumpRules(tester, size: size, locale: lang);
      await typeIn(h, RulesKeys.tierFrom(1), '20');
      await typeIn(h, RulesKeys.workingDays, '0');
      await shootPage(h, 'errors');
      await pickIn(
        h,
        RulesKeys.scope,
        h.t('staff.rulesBranchOwn', args: {'name': 'Zamalek'}),
      );
      await h.tap(
        find.bySemanticsLabel(
          h.t('staff.rulesInherit', args: {'rule': h.t('dawam.limitDay')}),
        ),
      );
      await typeIn(h, RulesKeys.workingDays, '24');
      await shootPage(h, 'branch');
      await tapKey(h, RulesKeys.save);
      await h.shot('rules/confirm');
      await h.tap(find.text(h.t('common.cancel')).last);
      await tapKey(h, RulesKeys.follow);
      await h.shot('rules/follow');
      await h.tap(find.text(h.t('common.cancel')).last);
    });
  }
}
