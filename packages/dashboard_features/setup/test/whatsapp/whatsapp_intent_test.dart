// Intent warming on WhatsApp: the pane's only read is the status, and the
// only press that reads is Refresh, a forced re-read (warming it would answer
// from the cache it is meant to bypass). Generate QR, Unlink and the pause
// switch are writes and warm nothing. The web has no `prefetchRoute` case for
// `/settings/whatsapp`; ours warms the status for a platform admin (intent
// beyond the web).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
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

  testWidgets('resting on the WhatsApp rail entry warms the status; opening '
      'it asks nothing more', (tester) async {
    final b = whatsappServer();
    final h = await pumpSetup(
      tester,
      persona: Persona.platform,
      server: b.server,
      db: b.db,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    expect(statusReads(h), 0);
    final entry = find.descendant(
      of: find.byKey(const ValueKey('settings-rail')),
      matching: find.text('WhatsApp'),
    );
    await mouse.moveTo(tester.getCenter(entry));
    await h.settle();
    expect(statusReads(h), 1, reason: 'warmed on intent');
    await tester.tap(entry);
    await tester.pump();
    expect(h.location.path, waPath);
    expect(statusReads(h), 1, reason: 'opened from the cache');
  });

  testWidgets('the warming asks nothing for anyone but a platform admin', (
    tester,
  ) async {
    final h = await pumpWhatsapp(tester, persona: Persona.owner);
    h.container.read(routePrefetchesProvider)[waPath]!(
      DashPrefetcher(h.container),
      h.container.read(currentScopeProvider),
    );
    await h.settle();
    expect(statusReads(h), 0);
  });
}
