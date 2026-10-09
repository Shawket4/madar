// The Overview tab: its two reads, the five figures, the top rewards, the
// branch scope and its failure (SET-LOY-076 … 079, 085).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/mock/loyalty_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _overview(
  WidgetTester tester, {
  String query = '',
  ({MockServer server, MockDb db})? backend,
}) async {
  final h = await pumpLoyalty(tester, query: query, backend: backend);
  await openTab(h, 'Overview');
  return h;
}

DashStatCard _card(WidgetTester tester, String key) =>
    tester.widget<DashStatCard>(find.byKey(ValueKey(key)));

void main() {
  testWidgets('SET-LOY-076 the analytics and the member total (limit 1), '
      'each asked once', (tester) async {
    final h = await _overview(tester);
    expect(q1(h.server.callsTo(LoyaltyRoutes.analytics).single), isEmpty);
    expect(
      q1(h.server.callsTo(LoyaltyRoutes.members).single),
      {'limit': '1'},
    );
  });

  testWidgets('SET-LOY-077 a failure: "Couldn\'t work out the totals" and '
      'Retry, which re-reads both', (tester) async {
    final m = loyaltyServer();
    final boom = MockResponse.error(500, 'Database error: timeout');
    m.server.fail('GET', LoyaltyRoutes.analytics, boom, times: null);
    final h = await _overview(tester, backend: m);
    expect(pageText("Couldn't work out the totals"), findsOneWidget);
    expect(pageText(h.refusalWords(boom)), findsOneWidget);
    m.server.clearFailures();
    final a = h.server.callsTo(LoyaltyRoutes.analytics).length;
    final n = h.server.callsTo(LoyaltyRoutes.members).length;
    await h.tap(inPage(find.text('Retry')));
    expect(h.server.callsTo(LoyaltyRoutes.analytics), hasLength(a + 1));
    expect(h.server.callsTo(LoyaltyRoutes.members), hasLength(n + 1));
    expect(find.byKey(const ValueKey('stat-members')), findsOneWidget);
  });

  testWidgets('SET-LOY-078 loading: every card a skeleton; no top rewards '
      'until the analytics arrive (SET-LOY-085)', (tester) async {
    final m = loyaltyServer();
    final gate = m.server.hold('GET', LoyaltyRoutes.analytics);
    final h = await _overview(tester, backend: m);
    for (final k in [
      'stat-members',
      'stat-outstanding',
      'stat-liability',
      'stat-redemptions',
      'stat-value',
    ]) {
      expect(_card(tester, k).loading, isTrue, reason: k);
    }
    expect(find.byKey(const ValueKey('loyalty-top-rewards')), findsNothing);
    gate.release();
    await h.settle();
    expect(_card(tester, 'stat-members').loading, isFalse);
    expect(find.byKey(const ValueKey('loyalty-top-rewards')), findsOneWidget);
  });

  testWidgets('SET-LOY-078 the five figures, worded as the web words them',
      (tester) async {
    final m = loyaltyServer();
    final h = await _overview(tester, backend: m);
    final fmt = h.container.read(formatProvider);
    final now = m.db.clock.now;
    final a = loyaltyAnalyticsOf(
      m.db,
      org: SeedIds.sabahOrg,
      from: now.subtract(const Duration(days: 30)),
      to: now,
    );
    final members = m.db['customers'].rows
        .where((c) => c['is_member'] == true)
        .length;
    final l = a.liability;
    expect(_card(tester, 'stat-members').valueText, fmt.fmtNumber(members));
    expect(_card(tester, 'stat-members').label, 'Members');
    expect(
      _card(tester, 'stat-outstanding').valueText,
      '${fmt.fmtNumber(l.outstandingVisits)} orders',
    );
    expect(
      _card(tester, 'stat-outstanding').hint,
      'Held by ${l.membersWithBalance} members',
    );
    final liability = _card(tester, 'stat-liability');
    expect(liability.tone, DashTone.warning);
    expect(liability.valueText, fmt.fmtMoney(l.valuedMinor));
    expect(liability.hint, h.t('loyalty.statLiabilityValued'));
    expect(
      _card(tester, 'stat-redemptions').valueText,
      fmt.fmtNumber(a.redemptions),
    );
    expect(
      _card(tester, 'stat-redemptions').hint,
      '${fmt.fmtNumber(a.redeemedUnits)} items over the last 30 days',
    );
    expect(
      _card(tester, 'stat-value').valueText,
      fmt.fmtMoney(a.redeemedValueMinor),
    );
    expect(_card(tester, 'stat-value').hint, isNull);
  });

  testWidgets('SET-LOY-078 no redemptions to value the balances: "—"; '
      'refused redemptions: the hint', (tester) async {
    final m = loyaltyServer();
    m.db[LoyaltyTables.ledger].removeWhere((e) => e['kind'] == 'redeem');
    final order = m.db['orders'].rows.last;
    order['loyalty_redemption_refused'] = 'balance';
    final h = await _overview(tester, backend: m);
    expect(_card(tester, 'stat-liability').valueText, '—');
    expect(
      _card(tester, 'stat-liability').hint,
      h.t('loyalty.statLiabilityNoRedemptions'),
    );
    expect(_card(tester, 'stat-value').hint, '1 refused on sync');
    expect(
      pageText('No rewards redeemed in the last 30 days.'),
      findsOneWidget,
    );
  });

  testWidgets('SET-LOY-079 top rewards: name, "n redemptions · n items", '
      'the value', (tester) async {
    final m = loyaltyServer();
    final h = await _overview(tester, backend: m);
    final fmt = h.container.read(formatProvider);
    final now = m.db.clock.now;
    final a = loyaltyAnalyticsOf(
      m.db,
      org: SeedIds.sabahOrg,
      from: now.subtract(const Duration(days: 30)),
      to: now,
    );
    expect(a.topRewards, isNotEmpty);
    expect(pageText('Top rewards (last 30 days)'), findsOneWidget);
    final top = a.topRewards.first;
    final row = find.byKey(ValueKey('top-reward-${top.menuItemId}'));
    expect(find.descendant(of: row, matching: find.text(top.name)), findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          '${top.redemptions} redemptions · ${top.units} items',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining(fmt.fmtMoney(top.valueMinor)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SET-LOY-085 a branch in the header: both reads narrow to it',
      (tester) async {
    final h = await _overview(tester, query: atBranch(SeedIds.zamalek));
    expect(
      q1(h.server.callsTo(LoyaltyRoutes.analytics).single),
      {'branch_id': SeedIds.zamalek},
    );
    expect(
      q1(h.server.callsTo(LoyaltyRoutes.members).single),
      {'branch_id': SeedIds.zamalek, 'limit': '1'},
    );
  });

  testWidgets('phone: two cards a row', (tester) async {
    await pumpLoyalty(tester, size: DashSize.phone).then(
      (h) => openTab(h, 'Overview'),
    );
    final a = tester.getTopLeft(find.byKey(const ValueKey('stat-members'))).dy;
    final b = tester
        .getTopLeft(find.byKey(const ValueKey('stat-outstanding')))
        .dy;
    final c = tester.getTopLeft(find.byKey(const ValueKey('stat-liability'))).dy;
    expect(a, b);
    expect(c, greaterThan(a));
  });
}
