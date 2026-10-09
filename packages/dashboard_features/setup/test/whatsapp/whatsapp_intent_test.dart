// Intent warming on WhatsApp: the pane's only read is the status, and the
// only press that reads is Refresh, a forced re-read (warming it would answer
// from the cache it is meant to bypass). Generate QR, Unlink and the pause
// switch are writes and warm nothing; the web has no `prefetchRoute` case for
// `/settings/whatsapp`.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('resting on the controls asks nothing; Refresh then reads '
      'once', (tester) async {
    final h = await pumpWhatsapp(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final before = h.server.calls.length;
    for (final key in [
      'whatsapp-unlink',
      'whatsapp-pause-switch',
      'whatsapp-refresh',
    ]) {
      await mouse.moveTo(tester.getCenter(inPage(find.byKey(ValueKey(key)))));
      await tester.pump(const Duration(milliseconds: 200));
    }
    final rested = h.server.calls.skip(before).toList();
    expect(
      rested.where((c) => c.method != 'GET' || c.template != waStatus),
      isEmpty,
      reason: 'no write, no other read',
    );
    expect(rested.length, lessThanOrEqualTo(1), reason: 'at most the poll');

    final reads = statusReads(h);
    await tester.tap(inPage(find.byKey(const ValueKey('whatsapp-refresh'))));
    await tester.pump();
    expect(statusReads(h), reads + 1);
    await h.settle();
  });
}
