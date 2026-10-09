// The person's access sheet (ADM-USR-037..051, 056..058): roles and
// branches, Where and Reason, the capability list with Role / Allow / Deny,
// limits and Why?.
import 'package:dashboard_admin/src/mock/users_mock.dart';
import 'package:dashboard_admin/src/users/person_access_sheet.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _open(
  WidgetTester tester, {
  String? id,
  String who = 'mariam',
  Persona persona = Persona.owner,
  MockServer? server,
  MockDb? db,
  DashSize size = DashSize.desktop,
  String locale = 'en',
}) => pumpUsers(
  tester,
  path: '$usersPath?access=${id ?? uid(who)}',
  persona: persona,
  server: server,
  db: db,
  size: size,
  locale: locale,
);

Finder get _sheet => find.byType(PersonAccessSheet);

Finder _inSheet(String text) =>
    find.descendant(of: _sheet, matching: find.text(text));

/// [text] in the Roles card.
Finder _inRoles(String text) => find.descendant(
  of: find.byKey(const ValueKey('access-roles')),
  matching: find.text(text),
);

Finder _effect(String cap) => find.byKey(ValueKey('effect-$cap'));

Finder _segment(String cap, String label) =>
    find.descendant(of: _effect(cap), matching: find.text(label));

String _selected(WidgetTester tester, String cap) =>
    tester.widget<DashSegmentedControl<String>>(_effect(cap)).value;

String _roleId(String kind) => mockUuid('role:sabah:$kind');

void main() {
  testWidgets('ADM-USR-037 a side panel from the end edge: "<name>\'s '
      'access" and the hint', (tester) async {
    await _open(tester);
    expect(_inSheet("Mariam Fathy's access"), findsOneWidget);
    expect(
      _inSheet(
        'Their roles give them a starting point. Allow or deny single '
        'things here.',
      ),
      findsOneWidget,
    );
    final box = tester.getRect(find.byType(PersonAccessSheet));
    expect(box.width, lessThanOrEqualTo(672));
    expect(box.right, closeTo(1440, 1), reason: 'the end edge');
  });

  testWidgets('ADM-USR-037 phone: full screen', (tester) async {
    await _open(tester, size: DashSize.phone);
    expect(tester.getRect(_sheet).width, 390);
  });

  testWidgets('ADM-USR-038 reads the access at All branches and the org\'s '
      'branches', (tester) async {
    final h = await _open(tester);
    final read = h.server.callsTo(accessRoute).single;
    expect(read.path, '/authz/users/${uid('mariam')}');
    expect(read.query, isEmpty);
    expect(
      h.server.callsTo(branchesRoute).last.query['org_id'],
      [SeedIds.sabahOrg],
    );
  });

  testWidgets('ADM-USR-038 loading: six skeleton rows', (tester) async {
    final s = usersServer();
    final gate = s.server.hold('GET', accessRoute);
    final h = await _open(tester, server: s.server, db: s.db);
    expect(
      find.descendant(of: _sheet, matching: find.byType(DashSkeleton)),
      findsNWidgets(6),
    );
    gate.release();
    await h.settle();
    expect(_inSheet('Roles'), findsOneWidget);
  });

  testWidgets('ADM-USR-038 (divergence) a failed read says so, with Retry', (
    tester,
  ) async {
    final s = usersServer();
    s.server.fail(
      'GET',
      accessRoute,
      MockResponse.error(500, 'Internal error'),
      times: null,
    );
    final h = await _open(tester, server: s.server, db: s.db);
    expect(_inSheet("Couldn't load this"), findsOneWidget);
    s.server.clearFailures();
    await h.tap(find.descendant(of: _sheet, matching: find.text('Retry')));
    expect(_inSheet('Roles'), findsOneWidget);
  });

  testWidgets('ADM-USR-039 (divergence) locked: the reason in words, every '
      'editor inert', (tester) async {
    final h = await _open(tester, id: SeedIds.owner);
    expect(find.byKey(const ValueKey('access-locked')), findsOneWidget);
    expect(_inSheet("You can't change your own access."), findsOneWidget);
    expect(_inSheet('self'), findsNothing);
    expect(find.byKey(const ValueKey('access-roles-edit')), findsNothing);
    // The owner holds everything: "Owner" stands where the controls go.
    expect(_inSheet('Owner'), findsWidgets);
    expect(h.server.callsTo(overridesRoute), isEmpty);
  });

  testWidgets('ADM-USR-039 an unknown reason reads the generic sentence', (
    tester,
  ) async {
    final s = usersServer();
    s.server.on('GET', accessRoute, (req) {
      return MockResponse.ok({
        'user_id': uid('mariam'),
        'name': 'Mariam Fathy',
        'is_owner': false,
        'branch_id': null,
        'can_edit': false,
        'locked_reason': 'weird',
        'assignments': const [],
        'capabilities': const [],
      });
    });
    await _open(tester, server: s.server, db: s.db);
    expect(find.byKey(const ValueKey('access-locked')), findsOneWidget);
    expect(_inSheet("You can't change this person's access."), findsOneWidget);
    expect(_inSheet('weird'), findsNothing);
    expect(find.byKey(const ValueKey('access-roles-edit')), findsNothing);
  });

  testWidgets('ADM-USR-040 Roles: each role and where, "، " between '
      'branches', (tester) async {
    await _open(tester, who: 'dina');
    expect(_inRoles('Branch manager'), findsOneWidget);
    expect(_inRoles('New Cairo، Maadi'), findsOneWidget);
    expect(find.byKey(const ValueKey('access-roles-edit')), findsOneWidget);
  });

  testWidgets('ADM-USR-040 Arabic role names; "No roles" when none', (
    tester,
  ) async {
    final s = usersServer();
    s.db[UsersTables.assignments].removeWhere(
      (a) => a['user_id'] == uid('mariam'),
    );
    final h = await _open(tester, server: s.server, db: s.db, locale: 'ar');
    expect(_inRoles(h.t('access.noRolesHeld')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _open(tester, who: 'dina', locale: 'ar');
    expect(_inRoles('مدير الفرع'), findsOneWidget);
  });

  testWidgets('ADM-USR-041 Edit: every role but the owner\'s, ticked as held; '
      'All branches hides the branch boxes; Cancel saves nothing', (
    tester,
  ) async {
    final h = await _open(tester, who: 'dina');
    await h.tapKey(const ValueKey('access-roles-edit'));
    expect(h.server.callsTo(rolesRoute), isNotEmpty);
    for (final r in ['Branch manager', 'Cashier', 'Waiter', 'Kitchen']) {
      expect(_inRoles(r), findsOneWidget);
    }
    expect(_inRoles('Owner'), findsNothing);
    final held = tester.widget<DashCheckboxField>(
      find.ancestor(
        of: _inRoles('Branch manager'),
        matching: find.byType(DashCheckboxField),
      ),
    );
    expect(held.value, isTrue);
    expect(_inRoles('Zamalek'), findsOneWidget);
    await h.tap(_inRoles('All branches'));
    expect(_inRoles('Zamalek'), findsNothing);
    await h.tap(_inRoles('Cancel'));
    expect(h.server.callsTo(assignmentsRoute), isEmpty);
    expect(_inRoles('New Cairo، Maadi'), findsOneWidget);
  });

  testWidgets('ADM-USR-042 Save roles: the assignments, back to the list, the '
      'access read again', (tester) async {
    final h = await _open(tester, who: 'dina');
    final reads = h.server.callsTo(accessRoute).length;
    await h.tapKey(const ValueKey('access-roles-edit'));
    await h.tap(_inRoles('Cashier'));
    await h.tap(_inRoles('All branches').last);
    await h.tapKey(const ValueKey('access-roles-save'));
    expect(lastBody(h.server, assignmentsRoute, method: 'PUT'), {
      'assignments': [
        {
          'all_branches': false,
          'branch_ids': [SeedIds.newCairo, SeedIds.maadi],
          'role_id': _roleId('branch_manager'),
        },
        {'all_branches': true, 'branch_ids': <String>[], 'role_id': _roleId('teller')},
      ],
    });
    expect(h.server.callsTo(accessRoute).length, greaterThan(reads));
    expect(find.byKey(const ValueKey('access-roles-save')), findsNothing);
    expect(_inRoles('Cashier'), findsOneWidget);
    expect(_inRoles('All branches'), findsOneWidget);
  });

  testWidgets('ADM-USR-042 a refused Save toasts and stays editing', (
    tester,
  ) async {
    final h = await _open(tester, who: 'dina');
    await h.tapKey(const ValueKey('access-roles-edit'));
    // Untick the only role: the server wants at least one.
    await h.tap(_inRoles('Branch manager'));
    await h.tapKey(const ValueKey('access-roles-save'));
    await h.expectToast(
      shown(h, MockResponse.badRequest('A person needs at least one role')),
    );
    expect(find.byKey(const ValueKey('access-roles-save')), findsOneWidget);
  });

  testWidgets('ADM-USR-043 Where: All branches or one; the list reads there '
      'and a change applies there', (tester) async {
    final h = await _open(tester, who: 'youssef');
    expect(_selected(tester, 'orders.void'), 'inherit');
    await h.tap(field('access-where'));
    await pick(h, 'Zamalek');
    expect(
      h.server.callsTo(accessRoute).last.query['branch_id'],
      [SeedIds.zamalek],
    );
    expect(_selected(tester, 'orders.void'), 'deny');
    await h.tap(_segment('refunds.create', 'Deny'));
    expect(
      lastBody(h.server, overridesRoute, method: 'PUT')['branch_id'],
      SeedIds.zamalek,
    );
  });

  testWidgets('ADM-USR-044 Reason: optional, trimmed, null when blank', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(_inSheet('Reason (optional)'), findsOneWidget);
    expect(
      _inSheet(
        'Only if you want a note in the history. Nothing here is ever '
        'required.',
      ),
      findsOneWidget,
    );
    await h.tap(_segment('refunds.create', 'Allow'));
    expect(lastBody(h.server, overridesRoute, method: 'PUT')['reason'], isNull);
    await h.enterText(field('access-reason'), '  covering the late shift ');
    await h.tap(_segment('refunds.create', 'Deny'));
    expect(
      lastBody(h.server, overridesRoute, method: 'PUT')['reason'],
      'covering the late shift',
    );
  });

  testWidgets('ADM-USR-045 groups in order, no legacy capability, the '
      'advanced ones folded away', (tester) async {
    final h = await _open(tester);
    expect(_inSheet('Selling'), findsWidgets);
    expect(find.textContaining('Advanced'), findsOneWidget);
    expect(_inSheet('Create organizations (platform)'), findsNothing);
    expect(_inSheet('See business settings'), findsNothing);
    await h.tap(find.textContaining('Advanced'));
    expect(_inSheet('See business settings'), findsOneWidget);
  });

  testWidgets('ADM-USR-046 the row control by source: Always on, Role: on / '
      'off, the person\'s own', (tester) async {
    await _open(tester, who: 'omar');
    expect(
      find.descendant(
        of: find.ancestor(
          of: _inSheet('See branches'),
          matching: find.byType(Row),
        ).first,
        matching: find.text('Always on'),
      ),
      findsOneWidget,
    );
    expect(_segment('orders.void', 'Role: on'), findsOneWidget);
    expect(_selected(tester, 'refunds.create'), 'allow');
    expect(_segment('reports.read', 'Role: off'), findsOneWidget);
    expect(find.bySemanticsLabel('Why?'), findsWidgets);
  });

  testWidgets('ADM-USR-047 Allow / Deny / Role: the override, the access read '
      'again, no toast', (tester) async {
    final h = await _open(tester);
    final reads = h.server.callsTo(accessRoute).length;
    await h.tap(_segment('orders.void', 'Deny'));
    expect(lastBody(h.server, overridesRoute, method: 'PUT'), {
      'branch_id': null,
      'capability': 'orders.void',
      'effect': 'deny',
      'limits': null,
      'reason': null,
    });
    expect(h.server.callsTo(accessRoute).length, greaterThan(reads));
    expect(_selected(tester, 'orders.void'), 'deny');
    await h.tap(_segment('orders.void', 'Role: on'));
    expect(lastBody(h.server, overridesRoute, method: 'PUT')['effect'], 'inherit');
    expect(_selected(tester, 'orders.void'), 'inherit');
  });

  testWidgets('ADM-USR-048 Limits: "Limited", the popover in pounds, Save '
      'allows with the limits and closes', (tester) async {
    final h = await _open(tester, who: 'omar');
    final limits = find.byKey(const ValueKey('limits-refunds.create'));
    expect(
      find.descendant(of: limits, matching: find.text('Limited')),
      findsOneWidget,
    );
    await h.tap(find.descendant(of: limits, matching: find.text('Limited')));
    final box = find.byWidgetPredicate(
      (w) => w is DashTextInput && w.semanticLabel == 'Most per action (EGP)',
    );
    expect(box, findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Over a limit, the till asks a manager.'), findsOneWidget);
    await h.enterText(box, '300');
    await h.tap(find.text('Save').hitTestable().last);
    expect(lastBody(h.server, overridesRoute, method: 'PUT'), {
      'branch_id': null,
      'capability': 'refunds.create',
      'effect': 'allow',
      'limits': {'max_amount': 30000},
      'reason': null,
    });
    expect(box, findsNothing);
  });

  testWidgets('ADM-USR-049 Why?: asks on every open, then the answer in '
      'words', (tester) async {
    final h = await _open(tester, who: 'omar');
    final why = find.descendant(
      of: find
          .ancestor(of: _effect('refunds.create'), matching: find.byType(Wrap))
          .first,
      matching: find.bySemanticsLabel('Why?'),
    );
    await h.tap(why);
    final call = h.server.callsTo(explainRoute).single;
    expect(call.query['user_id'], [uid('omar')]);
    expect(call.query['capability'], ['refunds.create']);
    expect(find.text('Refund money'), findsWidgets);
    expect(find.text('Allowed'), findsOneWidget);
    expect(find.text('Cashier: allows it'), findsOneWidget);
    expect(find.text('Allowed for this person'), findsOneWidget);
    expect(find.text('Allowed up to a limit'), findsOneWidget);

    // Closed and opened again: asked again.
    await tester.tapAt(tester.getCenter(_inSheet("Omar Khaled's access")));
    await h.settle();
    expect(find.text('Cashier: allows it'), findsNothing);
    await h.tap(why);
    expect(h.server.callsTo(explainRoute), hasLength(2));
    await tester.tapAt(tester.getCenter(_inSheet("Omar Khaled's access")));
    await h.settle();

    // At a branch, the question names it.
    await h.tap(field('access-where'));
    await pick(h, 'Heliopolis');
    await h.tap(why);
    final atBranch = h.server.callsTo(explainRoute).last;
    expect(atBranch.query['branch_id'], [SeedIds.heliopolis]);
    expect(atBranch.query['capability'], ['refunds.create']);
  });

  testWidgets('ADM-USR-050 closing the sheet drops ?access', (tester) async {
    final h = await _open(tester);
    await h.tap(find.bySemanticsLabel(h.t('common.close')).last);
    expect(_sheet, findsNothing);
    expect(h.location.queryParameters.containsKey('access'), isFalse);
  });

  testWidgets('ADM-USR-051 by URL without staff.permissions.read: the read is '
      'refused', (tester) async {
    final h = await _open(tester, persona: Persona.manager);
    expect(h.server.callsTo(accessRoute).single.status, 403);
    expect(_inSheet(h.t('errors.unauthorized')), findsOneWidget);
  });

  testWidgets('ADM-USR-056 a refused change toasts "You don\'t have '
      'permission…" and keeps the server\'s state', (tester) async {
    final s = usersServer();
    s.server.fail(
      'PUT',
      overridesRoute,
      MockResponse.forbidden(
        'You can only grant what you hold yourself (orders.void)',
      ),
    );
    final h = await _open(tester, server: s.server, db: s.db);
    await h.tap(_segment('orders.void', 'Deny'));
    await h.expectToast(h.t('errors.unauthorized'));
    expect(_selected(tester, 'orders.void'), 'inherit');
  });

  testWidgets('ADM-USR-057 Why? fails: a toast; the skeleton stays until it '
      'is opened again', (tester) async {
    final s = usersServer();
    final boom = MockResponse.error(500, 'boom');
    s.server.fail('GET', explainRoute, boom);
    final h = await _open(tester, server: s.server, db: s.db);
    final why = find
        .descendant(of: _sheet, matching: find.bySemanticsLabel('Why?'))
        .first;
    await h.tap(why);
    await h.expectToast(shown(h, boom));
    expect(find.byType(DashSkeleton), findsWidgets);
    // Closed and opened again: asked again, and answered this time.
    await tester.tapAt(tester.getCenter(_inSheet("Mariam Fathy's access")));
    await h.settle();
    await h.tap(why);
    expect(h.server.callsTo(explainRoute), hasLength(2));
    expect(find.text(h.t('access.resultAllowed')), findsWidgets);
  });

  testWidgets('ADM-USR-058 the Reason rides every change until edited', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.enterText(field('access-reason'), 'weekend cover');
    await h.tap(_segment('orders.void', 'Deny'));
    await h.tap(_segment('refunds.create', 'Deny'));
    final bodies = [
      for (final c in h.server.callsTo(overridesRoute))
        (c.body! as Map)['reason'],
    ];
    expect(bodies, ['weekend cover', 'weekend cover']);
    expect(fieldText(tester, 'access-reason'), 'weekend cover');
  });

  testWidgets('ADM-USR-058 (divergence) a locked sheet\'s controls are '
      'visibly off and send nothing', (tester) async {
    final s = usersServer();
    final m = await pumpUsers(
      tester,
      path: '$usersPath?access=${SeedIds.manager}',
      persona: Persona.manager,
      server: s.server,
      db: s.db,
    );
    // The manager may read their own access, never change it.
    expect(m.server.callsTo(accessRoute).single.status, 200);
    expect(_inSheet("You can't change your own access."), findsOneWidget);
    final ctl = tester.widget<DashSegmentedControl<String>>(
      _effect('orders.void'),
    );
    expect(ctl.enabled, isFalse);
    await m.tap(_segment('orders.void', 'Deny'));
    expect(m.server.callsTo(overridesRoute), isEmpty);
  });

  testWidgets('ADM-USR-058 a capability the answer does not list: its name, '
      'no control', (tester) async {
    final s = usersServer();
    s.server.on('GET', accessRoute, (req) {
      return MockResponse.ok({
        'user_id': uid('mariam'),
        'name': 'Mariam Fathy',
        'is_owner': false,
        'branch_id': null,
        'can_edit': true,
        'locked_reason': null,
        'assignments': const [],
        'capabilities': const [],
      });
    });
    await _open(tester, server: s.server, db: s.db);
    expect(_inSheet('Refund money'), findsOneWidget);
    expect(_effect('refunds.create'), findsNothing);
  });

  testWidgets('ADM-USR-048 "Only their own" and a minutes limit through the '
      'popover', (tester) async {
    final h = await _open(tester);
    final limits = find.byKey(const ValueKey('limits-orders.void'));
    await h.tap(find.descendant(of: limits, matching: find.text('Limit')));
    final own = find.byWidgetPredicate(
      (w) => w is DashSwitch && w.semanticLabel == 'Only their own',
    );
    expect(own, findsOneWidget);
    await h.tap(own);
    await h.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is DashTextInput &&
            w.semanticLabel == 'Within minutes of the sale',
      ),
      '10',
    );
    await h.tap(find.text('Save').hitTestable().last);
    expect(lastBody(h.server, overridesRoute, method: 'PUT'), {
      'branch_id': null,
      'capability': 'orders.void',
      'effect': 'allow',
      'limits': {'max_age_minutes': 10, 'own': true},
      'reason': null,
    });
    expect(
      find.descendant(of: limits, matching: find.text('Limited')),
      findsOneWidget,
    );
  });

  testWidgets('ADM-USR-048 a percent limit is stored in basis points', (
    tester,
  ) async {
    final h = await _open(tester);
    final limits = find.byKey(
      const ValueKey('limits-orders.discount.manual_percent'),
    );
    await h.tap(find.descendant(of: limits, matching: find.text('Limit')));
    await h.enterText(
      find.byWidgetPredicate(
        (w) => w is DashTextInput && w.semanticLabel == 'Most per action (%)',
      ),
      '12.5',
    );
    await h.tap(find.text('Save').hitTestable().last);
    expect(
      lastBody(h.server, overridesRoute, method: 'PUT')['limits'],
      {'max_percent': 1250},
    );
  });

  testWidgets('ADM-USR-047 a failed refetch after a saved change toasts '
      'nothing; the sheet keeps the last answer', (tester) async {
    final s = usersServer();
    final h = await _open(tester, server: s.server, db: s.db);
    s.server.fail('GET', accessRoute, MockResponse.error(500, 'boom'));
    await h.tap(_segment('orders.void', 'Deny'));
    expect(h.server.callsTo(overridesRoute).single.status, 200);
    expect(h.server.callsTo(accessRoute).last.status, 500);
    expect(find.text('boom'), findsNothing);
    expect(_effect('orders.void'), findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('ADM-USR-042 a failed refetch after saved roles toasts '
      'nothing', (tester) async {
    final s = usersServer();
    final h = await _open(tester, who: 'dina', server: s.server, db: s.db);
    await h.tapKey(const ValueKey('access-roles-edit'));
    await h.tap(_inRoles('Cashier'));
    await h.tap(_inRoles('All branches').last);
    s.server.fail('GET', accessRoute, MockResponse.error(500, 'boom'));
    await h.tapKey(const ValueKey('access-roles-save'));
    expect(h.server.callsTo(assignmentsRoute).single.status, 200);
    expect(find.text('boom'), findsNothing);
    expect(find.byKey(const ValueKey('access-roles-save')), findsNothing);
    await h.flushTimers();
  });
}
