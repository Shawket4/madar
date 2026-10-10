// ADM-REV-001 intent: resting on the Access "Review" tab warms the open
// flags through the route's `prefetch:` (the real `adminArea`), so pressing
// it asks the server nothing more.
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_admin/src/shared/access_tabs.dart';
import 'package:dashboard_api/mock.dart' show Persona;
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('ADM-REV-001 intent: resting on the Review tab warms the open '
      'flags; pressing it asks nothing more', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/users',
      persona: Persona.owner,
    );
    final tab = find.descendant(
      of: find.byType(AccessSectionTabs),
      matching: find.text(h.t('access.review.title')),
    );
    expect(flagReads(h), isEmpty);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(tab));
    await h.settle();
    expect(flagReads(h), hasLength(1), reason: 'warmed on rest');
    expect(flagReads(h).single.query, isNot(contains('include_reviewed')));

    await h.tap(tab);
    expect(h.location.path, reviewPath);
    expect(flagReads(h), hasLength(1), reason: 'served from the cache');
  });
}
