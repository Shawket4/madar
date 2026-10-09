// Intent warming in the recipe builder: resting on "New ingredient" warms the
// dialog's category list, so the press asks the server nothing more.
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_host.dart';

const String _categories = '/inventory/orgs/{org_id}/categories';

void main() {
  testWidgets('MENU-RCP-003 / MENU-RCP-019 resting on "New ingredient" warms '
      'the categories; the press asks the server nothing more', (tester) async {
    final h = await pumpRecipeHost(tester);
    await openExtraShot(h);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final button = find.descendant(
      of: find.byType(RecipeBuilder),
      matching: find.text('New ingredient'),
    );
    expect(h.server.callsTo(_categories), isEmpty);

    await mouse.moveTo(tester.getCenter(button));
    await h.settle();
    expect(h.server.callsTo(_categories, method: 'GET'), hasLength(1),
        reason: 'the dialog read is warmed');
    await h.tap(button);
    expect(find.byType(CreateIngredientDialog), findsOneWidget);
    expect(h.server.callsTo(_categories, method: 'GET'), hasLength(1),
        reason: 'the dialog opened from the cache');
  });
}
