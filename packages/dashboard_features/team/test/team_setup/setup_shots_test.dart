// The Set-up screenshot matrix: the page opened on a half-done checklist at
// {phone, tablet, desktop} x {en light, ar dark}, scrolled through; and every
// other state (loading, failed, refused, each step, all set, the dialogs) at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set; the
// pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/src/team_setup/team_setup_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'setup_support.dart';

const _modes = [('en', false), ('ar', true)];
const _states = [(DashSize.desktop, 'en'), (DashSize.phone, 'ar')];

/// Maadi without a radius, nobody active, rules never saved: 1 of 4.
void _halfDone(MockDb db) {
  unpin(db, maadi, keepCoordinates: true);
  noActivePeople(db);
  rulesNeverSaved(db);
}

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> _shootPage(DashHarness h, String name) async {
  final position = find
      .descendant(
        of: find.byType(TeamSetupPage),
        matching: find.byType(Scrollable),
      )
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .firstWhere((s) => s.position.axis == Axis.vertical)
      .position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('setup/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, $tag', (tester) async {
        final h = await pumpSetup(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          edit: _halfDone,
        );
        await _shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in _states) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(
      WidgetTester tester, {
      void Function(MockDb db)? edit,
      ({MockServer server, MockDb db})? s,
      Persona persona = Persona.owner,
    }) => pumpSetup(
      tester,
      size: size,
      locale: lang,
      edit: edit,
      s: s,
      persona: persona,
    );

    testWidgets('loading, $tag', (tester) async {
      final s = setupServer();
      final gate = s.server.hold('GET', '/staff/work-shifts');
      final h = await open(tester, s: s);
      await h.shot('setup/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = setupServer();
      s.server.fail(
        'GET',
        '/staff/work-shifts',
        MockResponse.error(500, 'Database error: timeout'),
        times: null,
      );
      final h = await open(tester, s: s);
      await h.shot('setup/failed');
    });

    testWidgets('refused, $tag', (tester) async {
      final h = await open(tester, persona: Persona.manager);
      await h.shot('setup/refused');
    });

    testWidgets('step 1 pin editor, no rights note, $tag', (tester) async {
      final s = setupServer(edit: _halfDone);
      answerAuthz(s.server, const [
        'hr.rules.edit',
        'hr.staff.read',
        'hr.schedule.read',
        'branches.read',
      ]);
      final h = await open(tester, s: s);
      await _shootPage(h, 'branches-no-access');
    });

    testWidgets('step 1 pin pasted outside Egypt, $tag', (tester) async {
      final h = await open(tester, edit: _halfDone);
      await h.enterText(byKey('setup-paste-$maadi'), '51.5, -0.12');
      await _shootPage(h, 'branches-pasted');
    });

    testWidgets('step 1 no branches, $tag', (tester) async {
      final h = await open(
        tester,
        edit: (db) =>
            db['branches'].removeWhere((b) => b['org_id'] == SeedIds.sabahOrg),
      );
      h.allowUnmatched = true;
      await h.shot('setup/branches-empty');
    });

    testWidgets('step 2 empty, $tag', (tester) async {
      final h = await open(tester, edit: _halfDone);
      await h.tapKey(const ValueKey('setup-step-employees'));
      await _shootPage(h, 'people-empty');
    });

    testWidgets('step 2 list, $tag', (tester) async {
      final h = await open(tester);
      await h.tapKey(const ValueKey('setup-step-employees'));
      await _shootPage(h, 'people-list');
    });

    testWidgets('step 2 add employee, $tag', (tester) async {
      final h = await open(tester, edit: _halfDone);
      await h.tapKey(const ValueKey('setup-step-employees'));
      await h.tapKey(const ValueKey('setup-add-employee'));
      await h.shot('setup/add-employee');
    });

    testWidgets('step 2 import, $tag', (tester) async {
      final h = await open(tester, edit: _halfDone);
      await h.tapKey(const ValueKey('setup-step-employees'));
      await h.tapKey(const ValueKey('setup-import-people'));
      await h.shot('setup/import-people');
    });

    testWidgets('step 3 list, $tag', (tester) async {
      final h = await open(tester);
      await h.tapKey(const ValueKey('setup-step-shifts'));
      await _shootPage(h, 'shifts-list');
    });

    testWidgets('step 3 empty, $tag', (tester) async {
      final h = await open(tester, edit: noActiveShifts);
      await _shootPage(h, 'shifts-empty');
    });

    testWidgets('step 4 suggested, $tag', (tester) async {
      final h = await open(tester, edit: rulesNeverSaved);
      await _shootPage(h, 'rules-suggested');
    });

    testWidgets('all set, $tag', (tester) async {
      final h = await open(tester);
      await _shootPage(h, 'all-set');
    });
  }
}
