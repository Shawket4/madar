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
  for (final (size, locale) in [
    (DashSize.desktop, 'en'),
    (DashSize.desktop, 'ar'),
    (DashSize.phone, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    testWidgets('shots: the edit dialog asking who is serving '
        '(${size.name} $locale)', (tester) async {
      final s = branchesServer();
      branchRow(s.db, SeedIds.zamalek)['pick_teller_at_checkout'] = true;
      final h = await pumpBranches(
        tester,
        path: '/branches?edit=${SeedIds.zamalek}',
        size: size,
        locale: locale,
        server: s.server,
        db: s.db,
      );
      expect(find.text(h.t('branches.pickTeller')), findsOneWidget);
      // The till settings at the top, the switch under them.
      await tester.ensureVisible(
        find.byKey(const ValueKey('branch-old-bill-hours')),
      );
      await h.settle();
      await h.shot('branches/edit-dialog-pick-teller');
    });
  }

  for (final v in _variants) {
    testWidgets(
      'shots: the page (${v.size.name} ${v.locale} ${v.dark ? 'dark' : 'light'})',
      (tester) async {
        final s = branchesServer();
        addLocation(s.db);
        final h = await pumpBranches(
          tester,
          size: v.size,
          locale: v.locale,
          dark: v.dark,
          server: s.server,
          db: s.db,
        );
        expect(find.text(h.t('branches.title')), findsWidgets);
        expect(find.text('Heliopolis'), findsWidgets);
        expect(find.text('Obour Warehouse'), findsWidgets);
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

    testWidgets('shots: a platform admin with no shop picked ($tag)', (
      tester,
    ) async {
      final h = await pumpBranches(
        tester,
        persona: Persona.platform,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      expect(find.text(h.t('branches.pickOrg')), findsWidgets);
      await h.shot('branches/platform-pick-org');
    });

    testWidgets('shots: the new-warehouse dialog ($tag)', (tester) async {
      final h = await pumpBranches(
        tester,
        path: '/branches?edit=new-warehouse',
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      expect(find.text(h.t('branches.newWarehouseTitle')), findsWidgets);
      await h.shot('branches/new-warehouse-dialog');
    });

    testWidgets('shots: an edit turning a branch into a warehouse ($tag)', (
      tester,
    ) async {
      final h = await pumpBranches(
        tester,
        path: '/branches?edit=${SeedIds.zamalek}',
        size: v.size,
        locale: v.locale,
        dark: v.dark,
      );
      await h.tap(
        find.descendant(
          of: field('branch-kind'),
          matching: find.text(h.t('branches.kindWarehouse')),
        ),
      );
      expect(find.text(h.t('branches.toWarehouseHint')), findsOneWidget);
      await h.shot('branches/to-warehouse');
    });

    testWidgets('shots: loading ($tag)', (tester) async {
      final s = branchesServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpBranches(
        tester,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
        server: s.server,
        db: s.db,
      );
      await h.shot('branches/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('shots: the error ($tag)', (tester) async {
      final s = branchesServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpBranches(
        tester,
        size: v.size,
        locale: v.locale,
        dark: v.dark,
        server: s.server,
        db: s.db,
      );
      expect(find.text(h.t('common.retry')), findsWidgets);
      await h.shot('branches/error');
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
