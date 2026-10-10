// SET-LOY-062 / 067 through dashboard_core's cross-area seam: unwired (this
// package alone) a member row opens the local card and its ledger's "View
// order" goes to the Orders page; wired, the row opens the app's customer
// sheet under the scope branch and the order opens in place over the card,
// each warming through the opener on intent. The real sheets: apps/dashboard
// test/shell/openers_test.dart.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/loyalty/member_sheet.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

/// The Members tab at Zamalek, Nada searched for.
Future<DashHarness> _members(WidgetTester tester, AreaOpeners openers) async {
  final b = loyaltyServer();
  final h = await DashHarness.pump(
    tester,
    areas: [setupTestArea],
    path: '$loyaltyPath${atBranch(SeedIds.zamalek)}',
    server: b.server,
    db: b.db,
    shotArea: 'setup',
    overrides: [areaOpenersProvider.overrideWithValue(openers)],
  );
  await openTab(h, h.t('loyalty.tabMembers'));
  await h.enterText(inPage(find.byType(DashSearchInput)), 'Nada');
  await tester.pump(const Duration(milliseconds: 350));
  await h.settle();
  return h;
}

Finder get _nada => inPage(
  find.byWidgetPredicate(
    (w) => w is DashPressable && w.semanticLabel == 'Nada Kamal',
  ),
);

Future<void> _rest(WidgetTester tester, DashHarness h, Finder f) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.ensureVisible(f);
  await h.settle();
  await mouse.moveTo(tester.getCenter(f));
  await h.settle();
}

/// The first "View order" in the open card's ledger.
Finder get _viewOrder => inSheet(find.text('View order')).first;

void main() {
  testWidgets('SET-LOY-062 seam not wired: the row opens the local card; '
      'View order goes to the Orders page', (tester) async {
    final h = await _members(tester, const AreaOpeners());
    await h.tap(_nada);
    expect(find.byType(MemberSheet), findsOneWidget);
    h.allowUnmatched = true;
    await h.tap(_viewOrder);
    expect(h.location.path, '/orders');
    expect(find.byType(MemberSheet), findsNothing);
  });

  testWidgets('SET-LOY-062 seam wired: the row opens the app\'s customer '
      'sheet under the scope branch; intent warms through it', (tester) async {
    final opened = <(String, bool, String?)>[];
    final warmed = <(String, String?)>[];
    final h = await _members(
      tester,
      AreaOpeners(
        customerSheet: CustomerSheetOpener(
          open: (context, id, {readOnly = false, branchId}) async =>
              opened.add((id, readOnly, branchId)),
          warm: (ref, id, {branchId}) => warmed.add((id, branchId)),
        ),
      ),
    );
    final before = h.server.callsTo(LoyaltyRoutes.member).length;
    await _rest(tester, h, _nada);
    expect(warmed, [(nadaId, SeedIds.zamalek)]);
    await h.tap(_nada);
    expect(opened, [(nadaId, false, SeedIds.zamalek)]);
    expect(find.byType(MemberSheet), findsNothing);
    expect(h.server.callsTo(LoyaltyRoutes.member), hasLength(before));
  });

  testWidgets('SET-LOY-067 order seam wired: View order opens the order in '
      'place over the card; intent warms through it', (tester) async {
    final opened = <String>[];
    final warmed = <String>[];
    final h = await _members(
      tester,
      AreaOpeners(
        orderSheet: OrderSheetOpener(
          open: (context, id) async => opened.add(id),
          warm: (ref, id) => warmed.add(id),
        ),
      ),
    );
    await h.tap(_nada);
    final sale = h.db![LoyaltyTables.ledger].rows.firstWhere(
      (e) => e['customer_id'] == nadaId && e['kind'] == 'earn',
    );
    final link = find.descendant(
      of: find.byKey(ValueKey('ledger-row-${sale['id']}')),
      matching: find.text('View order'),
    );
    await _rest(tester, h, link);
    expect(warmed, [sale['order_id']]);
    await h.tap(link);
    expect(opened, [sale['order_id']]);
    expect(find.byType(MemberSheet), findsOneWidget);
    expect(h.location.path, loyaltyPath);
  });
}
