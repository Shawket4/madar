// Smoke test of the `studio` unit: the page opens through the real shell.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('/menu/items/:itemId opens', (tester) async {
    final h = await pumpStudio(tester);
    expect(studioText('Caffè Latte'), findsWidgets);
    expect(studioText(h.t('menu.studio.basics.title')), findsOneWidget);
  });
}
