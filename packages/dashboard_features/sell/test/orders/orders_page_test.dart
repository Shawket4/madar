// Orders (SELL-ORD rows). The orders unit's builder fills this file.
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';

void main() {
  testWidgets('/orders opens inside the shell', (tester) async {
    final h = await pumpSell(tester, '/orders');
    expect(find.text(h.t('orders.subtitle')), findsOneWidget);
    await h.shot('orders/smoke');
  });
}
