// The Roles & Permissions screenshot matrix: the page at phone / tablet /
// desktop in English-light and Arabic-dark (its top, and its end with the
// policy card), and every dialog / popover state at desktop-en-light and
// phone-ar-light. Written only with FDASH_SHOTS set; every case also
// asserts what it shows, so it is a test either way.
import 'package:dashboard_admin/src/mock/roles_mock.dart' show RolesSeed;
import 'package:dashboard_admin/src/roles/ask_manager_card.dart';
import 'package:dashboard_admin/src/roles/role_dialog.dart';
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

    testWidgets('shots: the owner role ($tag)', (tester) async {
      final h = await open(tester, '?role=${roleId('org_admin')}');
      expect(
        inHeader(h.t('access.ownerHoldsAll')),
        findsOneWidget,
      );
      await h.shot('roles/owner-role');
    });
  }
}
