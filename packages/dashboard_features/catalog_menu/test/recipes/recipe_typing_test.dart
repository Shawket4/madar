// Typing into the recipe builder's quantity box a key at a time (the web's
// e4170ce: its recipe grid remounted the box on every keystroke, so "18"
// could not be typed). Every key re-runs the builder's state and the host's
// row stream; the box must keep its value and its focus.
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/typing.dart';
import 'recipe_host.dart';

const String _blend = 'House espresso blend';
const String _milk = 'Full cream milk';

void main() {
  testWidgets('typing "18" a key at a time in the add-on recipe', (
    tester,
  ) async {
    final h = await pumpRecipeHost(tester);
    await openExtraShot(h);
    final typing = await TypingSession.start(h, qtyBox(h, _blend, 'One size'));
    await typing.clear();
    typing.expectFocusHeld();
    await typing.type('18');
    expect(typing.text, '18');
    expect(qtyText(tester, qtyBox(h, _blend, 'One size')), '18');
    // 18 × 95 = 1710: the line and the section total.
    expect(
      find.descendant(
        of: find.byType(RecipeBuilder),
        matching: find.text('EGP 17.10'),
      ),
      findsNWidgets(2),
    );
    typing.expectFocusHeld();
  });

  testWidgets('typing "18" a key at a time in the item recipe (deferred: '
      'every key streams the rows to the host)', (tester) async {
    final h = await pumpRecipeHost(tester);
    final (log, _) = await openLatte(h);
    final typing = await TypingSession.start(h, qtyBox(h, _milk, 'Large'));
    await typing.clear();
    typing.expectFocusHeld();
    await typing.type('18');
    expect(typing.text, '18');
    expect(qtyText(tester, qtyBox(h, _milk, 'Large')), '18');
    // The other boxes kept their values.
    expect(qtyText(tester, qtyBox(h, _milk, 'Regular')), '180');
    expect(qtyText(tester, qtyBox(h, _blend, 'Large')), '27');
    expect(
      log.last.where((r) => r.sizeLabel == 'Large').map((r) => r.quantityUsed),
      contains(18),
    );
    typing.expectFocusHeld();
  });
}
