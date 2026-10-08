// Tills (SELL-TIL rows). The tills unit's builder fills this file.
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';

void main() {
  testWidgets('/tills opens inside the shell', (tester) async {
    final h = await pumpSell(tester, '/tills');
    expect(find.text(h.t('tills.subtitle')), findsOneWidget);
    await h.shot('tills/smoke');
  });
}
