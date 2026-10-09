// The Team board's screenshot matrix: the default state at every size in
// English light and Arabic dark, plus each dialog and state at desktop-en-light
// and phone-ar-light. Run with FDASH_SHOTS set, then look at the PNGs.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'team_board_support.dart';

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpTeam(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    testWidgets('flag dialog (deduct), ${size.name} $lang', (tester) async {
      final h = await pumpTeam(tester, size: size, locale: lang);
      await h.tap(rowOf('Karim Adel · ${h.t('dawam.flag_left_mid_shift')}'));
      await h.shot('team_board/flag-deduct');
    });

    testWidgets('flag dialog (cover), ${size.name} $lang', (tester) async {
      final h = await pumpTeam(
        tester,
        size: size,
        locale: lang,
        edit: (db) => addFlag(db, 'cover', kind: 'cover', employeeKey: 'ziad'),
      );
      await h.tap(rowOf('Ziad Amr · ${h.t('dawam.flag_cover')}'));
      await h.shot('team_board/flag-cover');
    });

    testWidgets('own flag, ${size.name} $lang', (tester) async {
      final h = await pumpTeam(
        tester,
        persona: Persona.manager,
        size: size,
        locale: lang,
      );
      await h.tap(rowOf('Karim Adel · ${h.t('dawam.flag_left_mid_shift')}'));
      await h.shot('team_board/flag-own');
    });

    testWidgets('punch dialog, ${size.name} $lang', (tester) async {
      final h = await pumpTeam(tester, size: size, locale: lang);
      await h.tap(inRow('Tarek Saber', boardButton(h.t('dawam.punchIn'))));
      await h.shot('team_board/punch');
    });

    testWidgets('failed and banner, ${size.name} $lang', (tester) async {
      final s = teamServer(
        edit: (db) {
          for (final r in db['attendance_settings'].rows) {
            r['rules_saved_at'] = null;
          }
        },
      );
      s.server.fail(
        'GET',
        presenceT,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      s.server.fail(
        'GET',
        flagsT,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpTeam(tester, size: size, locale: lang, s: s);
      await shootPage(h, 'failed');
    });

    testWidgets('empty, ${size.name} $lang', (tester) async {
      final h = await pumpTeam(
        tester,
        size: size,
        locale: lang,
        edit: (db) {
          db['schedule_assignments'].clear();
          db['attendance_records'].clear();
          db['attendance_flags'].clear();
        },
      );
      await shootPage(h, 'empty');
    });

    testWidgets('loading, ${size.name} $lang', (tester) async {
      final s = teamServer();
      final a = s.server.hold('GET', presenceT);
      final b = s.server.hold('GET', flagsT);
      final h = await pumpTeam(tester, size: size, locale: lang, s: s);
      await h.shot('team_board/loading');
      a.release();
      b.release();
      await h.settle();
    });
  }
}
