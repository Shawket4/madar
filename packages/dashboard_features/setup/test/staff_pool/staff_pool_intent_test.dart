// Intent warming on Staff drinks: pointing at the items trigger warms the
// org menu the picker lists, so pressing it asks the server nothing more.
// (Save and Revert are writes and warm nothing; the route has no prefetch:
// `route-prefetch.ts` has no case for this path.)
import 'package:dashboard_api/mock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('the items trigger warms the menu; the press opens it from '
      'the cache', (tester) async {
    final m = splServer();
    // No items chosen: the menu is not needed to name chips, so only the
    // picker asks for it.
    savedRow(m.db, null)!['eligible_item_ids'] = <String>[];
    final h = await pumpStaffPool(tester, backend: m);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    expect(h.server.callsTo(splMenu), isEmpty);

    final trigger = find.byKey(const ValueKey('spl-items-trigger'));
    await mouse.moveTo(tester.getCenter(trigger));
    await h.settle();
    expect(h.server.callsTo(splMenu), hasLength(1), reason: 'warmed');
    expect(h.server.callsTo(splMenu).single.query['org_id'], [
      SeedIds.sabahOrg,
    ]);

    await h.tap(trigger);
    expect(inPicker(find.text(itemName('latte'))), findsOneWidget);
    expect(h.server.callsTo(splMenu), hasLength(1), reason: 'from the cache');
  });
}
