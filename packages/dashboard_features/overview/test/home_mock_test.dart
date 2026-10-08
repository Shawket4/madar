// The overview's mock backend: each read gates and scopes like the backend,
// and every figure agrees with every other (the totals a person compares
// across cards).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_overview/src/mock/home_figures.dart';
import 'package:dashboard_overview/src/mock/home_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// The default period: the last 30 Cairo days up to the seed's "now".
final from = DateTime.parse('2026-09-08T21:00:00.000Z');
final to = DateTime.parse('2026-10-08T20:59:59.999Z');

Future<Object> refusal(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

void main() {
  late MockServer server;
  late MockDb db;
  late DashboardApi api;

  setUp(() {
    final s = homeServer();
    server = s.server;
    db = s.db;
    api = DashboardApi(server);
  });

  test('every card adds up to the same revenue', () async {
    final cmp = await api.reports.orgBranchComparison(
      orgId: SeedIds.sabahOrg,
      from: from,
      to: to,
    );
    expect(cmp.branches, hasLength(4));
    final revenue = cmp.branches.fold(0, (s, b) => s + b.totalRevenue);
    final all = await api.reports.branchSales(
      branchId: nilBranchId,
      from: from,
      to: to,
    );
    expect(all.branchName, 'All branches');
    expect(all.totalRevenue, revenue);
    expect(
      all.totalOrders,
      cmp.branches.fold(0, (s, b) => s + b.totalOrders),
    );
    // The payment buckets are goods only and add up to revenue.
    final methods = (all.revenueByMethod! as Map).values.cast<int>();
    expect(methods.fold(0, (s, v) => s + v), revenue);
    // The trend's periods add up to the same total.
    final trend = await api.reports.branchSalesTimeseries(
      branchId: nilBranchId,
      from: from,
      to: to,
      granularity: 'daily',
    );
    expect(trend, hasLength(30));
    expect(trend.fold(0, (s, p) => s + p.revenue), revenue);
    // Delivered Talabat orders are the delivery revenue.
    final delivery = await api.reports.branchDeliverySales(
      branchId: nilBranchId,
      from: from,
      to: to,
    );
    final talabat = (all.revenueByMethod! as Map).entries
        .where((e) => '${e.key}'.startsWith('talabat'))
        .fold(0, (s, e) => s + (e.value as int));
    expect(delivery.totalRevenue, talabat);
    expect(delivery.totalRevenue, greaterThan(0));
  });

  test('comparison: every branch of the org, ranked, for anyone in it', () async {
    server.persona = Persona.manager;
    final cmp = await api.reports.orgBranchComparison(
      orgId: SeedIds.sabahOrg,
      from: from,
      to: to,
    );
    expect(cmp.branches.map((b) => b.branchName), hasLength(4));
    final revs = cmp.branches.map((b) => b.totalRevenue).toList();
    expect(revs, [...revs]..sort((a, b) => b.compareTo(a)));
    // Another org is refused.
    final e = await refusal(
      () => api.reports.orgBranchComparison(orgId: SeedIds.nakhlaOrg),
    );
    expect((e as ApiException).status, 403);
  });

  test('all branches rolls up only the caller\'s branches', () async {
    server.persona = Persona.manager;
    final mine = await api.reports.branchSalesTimeseries(
      branchId: nilBranchId,
      from: from,
      to: to,
    );
    server.persona = Persona.owner;
    final zamalek = await api.reports.branchSales(
      branchId: SeedIds.zamalek,
      from: from,
      to: to,
    );
    expect(mine.fold(0, (s, p) => s + p.revenue), zamalek.totalRevenue);
    // A branch the manager does not work at is refused.
    server.persona = Persona.manager;
    final e = await refusal(
      () => api.reports.branchSales(branchId: SeedIds.maadi),
    );
    expect((e as ApiException).message, contains('Not assigned to this branch'));
  });

  test('a platform admin with no org in scope is refused all branches', () async {
    server.persona = Persona.platform;
    final e = await refusal(
      () => api.reports.branchSales(branchId: nilBranchId),
    );
    expect((e as ApiException).status, 403);
    server.platformOrgId = SeedIds.sabahOrg;
    final ok = await api.reports.branchSales(
      branchId: nilBranchId,
      from: from,
      to: to,
    );
    expect(ok.totalOrders, greaterThan(0));
  });

  test('timeseries: naive wall-clock periods, only those with orders', () async {
    final today = await api.reports.branchSalesTimeseries(
      branchId: SeedIds.zamalek,
      from: DateTime.parse('2026-10-07T21:00:00.000Z'),
      to: DateTime.parse('2026-10-08T20:59:59.999Z'),
      granularity: 'hourly',
    );
    expect(today, isNotEmpty);
    for (final p in today) {
      expect(p.period, matches(RegExp(r'^2026-10-08T\d\d:00:00$')));
    }
    // Nothing after the seed's "now" (10:00 Cairo).
    expect(today.last.period.compareTo('2026-10-08T10:00:00'), lessThan(0));
  });

  test('delivery: the four channels, zero-filled, in order', () async {
    final d = await api.reports.branchDeliverySales(
      branchId: SeedIds.newCairo,
      from: from,
      to: to,
    );
    expect(d.channels.map((c) => c.channel), deliveryChannels);
    final outside = d.channels[1];
    expect(outside.revenue, d.totalRevenue);
    expect(d.channels[0].revenue, 0);
    expect(d.avgOrderValue, d.totalRevenue ~/ d.totalOrders);
  });

  test('margin watch: three best, three worst, signals, tallies', () async {
    final w = await api.insights.marginWatch(
      branchId: nilBranchId,
      from: from,
      to: to,
    );
    expect(w.top, hasLength(3));
    expect(w.bottom, hasLength(3));
    expect(w.top.first.margin! >= w.top.last.margin!, isTrue);
    expect(w.bottom.first.margin! <= w.bottom.last.margin!, isTrue);
    expect(w.targetPct, 60);
    expect(w.totals.marginKnown, greaterThan(0));
    // Six items have no recipe: their sold sizes are "missing cost".
    expect(w.rowsCostUnknown, greaterThanOrEqualTo(6));
    expect(w.openSignals, greaterThan(0));
    // The pricier recipes sit under the target.
    final flagged = {
      for (final r in [...w.top, ...w.bottom])
        if (r.flags.isNotEmpty) r.flags.first.kind,
    };
    expect(flagged, contains('below_target'));
    // 30 days back from the seed start has no orders: no previous margin.
    expect(w.totals.prevMarginKnown, 0);
    final week = await api.insights.marginWatch(
      branchId: nilBranchId,
      from: DateTime.parse('2026-10-01T21:00:00.000Z'),
      to: to,
    );
    expect(week.totals.prevMarginKnown, greaterThan(0));
  });

  test('open tills: the branch\'s open ones, newest first', () async {
    final tills = await api.tills.listOpenTills(branchId: SeedIds.maadi);
    expect(tills, hasLength(1));
    expect(tills.single.status, TillStatus.open);
    server.persona = Persona.manager;
    final e = await refusal(
      () => api.tills.listOpenTills(branchId: SeedIds.maadi),
    );
    expect((e as ApiException).status, 403);
  });

  test('onboarding: the backend\'s ten steps, from the org\'s data', () async {
    final o = await api.orgs.getOnboarding(id: SeedIds.sabahOrg);
    expect(o.steps.map((s) => s.key), [
      'org_profile',
      'branch',
      'payment_methods',
      'categories',
      'menu_items',
      'ingredients',
      'recipes',
      'addons',
      'team',
      'first_order',
    ]);
    expect(o.steps.where((s) => s.done), hasLength(8));
    expect(o.completed, isTrue);
    expect(o.canComplete, isTrue);
    expect(o.steps.firstWhere((s) => s.key == 'recipes').count, 34);
    // The read needs org.settings.read: a teller is refused.
    server.persona = Persona.limited;
    final e = await refusal(() => api.orgs.getOnboarding(id: SeedIds.sabahOrg));
    expect((e as ApiException).status, 403);
  });

  test('the recipe costs: six items without, ratios by category', () {
    expect(homeItemsWithRecipes(), 34);
    expect(homeUnitCost(MockSeed.menuItemId('v60'), 'one_size'), isNull);
    // An espresso single: EGP 70 at 24 %.
    expect(homeUnitCost(MockSeed.menuItemId('espresso'), 'Single'), 1680);
    expect(db['orders'].length, greaterThan(8000));
  });
}
