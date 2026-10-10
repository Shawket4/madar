// Intent warming on Legal (owner rule, SPEC 6.1): pointing at a tab warms
// the report it shows, so the press asks nothing more. The exports read
// nothing (they write what is on screen).
import 'package:dashboard_reports/src/legal/legal_words.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legal_support.dart';

void main() {
  testWidgets('a tab warms its report; pressing it asks nothing more', (
    tester,
  ) async {
    final h = await pumpLegal(tester);
    for (final tab in [LegalTab.refunds, LegalTab.voids]) {
      int reads() =>
          h.server.callsTo(auditRoute(tab.segment), method: 'GET').length;
      final target = tabText(h.t(tab.labelKey));
      expect(reads(), 0, reason: '${tab.id} not read yet');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(target));
      await h.settle();
      expect(reads(), 1, reason: '${tab.id} warmed on intent');
      await mouse.removePointer();
      await h.tap(target);
      expect(reads(), 1, reason: '${tab.id} pressed: from the cache');
    }
  });
}
