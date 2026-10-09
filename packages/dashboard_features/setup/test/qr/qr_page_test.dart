// The QR page's single codes (SET-QR-001 – 018, 025 – 027): the header, the
// render options, the org and branch cards, generating, the inline error,
// the result card and the preview dialog.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/shared/qr_preview_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qr_support.dart';

DashButton _button(WidgetTester tester, Finder f) => tester.widget(f);

void main() {
  testWidgets('SET-QR-001 header and subtitle', (tester) async {
    final h = await pumpQr(tester);
    expect(inQr(find.text('QR Codes')), findsOneWidget);
    expect(inQr(find.text(h.t('qr.subtitle'))), findsOneWidget);
  });

  testWidgets('SET-QR-002 SET-SHL-020 no org in scope: "Select an '
      'organization", nothing asked', (tester) async {
    final h = await pumpQr(tester, persona: Persona.platform, pickOrg: false);
    h.allowUnmatched = true;
    expect(inQr(find.text('QR Codes')), findsOneWidget);
    expect(inQr(find.text('Select an organization')), findsOneWidget);
    expect(inQr(find.byKey(const ValueKey('qr-options'))), findsNothing);
    expect(h.server.callsTo(QrRoutes.tables), isEmpty);
  });

  testWidgets('SET-QR-003 render options: branded card on, DPI 600, the '
      'hint; both sent on org and branch codes', (tester) async {
    final h = await pumpQr(tester);
    final bar = find.byKey(const ValueKey('qr-options'));
    Finder inBar(Finder f) => find.descendant(of: bar, matching: f);
    expect(inBar(find.text('Branded card')), findsOneWidget);
    expect(inBar(find.text('DPI')), findsOneWidget);
    expect(inBar(find.text('600')), findsOneWidget);
    expect(
      inBar(find.text('Applies to every code on this page.')),
      findsOneWidget,
    );

    await h.tap(generateOf(QrKind.orgOrder));
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).single), {
      'card': 'true',
      'dpi': '600',
    });

    // DPI 300.
    await h.tap(find.byKey(const ValueKey('qr-dpi')));
    await h.tap(find.text('300').last);
    await h.tap(generateOf(QrKind.orgOrder));
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).last), {
      'card': 'true',
      'dpi': '300',
    });

    // Card off: the DPI select goes, the DPI still rides along.
    await h.tap(inBar(find.text('Branded card')));
    expect(inBar(find.text('DPI')), findsNothing);
    await h.tap(generateOf(QrKind.orgOrder));
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).last), {
      'card': 'false',
      'dpi': '300',
    });

    await pickBranch(h, SeedIds.heliopolis);
    await h.tap(generateOf(QrKind.branchOrder));
    expect(queryOf(h.server.callsTo(QrRoutes.branchQr).last), {
      'card': 'false',
      'dpi': '300',
    });
  });

  testWidgets('SET-QR-004 SET-QR-006 the org section\'s two cards and the '
      'branch section\'s three', (tester) async {
    final h = await pumpQr(tester);
    expect(inQr(find.text('For the whole organization')), findsOneWidget);
    expect(inQr(find.text('For one branch')), findsOneWidget);
    expect(
      inKind(QrKind.orgOrder, find.text('All-branches QR')),
      findsOneWidget,
    );
    expect(
      inKind(QrKind.orgOrder, find.text(h.t('qr.org.description'))),
      findsOneWidget,
    );
    expect(
      inKind(QrKind.orgBooking, find.text('All-branches bookings')),
      findsOneWidget,
    );
    expect(
      inKind(QrKind.branchOrder, find.text('Branch menu QR')),
      findsOneWidget,
    );
    expect(
      inKind(QrKind.branchBooking, find.text('Branch bookings')),
      findsOneWidget,
    );
    expect(
      inKind(QrKind.branchOrderInMall, find.text('In-mall delivery QR')),
      findsOneWidget,
    );
    expect(
      inKind(QrKind.branchOrderInMall, find.text(h.t('qr.inMall.description'))),
      findsOneWidget,
    );
  });

  testWidgets('SET-QR-005 SET-QR-007 org cards need All branches; branch '
      'cards (and the in-mall fields) need a branch', (tester) async {
    final h = await pumpQr(tester);
    // All branches: org cards on, branch cards dimmed and disabled.
    expect(_button(tester, generateOf(QrKind.orgOrder)).onPressed, isNotNull);
    for (final k in [
      QrKind.branchOrder,
      QrKind.branchBooking,
      QrKind.branchOrderInMall,
    ]) {
      expect(_button(tester, generateOf(k)).onPressed, isNull, reason: k.name);
      expect(
        inKind(
          k,
          find.text('Select a branch in the scope bar to make this code.'),
        ),
        findsOneWidget,
      );
    }
    expect(
      tester
          .widget<Opacity>(
            inKind(QrKind.branchOrder, find.byType(Opacity)).first,
          )
          .opacity,
      0.7,
    );
    final place = find.descendant(
      of: find.byKey(const ValueKey('qr-place')),
      matching: find.byType(DashTextInput),
    );
    expect(tester.widget<DashTextInput>(place).enabled, isFalse);

    await pickBranch(h, SeedIds.heliopolis);
    for (final k in [QrKind.orgOrder, QrKind.orgBooking]) {
      expect(_button(tester, generateOf(k)).onPressed, isNull, reason: k.name);
      expect(
        inKind(
          k,
          find.text('Switch the scope bar to All branches to make this code.'),
        ),
        findsOneWidget,
      );
    }
    expect(
      _button(tester, generateOf(QrKind.branchOrder)).onPressed,
      isNotNull,
    );
    expect(tester.widget<DashTextInput>(place).enabled, isTrue);
  });

  testWidgets('SET-QR-008 SET-QR-016 Generate (All-branches QR) shows the '
      'code, its short link and where it lands', (tester) async {
    final h = await pumpQr(tester);
    await h.tap(generateOf(QrKind.orgOrder));
    final call = h.server.callsTo(QrRoutes.orgQr).single;
    expect(call.path, '/orgs/${SeedIds.sabahOrg}/qr');
    final qr = mockQrResponse(
      kind: 'org_order',
      longUrl: '$mockOrderBase/order/${SeedIds.sabahOrg}',
      key: 'org_order:${SeedIds.sabahOrg}',
    );
    final result = resultOf(QrKind.orgOrder);
    expect(result, findsOneWidget);
    expect(
      find.descendant(of: result, matching: find.text(qr.shortUrl)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: result, matching: find.text(qr.longUrl)),
      findsOneWidget,
    );
    // The short link opens outside the app.
    await h.tap(find.descendant(of: result, matching: find.text(qr.shortUrl)));
  });

  testWidgets('SET-QR-009 Generate (All-branches bookings)', (tester) async {
    final h = await pumpQr(tester);
    await h.tap(generateOf(QrKind.orgBooking));
    expect(
      h.server.callsTo(QrRoutes.orgBooking).single.path,
      '/orgs/${SeedIds.sabahOrg}/booking-qr',
    );
    expect(
      find.descendant(
        of: resultOf(QrKind.orgBooking),
        matching: find.text('$mockReservationsBase/${SeedIds.sabahOrg}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SET-QR-010 SET-QR-011 Generate (Branch menu QR, Branch '
      'bookings)', (tester) async {
    final h = await pumpQr(tester, query: atBranch(SeedIds.heliopolis));
    await h.tap(generateOf(QrKind.branchOrder));
    expect(
      h.server.callsTo(QrRoutes.branchQr).single.path,
      '/branches/${SeedIds.heliopolis}/qr',
    );
    expect(
      find.descendant(
        of: resultOf(QrKind.branchOrder),
        matching: find.text(
          '$mockOrderBase/order/${SeedIds.sabahOrg}?branch=${SeedIds.heliopolis}',
        ),
      ),
      findsOneWidget,
    );
    await h.tap(generateOf(QrKind.branchBooking));
    expect(
      h.server.callsTo(QrRoutes.branchBooking).single.path,
      '/branches/${SeedIds.heliopolis}/booking-qr',
    );
    expect(resultOf(QrKind.branchBooking), findsOneWidget);
  });

  testWidgets('SET-QR-012 in-mall: three required fields, limits, and the '
      'place sent with the render options', (tester) async {
    final h = await pumpQr(tester, query: atBranch(SeedIds.maadi));
    await h.tap(generateOf(QrKind.branchOrderInMall));
    expect(
      inKind(QrKind.branchOrderInMall, find.text('This field is required')),
      findsNWidgets(3),
    );
    expect(h.server.callsTo(QrRoutes.branchQr), isEmpty);

    Finder field(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    );
    await h.enterText(field('qr-place'), 'x' * 81);
    await h.enterText(field('qr-floor'), 'Ground Floor');
    await h.enterText(field('qr-unit'), 'Unit 42');
    expect(
      inKind(QrKind.branchOrderInMall, find.text('At most 80 characters')),
      findsOneWidget,
    );
    await h.tap(generateOf(QrKind.branchOrderInMall));
    expect(h.server.callsTo(QrRoutes.branchQr), isEmpty);

    await h.enterText(field('qr-place'), 'Sabah Kiosk 3');
    await h.tap(generateOf(QrKind.branchOrderInMall));
    final call = h.server.callsTo(QrRoutes.branchQr).single;
    expect(call.path, '/branches/${SeedIds.maadi}/qr');
    expect(queryOf(call), {
      'card': 'true',
      'dpi': '600',
      'place_name': 'Sabah Kiosk 3',
      'floor': 'Ground Floor',
      'unit_number': 'Unit 42',
    });
    final result = resultOf(QrKind.branchOrderInMall);
    expect(
      find.descendant(
        of: result,
        matching: find.textContaining('channel=in_mall'),
      ),
      findsOneWidget,
    );

    // Enter in a field submits the form too.
    await h.enterText(field('qr-unit'), 'Unit 43');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(
      queryOf(h.server.callsTo(QrRoutes.branchQr).last)['unit_number'],
      'Unit 43',
    );
  });

  testWidgets('SET-QR-013 generating again clears the card\'s result and '
      'error first; only that card is busy', (tester) async {
    final m = setupMockServer();
    final h = await pumpQr(tester, backend: m);
    // `times: null`: the touch going down warms the read too.
    m.server.fail(
      'GET',
      QrRoutes.orgBooking,
      MockResponse.error(500, 'Short-link provider unreachable'),
      times: null,
    );
    await h.tap(generateOf(QrKind.orgBooking));
    expect(find.byKey(const ValueKey('qr-error-orgBooking')), findsOneWidget);
    m.server.clearFailures();

    final gate = m.server.hold('GET', QrRoutes.orgBooking);
    await tester.tap(generateOf(QrKind.orgBooking));
    await tester.pump();
    expect(find.byKey(const ValueKey('qr-error-orgBooking')), findsNothing);
    expect(_button(tester, generateOf(QrKind.orgBooking)).loading, isTrue);
    expect(_button(tester, generateOf(QrKind.orgBooking)).onPressed, isNull);
    expect(_button(tester, generateOf(QrKind.orgOrder)).loading, isFalse);
    expect(_button(tester, generateOf(QrKind.orgOrder)).onPressed, isNotNull);
    gate.release();
    await h.settle();
    expect(resultOf(QrKind.orgBooking), findsOneWidget);

    // A second press: the old code goes while the new one is made.
    final again = m.server.hold('GET', QrRoutes.orgBooking);
    // A cached answer would come back at once: drop it.
    h.container.invalidate(qrCodeProvider);
    await tester.tap(generateOf(QrKind.orgBooking));
    await tester.pump();
    expect(resultOf(QrKind.orgBooking), findsNothing);
    again.release();
    await h.settle();
    expect(resultOf(QrKind.orgBooking), findsOneWidget);
  });

  testWidgets('SET-QR-014 a failure shows inline, in the server\'s words, '
      'no toast', (tester) async {
    final m = setupMockServer();
    // Maadi has rules but bookings are switched off.
    final h = await pumpQr(tester, backend: m, query: atBranch(SeedIds.maadi));
    await h.tap(generateOf(QrKind.branchBooking));
    final words = h.refusalWords(
      MockResponse.conflict('Bookings are switched off for this branch'),
    );
    expect(inKind(QrKind.branchBooking, find.text(words)), findsOneWidget);
    expect(resultOf(QrKind.branchBooking), findsNothing);
    expect(find.text(words), findsOneWidget, reason: 'no toast');

    // Switched on: the next press asks again (a refusal is not kept).
    m.db['booking_settings'].firstWhere(
      (r) => r['branch_id'] == SeedIds.maadi,
    )!['enabled'] = true;
    final before = h.server.callsTo(QrRoutes.branchBooking).length;
    await h.tap(generateOf(QrKind.branchBooking));
    expect(
      h.server.callsTo(QrRoutes.branchBooking).length,
      greaterThan(before),
    );
    expect(resultOf(QrKind.branchBooking), findsOneWidget);
    expect(inKind(QrKind.branchBooking, find.text(words)), findsNothing);
  });

  testWidgets('SET-QR-014 no branch takes bookings: the org bookings code '
      'is refused inline', (tester) async {
    final m = setupMockServer();
    for (final r in m.db['booking_settings'].rows) {
      r['enabled'] = false;
    }
    final h = await pumpQr(tester, backend: m);
    await h.tap(generateOf(QrKind.orgBooking));
    expect(
      inKind(
        QrKind.orgBooking,
        find.text(
          h.refusalWords(
            MockResponse.conflict(
              'No branch in this organisation takes bookings yet',
            ),
          ),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SET-QR-015 SET-QR-025 the result: beside the controls from '
      '1024, 256 wide; the code opens the preview titled by the card', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    await h.tap(generateOf(QrKind.orgOrder));
    final result = resultOf(QrKind.orgOrder);
    expect(tester.getSize(result).width, 256);
    expect(
      tester.getTopLeft(result).dy,
      lessThan(tester.getBottomLeft(generateOf(QrKind.orgOrder)).dy),
    );

    final qr = mockQrResponse(
      kind: 'org_order',
      longUrl: '$mockOrderBase/order/${SeedIds.sabahOrg}',
      key: 'org_order:${SeedIds.sabahOrg}',
    );
    await h.tap(
      find.descendant(
        of: result,
        matching: find.bySemanticsLabel('Enlarge QR code'),
      ),
    );
    final dialog = find.byType(QrPreviewDialog);
    expect(dialog, findsOneWidget);
    Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
    expect(inDialog(find.text('All-branches QR')), findsOneWidget);
    expect(inDialog(find.text(qr.longUrl)), findsOneWidget);
    expect(inDialog(find.text(qr.shortUrl)), findsOneWidget);
    expect(
      find.descendant(
        of: inDialog(find.byType(DashBadge)),
        matching: find.textContaining(qr.shortCode),
      ),
      findsOneWidget,
    );
    await h.tap(inDialog(find.text('Copy link')));
    expect(inDialog(find.text('Copied!')), findsOneWidget);
    await h.tap(inDialog(find.text('Download')));
    expect(h.files.saved.single.filename, 'qr-${qr.shortCode}.png');
    await h.flushTimers();
    expect(inDialog(find.text('Copy link')), findsOneWidget);
  });

  testWidgets('SET-QR-015 SET-QR-018 below 1024 the result sits under the '
      'controls; on a phone its buttons stack', (tester) async {
    final h = await pumpQr(tester, size: DashSize.phone);
    await h.tap(generateOf(QrKind.orgOrder));
    final result = resultOf(QrKind.orgOrder);
    await tester.ensureVisible(result);
    await h.settle();
    expect(
      tester.getTopLeft(result).dy,
      greaterThan(tester.getBottomLeft(generateOf(QrKind.orgOrder)).dy),
    );
    final copy = find.descendant(
      of: result,
      matching: find.byKey(const ValueKey('qr-copy')),
    );
    final download = find.descendant(
      of: result,
      matching: find.byKey(const ValueKey('qr-download')),
    );
    expect(
      tester.getTopLeft(download).dy,
      greaterThan(tester.getBottomLeft(copy).dy),
    );
  });

  testWidgets('SET-QR-017 Copy link: "Copied" for 1.6 s; a failure toasts', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    await h.tap(generateOf(QrKind.orgOrder));
    final result = resultOf(QrKind.orgOrder);
    final qr = mockQrResponse(
      kind: 'org_order',
      longUrl: '$mockOrderBase/order/${SeedIds.sabahOrg}',
      key: 'org_order:${SeedIds.sabahOrg}',
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await h.tap(
      find.descendant(
        of: result,
        matching: find.byKey(const ValueKey('qr-copy')),
      ),
    );
    expect(copied, qr.shortUrl);
    expect(
      find.descendant(of: result, matching: find.text('Copied')),
      findsOneWidget,
    );
    // 0.4 s of settling + 1.1 s: still "Copied"; at 1.7 s it is back.
    await tester.pump(const Duration(milliseconds: 1100));
    expect(
      find.descendant(of: result, matching: find.text('Copied')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(of: result, matching: find.text('Copy link')),
      findsOneWidget,
    );

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'denied');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await h.tap(
      find.descendant(
        of: result,
        matching: find.byKey(const ValueKey('qr-copy')),
      ),
    );
    await h.expectToast('Could not copy the link');
  });

  testWidgets('SET-QR-018 Download saves qr-<code>.png', (tester) async {
    final h = await pumpQr(tester, query: atBranch(SeedIds.zamalek));
    await h.tap(generateOf(QrKind.branchOrder));
    final qr = mockQrResponse(
      kind: 'branch_order',
      longUrl:
          '$mockOrderBase/order/${SeedIds.sabahOrg}'
          '?branch=${SeedIds.zamalek}',
      key: 'branch_order:${SeedIds.zamalek}',
    );
    await h.tap(
      find.descendant(
        of: resultOf(QrKind.branchOrder),
        matching: find.byKey(const ValueKey('qr-download')),
      ),
    );
    final saved = h.files.saved.single;
    expect(saved.filename, 'qr-${qr.shortCode}.png');
    expect(saved.bytes, qrImageBytes(qr.qrDataUrl));
  });

  testWidgets('SET-QR-026 leaving the page clears every code', (tester) async {
    final h = await pumpQr(tester);
    await h.tap(generateOf(QrKind.orgOrder));
    expect(resultOf(QrKind.orgOrder), findsOneWidget);
    await h.go('/settings/brand');
    await h.go(qrPath);
    expect(resultOf(QrKind.orgOrder), findsNothing);
  });

  testWidgets('SET-QR-027 (divergence) moving the header branch drops the '
      'branch cards\' codes and errors; org codes and typed fields stay', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    await h.tap(generateOf(QrKind.orgOrder));
    await pickBranch(h, SeedIds.maadi);
    // The org code stays (dimmed): it is still this organization's.
    expect(resultOf(QrKind.orgOrder), findsOneWidget);
    await h.tap(generateOf(QrKind.branchOrder));
    await h.tap(generateOf(QrKind.branchBooking)); // Maadi: switched off
    expect(resultOf(QrKind.branchOrder), findsOneWidget);
    expect(
      find.byKey(const ValueKey('qr-error-branchBooking')),
      findsOneWidget,
    );
    await h.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('qr-floor')),
        matching: find.byType(EditableText),
      ),
      'Ground Floor',
    );

    await pickBranch(h, SeedIds.zamalek);
    expect(resultOf(QrKind.branchOrder), findsNothing);
    expect(find.byKey(const ValueKey('qr-error-branchBooking')), findsNothing);
    expect(resultOf(QrKind.orgOrder), findsOneWidget);
    expect(
      inKind(QrKind.branchOrderInMall, find.text('Ground Floor')),
      findsOneWidget,
    );
  });

  testWidgets('refusal: the limited persona may not make booking codes '
      '(bookings.read), the reason inline', (tester) async {
    final h = await pumpQr(
      tester,
      persona: Persona.limited,
      query: atBranch(SeedIds.maadi),
    );
    await h.tap(generateOf(QrKind.branchBooking));
    expect(
      inKind(
        QrKind.branchBooking,
        find.text(h.refusalWords(MockResponse.denied('bookings.read'))),
      ),
      findsOneWidget,
    );
    await h.tap(generateOf(QrKind.branchOrder));
    expect(resultOf(QrKind.branchOrder), findsOneWidget);
  });

  testWidgets('refusal: a manager makes Zamalek\'s codes', (tester) async {
    final h = await pumpQr(
      tester,
      persona: Persona.manager,
      query: atBranch(SeedIds.zamalek),
    );
    await h.tap(generateOf(QrKind.branchBooking));
    expect(resultOf(QrKind.branchBooking), findsOneWidget);
  });

  testWidgets('refusal: another org\'s branch is refused in the server\'s '
      'words', (tester) async {
    final m = setupMockServer();
    m.server.fail(
      'GET',
      QrRoutes.branchQr,
      MockResponse.forbidden('Access to this org is not allowed'),
      times: null,
    );
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.heliopolis),
    );
    await h.tap(generateOf(QrKind.branchOrder));
    expect(
      inKind(
        QrKind.branchOrder,
        find.text(
          h.refusalWords(
            MockResponse.forbidden('Access to this org is not allowed'),
          ),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('refusal: a Dawam-only org never reaches the page (module '
      'pos), nothing is asked', (tester) async {
    final h = await pumpQr(tester, persona: Persona.dawamOnly);
    h.allowUnmatched = true;
    expect(find.byKey(const ValueKey('qr-options')), findsNothing);
    expect(h.server.callsTo(QrRoutes.tables), isEmpty);
    expect(h.server.callsTo(QrRoutes.orgQr), isEmpty);
  });
}
