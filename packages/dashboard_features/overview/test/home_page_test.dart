// The home, driven through the real app shell (inventory rows OVW-HOME-001
// to -056): routing and scope, the header, the Setup card, the KPI
// strip and the Open tills card.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' show Readiness;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:dashboard_overview/src/home/home_kpis.dart';
import 'package:dashboard_overview/src/home/home_page.dart';
import 'package:dashboard_overview/src/home/home_parts.dart';
import 'package:dashboard_overview/src/setup/setup_card.dart';
import 'package:dashboard_overview/src/mock/home_figures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _sales = '/reports/branches/{branchId}/sales';
const _series = '/reports/branches/{branchId}/sales/timeseries';
const _cmp = '/reports/orgs/{orgId}/comparison';
const _delivery = '/reports/branches/{branchId}/delivery-sales';
const _watch = '/insights/branches/{branchId}/margin-watch';
const _tills = '/tills/branches/{branchId}/open';
const _readiness = '/orgs/{id}/readiness';
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
      expect(homeText('Welcome back, Nour El-Sayed'), findsOneWidget);
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
      s.server.fail(
        'GET',
        _modules,
        MockResponse.error(500, 'boom'),
        times: null,
      );
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
        homeText('Sales for this period will appear here.'),
        findsNWidgets(3),
      );
      expect(
        homeText('Margins appear here once items sell in this period'),
        findsOneWidget,
      );
      expect(kpi(tester, 'Delivery revenue').value, 0);
      expect(homeText('In-mall delivery'), findsNothing);
      expect(homeText('Open tills'), findsNothing);
      expect(find.byType(SetupHomeCard), findsNothing);
      expect(scopePart('All branches'), findsOneWidget);
      for (final t in [_sales, _series, _cmp, _delivery, _watch, _readiness]) {
        expect(h.server.callsTo(t), isEmpty, reason: t);
      }
    });

    testWidgets('OVW-HOME-006 an unfinished set-up sends nobody anywhere: '
        'the home opens with its card, the old checklist is never asked', (
      tester,
    ) async {
      final s = unfinishedServer();
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(h.location.path, '/');
      expect(find.byType(SetupHomeCard), findsOneWidget);
      expect(h.server.callsTo(_onboarding), isEmpty);
    });

    testWidgets('OVW-HOME-008 the sidebar\'s Overview › Dashboard is active', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      h.allowUnmatched = true; // the tills page is another area's
      final sidebar = find.byType(DashSidebar);
      Finder row(String text) =>
          find.descendant(of: sidebar, matching: find.text(text));
      expect(row('Overview'), findsOneWidget);
      expect(row('Dashboard'), findsOneWidget);
      expect(
        tester.getSemantics(row('Dashboard')),
        isSemantics(isSelected: true),
      );
      await h.go('/tills');
      expect(
        tester.getSemantics(row('Dashboard')),
        isSemantics(isSelected: false),
      );
      // The logo leads home too.
      await h.tap(
        find.descendant(of: sidebar, matching: find.byType(ShellWordmark)),
      );
      expect(h.location.path, '/');
      await h.tap(row('Orders'));
      await h.tap(row('Dashboard'));
      expect(h.location.path, '/');
    });

    testWidgets('OVW-HOME-010 a deep link picks the branch', (tester) async {
      final h = await pumpHome(tester, path: '/?branchId=${SeedIds.zamalek}');
      final calls = h.server.callsTo(_sales);
      expect(calls, isNotEmpty);
      expect(calls.last.path, '/reports/branches/${SeedIds.zamalek}/sales');
      expect(calls.last.query.keys.toSet(), {'from', 'to'});
      expect(homeText('Open tills'), findsOneWidget);
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
      expect(homeText('Open tills'), findsNothing);
      expect(h.server.callsTo(_sales), isEmpty);
      await h.tapText('All branches');
      await pick(h, 'Maadi');
      expect(h.server.callsTo(_sales).last.path, contains(SeedIds.maadi));
      expect(h.server.callsTo(_series).last.path, contains(SeedIds.maadi));
      expect(h.server.callsTo(_delivery).last.path, contains(SeedIds.maadi));
      expect(h.server.callsTo(_watch).last.path, contains(SeedIds.maadi));
      expect(h.server.callsTo(_tills).last.path, contains(SeedIds.maadi));
      expect(homeText('Open tills'), findsOneWidget);
      expect(kpi(tester, 'Revenue').value, totals(h, [SeedIds.maadi]).revenue);
      await h.tapText('Maadi');
      await pick(h, 'All branches');
      expect(homeText('Open tills'), findsNothing);
      // All branches again: its trend is still fresh (< 30 s), shown from the
      // cache without a second request, as the web's staleTime does.
      expect(
        h.server.callsTo(_series).where((c) => c.path.contains(nilBranchId)),
        hasLength(1),
      );
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
      expect(homeText('Open tills'), findsNothing);
      expect(kpi(tester, 'Revenue').value, totals(h, _sabah).revenue);
      expect(h.server.callsTo(_series).last.path, contains(nilBranchId));
      expect(find.byType(SetupHomeCard), findsNothing);
      expect(h.server.callsTo(_readiness), isEmpty);
    });
  });

  group('header', () {
    testWidgets('OVW-HOME-018 the greeting; without a name, "Welcome back"', (
      tester,
    ) async {
      final s = homeServer();
      s.db['users'].update(SeedIds.owner, {'name': ''});
      await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText('Welcome back'), findsOneWidget);
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
      s.db['branches'].update(SeedIds.zamalek, {
        'timezone': 'America/New_York',
      });
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
      s.db['branches'].update(SeedIds.zamalek, {
        'timezone': 'America/New_York',
      });
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

  group('setup card', () {
    /// The server answers [edit] of Sabah's real readiness.
    void answer(
      MockServer server,
      MockDb db,
      Readiness Function(Readiness) edit,
    ) => server.on('GET', _readiness, (req) {
      req.requireCap('org.settings.read');
      return MockResponse.ok(edit(mockReadiness(db, req.param('id'))));
    });

    testWidgets('a shop that is ready and has sold: no card, but the '
        'answer was asked', (tester) async {
      final h = await pumpHome(tester);
      expect(find.byType(SetupHomeCard), findsNothing);
      expect(h.server.callsTo(_readiness), isNotEmpty);
    });

    testWidgets('a blocking check: how many, the next one, Continue setup '
        'opens Setup', (tester) async {
      final s = unfinishedServer();
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText('One thing before your first sale'), findsOneWidget);
      expect(
        homeText(
          'Next: Payment. Nothing is left to pay with at Heliopolis, Maadi, '
          'New Cairo and 1 more.',
        ),
        findsOneWidget,
      );
      await h.tapText('Continue setup');
      expect(h.location.path, '/setup');
    });

    testWidgets('ready but no sale yet: ring up a first order', (tester) async {
      final s = homeServer();
      answer(
        s.server,
        s.db,
        (r) => Readiness(
          orgId: r.orgId,
          ready: true,
          live: false,
          checks: r.checks,
        ),
      );
      await pumpHome(tester, server: s.server, db: s.db);
      expect(homeText('Ready to sell'), findsOneWidget);
      expect(
        homeText('Ring up a first order on the tablet and you\'re live.'),
        findsOneWidget,
      );
      expect(homeText('Get the apps'), findsOneWidget);
    });

    testWidgets('a new blocking problem brings it back, without a reload', (
      tester,
    ) async {
      final h = await pumpHome(tester);
      expect(find.byType(SetupHomeCard), findsNothing);
      h.db!['payment_methods'].removeWhere(
        (r) => r['org_id'] == SeedIds.sabahOrg,
      );
      h.container.read(realtimeBusProvider).invalidate([
        '/orgs/${SeedIds.sabahOrg}/readiness',
      ]);
      await h.settle();
      expect(find.byType(SetupHomeCard), findsOneWidget);
    });

    testWidgets('a Dawam-only answer (no checks) shows nothing', (
      tester,
    ) async {
      final s = homeServer();
      answer(
        s.server,
        s.db,
        (r) => Readiness(
          orgId: r.orgId,
          ready: true,
          live: false,
          checks: const [],
        ),
      );
      await pumpHome(tester, server: s.server, db: s.db);
      expect(find.byType(SetupHomeCard), findsNothing);
    });

    testWidgets('hidden while loading and on a refusal', (tester) async {
      final s = unfinishedServer();
      final gate = s.server.hold('GET', _readiness);
      final h = await pumpHome(tester, server: s.server, db: s.db);
      expect(find.byType(SetupHomeCard), findsNothing);
      gate.release();
      await h.settle();
      expect(find.byType(SetupHomeCard), findsOneWidget);

      final refused = unfinishedServer();
      refused.server.fail(
        'GET',
        _readiness,
        MockResponse.denied('org.settings.read'),
        times: null,
      );
      await pumpHome(tester, server: refused.server, db: refused.db);
      expect(find.byType(SetupHomeCard), findsNothing);
    });

    testWidgets('a teller never sees it, nothing is asked', (tester) async {
      final s = unfinishedServer(persona: Persona.limited);
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        persona: Persona.limited,
      );
      expect(find.byType(SetupHomeCard), findsNothing);
      expect(h.server.callsTo(_readiness), isEmpty);
    });

    testWidgets('a platform admin in a shop sees it', (tester) async {
      final s = unfinishedServer(persona: Persona.platform);
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        persona: Persona.platform,
        prefs: {
          ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
        },
      );
      expect(find.byType(SetupHomeCard), findsOneWidget);
      expect(h.location.path, '/');
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
      expect(homeText('Tips'), findsNothing);
      expect(homeText('Avg ticket'), findsNWidgets(2));
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
      expect(homeText(exact), findsNothing);
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
      s.server.fail(
        'GET',
        _sales,
        MockResponse.error(500, 'boom'),
        times: null,
      );
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
      s.server.fail(
        'GET',
        _cmp,
        MockResponse.denied('orders.read'),
        times: null,
      );
      await pumpHome(tester, server: s.server, db: s.db);
      expect(kpi(tester, 'Revenue').value, 0);
      expect(kpi(tester, 'Orders').value, 0);
      expect(homeHas("You don't have permission"), findsNothing);
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
      expect(homeText('Open tills'), findsOneWidget);
      final count = h.db!['tills'].rows
          .where(
            (t) => t['branch_id'] == SeedIds.maadi && t['status'] == 'open',
          )
          .length;
      expect(
        find.descendant(
          of: find.byType(HomeOpenTillsCard),
          matching: find.text('$count'),
        ),
        findsOneWidget,
      );
      expect(
        homeHas(open['teller_name']! as String, findRichText: true),
        findsOneWidget,
      );
      expect(homeHas('T1', findRichText: true), findsWidgets);
      final age = h.container
          .read(formatProvider)
          .fmtDuration(open['opened_at']);
      expect(age, matches(RegExp(r'^\d+h \d\dm$')));
      expect(homeText(age), findsOneWidget);
    });

    testWidgets('OVW-HOME-045 16 px between the KPI strip and the card, at '
        'every width', (tester) async {
      for (final size in [DashSize.desktop, DashSize.phone]) {
        await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}', size: size);
        final strip = tester.getRect(find.byType(HomeKpiStrip));
        final card = tester.getRect(find.byType(HomeOpenTillsCard));
        expect(card.top - strip.bottom, 16, reason: '$size');
      }
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
      expect(homeText('Open tills'), findsNothing);
      final block = find.descendant(
        of: find.byType(HomeOpenTillsCard),
        matching: find.byType(HomeSkeleton),
      );
      expect(block, findsOneWidget);
      expect(tester.getSize(block).height, 96);
      gate.release();
      await h.settle();
      expect(homeText('Open tills'), findsOneWidget);
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('OVW-HOME-047/048 View all sits at the card\'s end edge '
          '($lang)', (tester) async {
        await pumpHome(
          tester,
          locale: lang,
          path: '/?branchId=${SeedIds.maadi}',
        );
        final card = tester.getRect(
          find.descendant(
            of: find.byType(HomeOpenTillsCard),
            matching: find.byType(DashCard),
          ),
        );
        final link = tester.getRect(
          find.descendant(
            of: find.byType(HomeOpenTillsCard),
            matching: find.byType(HomeLink),
          ),
        );
        if (lang == 'ar') {
          expect(link.left, closeTo(card.left + Space.lg, 1));
        } else {
          expect(link.right, closeTo(card.right - Space.lg, 1));
        }
        expect(link.center.dy, lessThan(card.top + Space.xxl + Space.sm));
      });
    }

    testWidgets('OVW-HOME-049 none open: "No open till" and 0', (tester) async {
      final s = homeServer();
      s.server.on('GET', _tills, (req) => MockResponse.ok(const []));
      await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        path: '/?branchId=${SeedIds.maadi}',
      );
      final card = find.byType(HomeOpenTillsCard);
      expect(
        find.descendant(of: card, matching: find.text('No open till')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('0')),
        findsOneWidget,
      );
    });

    testWidgets(
      'OVW-HOME-048 (divergence) View all opens the tills page, scope kept',
      (tester) async {
        final h = await pumpHome(tester, path: '/?branchId=${SeedIds.maadi}');
        h.allowUnmatched = true;
        await h.tapText('View all');
        expect(h.location.path, '/tills');
        // The scope is app state: the branch stays picked (divergence log).
        expect(h.container.read(currentScopeProvider).branchId, SeedIds.maadi);
      },
    );

    testWidgets('OVW-HOME-054 a refused read reads like none open', (
      tester,
    ) async {
      final s = homeServer();
      s.server.fail(
        'GET',
        _tills,
        MockResponse.denied('till.read'),
        times: null,
      );
      await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        path: '/?branchId=${SeedIds.maadi}',
      );
      expect(homeText('No open till'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(HomeOpenTillsCard),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(homeText('Retry'), findsNothing);
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
      expect(homeText('Not verified'), findsOneWidget);
      expect(homeText('Verified on LAN'), findsOneWidget);
      expect(homeText('Opened while another till was open'), findsOneWidget);
      expect(homeText('See the other till'), findsNothing);
      // Newest first: Salma opened later.
      final salma = tester.getTopLeft(
        homeHas('Salma Fathy', findRichText: true),
      );
      final first = tester.getTopLeft(
        homeHas(open['teller_name']! as String, findRichText: true),
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
