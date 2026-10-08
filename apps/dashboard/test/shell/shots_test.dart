// The frame's screenshot matrix: {phone, tablet, desktop} x {en light,
// ar dark} for the signed-in frame and the sign-in page, and the open states
// (palette, user menu, theme menu, scope controls, drawer, gates) at
// desktop-en-light and phone-ar-light. Shots are written only with
// FDASH_SHOTS set; the pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('frame, $tag', (tester) async {
        final h = await pumpShell(tester, size: size, locale: lang, dark: dark);
        await h.shot('frame/home');
        await h.go('/reports/staff-pool');
        await h.shot('frame/nested-active');
      });
      testWidgets('sign-in, $tag', (tester) async {
        final h = await pumpShell(
          tester,
          persona: null,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.shot('sign-in/default');
      });
      testWidgets('platform admin, $tag', (tester) async {
        final h = await pumpShell(
          tester,
          persona: Persona.platform,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.shot('frame/platform');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';
    final phone = size == DashSize.phone;
    testWidgets('open states, $tag', (tester) async {
      final h = await pumpShell(tester, size: size, locale: lang);
      final t = h.t;
      // The palette.
      await h.tap(
        labelled(phone ? t('shell.searchPages') : t('common.search')).first,
      );
      await h.shot('open/palette');
      await h.tap(labelled(t('common.close')).last);
      // The user menu.
      await h.tap(labelled(t('common.account')));
      await h.shot('open/user-menu');
      await tester.tapAt(const Offset(5, 400));
      await h.settle();
      // The theme menu.
      await h.tap(labelled(t('theme.toggle')));
      await h.shot('open/theme-menu');
      await tester.tapAt(const Offset(5, 400));
      await h.settle();
      if (phone) {
        await h.tap(labelled(t('common.filters')));
        await h.shot('open/filters');
        await h.tap(labelled(t('common.close')).last);
        await h.tap(labelled(t('common.more')).last);
        await h.settle(rounds: 12);
        await h.shot('open/drawer');
      } else {
        await h.tapText(t('scope.allBranches'));
        await h.shot('open/branch');
        await tester.tapAt(const Offset(5, 400));
        await h.settle();
        await h.tapText(t('scope.preset.30d'));
        await h.shot('open/period');
      }
    });

    testWidgets('gates, $tag', (tester) async {
      var h = await pumpShell(
        tester,
        size: size,
        locale: lang,
        path: '/nowhere',
      );
      await h.shot('gates/not-found');
      h = await pumpShell(
        tester,
        size: size,
        locale: lang,
        path: '/inventory/today',
        persona: Persona.limited,
      );
      await h.shot('gates/restricted');
      h = await pumpShell(
        tester,
        size: size,
        locale: lang,
        path: '/orders',
        persona: Persona.dawamOnly,
      );
      await h.shot('gates/module-off');
    });
  }
}
