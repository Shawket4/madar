// The Organizations screenshots (SPEC 6.2): the default list at phone /
// tablet / desktop in English light and Arabic dark, and every dialog and
// state at desktop-en-light and phone-ar-light. Written only with
// FDASH_SHOTS set; each also checks the state it pictures.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _matrix = [
  (DashSize.phone, 'en', false),
  (DashSize.tablet, 'en', false),
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', true),
  (DashSize.tablet, 'ar', true),
  (DashSize.desktop, 'ar', true),
];

const _dialogs = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

String _name(DashSize s, String l, bool d) =>
    '${s.name}-$l-${d ? 'dark' : 'light'}';

/// The open dialog's (or sheet's) own scroll view.
Finder _surfaceScroll() => find
    .descendant(
      of: find.byType(DashSurface),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _wizardNext(DashHarness h) =>
    h.tapKey(const ValueKey('wizard-next'));

void main() {
  for (final (size, lang, dark) in _matrix) {
    testWidgets('default: the Organizations list ${_name(size, lang, dark)}', (
      tester,
    ) async {
      final h = await pumpOrgs(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(find.text('Layali Bistro'), findsOneWidget);
      expect(find.text('Sabah Coffee'), findsOneWidget);
      await h.shot('orgs/default');
    });
  }

  for (final (size, lang, dark) in _dialogs) {
    final n = _name(size, lang, dark);

    testWidgets('wizard: the three steps $n', (tester) async {
      final h = await pumpOrgs(
        tester,
        path: '/orgs?edit=new',
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(find.text(h.t('orgs.newTitle')), findsOneWidget);
      await h.shot('orgs/wizard-business');
      // Next on an empty step 1: its checks show.
      await _wizardNext(h);
      expect(find.text(h.t('orgs.wizard.templateRequired')), findsOneWidget);
      await h.shot('orgs/wizard-business-errors');
      await h.enterText(
        find.byKey(const ValueKey('wizard-name')),
        'Drops Coffee',
      );
      await h.tapKey(const ValueKey('wizard-template-cafe'));
      await _wizardNext(h);
      expect(find.byKey(const ValueKey('wizard-branchName')), findsOneWidget);
      await h.shot('orgs/wizard-branch');
      await h.enterText(
        find.byKey(const ValueKey('wizard-branchName')),
        'Zamalek',
      );
      await _wizardNext(h);
      expect(find.byKey(const ValueKey('wizard-ownerName')), findsOneWidget);
      await h.shot('orgs/wizard-owner');
    });

    testWidgets('editor: top and bottom $n', (tester) async {
      final h = await pumpOrgs(
        tester,
        path: '/orgs?edit=${AdminSeed.layaliOrg}',
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(find.text(h.t('orgs.editTitle')), findsOneWidget);
      await h.shot('orgs/edit');
      await h.scrollUntilVisible(
        find.byKey(const ValueKey('org-social-website')),
        scrollable: _surfaceScroll(),
      );
      await h.shot('orgs/edit-social');
    });

    testWidgets('delete: the confirm $n', (tester) async {
      final h = await pumpOrgs(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(find.bySemanticsLabel(h.t('common.delete')).at(2));
      expect(find.byType(DashConfirmDialog), findsOneWidget);
      await h.shot('orgs/delete-confirm');
    });

    testWidgets('state: refused $n', (tester) async {
      final h = await pumpOrgs(
        tester,
        persona: Persona.owner,
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(find.text(h.t('errors.unauthorized')), findsOneWidget);
      await h.shot('orgs/refused');
    });

    testWidgets('state: empty $n', (tester) async {
      final s = orgsServer();
      s.db['orgs'].clear();
      final h = await pumpOrgs(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      expect(find.text(h.t('orgs.empty')), findsOneWidget);
      await h.shot('orgs/empty');
    });

    testWidgets('state: error $n', (tester) async {
      final s = orgsServer();
      s.server.fail(
        'GET',
        '/orgs',
        MockResponse.error(500, 'Internal error'),
        times: null,
      );
      final h = await pumpOrgs(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      expect(find.text(h.t('common.retry')), findsOneWidget);
      await h.shot('orgs/error');
    });

    testWidgets('state: loading $n', (tester) async {
      final s = orgsServer();
      final gate = s.server.hold('GET', '/orgs');
      final h = await pumpOrgs(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
      );
      expect(find.byType(DashSkeleton), findsWidgets);
      await h.shot('orgs/loading');
      gate.release();
      await h.settle();
    });
  }

  testWidgets('columns: the menu open desktop-en-light', (tester) async {
    final h = await pumpOrgs(tester);
    await h.tapText('Columns');
    expect(find.text('Custom branding'), findsWidgets);
    await h.shot('orgs/columns-menu');
  });
}
