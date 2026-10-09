// `/reports/loyalty` Loyalty, driven through the real app shell (inventory
// rows REP-LOY-001 to -018): the gate, the tabs, the behaviour KPIs, the
// campaigns and the liability trend, with their loading, error and empty
// states.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/loyalty_inventory_staff/liability_chart.dart';
import 'package:dashboard_reports/src/loyalty_inventory_staff/loyalty_report_page.dart';
import 'package:dashboard_reports/src/mock/loyalty_inventory_staff_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

DashStatCard kpi(WidgetTester tester, String key) =>
    tester.widget<DashStatCard>(find.byKey(ValueKey(key)));

LoyaltyBehavior behaviorOf(MockDb db, {List<String>? branches}) =>
    loyaltyBehavior(
      db,
      orgId: SeedIds.sabahOrg,
      branches: branches,
      from: DateTime.parse(defaultFrom),
      to: DateTime.parse(defaultTo),
    );

void main() {
  group('the gate', () {
    testWidgets('REP-LOY-001 without loyalty.members.list: Restricted '
        '"Loyalty", the behaviour never asked', (tester) async {
      final h = await pumpUnit(tester, path: loyaltyPath, persona: Persona.limited);
      expect(find.text('Loyalty'), findsWidgets);
      expect(find.text('Not available on this account'), findsOneWidget);
      expect(find.text(h.t('reports.noAccess')), findsOneWidget);
      expect(callsUnder(h, '/loyalty'), isEmpty);
      await h.shot('loyalty/restricted');
    });

    for (final (name, caps) in [
      ('loyalty.read only', {Cap.loyaltyRead}),
      ('customers.view + customers.merge', {Cap.customersView, Cap.customersMerge}),
    ]) {
      testWidgets('REP-LOY-001 $name is not enough', (tester) async {
        final s = unitServer();
        authzWith(s.server, Persona.owner, caps);
        final h = await pumpUnit(
          tester,
          path: loyaltyPath,
          server: s.server,
          db: s.db,
        );
        expect(find.text(h.t('reports.noAccess')), findsOneWidget);
        expect(callsUnder(h, '/loyalty'), isEmpty);
      });
    }

    testWidgets('REP-LOY-001 Restricted in Arabic', (tester) async {
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        persona: Persona.limited,
        locale: 'ar',
        size: DashSize.phone,
      );
      expect(find.text('الولاء'), findsWidgets);
      expect(find.text(h.t('reports.noAccess')), findsOneWidget);
      await h.shot('loyalty/restricted');
    });

    testWidgets('REP-LOY-001 a manager sees the report', (tester) async {
      final h = await pumpUnit(tester, path: loyaltyPath, persona: Persona.manager);
      expect(find.text(h.t('reports.noAccess')), findsNothing);
      final call = h.server.callsTo(behaviorTpl).single;
      expect(call.status, 200);
      // All branches: the server counts only the branches she works at.
      expect(call.query.containsKey('branch_id'), isFalse);
      final zamalek = loyaltyBehavior(
        MockDb.seeded(),
        orgId: SeedIds.sabahOrg,
        branches: [SeedIds.zamalek],
        from: DateTime.parse(defaultFrom),
        to: DateTime.parse(defaultTo),
      );
      expect(kpi(tester, 'active_member_rate').value, zamalek.activeMemberRate);
    });
  });

  group('header and tabs', () {
    testWidgets('REP-LOY-002 title, period, Overview / Campaigns / Liability; '
        'no export', (tester) async {
      final h = await pumpUnit(tester, path: loyaltyPath);
      expect(inPage(find.text('Loyalty')), findsOneWidget);
      expect(inPage(find.text('Last 30 days')), findsOneWidget);
      for (final l in ['Overview', 'Campaigns', 'Liability']) {
        expect(tabLabel(l), findsOneWidget, reason: l);
      }
      final strip = tester.widget<DashTabStrip<String>>(
        find.byType(DashTabStrip<String>),
      );
      expect(strip.value, 'overview');
      expect(find.byType(DashExportButton), findsNothing);
      expect(find.byType(DashLedgerStrip), findsOneWidget);
    });

    testWidgets('REP-LOY-002 the tabs in Arabic, first on the right', (
      tester,
    ) async {
      await pumpUnit(tester, path: loyaltyPath, locale: 'ar');
      final a = tester.getCenter(tabLabel('نظرة عامة'));
      final b = tester.getCenter(tabLabel('الحملات'));
      expect(a.dx, greaterThan(b.dx));
      expect(tabLabel('الالتزامات'), findsOneWidget);
    });
  });

  group('overview', () {
    testWidgets('REP-LOY-003 all branches: no branch_id, the scope\'s '
        'instants', (tester) async {
      final h = await pumpUnit(tester, path: loyaltyPath);
      final q = h.server.callsTo(behaviorTpl).single.query;
      expect(q.containsKey('branch_id'), isFalse);
      expect(q['from'], [defaultFrom]);
      expect(q['to'], [defaultTo]);
    });

    testWidgets('REP-LOY-003 a branch narrows the activity, not the member '
        'totals', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        branchId: SeedIds.maadi,
        server: s.server,
        db: s.db,
      );
      expect(h.server.callsTo(behaviorTpl).single.query['branch_id'], [
        SeedIds.maadi,
      ]);
      final all = behaviorOf(s.db);
      final maadi = behaviorOf(s.db, branches: [SeedIds.maadi]);
      expect(maadi.totalMembers, all.totalMembers);
      expect(kpi(tester, 'active_member_rate').hint, contains(
        'of ${all.totalMembers} members',
      ));
      expect(kpi(tester, 'active_member_rate').value, maadi.activeMemberRate);
    });

    testWidgets('REP-LOY-004…008 the five KPIs: labels, rates, hints', (
      tester,
    ) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      final b = behaviorOf(s.db);
      final f = fmtOf(h);
      final active = kpi(tester, 'active_member_rate');
      expect(active.label, 'Active member rate');
      expect(active.format, DashStatFormat.percent);
      expect(active.value, b.activeMemberRate);
      expect(
        active.hint,
        '${f.fmtNumber(b.activeMembers)} of ${f.fmtNumber(b.totalMembers)} members',
      );
      final rate = kpi(tester, 'redemption_rate');
      expect(rate.label, 'Redemption rate');
      expect(rate.value, b.redemptionRate);
      expect(rate.hint, '${b.membersEverRedeemed} members have ever redeemed');
      final ratio = kpi(tester, 'redemption_ratio');
      expect(ratio.label, 'Points redeemed vs earned');
      expect(ratio.value, b.redemptionRatio);
      expect(ratio.hint, 'This period');
      final repeat = kpi(tester, 'repeat_visit_rate');
      expect(repeat.label, 'Repeat visit rate');
      expect(repeat.value, b.repeatVisitRate);
      // earning = repeat + one-time, worked out on the page (REP-LOY-007).
      expect(
        repeat.hint,
        '${b.repeatMembers} of ${b.repeatMembers + b.oneTimeMembers} '
        'earning members came back',
      );
      final share = kpi(tester, 'new_member_share');
      expect(share.label, 'New member share');
      expect(share.tone, DashTone.warning);
      expect(share.value, b.newMemberShare);
      expect(
        share.hint,
        '${b.newMembersActive} of ${b.activeMembers} active members joined '
        'this period',
      );
      // The figures as they read: a percent with at most one decimal.
      expect(figure(f.fmtPercent(b.activeMemberRate)), findsOneWidget);
      expect(figure(f.fmtPercent(b.redemptionRatio)), findsOneWidget);
    });

    testWidgets('REP-LOY-004…008 the KPIs in Arabic', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
        locale: 'ar',
      );
      final b = behaviorOf(s.db);
      expect(kpi(tester, 'active_member_rate').label, 'نسبة الأعضاء النشطين');
      expect(
        kpi(tester, 'active_member_rate').hint,
        '${b.activeMembers} من ${b.totalMembers} عضو',
      );
      expect(kpi(tester, 'active_member_rate').value, b.activeMemberRate);
      await h.shot('loyalty/overview');
    });

    testWidgets('REP-LOY-009 loading shows the KPI skeletons', (tester) async {
      final s = unitServer();
      final gate = s.server.hold('GET', behaviorTpl);
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      expect(kpi(tester, 'active_member_rate').loading, isTrue);
      expect(find.byType(DashErrorState), findsNothing);
      await h.shot('loyalty/overview-loading');
      gate.release();
      await h.settle();
      expect(kpi(tester, 'active_member_rate').loading, isFalse);
    });

    testWidgets('REP-LOY-009/018 a failed read replaces only the KPI strip '
        'with ErrorState + Retry; Retry asks again', (tester) async {
      final s = unitServer();
      s.server.fail('GET', behaviorTpl, MockResponse.error(500, 'boom'));
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      expect(find.byType(DashLedgerStrip), findsNothing);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      // The header and the tabs stay.
      expect(tabLabel('Campaigns'), findsOneWidget);
      await h.shot('loyalty/overview-failed');
      await h.tap(inPage(find.text('Retry')));
      expect(h.server.callsTo(behaviorTpl), hasLength(2));
      expect(find.byType(DashLedgerStrip), findsOneWidget);
      expect(callsUnder(h, '/loyalty'), hasLength(2));
    });

    testWidgets('REP-LOY-009 zeros for an org with no members', (tester) async {
      final s = unitServer();
      for (final c in [...s.db['customers'].rows]) {
        s.db['customers'].update(c['id']! as String, {'is_member': false});
      }
      await pumpUnit(tester, path: loyaltyPath, server: s.server, db: s.db);
      expect(kpi(tester, 'active_member_rate').value, 0);
      expect(kpi(tester, 'active_member_rate').hint, '0 of 0 members');
      expect(kpi(tester, 'new_member_share').value, 0);
    });
  });

  group('campaigns', () {
    testWidgets('REP-LOY-010 asked only when the tab opens, with the '
        'scope', (tester) async {
      final h = await pumpUnit(tester, path: loyaltyPath);
      expect(h.server.callsTo(campaignsTpl), isEmpty);
      expect(h.server.callsTo(liabilityTpl), isEmpty);
      await openTab(h, 'Campaigns');
      final q = h.server.callsTo(campaignsTpl).single.query;
      expect(q['from'], [defaultFrom]);
      expect(q['to'], [defaultTo]);
      expect(q.containsKey('branch_id'), isFalse);
      expect(h.server.callsTo(liabilityTpl), isEmpty);
    });

    testWidgets('REP-LOY-012 a row per campaign: name, return rate, bar, '
        'hint', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Campaigns');
      final c = loyaltyCampaigns(
        s.db,
        orgId: SeedIds.sabahOrg,
        from: DateTime.parse(defaultFrom),
        to: DateTime.parse(defaultTo),
      );
      final f = fmtOf(h);
      expect(inPage(find.text('Win-back')), findsOneWidget);
      expect(inPage(find.text('Birthday')), findsOneWidget);
      for (final r in c.campaigns) {
        final row = find.byKey(ValueKey('campaign-${r.campaign}'));
        expect(
          find.descendant(of: row, matching: figure(f.fmtPercent(r.returnRate))),
          findsOneWidget,
        );
        final bar = tester.widget<DashProgressBar>(
          find.descendant(of: row, matching: find.byType(DashProgressBar)),
        );
        expect(bar.value, r.returnRate);
        expect(bar.max, 1);
        expect(
          find.descendant(
            of: row,
            matching: find.text(
              '${r.returnedWithin30d} of ${r.sent} nudged members earned '
              'again within 30 days',
            ),
          ),
          findsOneWidget,
        );
      }
      await h.shot('loyalty/campaigns');
    });

    testWidgets('REP-LOY-012 an unknown campaign shows its code', (
      tester,
    ) async {
      final s = unitServer();
      s.server.on('GET', campaignsTpl, (req) {
        return MockResponse.ok(
          CampaignEffectiveness(
            from: DateTime.parse(defaultFrom),
            to: DateTime.parse(defaultTo),
            campaigns: [
              CampaignEffectivenessRow(
                campaign: 'reengage',
                sent: 4,
                returnedWithin30d: 1,
                returnRate: 0.25,
              ),
            ],
          ),
        );
      });
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Campaigns');
      expect(inPage(find.text('reengage')), findsOneWidget);
      expect(figure('25%'), findsOneWidget);
    });

    testWidgets('REP-LOY-011 loading: two skeletons in a card', (tester) async {
      final s = unitServer();
      final gate = s.server.hold('GET', campaignsTpl);
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Campaigns');
      expect(
        find.descendant(
          of: find.byType(LoyaltyCampaignsTab),
          matching: find.byType(DashSkeleton),
        ),
        findsNWidgets(2),
      );
      expect(inPage(find.text(h.t('reports.loyalty.noCampaigns'))), findsNothing);
      gate.release();
      await h.settle();
      expect(inPage(find.text('Win-back')), findsOneWidget);
    });

    testWidgets('REP-LOY-011 failed: ErrorState + Retry', (tester) async {
      final s = unitServer();
      s.server.fail('GET', campaignsTpl, MockResponse.error(500, 'boom'));
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Campaigns');
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      await h.shot('loyalty/campaigns-failed');
      final behavior = h.server.callsTo(behaviorTpl).length;
      await h.tap(inPage(find.text('Retry')));
      expect(h.server.callsTo(campaignsTpl), hasLength(2));
      expect(h.server.callsTo(behaviorTpl), hasLength(behavior));
      expect(inPage(find.text('Win-back')), findsOneWidget);
    });

    for (final (name, rows) in [
      ('no campaigns', <CampaignEffectivenessRow>[]),
      (
        'nothing sent',
        [
          CampaignEffectivenessRow(
            campaign: 'winback',
            sent: 0,
            returnedWithin30d: 0,
            returnRate: 0,
          ),
          CampaignEffectivenessRow(
            campaign: 'birthday',
            sent: 0,
            returnedWithin30d: 0,
            returnRate: 0,
          ),
        ],
      ),
    ]) {
      testWidgets('REP-LOY-011 empty ($name)', (tester) async {
        final s = unitServer();
        s.server.on(
          'GET',
          campaignsTpl,
          (req) => MockResponse.ok(
            CampaignEffectiveness(
              from: DateTime.parse(defaultFrom),
              to: DateTime.parse(defaultTo),
              campaigns: rows,
            ),
          ),
        );
        final h = await pumpUnit(
          tester,
          path: loyaltyPath,
          server: s.server,
          db: s.db,
        );
        await openTab(h, 'Campaigns');
        expect(
          inPage(find.text('No outreach sent for this scope and period.')),
          findsOneWidget,
        );
        await h.shot('loyalty/campaigns-empty');
      });
    }

    testWidgets('REP-LOY-018 (divergence) a bar is named by the campaign\'s '
        'words, not its code', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await pumpUnit(tester, path: loyaltyPath, locale: 'ar');
      await openTab(h, 'الحملات');
      final bars = tester.widgetList<DashProgressBar>(
        find.byType(DashProgressBar),
      );
      expect(bars.map((b) => b.semanticLabel), ['استعادة العملاء', 'عيد الميلاد']);
      expect(find.bySemanticsLabel('winback'), findsNothing);
      semantics.dispose();
    });
  });

  group('liability', () {
    testWidgets('REP-LOY-013 asked only when the tab opens', (tester) async {
      final h = await pumpUnit(tester, path: loyaltyPath, branchId: SeedIds.zamalek);
      expect(h.server.callsTo(liabilityTpl), isEmpty);
      await openTab(h, 'Liability');
      final q = h.server.callsTo(liabilityTpl).single.query;
      expect(q['branch_id'], [SeedIds.zamalek]);
      expect(q['from'], [defaultFrom]);
    });

    testWidgets('REP-LOY-014/015 the card and the weekly bars', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Liability');
      expect(inPage(find.text('Liability trend')), findsOneWidget);
      // A visits programme counts orders.
      expect(
        inPage(find.text('Net orders earned minus redeemed each week')),
        findsOneWidget,
      );
      final trend = loyaltyLiability(
        s.db,
        orgId: SeedIds.sabahOrg,
        zone: 'Africa/Cairo',
        from: DateTime.parse(defaultFrom),
        to: DateTime.parse(defaultTo),
      );
      final f = fmtOf(h);
      final chart = tester.widget<LiabilityChart>(find.byType(LiabilityChart));
      expect(chart.labels, [for (final p in trend.points) f.fmtDate(p.week)]);
      expect(chart.labels.first, '05 Sept 2026');
      expect(chart.values, [
        for (final p in trend.points) p.outstanding.toDouble(),
      ]);
      expect(
        chart.tooltip(0),
        '${trend.points.first.outstanding} orders',
      );
      expect(chart.formatAxis(1200), '1,200');
      for (final l in chart.labels) {
        expect(inPage(find.text(l)), findsOneWidget, reason: l);
      }
      await h.shot('loyalty/liability');
    });

    testWidgets('REP-LOY-014/015 a points programme reads "points", one '
        '"point"', (tester) async {
      final s = unitServer();
      s.server.on(
        'GET',
        liabilityTpl,
        (req) => MockResponse.ok(
          LiabilityTrend(
            from: DateTime.parse(defaultFrom),
            to: DateTime.parse(defaultTo),
            currency: 'points',
            points: [
              LiabilityTrendPoint(
                week: DateTime.parse('2026-09-11T21:00:00Z'),
                outstanding: 1,
              ),
              LiabilityTrendPoint(
                week: DateTime.parse('2026-09-18T21:00:00Z'),
                outstanding: -240,
              ),
            ],
          ),
        ),
      );
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Liability');
      expect(
        inPage(find.text('Net points earned minus redeemed each week')),
        findsOneWidget,
      );
      final chart = tester.widget<LiabilityChart>(find.byType(LiabilityChart));
      expect(chart.tooltip(0), '1 point');
      expect(chart.tooltip(1), '−240 points');
      // A week that redeemed more than it earned goes below zero.
      final (lo, hi, _) = LiabilityChart.bounds(chart.values);
      expect(lo, lessThan(0));
      expect(hi, greaterThan(0));
      await h.shot('loyalty/liability-negative');
    });

    testWidgets('REP-LOY-014/015 in Arabic', (tester) async {
      final s = unitServer();
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
        locale: 'ar',
      );
      await openTab(h, 'الالتزامات');
      expect(inPage(find.text('اتجاه الالتزامات')), findsOneWidget);
      expect(
        inPage(find.text('صافي طلب المكتسبة مطروحًا منها المستبدلة أسبوعيًا')),
        findsOneWidget,
      );
      final chart = tester.widget<LiabilityChart>(find.byType(LiabilityChart));
      expect(chart.labels.first, '05 سبتمبر 2026');
    });

    testWidgets('REP-LOY-016/018 loading: a 288 px skeleton under the card\'s '
        'title', (tester) async {
      final s = unitServer();
      final gate = s.server.hold('GET', liabilityTpl);
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Liability');
      final sk = find.descendant(
        of: find.byType(LoyaltyLiabilityTab),
        matching: find.byType(DashSkeleton),
      );
      expect(sk, findsOneWidget);
      expect(tester.getSize(sk).height, 288);
      expect(inPage(find.text('Liability trend')), findsOneWidget);
      // While loading, the unit reads the default (points).
      expect(
        inPage(find.text('Net points earned minus redeemed each week')),
        findsOneWidget,
      );
      gate.release();
      await h.settle();
      expect(find.byType(LiabilityChart), findsOneWidget);
    });

    testWidgets('REP-LOY-016/018 failed: ErrorState + Retry inside the '
        'card', (tester) async {
      final s = unitServer();
      s.server.fail('GET', liabilityTpl, MockResponse.error(500, 'boom'));
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Liability');
      expect(inPage(find.text('Liability trend')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DashChartCard),
          matching: find.text("Couldn't load this"),
        ),
        findsOneWidget,
      );
      await h.shot('loyalty/liability-failed');
      await h.tap(inPage(find.text('Retry')));
      expect(h.server.callsTo(liabilityTpl), hasLength(2));
      expect(find.byType(LiabilityChart), findsOneWidget);
    });

    testWidgets('REP-LOY-016 empty: no loyalty activity', (tester) async {
      final s = unitServer();
      s.server.on(
        'GET',
        liabilityTpl,
        (req) => MockResponse.ok(
          LiabilityTrend(
            from: DateTime.parse(defaultFrom),
            to: DateTime.parse(defaultTo),
            currency: 'visits',
            points: const [],
          ),
        ),
      );
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Liability');
      expect(
        inPage(find.text('No loyalty activity for this scope and period.')),
        findsOneWidget,
      );
      await h.shot('loyalty/liability-empty');
    });
  });

  group('the reads', () {
    testWidgets('REP-LOY-017 each tab asks for its own report once; going '
        'back is served from the cache', (tester) async {
      final h = await pumpUnit(tester, path: loyaltyPath);
      await openTab(h, 'Campaigns');
      await openTab(h, 'Liability');
      await openTab(h, 'Overview');
      await openTab(h, 'Campaigns');
      expect(h.server.callsTo(behaviorTpl), hasLength(1));
      expect(h.server.callsTo(campaignsTpl), hasLength(1));
      expect(h.server.callsTo(liabilityTpl), hasLength(1));
      expect(callsUnder(h, '/loyalty').every((c) => c.status == 200), isTrue);
    });

    testWidgets('REP-LOY-017 a scope change asks again with the new '
        'params', (tester) async {
      final h = await pumpUnit(tester, path: loyaltyPath);
      h.container.read(scopeProvider.notifier).setBranch(SeedIds.newCairo);
      await h.settle();
      final calls = h.server.callsTo(behaviorTpl);
      expect(calls, hasLength(2));
      expect(calls.last.query['branch_id'], [SeedIds.newCairo]);
    });

    testWidgets('REP-LOY-017 a resync refetches the open tab; a till event '
        'does not', (tester) async {
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        branchId: SeedIds.zamalek,
      );
      h.realtime.current!.emit('till.opened', data: '{}');
      await h.settle();
      expect(h.server.callsTo(behaviorTpl), hasLength(1));
      h.realtime.current!.emit('resync', data: '{}');
      await h.settle();
      expect(h.server.callsTo(behaviorTpl), hasLength(2));
    });

    testWidgets('REP-LOY-001 a refusal from the server shows in the error '
        'state', (tester) async {
      final s = unitServer();
      s.server.fail(
        'GET',
        behaviorTpl,
        MockResponse.denied('loyalty.members.list'),
      );
      final h = await pumpUnit(
        tester,
        path: loyaltyPath,
        server: s.server,
        db: s.db,
      );
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(find.byType(DashLedgerStrip), findsNothing);
      // No server message on this page's error state (REP-LOY-018).
      expect(
        find.text(h.refusalWords(MockResponse.denied('loyalty.members.list'))),
        findsNothing,
      );
    });
  });

  testWidgets('REP-LOY-002 the phone layout stacks the KPIs two up', (
    tester,
  ) async {
    final h = await pumpUnit(
      tester,
      path: loyaltyPath,
      size: DashSize.phone,
      locale: 'ar',
    );
    final a = tester.getTopLeft(find.byKey(const ValueKey('active_member_rate')));
    final b = tester.getTopLeft(find.byKey(const ValueKey('redemption_rate')));
    final c = tester.getTopLeft(find.byKey(const ValueKey('redemption_ratio')));
    expect(a.dy, b.dy);
    expect(c.dy, greaterThan(a.dy));
    expect(h.server.callsTo(behaviorTpl), hasLength(1));
    await h.shot('loyalty/phone');
  });
}
