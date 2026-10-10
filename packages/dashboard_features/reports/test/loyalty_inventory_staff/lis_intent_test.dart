// Intent warming (SPEC 6.1): pointing at a tab or the scope toggle warms the
// exact read its press makes, so the press asks nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Rests a mouse on [target] past the dwell, then presses it: [tpl] is
/// asked once on intent and never again on the press.
Future<void> restThenPress(DashHarness h, Finder target, String tpl) async {
  expect(h.server.callsTo(tpl), isEmpty, reason: '$tpl before intent');
  // A previous press may have scrolled [target] under the header.
  await h.tester.ensureVisible(target);
  await h.tester.pump();
  final mouse = await h.tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(h.tester.getCenter(target));
  await h.settle();
  expect(h.server.callsTo(tpl), hasLength(1), reason: '$tpl warmed');
  await mouse.removePointer();
  await h.tap(target);
  expect(h.server.callsTo(tpl), hasLength(1), reason: '$tpl from the cache');
}

void main() {
  testWidgets('REP-LOY-002/010/013 the tabs warm Campaigns and Liability', (
    tester,
  ) async {
    final h = await pumpUnit(tester, path: loyaltyPath);
    await restThenPress(
      h,
      tabLabel(h.t('reports.loyalty.tabs.campaigns')),
      campaignsTpl,
    );
    await restThenPress(
      h,
      tabLabel(h.t('reports.loyalty.tabs.liability')),
      liabilityTpl,
    );
  });

  testWidgets('REP-INV-003/005/007/015 the scope toggle and the tabs warm '
      'the read they open', (tester) async {
    final h = await pumpUnit(
      tester,
      path: inventoryPath,
      branchId: SeedIds.heliopolis,
    );
    expect(h.server.callsTo(branchTpl('consumption')), hasLength(1));
    await restThenPress(
      h,
      find.descendant(
        of: find.byKey(const ValueKey('inv-scope')),
        matching: find.text(h.t('inventory.reports.org')),
      ),
      orgTpl('consumption'),
    );
    for (final (label, report) in [
      ('inventory.reports.shrinkage', 'shrinkage'),
      ('inventory.reports.wasteReport', 'waste-report'),
      ('inventory.reports.poLeadTime', 'po-lead-time'),
    ]) {
      await restThenPress(h, tabLabel(h.t(label)), orgTpl(report));
    }
    // Low stock follows the scope bar (the branch), not the toggle.
    await restThenPress(
      h,
      tabLabel(h.t('reports.operations.tabs.lowStock')),
      branchTpl('low-stock'),
    );
  });
}
