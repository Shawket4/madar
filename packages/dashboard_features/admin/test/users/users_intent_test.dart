// Intent warming on Users: pointing at a row action warms what its sheet or
// dialog reads, pointing at a branch option warms that branch's access, and
// pointing at New (platform) warms the org list, so each press asks the
// server nothing more.
import 'package:dashboard_admin/src/orgs/orgs_providers.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _rest(DashHarness h, TestGesture mouse, Finder target) async {
  await h.tester.ensureVisible(target);
  await h.settle();
  await mouse.moveTo(h.tester.getCenter(target));
  await h.settle();
}

/// GETs of [route] for the person [who] (at [branch], when given).
int _gets(DashHarness h, String route, String who, {String? branch}) => [
  for (final c in h.server.callsTo(route, method: 'GET'))
    if (c.path.contains(uid(who)))
      if (branch == null || c.query['branch_id']?.single == branch) c,
].length;

void main() {
  testWidgets('ADM-USR-037 Permissions warms the sheet\'s reads; a branch '
      'option warms that branch\'s access', (tester) async {
    final h = await pumpUsers(tester);
    final mouse = await _mouse(tester);
    final action = rowAction('Mariam Fathy', 'Manage permissions');
    expect(_gets(h, accessRoute, 'mariam'), 0);

    await _rest(h, mouse, action);
    expect(_gets(h, accessRoute, 'mariam'), 1, reason: 'the access read is warmed');
    final roles = h.server.callsTo(rolesRoute, method: 'GET').length;
    expect(roles, 1, reason: 'the roles card read is warmed');

    await h.tap(action);
    expect(h.location.queryParameters['access'], uid('mariam'));
    expect(_gets(h, accessRoute, 'mariam'), 1, reason: 'the sheet opened from cache');
    expect(h.server.callsTo(rolesRoute, method: 'GET'), hasLength(roles));

    await h.tap(field('access-where'));
    final option = find.text('Zamalek').hitTestable().last;
    await _rest(h, mouse, option);
    expect(_gets(h, accessRoute, 'mariam', branch: SeedIds.zamalek), 1);
    await h.tap(option);
    expect(_gets(h, accessRoute, 'mariam', branch: SeedIds.zamalek), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });

  testWidgets('ADM-USR-033 Assign branches warms the person\'s branches',
      (tester) async {
    final h = await pumpUsers(tester);
    final mouse = await _mouse(tester);
    final action = rowAction('Adham Reda', 'Assign branches');
    await _rest(h, mouse, action);
    expect(_gets(h, userBranchesRoute, 'adham'), 1, reason: 'warmed on rest');
    final branches = h.server.callsTo(branchesRoute, method: 'GET').length;

    await h.tap(action);
    expect(h.location.queryParameters['branches'], uid('adham'));
    expect(_gets(h, userBranchesRoute, 'adham'), 1, reason: 'opened from cache');
    expect(h.server.callsTo(branchesRoute, method: 'GET'), hasLength(branches));
  });

  testWidgets('ADM-USR-022 a platform admin\'s New warms the org list; '
      'the dialog opens on it with no request',
      (tester) async {
    final h = await pumpUsers(tester, persona: Persona.platform);
    await h.container
        .read(selectedOrgProvider.notifier)
        .select(SeedIds.sabahOrg);
    await h.settle();
    final mouse = await _mouse(tester);
    final before = h.server.callsTo('/orgs', method: 'GET').length;
    await _rest(h, mouse, field('users-new'));
    // The shell's org picker may hold the list already (one shared entry),
    // so the rest may ask nothing; the press must ask nothing either way.
    final warmed = h.server.callsTo('/orgs', method: 'GET').length;
    expect(warmed, greaterThanOrEqualTo(before));
    expect(h.container.exists(orgsListProvider), isTrue,
        reason: 'the dialog\'s read is warmed');

    await h.tap(field('users-new'));
    expect(h.location.queryParameters['edit'], 'new');
    expect(h.server.callsTo('/orgs', method: 'GET'), hasLength(warmed));
  });
}
