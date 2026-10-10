// The WhatsApp pane, one driven test per SET-WA row (platform admins only):
// the gate, the polled status, the connection card's five states, unlink,
// pair, pause, and failures.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/whatsapp/whatsapp_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  for (final persona in [
    Persona.owner,
    Persona.manager,
    Persona.limited,
    Persona.dawamOnly,
  ]) {
    testWidgets('SET-WA-001 ${persona.name}: refused in the pane, nothing '
        'asked', (tester) async {
      final h = await pumpWhatsapp(tester, persona: persona);
      expect(pageText('WhatsApp'), findsOneWidget);
      expect(
        pageText('Only super admins can manage the WhatsApp connection.'),
        findsOneWidget,
      );
      expect(
        inPage(find.byKey(const ValueKey('whatsapp-refresh'))),
        findsNothing,
      );
      await tester.pump(kWhatsappPoll * 3);
      await h.settle();
      expect(statusReads(h), 0);
    });
  }

  testWidgets('SET-WA-002 header, description, Refresh re-reads (busy while '
      'it runs)', (tester) async {
    final b = whatsappServer();
    final h = await pumpWhatsapp(tester, backend: b);
    expect(pageText('WhatsApp'), findsOneWidget);
    expect(
      pageText(
        'Link the WhatsApp number that sends delivery OTP codes and order '
        'updates.',
      ),
      findsOneWidget,
    );
    expect(refresh(tester).loading, isFalse);
    final before = statusReads(h);
    final gate = b.server.hold('GET', waStatus);
    await tester.tap(inPage(find.text('Refresh')));
    await tester.pump();
    expect(statusReads(h), before + 1);
    expect(refresh(tester).loading, isTrue, reason: 'spins, disabled');
    // A poll never stacks on a read in flight.
    await tester.pump(kWhatsappPoll * 2);
    expect(statusReads(h), before + 1);
    gate.release();
    await h.settle();
    expect(refresh(tester).loading, isFalse);
  });

  testWidgets('SET-WA-003 polled every 2.5 s: a scan flips the QR to '
      'connected; paused while hidden, re-read on coming back when stale', (
    tester,
  ) async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {
      'logged_in': false,
      'connected': true,
      'has_qr': true,
    });
    final h = await pumpWhatsapp(tester, backend: b);
    expect(inPage(find.byKey(const ValueKey('whatsapp-qr'))), findsOneWidget);
    final n = statusReads(h);
    await tester.pump(kWhatsappPoll);
    await h.settle(rounds: 1);
    expect(statusReads(h), greaterThan(n));

    // The phone scans.
    WhatsappMock.set(b.db, {'logged_in': true, 'has_qr': false});
    await tester.pump(kWhatsappPoll);
    await h.settle(rounds: 1);
    expect(pageText('A number is linked and ready to send.'), findsOneWidget);
    expect(pill(tester), 'Connected');

    // Hidden: no polling.
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    final hidden = statusReads(h);
    await tester.pump(const Duration(seconds: 31));
    b.db.clock.advance(const Duration(seconds: 31));
    expect(statusReads(h), hidden);
    // Back after 31 s: read at once, before any poll tick.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(Duration.zero);
    expect(statusReads(h), hidden + 1);
    await h.settle();

    // Back after a short absence: the poll alone resumes.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 5));
    b.db.clock.advance(const Duration(seconds: 5));
    final short = statusReads(h);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(Duration.zero);
    expect(statusReads(h), short);
    await h.settle();
  });

  testWidgets('SET-WA-004 connection head: Connection, the session, and the '
      'pill per state', (tester) async {
    final b = whatsappServer();
    final gate = b.server.hold('GET', waStatus);
    final h = await pumpWhatsapp(tester, backend: b);
    expect(pageText('Connection'), findsOneWidget);
    expect(inPage(find.textContaining('Session: —')), findsOneWidget);
    expect(pill(tester), 'Checking…');
    gate.release();
    await h.settle();
    expect(inPage(find.textContaining('Session: main')), findsOneWidget);
    expect(pill(tester), 'Connected');

    Future<void> next(MockRow patch, String expected) async {
      WhatsappMock.set(b.db, patch);
      await tester.tap(inPage(find.text('Refresh')));
      await h.settle();
      expect(pill(tester), expected, reason: '$patch');
    }

    await next({'logged_in': false, 'has_qr': true}, 'Awaiting scan');
    await next({'has_qr': false}, 'Awaiting scan');
    await next({'reachable': false}, 'Offline');
    await next({'reachable': true, 'configured': false}, 'Offline');
    expect(
      tester
          .widget<DashStatusPill>(
            inPage(find.byKey(const ValueKey('whatsapp-status'))),
          )
          .tone,
      DashTone.warning,
    );
  });

  testWidgets('SET-WA-005 first load: two skeleton bars, Checking…, no pause '
      'card', (tester) async {
    final b = whatsappServer();
    final gate = b.server.hold('GET', waStatus);
    final h = await pumpWhatsapp(tester, backend: b);
    expect(
      inPage(find.byKey(const ValueKey('whatsapp-skeleton'))),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: inPage(find.byKey(const ValueKey('whatsapp-skeleton'))),
        matching: find.byType(DashSkeleton),
      ),
      findsNWidgets(2),
    );
    expect(pill(tester), 'Checking…');
    expect(inPage(find.byKey(const ValueKey('whatsapp-pause'))), findsNothing);
    gate.release();
    await h.settle();
    expect(
      inPage(find.byKey(const ValueKey('whatsapp-skeleton'))),
      findsNothing,
    );
    expect(
      inPage(find.byKey(const ValueKey('whatsapp-pause'))),
      findsOneWidget,
    );
  });

  testWidgets('SET-WA-005 (divergence) a failed read shows the error with '
      'Retry, not "Gateway not configured"; polling keeps trying and a '
      'success replaces it', (tester) async {
    final b = whatsappServer();
    final failure = MockResponse.error(500, 'boom');
    b.server.fail('GET', waStatus, failure, times: null);
    final h = await pumpWhatsapp(tester, backend: b);
    expect(
      inPage(find.byKey(const ValueKey('whatsapp-error'))),
      findsOneWidget,
    );
    expect(pageText(h.refusalWords(failure)), findsOneWidget);
    expect(pageText('Gateway not configured'), findsNothing);
    expect(pill(tester), 'Checking…');
    expect(inPage(find.byKey(const ValueKey('whatsapp-pause'))), findsNothing);
    final n = statusReads(h);
    await tester.pump(kWhatsappPoll);
    await h.settle(rounds: 1);
    expect(statusReads(h), greaterThan(n), reason: 'the poll keeps trying');

    b.server.clearFailures();
    await h.tap(inPage(find.text('Retry')));
    expect(inPage(find.byKey(const ValueKey('whatsapp-error'))), findsNothing);
    expect(pill(tester), 'Connected');
  });

  testWidgets('SET-WA-006 not configured: the warning notice, no pause card', (
    tester,
  ) async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'configured': false, 'reachable': false});
    await pumpWhatsapp(tester, backend: b);
    expect(pageText('Gateway not configured'), findsOneWidget);
    expect(
      pageText(
        'Set WHATSAPP_SERVICE_URL on the backend to enable WhatsApp sending.',
      ),
      findsOneWidget,
    );
    expect(pill(tester), 'Offline');
    expect(inPage(find.byKey(const ValueKey('whatsapp-pause'))), findsNothing);
  });

  testWidgets('SET-WA-007 unreachable: the warning notice', (tester) async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'reachable': false});
    await pumpWhatsapp(tester, backend: b);
    expect(pageText('Gateway unreachable'), findsOneWidget);
    expect(
      pageText(
        'The WhatsApp service did not respond. Make sure it is running on '
        'the private network.',
      ),
      findsOneWidget,
    );
    expect(pill(tester), 'Offline');
  });

  testWidgets('SET-WA-008 linked: the success line and Unlink, its own '
      'width on a desktop', (tester) async {
    await pumpWhatsapp(tester);
    expect(pageText('A number is linked and ready to send.'), findsOneWidget);
    final unlink = inPage(find.byKey(const ValueKey('whatsapp-unlink')));
    expect(
      find.descendant(of: unlink, matching: find.text('Unlink number')),
      findsOneWidget,
    );
    final card = inPage(find.byKey(const ValueKey('whatsapp-connection')));
    expect(
      tester.getSize(unlink).width,
      lessThan(tester.getSize(card).width / 2),
    );
  });

  testWidgets('SET-WA-008 Unlink is full width on a phone', (tester) async {
    await pumpWhatsapp(tester, size: DashSize.phone);
    final unlink = inPage(find.byKey(const ValueKey('whatsapp-unlink')));
    final card = inPage(find.byKey(const ValueKey('whatsapp-connection')));
    // The card's padding (`p-5`) and its 1 px edges on both sides.
    expect(
      tester.getSize(unlink).width,
      closeTo(tester.getSize(card).width - 2 * 20, 2),
    );
  });

  testWidgets('SET-WA-009 Unlink: confirm, then the answer replaces the '
      'status and toasts; Cancel asks nothing', (tester) async {
    final b = whatsappServer();
    final h = await pumpWhatsapp(tester, backend: b);
    await h.tap(inPage(find.byKey(const ValueKey('whatsapp-unlink'))));
    expect(top('Unlink this WhatsApp number?'), findsOneWidget);
    expect(
      top(
        'OTP codes and order updates stop sending until a number is linked '
        'again by scanning a new QR code.',
      ),
      findsOneWidget,
    );
    await h.tap(top('Cancel'));
    expect(b.server.callsTo(waLogout), isEmpty);

    await h.tap(inPage(find.byKey(const ValueKey('whatsapp-unlink'))));
    final gate = b.server.hold('POST', waLogout);
    await tester.tap(top('Unlink number').last);
    await tester.pump();
    await tester.pump();
    expect(b.server.callsTo(waLogout), hasLength(1));
    expect(
      find.descendant(
        of: inPage(find.byKey(const ValueKey('whatsapp-unlink'))),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
      reason: 'the button spins',
    );
    gate.release();
    await h.settle();
    expect(pageText('No number is linked yet.'), findsOneWidget);
    expect(pill(tester), 'Awaiting scan');
    await h.expectToast('WhatsApp number unlinked.');
  });

  testWidgets('SET-WA-010 a pairing QR: the code and the three steps', (
    tester,
  ) async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'logged_in': false, 'has_qr': true});
    await pumpWhatsapp(tester, backend: b);
    final qr = inPage(find.byKey(const ValueKey('whatsapp-qr')));
    expect(tester.getSize(qr), const Size(240, 240));
    expect(
      find.descendant(of: qr, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Image>(find.descendant(of: qr, matching: find.byType(Image)))
          .semanticLabel,
      'WhatsApp pairing QR code',
    );
    expect(pageText('Open WhatsApp on your phone.'), findsOneWidget);
    expect(
      pageText('Tap Settings → Linked devices → Link a device.'),
      findsOneWidget,
    );
    expect(
      pageText('Scan this QR code. It refreshes automatically.'),
      findsOneWidget,
    );
    expect(pageText('1.'), findsOneWidget);
    expect(pageText('3.'), findsOneWidget);
    expect(pill(tester), 'Awaiting scan');
  });

  testWidgets('SET-WA-011 not linked, no QR: the line and Generate QR', (
    tester,
  ) async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'logged_in': false, 'connected': false});
    await pumpWhatsapp(tester, backend: b);
    expect(pageText('No number is linked yet.'), findsOneWidget);
    final pair = tester.widget<DashButton>(
      inPage(find.byKey(const ValueKey('whatsapp-pair'))),
    );
    expect(pair.label, 'Generate QR to link');
    expect(pair.icon, 'smartphone');
  });

  testWidgets('SET-WA-012 Generate QR: the answer replaces the status (the '
      'QR shows), spinner meanwhile', (tester) async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'logged_in': false, 'connected': false});
    final h = await pumpWhatsapp(tester, backend: b);
    final gate = b.server.hold('POST', waPair);
    await tester.tap(inPage(find.text('Generate QR to link')));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<DashButton>(
            inPage(find.byKey(const ValueKey('whatsapp-pair'))),
          )
          .loading,
      isTrue,
    );
    gate.release();
    await h.settle();
    expect(b.server.callsTo(waPair), hasLength(1));
    expect(inPage(find.byKey(const ValueKey('whatsapp-qr'))), findsOneWidget);
    expect(pill(tester), 'Awaiting scan');
  });

  testWidgets('SET-WA-013 the pause card: words, the Paused pill when '
      'paused, the switch = paused', (tester) async {
    final b = whatsappServer();
    final h = await pumpWhatsapp(tester, backend: b);
    expect(pageText('Pause sending'), findsOneWidget);
    expect(
      pageText(
        'Mute all WhatsApp messages (OTP + order updates) without unlinking '
        'the number.',
      ),
      findsOneWidget,
    );
    expect(pauseSwitch(tester).value, isFalse);
    expect(pageText('Paused'), findsNothing);

    WhatsappMock.set(b.db, {'paused': true});
    await h.tap(inPage(find.text('Refresh')));
    expect(pauseSwitch(tester).value, isTrue);
    expect(pageText('Paused'), findsOneWidget);
  });

  testWidgets('SET-WA-014 flipping pause sends {paused}, takes the answer, '
      'toasts; disabled while saving', (tester) async {
    final b = whatsappServer();
    final h = await pumpWhatsapp(tester, backend: b);
    final gate = b.server.hold('POST', waPause);
    await tester.tap(
      inPage(find.byKey(const ValueKey('whatsapp-pause-switch'))),
    );
    await tester.pump();
    await tester.pump();
    expect(pauseSwitch(tester).enabled, isFalse);
    expect(pauseSwitch(tester).value, isFalse, reason: 'follows the server');
    gate.release();
    await h.settle();
    expect(b.server.callsTo(waPause).single.body, {'paused': true});
    expect(pauseSwitch(tester).value, isTrue);
    expect(pageText('Paused'), findsOneWidget);
    await h.expectToast('Sending paused.');

    await h.tap(inPage(find.byKey(const ValueKey('whatsapp-pause-switch'))));
    expect(b.server.callsTo(waPause).last.body, {'paused': false});
    expect(pauseSwitch(tester).value, isFalse);
    await h.expectToast('Sending resumed.');
  });

  testWidgets('SET-WA-015 a failed write toasts the server\'s words and '
      'keeps the status', (tester) async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'logged_in': false, 'connected': false});
    final h = await pumpWhatsapp(tester, backend: b);
    final refused = MockResponse.error(
      503,
      'Service unavailable: WhatsApp gateway is unreachable',
    );
    b.server.fail('POST', waPair, refused);
    await h.tap(inPage(find.text('Generate QR to link')));
    await h.expectToast(h.refusalWords(refused));
    expect(pageText('No number is linked yet.'), findsOneWidget);

    final denied = MockResponse.forbidden('Super admin access required');
    b.server.fail('POST', waPause, denied);
    await h.tap(inPage(find.byKey(const ValueKey('whatsapp-pause-switch'))));
    await h.expectToast(h.refusalWords(denied));
    expect(pauseSwitch(tester).value, isFalse);
    expect(pauseSwitch(tester).enabled, isTrue);
  });

  Finder rail(String text) => find.descendant(
    of: find.byKey(const ValueKey('settings-rail')),
    matching: find.text(text),
  );

  testWidgets('SET-WA-016 the platform admin sees WhatsApp in the rail and '
      'the pane', (tester) async {
    await pumpWhatsapp(tester);
    expect(rail('WhatsApp'), findsOneWidget);
    expect(pageText('Connection'), findsOneWidget);
  });

  testWidgets('SET-WA-016 an org admin: no rail entry, and the pane refuses '
      'by role', (tester) async {
    await pumpWhatsapp(tester, persona: Persona.owner);
    expect(rail('WhatsApp'), findsNothing);
    expect(
      pageText('Only super admins can manage the WhatsApp connection.'),
      findsOneWidget,
    );
  });

  testWidgets('SET-WA-017 the pause card shows while unreachable; Refresh '
      'spins on the background poll too', (tester) async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'reachable': false});
    final h = await pumpWhatsapp(tester, backend: b);
    expect(pageText('Gateway unreachable'), findsOneWidget);
    expect(
      inPage(find.byKey(const ValueKey('whatsapp-pause'))),
      findsOneWidget,
    );
    expect(pauseSwitch(tester).enabled, isTrue);

    final gate = b.server.hold('GET', waStatus);
    await tester.pump(kWhatsappPoll);
    await tester.pump();
    expect(refresh(tester).loading, isTrue);
    gate.release();
    await h.settle();
    expect(refresh(tester).loading, isFalse);
  });
}
