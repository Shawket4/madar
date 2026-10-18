// Intent warming on Set-up (owner rule): "Add a branch" warms the Branches
// page, "Add employee" the linkable users, and each link to another team
// page warms that page, so the press asks nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/employees/add_employee_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'setup_support.dart';

const String linkableT = '/staff/employees/linkable';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _hover(DashHarness h, TestGesture mouse, Finder f) async {
  await mouse.moveTo(h.tester.getCenter(f));
  await h.settle();
}

void main() {
  testWidgets('TEAM-SET-013 (intent) "Add a branch" warms the Branches page '
      'for the org in scope', (tester) async {
    // The admin area's /branches route, standing in for it: its prefetch
    // records the scope it was asked for.
    final warmed = <String?>[];
    final branchesArea = DashArea(
      key: 'branches_stub',
      routes: [
        DashRoute(path: '/branches', prefetch: (_, s) => warmed.add(s.orgId)),
      ],
    );
    final s = setupServer(
      edit: (db) =>
          db['branches'].removeWhere((b) => b['org_id'] == SeedIds.sabahOrg),
    );
    final h = await DashHarness.pump(
      tester,
      areas: [teamArea, branchesArea],
      path: setupPath,
      server: s.server,
      db: s.db,
    );
    expect(byKey('setup-no-branches'), findsOneWidget);
    final mouse = await _mouse(tester);
    await _hover(
      h,
      mouse,
      find.widgetWithText(DashButton, h.t('dawam.setupAddBranch')),
    );
    expect(warmed, [SeedIds.sabahOrg]);
  });

  testWidgets('TEAM-SET-027/036 (intent) "Add employee" warms the linkable '
      'users; the dialog opens on them', (tester) async {
    final h = await pumpSetup(tester, edit: noActivePeople);
    final mouse = await _mouse(tester);
    expect(h.server.callsTo(linkableT, method: 'GET'), isEmpty);
    await _hover(h, mouse, byKey('setup-add-employee'));
    expect(
      h.server.callsTo(linkableT, method: 'GET'),
      hasLength(1),
      reason: 'warmed on hover',
    );
    await h.tapKey(const ValueKey('setup-add-employee'));
    expect(find.byType(AddEmployeeDialog), findsOneWidget);
    expect(
      h.server.callsTo(linkableT, method: 'GET'),
      hasLength(1),
      reason: 'served from the cache',
    );
  });

  testWidgets('TEAM-SET-028/035/009 (intent) the links to Shifts, Rules, '
      'Schedule and the Team board warm their page', (tester) async {
    String? toOf(String key) => tester.widget<DashButton>(byKey(key)).to;

    final h = await pumpSetup(tester);
    expect(toOf('setup-open-rules'), '/staff/rules');
    expect(toOf('setup-go-schedule'), '/staff/schedule');
    expect(toOf('setup-go-team'), '/staff/team');

    // The page's own prefetch runs on hover: the rules' branch list.
    const rulesT = '/staff/attendance/settings/branches';
    h.container.read(queryCacheProvider).clear();
    await h.settle();
    final before = h.server.callsTo(rulesT, method: 'GET').length;
    final mouse = await _mouse(tester);
    await _hover(h, mouse, byKey('setup-open-rules'));
    expect(
      h.server.callsTo(rulesT, method: 'GET').length,
      before + 1,
      reason: 'the Rules page warmed through the route registry',
    );

    await h.tapKey(const ValueKey('setup-step-shifts'));
    expect(toOf('setup-open-shifts'), '/staff/shifts');
  });
}
