// Intent warming on Financial (owner rule, SPEC 6.1): pointing at a control
// whose press reads warms that exact read, so the press asks nothing more.
// The class filter, Flagged only, the Table / Quadrant view and the tables'
// pagers read nothing (they work on rows already loaded).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// [label] inside the control keyed [key].
Finder inControl(String key, String label) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(label));

/// Rests a mouse on [target] (past the dwell), then presses it; [reads]
/// counts the read the press makes: warmed once, never asked again.
Future<void> restThenPress(
  DashHarness h,
  Finder target,
  int Function() reads, {
  String? reason,
}) async {
  final mouse = await h.tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(h.tester.getCenter(target));
  await h.settle();
  expect(reads(), 1, reason: '${reason ?? ''} warmed on intent');
  await mouse.removePointer();
  await h.tap(target);
  expect(reads(), 1, reason: '${reason ?? ''} pressed: from the cache');
}

int withQuery(DashHarness h, String route, String key, String? value) => [
  for (final c in callsTo(h, route))
    if (value == null
        ? !c.query.containsKey(key)
        : c.query[key]?.single == value)
      c,
].length;

void main() {
  testWidgets('the page tabs warm the tab they open: Channel, Revenue '
      '(the picked granularity), Valuation (stock and catalog)', (t) async {
    final h = await pumpFin(t);
    await restThenPress(
      h,
      inControl('fin-tabs', h.t('reports.financial.tabs.channel')),
      () => callsTo(h, channelRoute).length,
      reason: 'channel',
    );
    await restThenPress(
      h,
      inControl('fin-tabs', h.t('reports.financial.tabs.revenue')),
      () => withQuery(h, seriesRoute, 'granularity', 'daily'),
      reason: 'revenue',
    );
    await restThenPress(
      h,
      inControl('fin-tabs', h.t('reports.financial.tabs.valuation')),
      () => callsTo(h, orgValuationRoute).length,
      reason: 'valuation',
    );
    expect(callsTo(h, catalogRoute), hasLength(1));
    await restThenPress(
      h,
      inControl('fin-tabs', h.t('reports.financial.tabs.supplierSpend')),
      () => callsTo(h, orgSpendRoute).length,
      reason: 'spend',
    );
  });

  testWidgets('the granularity segments warm their series: Monthly, Peak '
      'Hours, Peak Days', (t) async {
    final h = await pumpFin(t);
    await openTab(h, h.t('reports.financial.tabs.revenue'));
    await restThenPress(
      h,
      inControl('fin-granularity', h.t('analytics.granularity.monthly')),
      () => withQuery(h, seriesRoute, 'granularity', 'monthly'),
    );
    await restThenPress(
      h,
      inControl('fin-granularity', h.t('analytics.granularity.peak_hours')),
      () => callsTo(h, peakHoursRoute).length,
    );
    await restThenPress(
      h,
      inControl('fin-granularity', h.t('analytics.granularity.peak_days')),
      () => callsTo(h, peakDaysRoute).length,
    );
  });

  testWidgets('Snapshot / Today\'s costs warms the ledger at the current '
      'cost basis', (t) async {
    final h = await pumpFin(t);
    await restThenPress(
      h,
      inControl('fin-basis', h.t('insights.profitability.basisCurrent')),
      () => withQuery(h, ledgerRoute, 'cost_basis', 'current'),
    );
  });

  testWidgets('the inventory scope toggle warms the other scope\'s read', (
    t,
  ) async {
    final h = await pumpFin(t, branchId: SeedIds.heliopolis);
    await openTab(h, h.t('reports.financial.tabs.supplierSpend'));
    expect(callsTo(h, branchSpendRoute), hasLength(1));
    expect(callsTo(h, orgSpendRoute), isEmpty);
    await restThenPress(
      h,
      inControl('fin-inv-scope', h.t('inventory.reports.org')),
      () => callsTo(h, orgSpendRoute).length,
    );
  });

  testWidgets('the inner tabs warm Repricing and the decision log with its '
      'users', (t) async {
    final h = await pumpFin(t);
    await restThenPress(
      h,
      inControl('fin-inner-tabs', h.t('insights.profitability.repricingTab')),
      () => callsTo(h, repricingRoute).length,
    );
    await restThenPress(
      h,
      inControl('fin-inner-tabs', h.t('insights.profitability.decisionsTab')),
      () => callsTo(h, decisionsRoute).length,
    );
    expect(callsTo(h, usersRoute), hasLength(1));
  });

  testWidgets('the margin-target trigger warms the targets its editor reads', (
    t,
  ) async {
    final h = await pumpFin(t);
    await restThenPress(
      h,
      find.byKey(const ValueKey('fin-target-trigger')),
      () => callsTo(h, targetsRoute).length,
    );
  });
}
