// The Branches screenshot matrix: the default page at phone / tablet /
// desktop in English-light and Arabic-dark, and every dialog / sheet state
// at desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// every case also asserts what it shows, so it is a test either way.
import 'package:dashboard_api/mock.dart';
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
        final h = await pumpBranches(
          tester,
          size: v.size,
          locale: v.locale,
          dark: v.dark,
        );
        expect(find.text(h.t('branches.title')), findsWidgets);
        expect(find.text('Heliopolis'), findsWidgets);
        await h.shot('branches/default');
      },
    );
  }

  for (final v in _sheetVariants) {
    final tag = '${v.size.name} ${v.locale}';

    testWidgets('shots: the new-branch dialog ($tag)', (tester) async {
      final h = await pumpBranches(
        tester,
        path: '/branches?edit=new',
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      expect(find.text(h.t('branches.newTitle')), findsOneWidget);
      await h.shot('branches/new-dialog');
    });

    testWidgets('shots: the edit dialog as a platform admin ($tag)', (
      tester,
    ) async {
      final h = await pumpBranches(
        tester,
        path: '/branches?edit=${SeedIds.zamalek}',
        persona: Persona.platform,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      // A platform admin picks the shop first.
      h.allowUnmatched = false;
      expect(find.text(h.t('branches.pickOrg')), findsWidgets);
      await h.shot('branches/platform-pick-org');
    });

    testWidgets('shots: the edit dialog ($tag)', (tester) async {
      final h = await pumpBranches(
        tester,
        path: '/branches?edit=${SeedIds.zamalek}',
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      expect(find.text(h.t('branches.editTitle')), findsOneWidget);
      await h.shot('branches/edit-dialog');
    });

    testWidgets('shots: the delete confirm ($tag)', (tester) async {
      final h = await pumpBranches(
        tester,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      await h.tap(labelled(h.t('common.delete')).first);
      expect(
        find.text(h.t('branches.deleteTitle', args: {'name': 'Heliopolis'})),
        findsOneWidget,
      );
      await h.shot('branches/delete-confirm');
      await h.tapText(h.t('common.cancel'));
    });
  }

  testWidgets('shots: empty and error states (desktop en)', (tester) async {
    final s = branchesServer();
    s.db['branches'].removeWhere((r) => r['org_id'] == SeedIds.sabahOrg);
    final h = await pumpBranches(tester, server: s.server, db: s.db);
    expect(find.text(h.t('branches.empty')), findsOneWidget);
    await h.shot('branches/empty');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
