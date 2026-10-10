// The Reports page's screenshot matrix: the default state at every size in
// English light and Arabic dark, and every other state (loading, failed,
// empty, each tab, a backwards range, the refusal) at desktop-en-light and
// phone-ar-light. Run with FDASH_SHOTS set to write the PNGs.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reports_support.dart';

Future<void> _tab(DashHarness h, String key) => h.tap(
  find.descendant(
    of: find.byType(DashPageTabs<String>),
    matching: find.text(h.t(key)),
  ),
);

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpReports(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });
    }
  }

  // TEAM-RPT-031: on a tablet the payroll table scrolls, never cuts a cell.
  for (final lang in ['en', 'ar']) {
    testWidgets('payroll last month, tablet $lang', (tester) async {
      final h = await pumpReports(tester, size: DashSize.tablet, locale: lang);
      await _tab(h, 'dawam.rPayroll');
      await h.tap(pageText(h.t('inputs.lastMonth')));
      await shootPage(h, 'payroll');
    });
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';

    testWidgets('loading, $tag', (tester) async {
      final s = reportsServer();
      final gate = s.server.hold('GET', summaryT);
      final h = await pumpReports(tester, size: size, locale: lang, s: s);
      await h.shot('reports/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = reportsServer();
      s.server.fail('GET', summaryT, MockResponse.error(500, 'boom'));
      final h = await pumpReports(tester, size: size, locale: lang, s: s);
      await shootPage(h, 'failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final h = await pumpReports(
        tester,
        size: size,
        locale: lang,
        edit: (db) => db[TeamTables.attendance].removeWhere((_) => true),
      );
      await shootPage(h, 'empty');
    });

    testWidgets('labour, $tag', (tester) async {
      final h = await pumpReports(tester, size: size, locale: lang);
      await _tab(h, 'dawam.rLabour');
      await shootPage(h, 'labour');
    });

    testWidgets('payroll last month, $tag', (tester) async {
      final h = await pumpReports(tester, size: size, locale: lang);
      await _tab(h, 'dawam.rPayroll');
      await h.tap(pageText(h.t('inputs.lastMonth')));
      await shootPage(h, 'payroll');
    });

    testWidgets('advances, $tag', (tester) async {
      final h = await pumpReports(
        tester,
        size: size,
        locale: lang,
        edit: (db) => db[TeamTables.advances].rows.firstWhere(
          (a) => a['id'] == TeamSeedIds.advance('mariam'),
        )['decided_at'] = '2026-10-02T09:00:00Z',
      );
      await _tab(h, 'dawam.salaryAdvances');
      await shootPage(h, 'advances');
    });

    testWidgets('backwards, $tag', (tester) async {
      final h = await pumpReports(tester, size: size, locale: lang);
      await h.tap(pageText(h.t('inputs.thisWeek')));
      await h.tap(inPage(find.byType(DashDateField)).first);
      await h.tap(find.text('14').hitTestable().last);
      await h.shot('reports/backwards');
    });

    testWidgets('refused, $tag', (tester) async {
      final h = await pumpReports(
        tester,
        size: size,
        locale: lang,
        persona: Persona.limited,
      );
      await h.shot('reports/refused');
    });
  }
}
