// The Users screenshot matrix: the page at phone / tablet / desktop in
// English-light and Arabic-dark, and every dialog / panel / popover state at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// every case also asserts what it shows, so it is a test either way.
import 'package:dashboard_admin/src/users/person_access_sheet.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _variants = [
  (size: DashSize.phone, locale: 'en', dark: false),
  (size: DashSize.tablet, locale: 'en', dark: false),
  (size: DashSize.desktop, locale: 'en', dark: false),
  (size: DashSize.phone, locale: 'ar', dark: true),
  (size: DashSize.tablet, locale: 'ar', dark: true),
  (size: DashSize.desktop, locale: 'ar', dark: true),
];

const _sheetVariants = [
  (size: DashSize.desktop, locale: 'en', dark: false),
  (size: DashSize.phone, locale: 'ar', dark: false),
];

void main() {
  for (final v in _variants) {
    testWidgets(
      'shots: the page (${v.size.name} ${v.locale} ${v.dark ? 'dark' : 'light'})',
      (tester) async {
        final h = await pumpUsers(
          tester,
          size: v.size,
          locale: v.locale,
          dark: v.dark,
        );
        expect(onPage('Adham Reda'), findsOneWidget);
        await h.shot('users/default');
      },
    );
  }

  for (final v in _sheetVariants) {
    final tag = '${v.size.name} ${v.locale}';

    Future<DashHarness> open(WidgetTester tester, String query) => pumpUsers(
      tester,
      path: '$usersPath?$query',
      size: v.size,
      locale: v.locale,
      dark: v.dark,
    );

    testWidgets('shots: the new-user dialog ($tag)', (tester) async {
      final h = await open(tester, 'edit=new');
      expect(inSurface(h.t('users.newTitle')), findsOneWidget);
      await h.shot('users/new-dialog');
      await h.tapKey(const ValueKey('user-submit'));
      expect(inSurface(h.t('common.requiredField')), findsOneWidget);
      await h.shot('users/new-dialog-errors');
    });

    testWidgets('shots: the edit dialog ($tag)', (tester) async {
      final h = await open(tester, 'edit=${uid('karim')}');
      expect(inSurface(h.t('users.editTitle')), findsOneWidget);
      await h.shot('users/edit-dialog');
    });

    testWidgets('shots: branch access ($tag)', (tester) async {
      final h = await open(tester, 'branches=${uid('dina')}');
      expect(inSurface(h.t('users.branchAccess')), findsOneWidget);
      await h.shot('users/branch-access');
    });

    testWidgets('shots: the access sheet ($tag)', (tester) async {
      final h = await open(tester, 'access=${uid('omar')}');
      expect(find.byType(PersonAccessSheet), findsOneWidget);
      await h.shot('users/access-sheet');
      await h.tapKey(const ValueKey('access-roles-edit'));
      expect(find.byKey(const ValueKey('access-roles-save')), findsOneWidget);
      await h.shot('users/access-roles-edit');
    });

    testWidgets('shots: the access sheet, locked ($tag)', (tester) async {
      final h = await open(tester, 'access=${SeedIds.owner}');
      expect(find.byKey(const ValueKey('access-locked')), findsOneWidget);
      await h.shot('users/access-locked');
    });

    testWidgets('shots: the limits and Why? popovers ($tag)', (tester) async {
      final h = await open(tester, 'access=${uid('omar')}');
      final limits = find.byKey(const ValueKey('limits-refunds.create'));
      await h.tap(
        find.descendant(of: limits, matching: find.text(h.t('access.limited'))),
      );
      expect(find.text(h.t('access.maxAmount')), findsOneWidget);
      await h.shot('users/access-limits');
      await tester.tapAt(const Offset(2, 2));
      await h.settle();
      final why = find.descendant(
        of: find
            .ancestor(
              of: find.byKey(const ValueKey('effect-refunds.create')),
              matching: find.byType(Wrap),
            )
            .first,
        matching: find.bySemanticsLabel(h.t('access.why')),
      );
      await h.tap(why);
      expect(find.text(h.t('access.resultAllowed')), findsOneWidget);
      await h.shot('users/access-why');
    });

    testWidgets('shots: the delete confirm ($tag)', (tester) async {
      final h = await pumpUsers(
        tester,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      await h.tap(rowAction('Adham Reda', h.t('common.delete')));
      expect(
        inConfirm(h.t('users.deleteTitle', args: {'name': 'Adham Reda'})),
        findsOneWidget,
      );
      await h.shot('users/delete-confirm');
      await h.tap(inConfirm(h.t('common.cancel')));
    });

    testWidgets('shots: loading, error, empty, no shop picked ($tag)', (
      tester,
    ) async {
      final s = usersServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpUsers(
        tester,
        server: s.server,
        db: s.db,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      expect(find.byType(DashSkeleton), findsWidgets);
      await h.shot('users/loading');
      gate.release();
      await h.settle();
      await tester.pumpWidget(const SizedBox.shrink());

      final e = usersServer();
      e.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Database error: pool timed out'),
        times: null,
      );
      final he = await pumpUsers(
        tester,
        server: e.server,
        db: e.db,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      expect(onPage(he.t('common.loadFailed')), findsOneWidget);
      await he.shot('users/error');
      await tester.pumpWidget(const SizedBox.shrink());

      final m = usersServer();
      m.db['users'].removeWhere((u) => u['org_id'] == SeedIds.sabahOrg);
      final hm = await pumpUsers(
        tester,
        server: m.server,
        db: m.db,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      expect(onPage(hm.t('users.empty')), findsOneWidget);
      await hm.shot('users/empty');
      await tester.pumpWidget(const SizedBox.shrink());

      final hp = await pumpUsers(
        tester,
        persona: Persona.platform,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      expect(onPage(hp.t('users.pickOrg')), findsOneWidget);
      await hp.shot('users/pick-org');
    });
  }
}
