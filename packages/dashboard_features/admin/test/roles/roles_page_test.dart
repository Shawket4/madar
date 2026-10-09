// Roles & Permissions (`/access/roles`), driven through the real app shell
// on the mock server: one test per inventory row (ADM-ROL-001..016, 022,
// 023), plus the refusal, loading, error and empty states. The role dialog
// is `role_dialog_test.dart`, the policy card `ask_manager_test.dart`.
import 'package:dashboard_admin/src/mock/roles_mock.dart' show RolesSeed;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('gate', () {
    for (final persona in [Persona.limited, Persona.manager]) {
      testWidgets('ADM-ROL-001 ${persona.name}: neither capability → the '
          'Access tabs over a lock, roles never asked for', (tester) async {
        final h = await pumpRoles(tester, persona: persona);
        expect(onPage('Not available on this account'), findsOneWidget);
        expect(
          onPage('Only people who can see permissions can open this page.'),
          findsOneWidget,
        );
        expect(onPage('Users'), findsOneWidget);
        expect(onPage('Roles & Permissions'), findsWidgets);
        expect(onPage('New role'), findsNothing);
        expect(h.server.callsTo(rolesRoute), isEmpty);
        expect(h.server.callsTo(policyRoute), isEmpty);
      });
    }

    testWidgets('ADM-ROL-001 with only "See who can do what" the page opens '
        'read-only', (tester) async {
      final s = rolesServer();
      signedInWithout(s.server, {'staff.roles.manage'});
      final h = await pumpRoles(tester, server: s.server, db: s.db);
      expect(onPage('Not available on this account'), findsNothing);
      expect(h.server.callsTo(rolesRoute), hasLength(1));
      expect(roleRow(roleId('teller')), findsOneWidget);
    });
  });

  group('header and list', () {
    testWidgets('ADM-ROL-002 title, subtitle and "New role" with '
        'roles.manage', (tester) async {
      await pumpRoles(tester);
      expect(onPage('Roles & Permissions'), findsWidgets);
      expect(
        onPage("What each role may do. Change one person's access from Users."),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('roles-new')), findsOneWidget);
    });

    testWidgets('ADM-ROL-002/010/011/019 without roles.manage: no New role, '
        'Rename, Delete or policy card; switches off', (tester) async {
      final s = rolesServer();
      signedInWithout(s.server, {'staff.roles.manage'});
      final h = await pumpRoles(
        tester,
        path: '$rolesPath?role=${RolesSeed.seniorCashier}',
        server: s.server,
        db: s.db,
      );
      expect(find.byKey(const ValueKey('roles-new')), findsNothing);
      expect(find.byKey(const ValueKey('role-rename')), findsNothing);
      expect(find.byKey(const ValueKey('role-delete')), findsNothing);
      expect(onPage("When someone isn't allowed"), findsNothing);
      expect(h.server.callsTo(policyRoute), isEmpty);
      expect(switchOf(tester, 'refunds.create').onChanged, isNull);
      expect(switchOf(tester, 'branches.edit').onChanged, isNull);
    });

    testWidgets('ADM-ROL-003 from 1024 px the list (280) sits beside the '
        'role', (tester) async {
      final h = await pumpRoles(tester, size: DashSize.tablet);
      final row = tester.getRect(find.byType(DashListCard));
      final card = tester.getRect(header);
      expect(row.width, closeTo(280, 1));
      expect(card.left, greaterThan(row.right));
      expect(card.top, closeTo(row.top, 1));
      // RTL: the list on the right.
      await h.shot('roles/layout-wide');
    });

    testWidgets('ADM-ROL-003 below 1024 px the list sits above the role',
        (tester) async {
      final h = await pumpRoles(tester);
      tester.view.physicalSize = const Size(900, 900) * DashSize.pixelRatio;
      await h.settle();
      final list = tester.getRect(find.byType(DashListCard));
      final card = tester.getRect(header);
      expect(card.top, greaterThan(list.bottom));
      expect(card.width, closeTo(list.width, 1));
    });

    testWidgets('ADM-ROL-003 phone: stacked, every part reachable',
        (tester) async {
      final h = await pumpRoles(tester, size: DashSize.phone);
      expect(tester.getRect(header).top,
          greaterThan(tester.getRect(find.byType(DashListCard)).bottom));
      await h.tap(roleRow(roleId('kitchen')));
      expect(h.location.queryParameters['role'], roleId('kitchen'));
      expect(inHeader('Works like Kitchen on older tablets'), findsOneWidget);
    });

    testWidgets('ADM-ROL-004 loading: five skeleton rows, never "No roles '
        'yet"', (tester) async {
      final s = rolesServer();
      final gate = s.server.hold('GET', rolesRoute);
      final h = await pumpRoles(tester, server: s.server, db: s.db);
      final loading = find.byKey(const ValueKey('roles-loading'));
      expect(
        find.descendant(of: loading, matching: find.byType(DashSkeleton)),
        findsNWidgets(5),
      );
      expect(onPage('No roles yet'), findsNothing);
      expect(header, findsNothing);
      await h.shot('roles/loading');
      gate.release();
      await h.settle();
      expect(loading, findsNothing);
      expect(roleRow(roleId('teller')), findsOneWidget);
    });

    testWidgets('ADM-ROL-004 (divergence) while the permissions load: the '
        'skeleton, never "No roles yet", and no roles asked', (tester) async {
      final s = rolesServer();
      final gate = s.server.hold('GET', '/authz/me');
      final h = await pumpRoles(tester, server: s.server, db: s.db);
      expect(find.byKey(const ValueKey('roles-loading')), findsOneWidget);
      expect(onPage('No roles yet'), findsNothing);
      expect(h.server.callsTo(rolesRoute), isEmpty);
      gate.release();
      await h.settle();
      expect(roleRow(roleId('teller')), findsOneWidget);
    });

    testWidgets('ADM-ROL-005 error: "Couldn\'t load roles" + Retry, which '
        'asks again for the roles only', (tester) async {
      final s = rolesServer();
      s.server.fail(
        'GET',
        rolesRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpRoles(tester, server: s.server, db: s.db);
      expect(onPage("Couldn't load roles"), findsOneWidget);
      expect(onPage('No roles yet'), findsNothing);
      expect(header, findsNothing);
      await h.shot('roles/failed');
      final before = h.server.callsTo(rolesRoute).length;
      final policy = h.server.callsTo(policyRoute).length;
      s.server.clearFailures();
      final gate = s.server.hold('GET', rolesRoute);
      await h.tap(find.descendant(of: page, matching: find.text('Retry')));
      // Retrying: the button spins.
      expect(
        tester
            .widget<DashErrorState>(find.byType(DashErrorState))
            .retrying,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(h.server.callsTo(rolesRoute).length, before + 1);
      expect(h.server.callsTo(policyRoute).length, policy + 1);
      expect(roleRow(roleId('teller')), findsOneWidget);
    });

    testWidgets('ADM-ROL-006 empty: a shield and "No roles yet", no role '
        'card and no policy card', (tester) async {
      final s = rolesServer();
      s.db['roles'].clear();
      final h = await pumpRoles(tester, server: s.server, db: s.db);
      expect(onPage('No roles yet'), findsOneWidget);
      expect(header, findsNothing);
      expect(onPage("When someone isn't allowed"), findsNothing);
      expect(h.server.callsTo(policyRoute), isEmpty);
      await h.shot('roles/empty');
    });

    testWidgets('ADM-ROL-007 rows: name and "<works like> · N people"; the '
        'selected one marked; a tap selects by ?role', (tester) async {
      final h = await pumpRoles(tester);
      DashListRow row(String id) => tester.widget(roleRow(id));
      expect(row(roleId('branch_manager')).title, 'Branch manager');
      expect(
        row(roleId('branch_manager')).meta,
        'Branch manager · ${h.t('access.members', count: 4)}',
      );
      expect(row(roleId('org_admin')).meta, 'Owner · 1 person');
      expect(row(roleId('teller')).meta, 'Cashier · 8 people');
      expect(row(RolesSeed.seniorCashier).meta, 'Cashier · 0 people');
      expect(row(roleId('branch_manager')).selected, isTrue);
      await h.tap(roleRow(roleId('waiter')));
      expect(h.location.queryParameters['role'], roleId('waiter'));
      expect(row(roleId('waiter')).selected, isTrue);
      expect(row(roleId('branch_manager')).selected, isFalse);
      expect(inHeader('Waiter'), findsOneWidget);
      // The list in the backend's order: built-in by kind, then custom.
      final order = [
        for (final e in tester.widgetList<DashListRow>(
          find.descendant(
            of: find.byType(DashListCard).first,
            matching: find.byType(DashListRow),
          ),
        ))
          e.title,
      ];
      expect(order, [
        'Owner',
        'Branch manager',
        'Cashier',
        'Waiter',
        'Kitchen',
        'Senior cashier',
      ]);
    });

    testWidgets('ADM-ROL-007 Arabic: Arabic names, kinds and plurals',
        (tester) async {
      await pumpRoles(tester, locale: 'ar');
      final row = tester.widget<DashListRow>(roleRow(roleId('waiter')));
      expect(row.title, 'نادل');
      expect(row.meta, 'نادل · شخصان');
      expect(
        tester.widget<DashListRow>(roleRow(roleId('org_admin'))).meta,
        'المالك · شخص واحد',
      );
      expect(
        tester.widget<DashListRow>(roleRow(RolesSeed.seniorCashier)).title,
        'كاشير أول',
      );
    });

    for (final (query, expected) in [
      ('', 'branch_manager'),
      ('?role=${roleId('teller')}', 'teller'),
      ('?role=gone', 'branch_manager'),
      ('?user=abc', 'branch_manager'),
    ]) {
      testWidgets('ADM-ROL-008 default selection "$query" → $expected',
          (tester) async {
        await pumpRoles(tester, path: '$rolesPath$query');
        expect(
          tester.widget<DashListRow>(roleRow(roleId(expected))).selected,
          isTrue,
        );
      });
    }

    testWidgets('ADM-ROL-008 no branch manager role: the first role',
        (tester) async {
      final s = rolesServer();
      s.db['roles'].removeWhere((r) => r['kind'] == 'branch_manager');
      await pumpRoles(tester, server: s.server, db: s.db);
      expect(
        tester.widget<DashListRow>(roleRow(roleId('org_admin'))).selected,
        isTrue,
      );
      expect(inHeader('The owner can do everything. This role cannot be '
          'changed.'), findsOneWidget);
    });
  });

  group('the selected role', () {
    testWidgets('ADM-ROL-009 a built-in role: name, "Works like …", "Built '
        'in"', (tester) async {
      await pumpRoles(tester, path: '$rolesPath?role=${roleId('teller')}');
      expect(inHeader('Cashier'), findsOneWidget);
      expect(inHeader('Works like Cashier on older tablets'), findsOneWidget);
      expect(inHeader('Built in'), findsOneWidget);
    });

    testWidgets('ADM-ROL-009/013 the owner role: "can do everything", no '
        'capability list, Rename still offered (ADM-ROL-023)', (tester) async {
      final h = await pumpRoles(
        tester,
        path: '$rolesPath?role=${roleId('org_admin')}',
      );
      expect(
        inHeader('The owner can do everything. This role cannot be changed.'),
        findsOneWidget,
      );
      expect(inHeader('Built in'), findsOneWidget);
      expect(find.byKey(const ValueKey('role-rename')), findsOneWidget);
      expect(find.byKey(const ValueKey('role-delete')), findsNothing);
      expect(grantSwitch('orders.void'), findsNothing);
      expect(onPage('Advanced'), findsNothing);
      // ADM-ROL-022: the policy card shows under the owner role too.
      expect(onPage("When someone isn't allowed"), findsOneWidget);
      await h.shot('roles/owner-role');
    });

    testWidgets('ADM-ROL-009/011 a custom role: no "Built in"; Delete '
        'offered', (tester) async {
      final h = await pumpRoles(
        tester,
        path: '$rolesPath?role=${RolesSeed.seniorCashier}',
      );
      expect(inHeader('Senior cashier'), findsOneWidget);
      expect(inHeader('Built in'), findsNothing);
      final delete = tester.widget<DashButton>(
        find.byKey(const ValueKey('role-delete')),
      );
      expect(delete.onPressed, isNotNull);
      await h.shot('roles/custom-role');
    });

    testWidgets('ADM-ROL-010 Rename opens "Rename role" with the names '
        'filled in', (tester) async {
      final h = await pumpRoles(tester);
      await h.tapKey(const ValueKey('role-rename'));
      expect(inSurface('Rename role'), findsOneWidget);
      expect(
        tester
            .widget<DashTextField>(field('role-name-en'))
            .value,
        'Branch manager',
      );
      expect(
        tester.widget<DashTextField>(field('role-name-ar')).value,
        'مدير الفرع',
      );
      expect(field('role-kind'), findsNothing);
    });

    testWidgets('ADM-ROL-011 built-in roles have no Delete; a held custom '
        'role\'s Delete is disabled', (tester) async {
      final s = rolesServer();
      s.db['role_assignments'].insert({
        'user_id': SeedIds.user('mariam'),
        'role_id': RolesSeed.seniorCashier,
        'kind': 'teller',
        'all_branches': false,
        'branch_ids': [SeedIds.zamalek],
      }, timestamps: false);
      registerRolesArea(s.server, s.db); // members recounted
      final h = await pumpRoles(
        tester,
        path: '$rolesPath?role=${RolesSeed.seniorCashier}',
        server: s.server,
        db: s.db,
      );
      expect(
        tester.widget<DashListRow>(roleRow(RolesSeed.seniorCashier)).meta,
        'Cashier · 1 person',
      );
      final delete = tester.widget<DashButton>(
        find.byKey(const ValueKey('role-delete')),
      );
      expect(delete.onPressed, isNull);
      await h.tap(roleRow(roleId('teller')));
      expect(find.byKey(const ValueKey('role-delete')), findsNothing);
    });

    testWidgets('ADM-ROL-011/012 Delete: confirm, then the role goes, ?role '
        'is dropped and the list asked again; no toast', (tester) async {
      final h = await pumpRoles(
        tester,
        path: '$rolesPath?role=${RolesSeed.seniorCashier}',
      );
      final lists = h.server.callsTo(rolesRoute).length;
      await h.tapKey(const ValueKey('role-delete'));
      expect(inConfirm('Delete this role?'), findsOneWidget);
      expect(
        inConfirm('Nobody holds it. This cannot be undone.'),
        findsOneWidget,
      );
      await h.shot('roles/delete-confirm');
      await h.tap(inConfirm('Delete'));
      final call = h.server.callsTo(roleRoute, method: 'DELETE').single;
      expect(call.path, '/authz/roles/${RolesSeed.seniorCashier}');
      expect(h.location.queryParameters.containsKey('role'), isFalse);
      expect(h.server.callsTo(rolesRoute).length, lists + 1);
      expect(roleRow(RolesSeed.seniorCashier), findsNothing);
      expect(
        tester.widget<DashListRow>(roleRow(roleId('branch_manager'))).selected,
        isTrue,
      );
      expect(toasts, findsNothing);
    });

    testWidgets('ADM-ROL-011 Delete cancelled: nothing sent', (tester) async {
      final h = await pumpRoles(
        tester,
        path: '$rolesPath?role=${RolesSeed.seniorCashier}',
      );
      await h.tapKey(const ValueKey('role-delete'));
      await h.tap(inConfirm('Cancel'));
      expect(h.server.callsTo(roleRoute, method: 'DELETE'), isEmpty);
      expect(roleRow(RolesSeed.seniorCashier), findsOneWidget);
    });

    testWidgets('ADM-ROL-012/023 a refused delete toasts the server\'s '
        'words and keeps the role', (tester) async {
      final s = rolesServer();
      final refusal = MockResponse.conflict(
        'People still hold this role. Move them to another role first.',
      );
      s.server.fail('DELETE', roleRoute, refusal);
      final h = await pumpRoles(
        tester,
        path: '$rolesPath?role=${RolesSeed.seniorCashier}',
        server: s.server,
        db: s.db,
      );
      await h.tapKey(const ValueKey('role-delete'));
      await h.tap(inConfirm('Delete'));
      await h.expectToast(shown(h, refusal));
      expect(h.location.queryParameters['role'], RolesSeed.seniorCashier);
      expect(roleRow(RolesSeed.seniorCashier), findsOneWidget);
    });
  });

  group('capabilities', () {
    testWidgets('ADM-ROL-013 the registry groups, legacy never shown, '
        'advanced behind "Advanced (N)"', (tester) async {
      final h = await pumpRoles(tester);
      expect(capabilityRow('Refund money'), findsOneWidget);
      expect(onPage('Selling'), findsOneWidget);
      // Advanced: "Add branches" waits behind the toggle.
      expect(onPage('Add branches'), findsNothing);
      final advanced = find.descendant(
        of: page,
        matching: find.bySemanticsLabel(RegExp(r'^Advanced \(\d+\)$')),
      );
      expect(advanced, findsOneWidget);
      await h.tap(advanced);
      expect(onPage('Add branches'), findsOneWidget);
      // Legacy rows ("… (legacy)") never.
      expect(
        find.descendant(of: page, matching: find.textContaining('(legacy)')),
        findsNothing,
      );
    });

    testWidgets('ADM-ROL-014 core → "Always on"; held → on; not held → off',
        (tester) async {
      await pumpRoles(tester);
      // Branch manager: "See orders" is core for the kind.
      expect(grantSwitch('orders.read'), findsNothing);
      expect(
        find.descendant(
          of: capabilityRow('See orders'),
          matching: find.text('Always on'),
        ),
        findsOneWidget,
      );
      expect(switchOf(tester, 'refunds.create').value, isTrue);
      expect(switchOf(tester, 'refunds.create').onChanged, isNotNull);
      expect(switchOf(tester, 'branches.edit').value, isFalse);
    });

    testWidgets('ADM-ROL-014 (divergence) a switch is named by the '
        "capability's words, not its key", (tester) async {
      await pumpRoles(tester);
      expect(switchOf(tester, 'branches.edit').semanticLabel, isNot(
        'branches.edit',
      ));
      expect(
        find.descendant(
          of: capabilityRow(switchOf(tester, 'branches.edit').semanticLabel),
          matching: grantSwitch('branches.edit'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ADM-ROL-014/015 switching on: PUT {capability, granted}, '
        'the row busy until the list is back, no toast', (tester) async {
      final h = await pumpRoles(tester);
      final lists = h.server.callsTo(rolesRoute).length;
      final gate = h.server.hold('PUT', grantsRoute);
      await h.tap(grantSwitch('branches.edit'));
      expect(switchOf(tester, 'branches.edit').onChanged, isNull);
      expect(switchOf(tester, 'refunds.create').onChanged, isNotNull);
      gate.release();
      await h.settle();
      final call = h.server.callsTo(grantsRoute).single;
      expect(call.path, '/authz/roles/${roleId('branch_manager')}/grants');
      expect(call.body, {'capability': 'branches.edit', 'granted': true});
      expect(h.server.callsTo(rolesRoute).length, lists + 1);
      expect(switchOf(tester, 'branches.edit').value, isTrue);
      expect(switchOf(tester, 'branches.edit').onChanged, isNotNull);
      expect(toasts, findsNothing);
    });

    testWidgets('ADM-ROL-015 switching off removes the grant', (tester) async {
      final h = await pumpRoles(tester);
      await h.tap(grantSwitch('refunds.create'));
      expect(lastBody(h.server, grantsRoute, method: 'PUT'), {
        'capability': 'refunds.create',
        'granted': false,
      });
      expect(switchOf(tester, 'refunds.create').value, isFalse);
      // The Limit button goes with it.
      expect(find.byKey(const ValueKey('limits-refunds.create')), findsNothing);
    });

    testWidgets('ADM-ROL-015/023 a refused change toasts "no permission" and '
        'the switch stays', (tester) async {
      final s = rolesServer();
      final refusal = MockResponse.forbidden(
        'You can only grant what you hold yourself (branches.edit)',
      );
      s.server.fail('PUT', grantsRoute, refusal);
      final h = await pumpRoles(tester, server: s.server, db: s.db);
      await h.tap(grantSwitch('branches.edit'));
      await h.expectToast(shown(h, refusal));
      expect(shown(h, refusal), h.t('errors.unauthorized'));
      expect(switchOf(tester, 'branches.edit').value, isFalse);
      expect(switchOf(tester, 'branches.edit').onChanged, isNotNull);
    });

    testWidgets('ADM-ROL-016 Limit on a held capability that takes limits; '
        'Save sends granted with the limits', (tester) async {
      final h = await pumpRoles(
        tester,
        path: '$rolesPath?role=${RolesSeed.seniorCashier}',
      );
      // Not held → no Limit button.
      expect(
        find.byKey(const ValueKey('limits-orders.discount.preset')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('limits-inventory.waste.record')),
          findsNothing);
      final limits = find.byKey(const ValueKey('limits-refunds.create'));
      // EGP 1,000 already set → "Limited", 1000 in the box.
      await h.tap(find.descendant(of: limits, matching: find.text('Limited')));
      final box = find.byWidgetPredicate(
        (w) => w is DashTextInput && w.semanticLabel == 'Most per action (EGP)',
      );
      expect(find.descendant(of: box, matching: find.text('1000')),
          findsOneWidget);
      await h.shot('roles/limits');
      await h.enterText(box, '250');
      await h.tap(find.text('Save').hitTestable().last);
      expect(lastBody(h.server, grantsRoute, method: 'PUT'), {
        'capability': 'refunds.create',
        'granted': true,
        'limits': {'max_amount': 25000},
      });
      expect(box, findsNothing);
      expect(
        h.db!['roles'].find(RolesSeed.seniorCashier)!['grants'],
        contains(
          equals({
            'capability': 'refunds.create',
            'limits': {'max_amount': 25000},
            'source': 'custom',
          }),
        ),
      );
    });

    testWidgets('ADM-ROL-016 a capability without limits set reads "Limit"',
        (tester) async {
      await pumpRoles(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('limits-orders.void')),
          matching: find.text('Limit'),
        ),
        findsOneWidget,
      );
    });
  });
}
