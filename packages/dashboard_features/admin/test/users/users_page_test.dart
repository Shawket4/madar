// The Users page (ADM-USR-001..019): tabs, nav, header, stats, columns,
// search, table states, row actions, delete, export, New and deep links,
// driven through the real shell on the mock server.
import 'package:dashboard_api/dashboard_api.dart' show MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show MadarClippedText;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('frame', () {
    testWidgets('ADM-USR-001 the Access tabs: Users, Roles & Permissions, '
        'Review only with approvals.review', (tester) async {
      await pumpUsers(tester);
      final tabs = find.byType(DashSectionTabs);
      expect(tabs, findsOneWidget);
      for (final w in ['Users', 'Roles & Permissions', 'Review']) {
        expect(
          find.descendant(of: tabs, matching: find.text(w)),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());

      final m = await pumpUsers(tester, persona: Persona.manager);
      final mTabs = find.byType(DashSectionTabs);
      expect(
        find.descendant(of: mTabs, matching: find.text('Review')),
        findsNothing,
      );
      expect(
        find.descendant(of: mTabs, matching: find.text('Roles & Permissions')),
        findsOneWidget,
      );
      expect(m.location.path, '/access/users');
    });

    testWidgets('ADM-USR-001 switching tabs keeps only the scope params', (
      tester,
    ) async {
      final h = await pumpUsers(
        tester,
        path: '$usersPath?preset=7d&edit=nobody',
      );
      // `/access/roles` is the roles unit's page, not loaded here.
      h.allowUnmatched = true;
      await h.tap(
        find.descendant(
          of: find.byType(DashSectionTabs),
          matching: find.text('Roles & Permissions'),
        ),
      );
      expect(h.location.path, '/access/roles');
      expect(h.location.queryParameters, {'preset': '7d'});
    });

    testWidgets('ADM-USR-005 a Dawam-only owner sees their own org\'s '
        'accounts', (tester) async {
      final h = await pumpUsers(tester, persona: Persona.dawamOnly);
      expect(h.server.callsTo(listRoute).single.query['org_id'], [
        SeedIds.nakhlaOrg,
      ]);
      expect(onPage('Yasmin Ghali'), findsOneWidget);
      expect(stat(tester, 'Total Users').value, 1);
    });

    testWidgets('ADM-USR-002 the nav leaf shows for staff.users.read or '
        'staff.permissions.read', (tester) async {
      Finder leaf() => find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Users & Permissions'),
      );
      await pumpUsers(tester);
      expect(leaf(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpUsers(tester, persona: Persona.manager);
      expect(leaf(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      final h = await pumpUsers(tester, persona: Persona.limited);
      expect(leaf(), findsNothing);
      // The page itself is not guarded: the server refuses the list.
      expect(onPage(h.t('errors.unauthorized')), findsOneWidget);
    });

    testWidgets('ADM-USR-003 title, subtitle, Export and New', (tester) async {
      await pumpUsers(tester);
      expect(onPage('Users'), findsWidgets);
      expect(onPage('Manage staff accounts and access'), findsOneWidget);
      expect(onPage('Export Excel'), findsOneWidget);
      expect(find.byKey(const ValueKey('users-new')), findsOneWidget);
    });

    testWidgets('ADM-USR-004 a platform admin with no shop picked: "Select an '
        'organization", nothing asked', (tester) async {
      final h = await pumpUsers(tester, persona: Persona.platform);
      expect(onPage('Select an organization'), findsOneWidget);
      expect(h.server.callsTo(listRoute), isEmpty);
      expect(find.byType(DashSectionTabs), findsOneWidget);
    });

    testWidgets('ADM-USR-005 loads every account of the org', (tester) async {
      final h = await pumpUsers(tester);
      final calls = h.server.callsTo(listRoute, method: 'GET');
      expect(calls, hasLength(1));
      expect(calls.single.query['org_id'], [SeedIds.sabahOrg]);
    });

    testWidgets('ADM-USR-006 stats: total, org admins, branch managers, '
        'tellers', (tester) async {
      await pumpUsers(tester);
      expect(stat(tester, 'Total Users').value, 16);
      expect(stat(tester, 'Org Admins').value, 1);
      expect(stat(tester, 'Branch managers').value, 4);
      expect(stat(tester, 'Tellers').value, 8);
    });
  });

  group('table', () {
    testWidgets('ADM-USR-007 columns: avatar, name, email or —, phone LTR, '
        'role badge, status pill', (tester) async {
      final s = usersServer();
      s.db['users'].update(uid('ali'), {'is_active': false, 'phone': null});
      final h = await pumpUsers(tester, server: s.server, db: s.db);
      for (final c in ['NAME', 'PHONE', 'ROLE', 'STATUS']) {
        expect(onPage(c), findsOneWidget);
      }
      // Adham Reda (waiter, no email) is first by name.
      final adham = rowOf('Adham Reda').first;
      expect(
        find.descendant(of: adham, matching: find.text('AR')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: adham, matching: find.text('—')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: adham, matching: find.text('+201111110000')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: adham, matching: find.text('Waiter')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: adham, matching: find.text('Active')),
        findsOneWidget,
      );
      final phone = tester.widget<Text>(
        find.descendant(of: adham, matching: find.text('+201111110000')),
      );
      expect(phone.textDirection, TextDirection.ltr);
      final ali = rowOf('Ali Hassan').first;
      expect(
        find.descendant(of: ali, matching: find.text('Inactive')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ali, matching: find.text('—')),
        findsNWidgets(2),
      );
      expect(h.location.path, usersPath);
    });

    testWidgets('ADM-USR-008 search: name, phone, the role (raw or in words); '
        'never the email', (tester) async {
      await pumpUsers(tester);
      final search = find.byType(DashSearchInput);
      Future<void> type(String q) async {
        await tester.enterText(
          find.descendant(of: search, matching: find.byType(EditableText)),
          q,
        );
        await tester.pump(const Duration(milliseconds: 400));
      }

      await type('branch_manager');
      for (final n in [
        'Dina Fouad',
        'Karim Adel',
        'Rana Helmy',
        'Tarek Saber',
      ]) {
        expect(onPage(n), findsOneWidget);
      }
      expect(onPage('Mariam Fathy'), findsNothing);
      await type('Branch Manager');
      expect(onPage('Tarek Saber'), findsOneWidget);
      await type('+20111000');
      expect(onPage('Mariam Fathy'), findsOneWidget);
      expect(onPage('Karim Adel'), findsNothing);
      await type('karim@sabah');
      expect(onPage('Karim Adel'), findsNothing);
      // No rows after a search: the page's own empty words.
      expect(onPage('Staff accounts you add appear here'), findsOneWidget);
    });

    testWidgets('ADM-USR-009 pages of 10, the Columns menu', (tester) async {
      final h = await pumpUsers(tester);
      expect(onPage('Page 1 of 2'), findsOneWidget);
      expect(onPage('Adham Reda'), findsOneWidget);
      expect(onPage('Ziad Amr'), findsNothing);
      await h.tap(labelled('Next').first);
      expect(onPage('Ziad Amr'), findsOneWidget);
      await h.tapText('Columns');
      await pick(h, 'Phone');
      await tester.tapAt(Offset.zero);
      await h.settle();
      expect(onPage('+201110001111'), findsNothing);
    });

    testWidgets('ADM-USR-009 loading: skeletons in the stats and the table', (
      tester,
    ) async {
      final s = usersServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpUsers(tester, server: s.server, db: s.db);
      expect(stat(tester, 'Total Users').loading, isTrue);
      expect(find.byType(DashSkeleton), findsWidgets);
      gate.release();
      await h.settle();
      expect(stat(tester, 'Total Users').loading, isFalse);
      expect(onPage('Adham Reda'), findsOneWidget);
    });

    testWidgets('ADM-USR-009 error: the words and Retry, which asks again', (
      tester,
    ) async {
      final s = usersServer();
      s.server.fail(
        'GET',
        listRoute,
        MockResponse.error(500, 'Database error: pool timed out'),
        times: null,
      );
      final h = await pumpUsers(tester, server: s.server, db: s.db);
      expect(onPage("Couldn't load this"), findsOneWidget);
      expect(onPage('pool timed out'), findsOneWidget);
      s.server.clearFailures();
      final before = h.server.callsTo(listRoute).length;
      final gate = s.server.hold('GET', listRoute);
      await h.tap(find.descendant(of: page, matching: find.text('Retry')));
      // Retrying: the table's Retry spins.
      expect(
        tester.widget<DashErrorState>(find.byType(DashErrorState)).retrying,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(h.server.callsTo(listRoute).length, before + 1);
      expect(onPage('Adham Reda'), findsOneWidget);
    });

    testWidgets('ADM-USR-009 a Latin name reads left to right in Arabic', (
      tester,
    ) async {
      await pumpUsers(tester, locale: 'ar');
      final name = tester.widget<MadarClippedText>(
        find
            .ancestor(
              of: onPage('Adham Reda'),
              matching: find.byType(MadarClippedText),
            )
            .first,
      );
      expect(name.textDirection, TextDirection.ltr);
    });

    testWidgets('ADM-USR-009 phone: one card per person with its actions', (
      tester,
    ) async {
      await pumpUsers(tester, size: DashSize.phone);
      expect(find.byType(DashCard), findsWidgets);
      expect(onPage('Adham Reda'), findsOneWidget);
      expect(rowAction('Adham Reda', 'Assign branches'), findsOneWidget);
      expect(onPage('Columns'), findsNothing);
    });

    testWidgets('ADM-USR-010 empty: "Staff accounts you add appear here"', (
      tester,
    ) async {
      final s = usersServer();
      s.db['users'].removeWhere((u) => u['org_id'] == SeedIds.sabahOrg);
      await pumpUsers(tester, server: s.server, db: s.db);
      expect(onPage('Staff accounts you add appear here'), findsOneWidget);
      expect(stat(tester, 'Total Users').value, 0);
      final export = tester.widget<DashExportButton>(
        find.byType(DashExportButton),
      );
      expect(export.enabled, isFalse, reason: 'ADM-USR-017 nothing to export');
    });
  });

  group('row actions', () {
    testWidgets('ADM-USR-011 a row opens the editor (?edit=<id>); the server '
        'refuses a Save without staff.users.edit', (tester) async {
      final s = usersServer();
      s.server.fail(
        'PATCH',
        itemRoute,
        MockResponse.denied('staff.users.edit'),
      );
      final h = await pumpUsers(tester, server: s.server, db: s.db);
      await h.tap(
        find.descendant(of: page, matching: find.text('Mariam Fathy')),
      );
      expect(h.location.queryParameters['edit'], uid('mariam'));
      expect(inSurface('Edit User'), findsOneWidget);
      await h.tapKey(const ValueKey('user-submit'));
      await h.expectToast(h.t('errors.unauthorized'));
      expect(inSurface('Edit User'), findsOneWidget);
    });

    testWidgets('ADM-USR-012 Manage permissions (shield) with '
        'staff.permissions.read opens the access sheet', (tester) async {
      final h = await pumpUsers(tester);
      await h.tap(rowAction('Mariam Fathy', 'Manage permissions'));
      expect(h.location.queryParameters['access'], uid('mariam'));
      expect(inSurface("Mariam Fathy's access"), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());

      await pumpUsers(tester, persona: Persona.manager);
      expect(rowAction('Mariam Fathy', 'Manage permissions'), findsNothing);
    });

    testWidgets('ADM-USR-013 Assign branches only on branch manager, teller, '
        'waiter and kitchen rows', (tester) async {
      final h = await pumpUsers(tester);
      expect(rowAction('Nour El-Sayed', 'Assign branches'), findsNothing);
      for (final n in ['Dina Fouad', 'Adham Reda', 'Hassan Ibrahim']) {
        expect(rowAction(n, 'Assign branches'), findsOneWidget);
      }
      await h.tap(rowAction('Hassan Ibrahim', 'Assign branches'));
      expect(h.location.queryParameters['branches'], uid('hassan'));
      expect(inSurface('Branch Access'), findsOneWidget);
    });

    testWidgets('ADM-USR-014 Make employee: Dawam on, hr.staff.create, a '
        'linkable account; opens the team dialog for that person', (
      tester,
    ) async {
      final opened = <String>[];
      final warmed = <String>[];
      final s = usersServer();
      // Mariam is not an employee yet.
      s.db['employees'].removeWhere((e) => e['user_id'] == uid('mariam'));
      final h = await pumpUsers(
        tester,
        server: s.server,
        db: s.db,
        openers: makeEmployeeSeam(opened, warmed: warmed),
      );
      expect(h.server.callsTo(linkableRoute), hasLength(1));
      expect(rowAction('Karim Adel', 'Make employee'), findsNothing);
      // Intent warms the dialog's reads, then the press opens it.
      await tester.ensureVisible(rowAction('Mariam Fathy', 'Make employee'));
      await h.settle();
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(
        tester.getCenter(rowAction('Mariam Fathy', 'Make employee')),
      );
      await h.settle();
      expect(warmed, isNotEmpty);
      await h.tap(rowAction('Mariam Fathy', 'Make employee'));
      expect(opened, [uid('mariam')]);
    });

    testWidgets('ADM-USR-014 with the team dialog wired: no hr.staff.create, '
        'no linkable read and no button', (tester) async {
      final s = usersServer();
      s.db['employees'].removeWhere((e) => e['user_id'] == uid('mariam'));
      // The owner, minus "Add staff".
      s.server.on('GET', '/authz/me', (req) {
        final caps = [
          for (final c in Persona.owner.capabilities)
            if (c != 'hr.staff.create') c,
        ]..sort();
        return MockResponse.ok(
          MyAuthz(
            userId: SeedIds.owner,
            capabilities: caps,
            everywhere: caps,
            askManager: const [],
            limits: const {},
            owner: true,
            platform: false,
            roleKinds: const ['org_admin'],
            epoch: 1,
            specVersion: 2,
          ),
        );
      });
      final h = await pumpUsers(
        tester,
        server: s.server,
        db: s.db,
        openers: makeEmployeeSeam([]),
      );
      expect(onPage('Mariam Fathy'), findsOneWidget);
      expect(h.server.callsTo(linkableRoute), isEmpty);
      expect(find.bySemanticsLabel('Make employee'), findsNothing);
    });

    testWidgets('ADM-USR-014 with the team dialog wired: an org without Dawam, '
        'no linkable read and no button', (tester) async {
      final s = usersServer();
      s.db['employees'].removeWhere((e) => e['user_id'] == uid('mariam'));
      s.db['orgs'].update(SeedIds.sabahOrg, {
        'modules': ['pos'],
      });
      final h = await pumpUsers(
        tester,
        server: s.server,
        db: s.db,
        openers: makeEmployeeSeam([]),
      );
      expect(onPage('Mariam Fathy'), findsOneWidget);
      expect(h.server.callsTo(linkableRoute), isEmpty);
      expect(find.bySemanticsLabel('Make employee'), findsNothing);
    });

    testWidgets('ADM-USR-014 nothing linkable is asked for without the team '
        'dialog or the capability', (tester) async {
      final h = await pumpUsers(tester);
      expect(h.server.callsTo(linkableRoute), isEmpty);
      expect(find.bySemanticsLabel('Make employee'), findsNothing);
    });

    testWidgets('ADM-USR-015 Edit (pencil) with staff.users.edit', (
      tester,
    ) async {
      final h = await pumpUsers(tester, persona: Persona.manager);
      // A branch manager sees the people of their branches.
      expect(onPage('Mariam Fathy'), findsOneWidget);
      expect(onPage('Dina Fouad'), findsNothing);
      await h.tap(rowAction('Mariam Fathy', 'Edit'));
      expect(h.location.queryParameters['edit'], uid('mariam'));
      expect(inSurface('Edit User'), findsOneWidget);
    });

    testWidgets('ADM-USR-016 Delete with staff.users.delete: confirm, call, '
        'refetch, toast', (tester) async {
      final h = await pumpUsers(tester);
      final before = h.server.callsTo(listRoute).length;
      await h.tap(rowAction('Adham Reda', 'Delete'));
      expect(inConfirm("Delete Adham Reda's account?"), findsOneWidget);
      expect(
        inConfirm(
          'They can no longer sign in to the dashboard or the POS. Their '
          'past orders and tills stay on record.',
        ),
        findsOneWidget,
      );
      await h.tap(inConfirm('Delete'));
      await h.expectToast('User deleted');
      expect(
        h.server.callsTo(itemRoute, method: 'DELETE').single.path,
        '/users/${uid('adham')}',
      );
      expect(h.server.callsTo(listRoute).length, before + 1);
      expect(onPage('Adham Reda'), findsNothing);
      expect(stat(tester, 'Total Users').value, 15);
    });

    testWidgets('ADM-USR-016 Delete is hidden without staff.users.delete', (
      tester,
    ) async {
      await pumpUsers(tester, persona: Persona.manager);
      expect(find.bySemanticsLabel('Delete'), findsNothing);
    });

    testWidgets('ADM-USR-016/054 deleting yourself is refused: the toast '
        'says so, the row stays', (tester) async {
      final h = await pumpUsers(tester);
      await h.tap(rowAction('Nour El-Sayed', 'Delete'));
      await h.tap(inConfirm('Delete'));
      await h.expectToast(h.t('errors.unauthorized'));
      expect(onPage('Nour El-Sayed'), findsOneWidget);
    });

    testWidgets('ADM-USR-016 Cancel deletes nothing', (tester) async {
      final h = await pumpUsers(tester);
      await h.tap(rowAction('Adham Reda', 'Delete'));
      await h.tap(inConfirm('Cancel'));
      expect(h.server.callsTo(itemRoute, method: 'DELETE'), isEmpty);
    });
  });

  group('export', () {
    testWidgets('ADM-USR-017 the workbook: five columns, every account, the '
        'engine\'s toasts', (tester) async {
      final h = await pumpUsers(tester);
      await h.tapText('Export Excel');
      await h.expectToast('Exported 16 rows');
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, 'Users');
      expect(
        [for (final c in sheet.columns) c.header],
        ['Name', 'Email address', 'Phone', 'Role', 'Status'],
      );
      expect([for (final c in sheet.columns) c.width], [28, 30, 18, 18, 12]);
      expect(sheet.rows.first, [
        'Adham Reda',
        '—',
        '+201111110000',
        'Waiter',
        'Active',
      ]);
      final now = h.server.clock.now.toUtc().toIso8601String().substring(0, 10);
      expect(h.files.saved.single.filename, 'Madar-Users-$now.xlsx');
    });

    testWidgets('ADM-USR-017 a failed export says "Export failed"', (
      tester,
    ) async {
      final h = await pumpUsers(tester);
      h.exports.failNext = Exception('disk full');
      await h.tapText('Export Excel');
      await h.expectToast('Export failed');
    });

    testWidgets('ADM-USR-017 Arabic: roles and status in Arabic', (
      tester,
    ) async {
      final h = await pumpUsers(tester, locale: 'ar');
      await h.tapText(h.t('common.export'));
      await h.expectToast(h.t('excel.done', count: 16));
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, h.t('users.title'));
      expect(sheet.rows.first[3], h.t('roles.waiter'));
    });
  });

  group('the editors in the address', () {
    testWidgets('ADM-USR-018 New opens the user dialog (?edit=new)', (
      tester,
    ) async {
      final h = await pumpUsers(tester);
      await h.tapKey(const ValueKey('users-new'));
      expect(h.location.queryParameters['edit'], 'new');
      expect(inSurface('New User'), findsOneWidget);
    });

    testWidgets('ADM-USR-019 ?edit=<id> opens once the list has the person; '
        'closing removes it', (tester) async {
      final h = await pumpUsers(tester, path: '$usersPath?edit=${uid('omar')}');
      expect(inSurface('Edit User'), findsOneWidget);
      expect(fieldText(tester, 'user-name'), 'Omar Khaled');
      await h.tapText('Cancel');
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
      expect(surface, findsNothing);
    });

    testWidgets('ADM-USR-019 an id not in the list opens nothing', (
      tester,
    ) async {
      final h = await pumpUsers(tester, path: '$usersPath?edit=nobody');
      expect(surface, findsNothing);
      expect(h.location.queryParameters['edit'], 'nobody');
    });

    testWidgets('ADM-USR-019/052 ?branches=<id> opens Branch Access for any '
        'role, even an owner', (tester) async {
      final h = await pumpUsers(
        tester,
        path: '$usersPath?branches=${SeedIds.owner}',
      );
      expect(inSurface('Branch Access'), findsOneWidget);
      await h.tapKey(const ValueKey('branch-access-done'));
      expect(h.location.queryParameters.containsKey('branches'), isFalse);
    });

    testWidgets('ADM-USR-019/051 ?access=<id> opens the sheet for anyone; '
        'without the capability the server refuses the read', (tester) async {
      final h = await pumpUsers(
        tester,
        persona: Persona.manager,
        path: '$usersPath?access=${uid('mariam')}',
      );
      expect(inSurface("Mariam Fathy's access"), findsOneWidget);
      expect(
        h.server.callsTo(accessRoute).single.status,
        403,
        reason: 'the manager may not read permissions',
      );
      expect(inSurface(h.t('errors.unauthorized')), findsOneWidget);
    });
  });
}
