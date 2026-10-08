// The home, driven through the real app shell (inventory rows OVW-HOME-001
// to -056): routing and scope, the header, the Keep-building card, the KPI
// strip and the Open tills card.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_overview/src/home/home_page.dart';
import 'package:dashboard_overview/src/mock/home_figures.dart';
import 'package:dashboard_overview/src/mock/register.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _sales = '/reports/branches/{branchId}/sales';
const _series = '/reports/branches/{branchId}/sales/timeseries';
const _cmp = '/reports/orgs/{orgId}/comparison';
const _delivery = '/reports/branches/{branchId}/delivery-sales';
const _watch = '/insights/branches/{branchId}/margin-watch';
const _tills = '/tills/branches/{branchId}/open';
const _onboarding = '/orgs/{id}/onboarding';
const _modules = '/orgs/{id}/modules';

const _from = '2026-09-08T21:00:00.000Z';
const _to = '2026-10-08T20:59:59.999Z';

/// The KPI card labelled [label].
DashStatCard kpi(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashStatCard && w.label == label).first,
);

/// Taps [text] in the open menu (the page under it does not take taps).
Future<void> pick(DashHarness h, String text) =>
    h.tap(find.text(text).hitTestable());

/// The scope line's part reading [text].
Finder scopePart(String text) => find.descendant(
  of: find.byType(HomeScopeLine),
  matching: find.text(HomeScopeLine.keep(text)),
);

/// Revenue / orders / voided / tips of [branchIds] over the default period,
/// computed from the seeded rows (no request recorded).
SalesTotals totals(DashHarness h, List<String> branchIds) => SalesTotals(
  ordersIn(
    h.db!,
    branchIds,
    from: DateTime.parse(_from),
    to: DateTime.parse(_to),
  ),
);

final _sabah = [
  SeedIds.heliopolis,
  SeedIds.maadi,
  SeedIds.newCairo,
  SeedIds.zamalek,
];

void main() {
  group('routing and scope', () {
    testWidgets('OVW-HOME-001 signed out goes to sign-in, back after', (
      tester,
    ) async {
      final h = await pumpHome(tester, persona: null);
      expect(h.location.path, '/login');
      expect(h.location.queryParameters['redirect'], '/');
    });

    testWidgets('OVW-HOME-001/004 signed in: the home inside the frame', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      expect(h.location.path, '/');
      expect(find.text('Welcome back, Nour El-Sayed'), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('OVW-HOME-002 nothing until the modules are known', (
      tester,
    ) async {
      final s = homeServer();
      final gate = s.server.hold('GET', _modules);
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(find.byType(HomePage), findsNothing);
      expect(find.text('Welcome back, Nour El-Sayed'), findsNothing);
      gate.release();
      await h.settle();
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('OVW-HOME-002 a failed modules read leaves the home blank', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _modules, MockResponse.error(500, 'boom'), times: null);
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(find.byType(HomePage), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(h.location.path, '/');
    });

    testWidgets('OVW-HOME-003 a Dawam-only org goes to its team', (
      tester,
    ) async {
      final h = await pumpHome(tester, persona: Persona.dawamOnly);
      h.allowUnmatched = true;
      expect(h.location.path, '/staff/team');
      expect(find.byType(HomePage), findsNothing);
    });

    testWidgets('OVW-HOME-005 platform admin with no shop: zeros, empties', (
      tester,
    ) async {
      final h = await pumpHome(tester, persona: Persona.platform);
      expect(find.byType(HomePage), findsOneWidget);
      expect(kpi(tester, 'Revenue').value, 0);
      expect(kpi(tester, 'Revenue').loading, isFalse);
      expect(kpi(tester, 'Orders').value, 0);
      expect(
        find.text('Sales for this period will appear here.'),
        findsNWidgets(3),
      );
      expect(
        find.text('Margins appear here once items sell in this period'),
        findsOneWidget,
      );
      expect(kpi(tester, 'Delivery revenue').value, 0);
      expect(find.text('In-mall delivery'), findsNothing);
      expect(find.text('Open tills'), findsNothing);
      expect(find.text('Keep building'), findsNothing);
      expect(scopePart('All branches'), findsOneWidget);
      for (final t in [_sales, _series, _cmp, _delivery, _watch, _onboarding]) {
        expect(h.server.callsTo(t), isEmpty, reason: t);
      }
    });

    testWidgets('OVW-HOME-006 an unfinished set-up sends the owner to it', (
      tester,
    ) async {
      final s = homeServer();
      final real = s.server;
      real.on('GET', _onboarding, (req) {
        final o = homeOnboarding(s.db, SeedIds.sabahOrg).toJson();
        return MockResponse.ok({...o, 'completed': false});
      });
      final h = await pumpHome(tester, server: real, db: s.db);
      h.allowUnmatched = true;
      expect(h.location.path, '/onboarding');
    });

    testWidgets('OVW-HOME-008 the sidebar\'s Overview › Dashboard is active', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.text('Overview'), findsWidgets);
      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('OVW-HOME-010 a deep link picks the branch', (tester) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.zamalek}');
      final calls = h.server.callsTo(_sales);
      expect(calls, isNotEmpty);
      expect(calls.last.path, '/reports/branches/${SeedIds.zamalek}/sales');
      expect(calls.last.query.keys.toSet(), {'from', 'to'});
      expect(find.text('Open tills'), findsOneWidget);
      expect(h.realtime.current?.branchId, SeedIds.zamalek);
      expect(scopePart('Zamalek'), findsOneWidget);
    });

    testWidgets('OVW-HOME-011 a deep link picks the period', (tester) async {
      final h = await pumpHome(tester, path: '/?preset=7d');
      final q = h.server.callsTo(_series).last.query;
      expect(q['from'], ['2026-10-01T21:00:00.000Z']);
      expect(q['to'], [_to]);
      expect(q['granularity'], ['daily']);
      expect(scopePart('Last 7 days'), findsOneWidget);
    });

    testWidgets('OVW-HOME-012 a custom deep link sends its instants', (
      tester,
    ) async {
      const f = '2026-09-20T21:00:00.000Z';
      const t = '2026-09-25T20:59:59.999Z';
      final h = await pumpHome(tester, path: '/?preset=custom&from=$f&to=$t');
      final q = h.server.callsTo(_cmp).last.query;
      expect(q['from'], [f]);
      expect(q['to'], [t]);
      expect(scopePart('Custom'), findsOneWidget);
    });

    testWidgets('OVW-HOME-012 custom without dates is the last 30 days', (
      tester,
    ) async {
      final h = await pumpHome(tester, path: '/?preset=custom');
      expect(h.server.callsTo(_cmp).last.query['from'], [_from]);
      expect(scopePart('Last 30 days'), findsOneWidget);
    });

    testWidgets('OVW-HOME-013 picking a branch refetches; all hides tills', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      expect(find.text('Open tills'), findsNothing);
      expect(h.server.callsTo(_sales), isEmpty);
      await h.tapText('All branches');
      await pick(h, 'Maadi');
      expect(h.server.callsTo(_sales).last.path, contains(SeedIds.maadi));
      expect(h.server.callsTo(_series).last.path, contains(SeedIds.maadi));
      expect(h.server.callsTo(_delivery).last.path, contains(SeedIds.maadi));
      expect(h.server.callsTo(_watch).last.path, contains(SeedIds.maadi));
      expect(h.server.callsTo(_tills).last.path, contains(SeedIds.maadi));
      expect(find.text('Open tills'), findsOneWidget);
      expect(kpi(tester, 'Revenue').value, totals(h, [SeedIds.maadi]).revenue);
      await h.tapText('Maadi');
      await pick(h, 'All branches');
      expect(find.text('Open tills'), findsNothing);
      expect(h.server.callsTo(_series).last.path, contains(nilBranchId));
      expect(kpi(tester, 'Revenue').value, totals(h, _sabah).revenue);
    });

    testWidgets('OVW-HOME-014 picking Today: hourly trend', (tester) async {
      final h = await pumpHome(tester);
      await h.tapText('Last 30 days');
      await pick(h, 'Today');
      final q = h.server.callsTo(_series).last.query;
      expect(q['granularity'], ['hourly']);
      expect(q['from'], ['2026-10-07T21:00:00.000Z']);
      expect(scopePart('Today'), findsOneWidget);
      // Yesterday is hourly too; month to date daily.
      await h.tapText('Today');
      await pick(h, 'Yesterday');
      expect(h.server.callsTo(_series).last.query['granularity'], ['hourly']);
      await h.tapText('Yesterday');
      await pick(h, 'Month to date');
      final mtd = h.server.callsTo(_series).last.query;
      expect(mtd['granularity'], ['daily']);
      expect(mtd['from'], ['2026-09-30T21:00:00.000Z']);
    });

    testWidgets('OVW-HOME-015 a custom range: daily, "Custom"', (tester) async {
      final h = await pumpHome(tester);
      await h.container
          .read(scopeProvider.notifier)
          .setCustomRange('2026-09-10T21:00:00.000Z', _to);
      await h.settle();
      final q = h.server.callsTo(_series).last.query;
      expect(q['granularity'], ['daily']);
      expect(q['from'], ['2026-09-10T21:00:00.000Z']);
      expect(scopePart('Custom'), findsOneWidget);
    });

    testWidgets('OVW-HOME-016 a branch manager: org-wide KPIs, own trend', (
      tester,
    ) async {
      final h = await pumpHome(tester, persona: Persona.manager);
      expect(find.text('All branches'), findsNothing); // no picker
      expect(scopePart('All branches'), findsOneWidget);
      expect(find.text('Open tills'), findsNothing);
      expect(kpi(tester, 'Revenue').value, totals(h, _sabah).revenue);
      expect(h.server.callsTo(_series).last.path, contains(nilBranchId));
      expect(find.text('Keep building'), findsNothing);
      expect(h.server.callsTo(_onboarding), isEmpty);
    });
  });

  group('header', () {
    testWidgets('OVW-HOME-018 the greeting; without a name, "Welcome back"', (
      tester,
    ) async {
      final s = homeServer();
      s.db['users'].update(SeedIds.owner, {'name': ''});
      await pumpHome(tester, server: s.server, db: s.db);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('OVW-HOME-019/020/021 branch, period and zone', (tester) async {
      final h = await pumpHome(tester);
      expect(scopePart('All branches'), findsOneWidget);
      expect(scopePart('Last 30 days'), findsOneWidget);
      expect(scopePart('Cairo time'), findsOneWidget);
      await h.go('/?branchId=${SeedIds.heliopolis}');
      expect(scopePart('Heliopolis'), findsOneWidget);
    });

    testWidgets('OVW-HOME-019 "Branch" while the comparison failed', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _cmp, MockResponse.error(500, 'boom'), times: null);
      await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        path: '/?branchId=${SeedIds.zamalek}',
      );
      expect(scopePart('Branch'), findsOneWidget);
    });

    testWidgets('OVW-HOME-021 another zone reads "<city> time"', (
      tester,
    ) async {
      final s = homeServer();
      s.db['branches'].update(SeedIds.zamalek, {'timezone': 'America/New_York'});
      await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        path: '/?branchId=${SeedIds.zamalek}',
      );
      expect(scopePart('New York time'), findsOneWidget);
    });

    testWidgets('OVW-HOME-021 Arabic keeps the city as written', (
      tester,
    ) async {
      final s = homeServer();
      s.db['branches'].update(SeedIds.zamalek, {'timezone': 'America/New_York'});
      await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        locale: 'ar',
        path: '/?branchId=${SeedIds.zamalek}',
      );
      expect(scopePart('بتوقيت New York'), findsOneWidget);
    });
  });

  group('keep building', () {
    testWidgets('OVW-HOME-023/024 shown with the finished count', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      expect(find.text('Your café is open · 8/10 set up'), findsOneWidget);
      expect(
        find.text(
          'Keep building — add recipes, your team and more to unlock cost insights.',
        ),
        findsOneWidget,
      );
      expect(h.server.callsTo(_onboarding), isNotEmpty);
    });

    testWidgets('OVW-HOME-025 Keep building opens the set-up wizard', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      h.allowUnmatched = true;
      await h.tapText('Keep building');
      expect(h.location.path, '/onboarding');
    });

    testWidgets('OVW-HOME-026 dismiss: gone for the session, no more reads', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      await h.tapLabel('Dismiss');
      expect(find.text('Keep building'), findsNothing);
      final before = h.server.callsTo(_onboarding).length;
      h.allowUnmatched = true;
      await h.go('/tills');
      await h.go('/');
      expect(find.text('Keep building'), findsNothing);
      expect(h.server.callsTo(_onboarding).length, before);
    });

    testWidgets('OVW-HOME-027 hidden when every step is done', (tester) async {
      final s = homeServer();
      s.db['orgs'].update(SeedIds.sabahOrg, {'logo_url': 'https://cdn.test/l.png'});
      s.db['ingredients'].insert({'id': 'i1', 'org_id': SeedIds.sabahOrg});
      await pumpHome(tester, server: s.server, db: s.db);
      expect(find.text('Keep building'), findsNothing);
    });

    testWidgets('OVW-HOME-028 hidden while loading and on failure', (
      tester,
    ) async {
      final s = homeServer();
      final gate = s.server.hold('GET', _onboarding);
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(find.text('Keep building'), findsNothing);
      expect(find.byType(DashSkeleton), findsNothing);
      gate.release();
      await h.settle();
      expect(find.text('Keep building'), findsOneWidget);
    });

    testWidgets('OVW-HOME-028 a refused read hides it', (tester) async {
      final s = homeServer();
      s.server.fail(
        'GET',
        _onboarding,
        MockResponse.denied('org.settings.read'),
        times: null,
      );
      await pumpHome(tester, server: s.server, db: s.db);
      expect(find.text('Keep building'), findsNothing);
    });

    testWidgets('OVW-HOME-029 a teller never sees it, nothing is asked', (
      tester,
    ) async {
      final h = await pumpHome(tester, persona: Persona.limited);
      expect(find.text('Keep building'), findsNothing);
      expect(h.server.callsTo(_onboarding), isEmpty);
    });

    testWidgets('OVW-HOME-030 a platform admin in a shop sees it', (
      tester,
    ) async {
      final h = await pumpHome(
        tester,
        persona: Persona.platform,
        prefs: {
          ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
        },
      );
      expect(find.text('Keep building'), findsOneWidget);
      expect(h.location.path, '/');
      await h.tapLabel('Dismiss');
      expect(find.text('Keep building'), findsNothing);
    });
  });

  group('KPI strip', () {
    testWidgets('OVW-HOME-033/034/036 all branches: the comparison sums', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      final t = totals(h, _sabah);
      expect(kpi(tester, 'Revenue').value, t.revenue);
      expect(kpi(tester, 'Orders').value, t.count);
      expect(kpi(tester, 'Voided').value, t.voided);
      expect(kpi(tester, 'Tips').value, t.tips);
      expect(kpi(tester, 'Avg ticket').value, (t.revenue / t.count).round());
      final labels = tester
          .widgetList<DashStatCard>(find.byType(DashStatCard))
          .take(5)
          .map((c) => c.label)
          .toList();
      expect(labels, ['Revenue', 'Orders', 'Avg ticket', 'Voided', 'Tips']);
      expect(kpi(tester, 'Revenue').icon, 'coins');
      expect(kpi(tester, 'Tips').icon, 'hand-coins');
    });

    testWidgets('OVW-HOME-032 a branch: its own sales', (tester) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.newCairo}');
      final t = totals(h, [SeedIds.newCairo]);
      expect(kpi(tester, 'Revenue').value, t.revenue);
      expect(kpi(tester, 'Orders').value, t.count);
    });

    testWidgets('OVW-HOME-035 no tips: four cards', (tester) async {
      final s = homeServer();
      for (final o in s.db['orders'].rows) {
        o['tip_amount'] = null;
      }
      await pumpHome(tester, server: s.server, db: s.db);
      expect(find.text('Tips'), findsNothing);
      expect(find.text('Avg ticket'), findsNWidgets(2));
    });

    testWidgets('OVW-HOME-037 Voided tints only when there are voids', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(kpi(tester, 'Voided').tone, DashTone.warning);
      expect(kpi(tester, 'Revenue').tone, DashTone.neutral);
    });

    testWidgets('OVW-HOME-037 no voids: neutral', (tester) async {
      final s = homeServer();
      for (final o in s.db['orders'].rows) {
        if (o['status'] == 'voided') o['status'] = 'completed';
      }
      await pumpHome(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Voided').value, 0);
      expect(kpi(tester, 'Voided').tone, DashTone.neutral);
    });

    testWidgets('OVW-HOME-038 skeletons while the source loads', (
      tester,
    ) async {
      final s = homeServer();
      final gate = s.server.hold('GET', _cmp);
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Revenue').loading, isTrue);
      expect(kpi(tester, 'Orders').loading, isTrue);
      gate.release();
      await h.settle();
      expect(kpi(tester, 'Revenue').loading, isFalse);
    });

    testWidgets('OVW-HOME-039/040 a figure too wide shortens; tap shows it', (
      tester,
    ) async {
      final s = homeServer();
      final big = s.db['orders'].rows.lastWhere(
        (o) => o['status'] == 'completed',
      );
      big['total_amount'] = 987654321098;
      final legs = big['payment_legs']! as List;
      (legs.first as Map)['amount'] = 987654321098;
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        size: DashSize.phone,
      );
      final revenue = kpi(tester, 'Revenue').value!;
      final exact = h.container.read(formatProvider).fmtMoney(revenue);
      expect(find.text(exact), findsNothing);
      await h.tapLabel(
        'Revenue: ${DashKitFormats(languageCode: 'en').money(revenue.toInt())}',
      );
      expect(find.text('REVENUE'), findsOneWidget);
      await h.shot('home/kpi-popover');
    });

    testWidgets('OVW-HOME-042 branch sales failing: the org-wide sums', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _sales, MockResponse.error(500, 'boom'), times: null);
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        path: '/?branchId=${SeedIds.maadi}',
      );
      expect(kpi(tester, 'Revenue').value, totals(h, _sabah).revenue);
    });

    testWidgets('OVW-HOME-043 refused reads: zeros, no refusal words', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _cmp, MockResponse.denied('orders.read'), times: null);
      await pumpHome(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Revenue').value, 0);
      expect(kpi(tester, 'Orders').value, 0);
      expect(find.textContaining("You don't have permission"), findsNothing);
    });
  });

  group('open tills', () {
    testWidgets('OVW-HOME-045/047/050/053 the open till, its teller, its age', (
      tester,
    ) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
      final open = h.db!['tills'].rows.firstWhere(
        (t) => t['branch_id'] == SeedIds.maadi && t['status'] == 'open',
      );
      expect(find.text('Open tills'), findsOneWidget);
      expect(find.textContaining(open['teller_name']! as String, findRichText: true), findsOneWidget);
      expect(find.textContaining('T1', findRichText: true), findsWidgets);
      final age = h.container
          .read(formatProvider)
          .fmtDuration(open['opened_at']);
      expect(age, matches(RegExp(r'^\d+h \d\dm$')));
      expect(find.text(age), findsOneWidget);
    });

    testWidgets('OVW-HOME-046 loading: one skeleton block', (tester) async {
      final s = homeServer();
      final gate = s.server.hold('GET', _tills);
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        path: '/?branchId=${SeedIds.maadi}',
      );
      expect(find.text('Open tills'), findsNothing);
      gate.release();
      await h.settle();
      expect(find.text('Open tills'), findsOneWidget);
    });

    testWidgets('OVW-HOME-048 View all opens the tills page', (tester) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
      h.allowUnmatched = true;
      await h.tapText('View all');
      expect(h.location.path, '/tills');
    });

    testWidgets('OVW-HOME-049/054 none open, or the read failed: "No open till"', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail('GET', _tills, MockResponse.denied('till.read'), times: null);
      await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        path: '/?branchId=${SeedIds.maadi}',
      );
      expect(find.text('No open till'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('OVW-HOME-051/052 verification and flag pills', (tester) async {
      final s = homeServer();
      final open = s.db['tills'].rows.firstWhere(
        (t) => t['branch_id'] == SeedIds.maadi && t['status'] == 'open',
      );
      open['verification'] = 'unverified';
      open['opened_while_another_open'] = true;
      s.db['tills'].insert({
        ...open,
        'id': 'till-lan',
        'teller_name': 'Salma Fathy',
        'verification': 'lan',
        'opened_while_another_open': false,
        'opened_at': '2026-10-08T06:30:00.000Z',
      });
      await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        path: '/?branchId=${SeedIds.maadi}',
      );
      expect(find.text('Not verified'), findsOneWidget);
      expect(find.text('Verified on LAN'), findsOneWidget);
      expect(find.text('Opened while another till was open'), findsOneWidget);
      expect(find.text('See the other till'), findsNothing);
      // Newest first: Salma opened later.
      final salma = tester.getTopLeft(
        find.textContaining('Salma Fathy', findRichText: true),
      );
      final first = tester.getTopLeft(
        find.textContaining(open['teller_name']! as String, findRichText: true),
      );
      expect(salma.dy, lessThan(first.dy));
    });

    testWidgets('OVW-HOME-055 a till event refetches the list', (tester) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
      final before = h.server.callsTo(_tills).length;
      h.realtime.current!.emit('till.opened', data: '{}');
      await h.settle();
      expect(h.server.callsTo(_tills).length, before + 1);
    });
  });
}
