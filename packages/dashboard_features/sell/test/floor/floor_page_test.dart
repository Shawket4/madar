// Floor (SELL-FLR rows). The floor unit's builder fills this file.
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';

void main() {
  testWidgets('/floor asks for a branch while All branches is selected', (
    tester,
  ) async {
    final h = await pumpSell(tester, '/floor');
    expect(find.text(h.t('floor.pickBranch')), findsOneWidget);
    await h.shot('floor/smoke-no-branch');
  });

  testWidgets('/floor opens for one branch', (tester) async {
    final h = await pumpSell(tester, '/floor', branchId: SeedIds.heliopolis);
    expect(find.text(h.t('floor.pickBranch')), findsNothing);
    expect(find.text(h.t('floor.title')), findsWidgets);
    await h.shot('floor/smoke');
  });
}
