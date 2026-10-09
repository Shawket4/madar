// The Roles & Permissions screenshot matrix: the page at phone / tablet /
// desktop in English-light and Arabic-dark (its top, and its end with the
// policy card), and every dialog / popover state at desktop-en-light and
// phone-ar-light. Written only with FDASH_SHOTS set; every case also
// asserts what it shows, so it is a test either way.
import 'package:dashboard_admin/src/mock/roles_mock.dart' show RolesSeed;
import 'package:dashboard_admin/src/roles/ask_manager_card.dart';
import 'package:dashboard_admin/src/roles/role_dialog.dart';
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

const _dialogVariants = [
  (size: DashSize.desktop, locale: 'en', dark: false),
  (size: DashSize.phone, locale: 'ar', dark: false),
];

void main() {
  for (final v in _variants) {
    testWidgets(
      'shots: the page (${v.size.name} ${v.locale} ${v.dark ? 'dark' : 'light'})',
      (tester) async {
        final h = await pumpRoles(
          tester,
          path: '$rolesPath?role=${RolesSeed.seniorCashier}',
          size: v.size,
          locale: v.locale,
          dark: v.dark,
        );
        expect(header, findsOneWidget);
        await h.shot('roles/default');
        await h.scrollUntilVisible(find.byType(AskManagerCard), delta: 600);
        await h.shot('roles/default-end');
      },
    );
  }

  for (final v in _dialogVariants) {
    final tag = '${v.size.name} ${v.locale}';

    Future<DashHarness> open(WidgetTester tester, [String query = '']) =>
        pumpRoles(
          tester,
          path: '$rolesPath$query',
          size: v.size,
          locale: v.locale,
          dark: v.dark,
        );

    testWidgets('shots: the new-role dialog ($tag)', (tester) async {
      final h = await open(tester);
      await h.tapKey(const ValueKey('roles-new'));
      expect(find.byType(RoleDialog), findsOneWidget);
      await h.shot('roles/new-dialog');
      await h.tapKey(const ValueKey('role-submit'));
      await h.shot('roles/new-dialog-errors');
    });

    testWidgets('shots: the rename dialog ($tag)', (tester) async {
      final h = await open(tester);
      await h.tapKey(const ValueKey('role-rename'));
      expect(find.byType(RoleDialog), findsOneWidget);
      await h.shot('roles/rename-dialog');
    });

    testWidgets('shots: delete confirm and limits ($tag)', (tester) async {
      final h = await open(tester, '?role=${RolesSeed.seniorCashier}');
      await h.tapKey(const ValueKey('role-delete'));
      expect(find.byType(DashConfirmDialog), findsOneWidget);
      await h.shot('roles/delete-confirm');
      await h.tap(inConfirm(h.t('common.cancel')));
      final limits = find.byKey(const ValueKey('limits-refunds.create'));
      await h.tap(
        find.descendant(of: limits, matching: find.text(h.t('access.limited'))),
      );
      await h.shot('roles/limits');
    });

    // The list's states, and the refusal screen.
    final states =
        <(String, Persona, void Function(MockServer, MockDb), Finder)>[
          (
            'loading',
            Persona.owner,
            (s, _) => s.hold('GET', rolesRoute),
            find.byKey(const ValueKey('roles-loading')),
          ),
          (
            'failed',
            Persona.owner,
            (s, _) => s.fail(
              'GET',
              rolesRoute,
              MockResponse.error(500, 'boom'),
              times: null,
            ),
            find.byType(DashErrorState),
          ),
          (
            'empty',
            Persona.owner,
            (_, db) => db['roles'].clear(),
            find.byType(DashEmptyState),
          ),
          ('refused', Persona.limited, (_, _) {}, find.byType(DashEmptyState)),
        ];
    for (final (name, persona, edit, shows) in states) {
      testWidgets('shots: $name ($tag)', (tester) async {
        final s = rolesServer(persona: persona);
        edit(s.server, s.db);
        final h = await pumpRoles(
          tester,
          server: s.server,
          db: s.db,
          persona: persona,
          size: v.size,
          locale: v.locale,
          dark: v.dark,
        );
        expect(find.descendant(of: page, matching: shows), findsOneWidget);
        await h.shot('roles/$name');
      });
    }

    testWidgets('shots: the owner role ($tag)', (tester) async {
      final h = await open(tester, '?role=${roleId('org_admin')}');
      expect(inHeader(h.t('access.ownerHoldsAll')), findsOneWidget);
      await h.shot('roles/owner-role');
    });
  }
}
