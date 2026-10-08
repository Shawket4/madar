// Bookings (SELL-BKG rows). The bookings unit's builder fills this file.
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';

void main() {
  testWidgets('/bookings asks for a branch while All branches is selected', (
    tester,
  ) async {
    final h = await pumpSell(tester, '/bookings');
    expect(find.text(h.t('bookings.pickBranch')), findsOneWidget);
    await h.shot('bookings/smoke-no-branch');
  });

  testWidgets('/bookings opens for one branch', (tester) async {
    final h = await pumpSell(tester, '/bookings', branchId: SeedIds.heliopolis);
    expect(find.text(h.t('bookings.description')), findsOneWidget);
    await h.shot('bookings/smoke');
  });
}
