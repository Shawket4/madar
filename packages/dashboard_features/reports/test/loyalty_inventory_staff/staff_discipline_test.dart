// `/reports/staff` Staff discipline, driven through the real app shell
// (inventory rows REP-STF-001 to -011): the nav leaf and the module gate,
// the page's own gate, the read and its dates, the Refresh button and the
// focus refetch, the department cards and a failed background refresh.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/loyalty_inventory_staff/staff_discipline_page.dart';
import 'package:dashboard_reports/src/mock/loyalty_inventory_staff_mock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

DisciplineRow row(
  String id,
  String name, {
  String? dept = 'd1',
  String? deptName = 'Floor',
  int rank = 1,
  int late = 0,
  int absent = 0,
  int minutes = 0,
  int given = 0,
  int coveredBy = 0,
}) => DisciplineRow(
  employeeId: id,
  employeeName: name,
  departmentId: dept,
  departmentName: deptName,
  presentDays: 20,
  lateDays: late,
  absentDays: absent,
  totalLateMinutes: minutes,
  coversGiven: given,
  coversPending: 0,
  coveredByOthers: coveredBy,
  rankInDepartment: rank,
);

/// Answers the report with [rows].
void answer(MockServer server, List<DisciplineRow> rows) => server.on(
  'GET',
  disciplineTpl,
  (req) => MockResponse.ok(
    DisciplineReport(from: req.q('from')!, to: req.q('to')!, rows: rows),
  ),
);

Finder get refresh => find.byType(StaffRefreshButton);

/// The department cards' titles, in order.
List<String> cardTitles(WidgetTester tester) => [
  for (final c in tester.widgetList<DepartmentCard>(
    find.byType(DepartmentCard),
  ))
    c.group.id == null ? 'Unassigned' : c.group.name,
];

Future<void> background(WidgetTester tester, DashHarness h) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await h.settle();
}

void main() {
  group('nav, module and gate', () {
    testWidgets('REP-STF-001 the "Staff" leaf under Reports opens the page', (
      tester,
    ) async {
      final h = await pumpUnit(tester, path: loyaltyPath);
      final leaf = find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Staff'),
      );
      await tester.scrollUntilVisible(
        leaf.first,
        200,
        scrollable: find
            .descendant(
              of: find.byType(DashSidebar),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await h.tap(leaf.first);
      expect(h.location.path, staffPath);
      expect(inPage(find.text('Staff discipline')), findsOneWidget);
    });

    testWidgets('REP-STF-001 a POS-only org sees the Dawam-off page', (
      tester,
    ) async {
      final s = unitServer();
      s.db['orgs'].update(SeedIds.sabahOrg, {
        'modules': ['pos'],
      });
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
      );
      expect(find.text("Not part of this business's plan"), findsOneWidget);
      expect(find.text(h.t('dawam.moduleDawamOff')), findsOneWidget);
      expect(h.server.callsTo(disciplineTpl), isEmpty);
      await h.shot('staff/module-off');
    });

    testWidgets('REP-STF-002 without hr.attendance.read: Restricted "Staff '
        'discipline", never asked', (tester) async {
      final h = await pumpUnit(
        tester,
        path: staffPath,
        persona: Persona.limited,
      );
      expect(find.text('Staff discipline'), findsWidgets);
      expect(find.text(h.t('reports.noAccess')), findsOneWidget);
      expect(h.server.callsTo(disciplineTpl), isEmpty);
      expect(refresh, findsNothing);
      await h.shot('staff/restricted');
    });

    testWidgets('REP-STF-002 the Dawam-only owner sees her own org', (
      tester,
    ) async {
      final h = await pumpUnit(
        tester,
        path: staffPath,
        persona: Persona.dawamOnly,
      );
      expect(find.text(h.t('reports.noAccess')), findsNothing);
      expect(h.server.callsTo(disciplineTpl).single.status, 200);
      expect(cardTitles(tester), contains('Bakery'));
    });
  });

  group('header and read', () {
    testWidgets('REP-STF-003 title, period, Refresh', (tester) async {
      final h = await pumpUnit(tester, path: staffPath);
      expect(find.text(h.t('reports.noAccess')), findsNothing);
      expect(inPage(find.text('Staff discipline')), findsOneWidget);
      expect(inPage(find.text('Last 30 days')), findsOneWidget);
      expect(refresh, findsOneWidget);
      expect(find.byTooltip('Refresh'), findsOneWidget);
    });

    testWidgets('REP-STF-005 local dates; branch_id only with a branch', (
      tester,
    ) async {
      final h = await pumpUnit(tester, path: staffPath);
      final q = h.server.callsTo(disciplineTpl).single.query;
      expect(q['from'], [defaultFromDate]);
      expect(q['to'], [defaultToDate]);
      expect(q.containsKey('branch_id'), isFalse);
      await h.container.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
      await h.settle();
      expect(h.server.callsTo(disciplineTpl).last.query['branch_id'], [
        SeedIds.maadi,
      ]);
    });

    testWidgets('REP-STF-005 coming back after 30 s asks again; sooner does '
        'not', (tester) async {
      final h = await pumpUnit(tester, path: staffPath);
      final clock = h.db!.clock;
      clock.advance(const Duration(seconds: 10));
      await background(tester, h);
      expect(h.server.callsTo(disciplineTpl), hasLength(1));
      clock.advance(const Duration(seconds: 25));
      await background(tester, h);
      expect(h.server.callsTo(disciplineTpl), hasLength(2));
    });

    testWidgets('REP-STF-005 reopened on cached data: coming back after '
        '30 s still asks again', (tester) async {
      final h = await pumpUnit(tester, path: staffPath);
      final clock = h.db!.clock;
      await h.go(loyaltyPath);
      clock.advance(const Duration(seconds: 10));
      await h.go(staffPath);
      expect(h.server.callsTo(disciplineTpl), hasLength(1));
      clock.advance(const Duration(seconds: 31));
      await background(tester, h);
      expect(h.server.callsTo(disciplineTpl), hasLength(2));
    });

    testWidgets('REP-STF-004 Refresh asks again; "Refreshing…" and the spin '
        'while it runs; a second tap joins it', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
        reducedMotion: false,
      );
      final gate = s.server.hold('GET', disciplineTpl);
      await h.tap(refresh);
      expect(find.byTooltip('Refreshing…'), findsOneWidget);
      expect(
        find.descendant(of: refresh, matching: find.byType(RotationTransition)),
        findsOneWidget,
      );
      // The cards stay while it refreshes.
      expect(find.byType(DepartmentCard), findsWidgets);
      await h.tap(refresh);
      expect(h.server.callsTo(disciplineTpl), hasLength(2));
      gate.release();
      await h.settle();
      expect(find.byTooltip('Refresh'), findsOneWidget);
      expect(
        find.descendant(of: refresh, matching: find.byType(RotationTransition)),
        findsNothing,
      );
    });

    testWidgets('REP-STF-004 under reduced motion the glyph dims instead of '
        'spinning', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
      );
      final gate = s.server.hold('GET', disciplineTpl);
      await h.tap(refresh);
      expect(
        find.descendant(of: refresh, matching: find.byType(RotationTransition)),
        findsNothing,
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: refresh, matching: find.byType(Opacity)),
            )
            .opacity,
        0.5,
      );
      await h.shot('staff/refreshing');
      gate.release();
      await h.settle();
    });

    testWidgets('REP-STF-004 Refresh leaves /staff-pool alone', (tester) async {
      final h = await pumpUnit(tester, path: staffPath);
      final bus = h.container.read(realtimeBusProvider);
      final seen = <List<String>>[];
      final sub = bus.invalidations.listen(seen.add);
      addTearDown(sub.cancel);
      await h.tap(refresh);
      expect(seen.single, ['/staff/']);
      expect(
        pathInvalidatedBy('/staff-pool/drinks', seen.single.single),
        isFalse,
      );
      expect(pathInvalidatedBy(disciplineTpl, seen.single.single), isTrue);
    });
  });

  group('states', () {
    testWidgets('REP-STF-006 loading: two 160 px skeletons', (tester) async {
      final s = unitServer();
      final gate = s.server.hold('GET', disciplineTpl);
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
      );
      final sk = inPage(find.byType(DashSkeleton));
      expect(sk, findsNWidgets(2));
      expect(tester.getSize(sk.first).height, 160);
      expect(inPage(find.text(h.t('reports.staff.empty'))), findsNothing);
      await h.shot('staff/loading');
      gate.release();
      await h.settle();
      expect(find.byType(DepartmentCard), findsWidgets);
    });

    testWidgets('REP-STF-006 failed: ErrorState + Retry', (tester) async {
      final s = unitServer();
      s.server.fail('GET', disciplineTpl, MockResponse.error(500, 'boom'));
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
      );
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      await h.shot('staff/failed');
      await h.tap(inPage(find.text('Retry')));
      expect(h.server.callsTo(disciplineTpl), hasLength(2));
      expect(find.byType(DepartmentCard), findsWidgets);
    });

    testWidgets('REP-STF-006 empty: "No attendance recorded in this '
        'period"', (tester) async {
      final s = unitServer();
      answer(s.server, const []);
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
      );
      expect(
        inPage(find.text('No attendance recorded in this period')),
        findsOneWidget,
      );
      await h.shot('staff/empty');
    });
  });

  group('the cards', () {
    testWidgets('REP-STF-007 a card per department in the server\'s order '
        '(every seeded person has one)', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
      );
      final rows = disciplineRows(
        s.db,
        orgId: SeedIds.sabahOrg,
        branches: null,
        from: defaultFromDate,
        to: defaultToDate,
      );
      final order = <String>[];
      for (final r in rows) {
        final name = r.departmentName ?? 'Unassigned';
        if (!order.contains(name)) order.add(name);
      }
      expect(cardTitles(tester), order);
      expect(inPage(find.text('Unassigned')), findsNothing);
      for (final t in ['Bar', 'Front of house', 'Kitchen', 'Management']) {
        expect(inPage(find.text(t)), findsOneWidget, reason: t);
      }
      await h.shot('staff/default');
    });

    testWidgets('REP-STF-007 the order is the server\'s (first appearance), '
        'never re-sorted', (tester) async {
      final s = unitServer();
      answer(s.server, [
        row('e1', 'Salma Hany', dept: 'd2', deptName: 'Kitchen'),
        row('e2', 'Omar Khaled', dept: null, deptName: null),
        row('e3', 'Mariam Adel', dept: 'd1', deptName: 'Bar'),
        row('e4', 'Ali Hassan', dept: 'd2', deptName: 'Kitchen', rank: 2),
      ]);
      await pumpUnit(tester, path: staffPath, server: s.server, db: s.db);
      expect(cardTitles(tester), ['Kitchen', 'Unassigned', 'Bar']);
      final kitchen = tester
          .widgetList<DepartmentCard>(find.byType(DepartmentCard))
          .first;
      expect(
        [for (final r in kitchen.group.rows) r.employeeName],
        ['Salma Hany', 'Ali Hassan'],
      );
    });

    testWidgets('REP-STF-008 #rank, the name, "late · absent · minutes"', (
      tester,
    ) async {
      final s = unitServer();
      answer(s.server, [
        row('e1', 'Salma Hany', late: 2, absent: 1, minutes: 37),
        row('e2', 'Omar Khaled', rank: 2, late: 12, absent: 3, minutes: 1240),
      ]);
      await pumpUnit(tester, path: staffPath, server: s.server, db: s.db);
      expect(inPage(figure('#1')), findsOneWidget);
      expect(inPage(figure('#2')), findsOneWidget);
      expect(inPage(find.text('Salma Hany')), findsOneWidget);
      expect(inPage(find.text('2 late · 1 absent · 37m')), findsOneWidget);
      expect(inPage(find.text('12 late · 3 absent · 1,240m')), findsOneWidget);
    });

    testWidgets('REP-STF-009 a cover shows for both people (CV-7), nothing '
        'extra for someone without one', (tester) async {
      final s = unitServer();
      answer(s.server, [
        row('e1', 'Salma Hany', given: 1),
        row('e2', 'Omar Khaled', rank: 2, absent: 1, coveredBy: 1),
        row('e3', 'Mariam Adel'),
        row('e4', 'Ali Hassan', rank: 3, given: 3, coveredBy: 2),
      ]);
      await pumpUnit(tester, path: staffPath, server: s.server, db: s.db);
      expect(inPage(find.text('Covered 1 shift')), findsOneWidget);
      expect(
        inPage(find.text('1 shift covered by a colleague')),
        findsOneWidget,
      );
      expect(inPage(find.text('Covered 3 shifts')), findsOneWidget);
      expect(
        inPage(find.text('2 shifts covered by a colleague')),
        findsOneWidget,
      );
      expect(
        inPage(find.textContaining('0 late · 0 absent')),
        findsNWidgets(3),
      );
      expect(
        inPage(find.textContaining(RegExp('Covered|covered by'))),
        findsNWidgets(4),
      );
    });

    testWidgets('REP-STF-008/009 in Arabic', (tester) async {
      final s = unitServer();
      answer(s.server, [
        row('e1', 'Salma Hany', given: 1, late: 2, absent: 1, minutes: 37),
        row('e2', 'Omar Khaled', rank: 2, coveredBy: 2),
        row('e3', 'Hana Mostafa', dept: null, deptName: null),
      ]);
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
        locale: 'ar',
        size: DashSize.phone,
      );
      expect(inPage(find.text('انضباط الموظفين')), findsOneWidget);
      expect(inPage(find.text('2 تأخير · 1 غياب · 37 دقيقة')), findsOneWidget);
      expect(inPage(find.text('غطّى وردية واحدة')), findsOneWidget);
      expect(inPage(find.text('ورديتان غطّاهما زميل')), findsOneWidget);
      expect(inPage(find.text('غير محدد')), findsOneWidget);
      await h.shot('staff/arabic');
    });

    testWidgets('REP-STF-010 two columns from 1024 px, one below', (
      tester,
    ) async {
      final h = await pumpUnit(tester, path: staffPath);
      final cards = find.byType(DepartmentCard);
      final a = tester.getTopLeft(cards.at(0));
      final b = tester.getTopLeft(cards.at(1));
      expect(a.dy, b.dy);
      expect(b.dx, greaterThan(a.dx));
      tester.view.physicalSize = const Size(900, 900) * DashSize.pixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await h.settle();
      final c = tester.getTopLeft(cards.at(0));
      final d = tester.getTopLeft(cards.at(1));
      expect(d.dy, greaterThan(c.dy));
      expect(d.dx, c.dx);
    });

    testWidgets('REP-STF-011 a department with an id but no name: an empty '
        'title', (tester) async {
      final s = unitServer();
      answer(s.server, [row('e1', 'Salma Hany', deptName: null)]);
      await pumpUnit(tester, path: staffPath, server: s.server, db: s.db);
      expect(cardTitles(tester), ['']);
      expect(inPage(find.text('Unassigned')), findsNothing);
    });
  });

  group('a failed background refresh', () {
    testWidgets('REP-STF-011 (divergence) the cards stay; the server\'s words '
        'in one toast per kind', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
      );
      final cards = tester.widgetList(find.byType(DepartmentCard)).length;
      final busy = MockResponse.error(429, 'Slow down a little');
      s.server.fail('GET', disciplineTpl, busy, times: null);
      await h.tap(refresh);
      expect(find.byType(DepartmentCard), findsNWidgets(cards));
      expect(inPage(find.text("Couldn't load this")), findsNothing);
      expect(find.text(h.refusalWords(busy)), findsOneWidget);
      await h.shot('staff/refresh-failed');
      await h.tap(refresh);
      // Replaced, not stacked.
      expect(find.text(h.refusalWords(busy)), findsOneWidget);
      final down = MockResponse.error(500, 'The ledger is busy');
      s.server.fail('GET', disciplineTpl, down, times: null);
      await h.tap(refresh);
      expect(find.text(h.refusalWords(down)), findsOneWidget);
      expect(find.text(h.refusalWords(busy)), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('REP-STF-011 a focus refetch that fails toasts the same '
        'way', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
      );
      final down = MockResponse.error(503, 'Try again shortly');
      s.server.fail('GET', disciplineTpl, down, times: null);
      h.db!.clock.advance(const Duration(minutes: 2));
      await background(tester, h);
      expect(find.byType(DepartmentCard), findsWidgets);
      await h.expectToast(h.refusalWords(down));
    });

    testWidgets('REP-STF-006 a failed first load shows no toast', (
      tester,
    ) async {
      final s = unitServer();
      final down = MockResponse.error(500, 'The ledger is busy');
      s.server.fail('GET', disciplineTpl, down);
      final h = await pumpUnit(
        tester,
        path: staffPath,
        server: s.server,
        db: s.db,
      );
      expect(find.text(h.refusalWords(down)), findsNothing);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
    });
  });

  testWidgets('REP-STF-005 a manager is answered for her branch', (
    tester,
  ) async {
    final h = await pumpUnit(tester, path: staffPath, persona: Persona.manager);
    final c = h.server.callsTo(disciplineTpl).single;
    expect(c.status, 200);
    expect(find.byType(DepartmentCard), findsWidgets);
  });
}
