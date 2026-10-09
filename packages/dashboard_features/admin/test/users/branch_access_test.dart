// Branch Access (ADM-USR-033..036, 052, 055): the person's branches as
// switches, assign / unassign, refusals.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _open(
  WidgetTester tester, {
  String who = 'dina',
  Persona persona = Persona.owner,
  MockServer? server,
  MockDb? db,
}) => pumpUsers(
  tester,
  path: '$usersPath?branches=${uid(who)}',
  persona: persona,
  server: server,
  db: db,
);

DashSwitch _switch(WidgetTester tester, String branchId) =>
    tester.widget(field('branch-access-$branchId'));

void main() {
  testWidgets('ADM-USR-033 title and "Toggle branch access for <name>"', (
    tester,
  ) async {
    await _open(tester);
    expect(inSurface('Branch Access'), findsOneWidget);
    expect(inSurface('Toggle branch access for Dina Fouad'), findsOneWidget);
  });

  testWidgets('ADM-USR-034/035 the org\'s branches with addresses, on where '
      'assigned', (tester) async {
    final h = await _open(tester);
    final branches = h.server.callsTo(branchesRoute, method: 'GET');
    expect(branches.last.query['org_id'], [SeedIds.sabahOrg]);
    expect(
      h.server.callsTo(userBranchesRoute).single.path,
      '/users/${uid('dina')}/branches',
    );
    for (final n in ['Heliopolis', 'Maadi', 'New Cairo', 'Zamalek']) {
      expect(inSurface(n), findsOneWidget);
    }
    expect(_switch(tester, SeedIds.newCairo).value, isTrue);
    expect(_switch(tester, SeedIds.maadi).value, isTrue);
    expect(_switch(tester, SeedIds.heliopolis).value, isFalse);
    expect(_switch(tester, SeedIds.zamalek).value, isFalse);
  });

  testWidgets('ADM-USR-034 loading: two skeleton rows', (tester) async {
    final s = usersServer();
    final gate = s.server.hold('GET', userBranchesRoute);
    final h = await _open(tester, server: s.server, db: s.db);
    expect(
      find.descendant(of: surface, matching: find.byType(DashSkeleton)),
      findsNWidgets(2),
    );
    gate.release();
    await h.settle();
    expect(inSurface('Zamalek'), findsOneWidget);
  });

  testWidgets('ADM-USR-034 a failed assignments read: every switch off', (
    tester,
  ) async {
    final s = usersServer();
    s.server.fail(
      'GET',
      userBranchesRoute,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    await _open(tester, server: s.server, db: s.db);
    expect(_switch(tester, SeedIds.newCairo).value, isFalse);
    expect(_switch(tester, SeedIds.maadi).value, isFalse);
  });

  testWidgets('ADM-USR-035 on assigns, off unassigns; the list and the '
      'switches refresh; no toast', (tester) async {
    final h = await _open(tester);
    final lists = h.server.callsTo(listRoute, method: 'GET').length;
    await h.tap(field('branch-access-${SeedIds.heliopolis}'));
    expect(lastBody(h.server, userBranchesRoute, method: 'POST'), {
      'branch_id': SeedIds.heliopolis,
    });
    expect(_switch(tester, SeedIds.heliopolis).value, isTrue);
    expect(h.server.callsTo(listRoute, method: 'GET').length, lists + 1);
    await h.tap(field('branch-access-${SeedIds.maadi}'));
    expect(
      h.server.callsTo(unassignRoute, method: 'DELETE').single.path,
      '/users/${uid('dina')}/branches/${SeedIds.maadi}',
    );
    expect(_switch(tester, SeedIds.maadi).value, isFalse);
    expect(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ToastCard'),
      findsNothing,
    );
  });

  testWidgets('ADM-USR-036 Done closes and drops ?branches', (tester) async {
    final h = await _open(tester);
    await h.tapKey(const ValueKey('branch-access-done'));
    expect(surface, findsNothing);
    expect(h.location.queryParameters.containsKey('branches'), isFalse);
  });

  testWidgets('ADM-USR-055 a failed branches read: "No results found"', (
    tester,
  ) async {
    final s = usersServer();
    s.server.fail(
      'GET',
      branchesRoute,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    await _open(tester, server: s.server, db: s.db);
    expect(inSurface('No results found'), findsOneWidget);
  });

  testWidgets('ADM-USR-055 a refusal toasts "You don\'t have permission…" and '
      'the switch stays', (tester) async {
    final h = await _open(tester, who: 'mariam', persona: Persona.manager);
    // A branch manager is shown the branches they work at.
    expect(inSurface('Heliopolis'), findsNothing);
    await h.tap(field('branch-access-${SeedIds.zamalek}'));
    await h.expectToast(h.t('errors.unauthorized'));
    expect(_switch(tester, SeedIds.zamalek).value, isTrue);
  });

  testWidgets('ADM-USR-055 (divergence) a switch is off-limits while its call '
      'runs: one tap, one call', (tester) async {
    final s = usersServer();
    final gate = s.server.hold('POST', userBranchesRoute);
    final h = await _open(tester, server: s.server, db: s.db);
    await h.tap(field('branch-access-${SeedIds.zamalek}'));
    expect(_switch(tester, SeedIds.zamalek).onChanged, isNull);
    gate.release();
    await h.settle();
    expect(h.server.callsTo(userBranchesRoute, method: 'POST'), hasLength(1));
    expect(_switch(tester, SeedIds.zamalek).value, isTrue);
  });

  testWidgets('ADM-USR-035 a failed refetch after a saved toggle toasts '
      'nothing', (tester) async {
    final s = usersServer();
    final h = await _open(tester, server: s.server, db: s.db);
    s.server.fail('GET', userBranchesRoute, MockResponse.error(500, 'boom'));
    await h.tap(field('branch-access-${SeedIds.zamalek}'));
    expect(
      h.server.callsTo(userBranchesRoute, method: 'POST').single.status,
      204,
    );
    expect(find.text('boom'), findsNothing);
    expect(_switch(tester, SeedIds.zamalek).onChanged, isNotNull);
    await h.flushTimers();
  });
}
