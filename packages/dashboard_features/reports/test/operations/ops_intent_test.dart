// Intent warming on Operations (owner rule, SPEC 6.1): pointing at a control
// whose press reads warms that exact read, so the press asks nothing more.
// The section filter, the charts and the tables' pagers read nothing (they
// work on rows already loaded).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show ensureTimeZones, excludedItemsPrefKey;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/src/area_seed.dart';
import 'package:dashboard_reports/src/operations/ops_tables.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Rests a mouse on [target] (past the dwell), then presses it; [reads]
/// counts the read the press makes: warmed once, never asked again.
Future<void> _restThenPress(
  DashHarness h,
  Finder target,
  int Function() reads, {
  String? reason,
}) async {
  expect(reads(), 0, reason: '${reason ?? ''} not read yet');
  final mouse = await h.tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(h.tester.getCenter(target));
  await h.settle();
  expect(reads(), 1, reason: '${reason ?? ''} warmed on intent');
  await mouse.removePointer();
  await h.tap(target);
  expect(reads(), 1, reason: '${reason ?? ''} pressed: from the cache');
}

Finder _tab(DashHarness h, String id) =>
    inPage(find.text(h.t('reports.operations.tabs.$id')));

int _sales(DashHarness h, String? exclude) => [
  for (final c in callsTo(h, salesRoute))
    if (c.query['exclude_items']?.single == exclude) c,
].length;

void main() {
  setUpAll(ensureTimeZones);

  testWidgets('the tabs warm what they show: Overview, Items (items and '
      'add-ons), Tellers, Waiters, Branches', (tester) async {
    final h = await pumpOps(tester);
    await _restThenPress(
      h,
      _tab(h, 'overview'),
      () => _sales(h, null),
      reason: 'overview',
    );
    await _restThenPress(
      h,
      _tab(h, 'items'),
      () => callsTo(h, itemsRoute).length,
      reason: 'items',
    );
    expect(callsTo(h, addonsRoute), hasLength(1));
    await _restThenPress(
      h,
      _tab(h, 'tellers'),
      () => callsTo(h, tellersRoute).length,
      reason: 'tellers',
    );
    await _restThenPress(
      h,
      _tab(h, 'waiters'),
      () => callsTo(h, waitersRoute).length,
      reason: 'waiters',
    );
    await _restThenPress(
      h,
      _tab(h, 'branches'),
      () => callsTo(h, comparisonRoute).length,
      reason: 'branches',
    );
  });

  testWidgets('a Tables row warms the history its panel reads', (tester) async {
    final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
    final name = find
        .descendant(
          of: find.byKey(const ValueKey('ops-tables-table')),
          matching: find.byKey(opsTableNameKey),
        )
        .first;
    await tester.ensureVisible(name);
    await h.settle();
    await _restThenPress(
      h,
      name,
      () => callsTo(h, historyRoute).length,
      reason: 'history',
    );
  });

  testWidgets('the exclude list: its funnel warms the menu, an item the '
      'sales without it, Clear the sales without any', (tester) async {
    final latte = MockSeed.menuItemId('latte');
    final mocha = MockSeed.menuItemId('mocha');
    final h = await pumpOps(
      tester,
      prefs: {excludedItemsPrefKey(SeedIds.sabahOrg): '["$latte"]'},
    );
    await h.tap(_tab(h, 'overview'));
    await _restThenPress(
      h,
      inPage(find.byKey(const ValueKey('ops-exclude-trigger'))),
      () => callsTo(h, menuRoute).length,
      reason: 'menu',
    );
    await h.enterText(
      find.byKey(const ValueKey('ops-exclude-search')),
      seedMenuItem('mocha')!.name,
    );
    await _restThenPress(
      h,
      find.byKey(ValueKey('ops-exclude-$mocha')),
      () => _sales(h, '$latte,$mocha'),
      reason: 'a pick',
    );
    await _restThenPress(
      h,
      find.byKey(const ValueKey('ops-exclude-clear')),
      () => _sales(h, null),
      reason: 'clear',
    );
  });
}
