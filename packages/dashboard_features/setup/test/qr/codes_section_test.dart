// The single codes of Settings › Links & QR codes (SET-QR-001 – 018,
// 025 – 027): the codes section's heading, the output switches as each code
// sends them, the org and branch cards, generating, the inline error, the
// result card and the preview dialog.
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
  testWidgets('SET-QR-001 the codes section: "QR codes" and its line', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    expect(inPage(find.text(h.t('linksQr.codes.title'))), findsWidgets);
    expect(inPage(find.text(h.t('linksQr.codes.desc'))), findsOneWidget);
  });

  testWidgets('SET-QR-002 SET-SHL-020 no org in scope: "Select an '
      'organization", nothing asked', (tester) async {
    final h = await pumpQr(tester, persona: Persona.platform, pickOrg: false);
    h.allowUnmatched = true;
    expect(inPage(find.text('Links & QR codes')), findsOneWidget);
    expect(inPage(find.text('Select an organization')), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-output-panel')), findsNothing);
    expect(h.server.callsTo(QrRoutes.tables), isEmpty);
    expect(h.server.callsTo(QrRoutes.linksQr), isEmpty);
  });

  testWidgets('SET-QR-003 SET-QR-030 the output switches: today\'s card at '
      '600 DPI by default; every code sends what they say', (tester) async {
    final h = await pumpQr(tester);
    expect(inPanel(find.text('Unbranded')), findsOneWidget);
    expect(inPanel(find.text('A6 card')), findsOneWidget);
    expect(inPanel(find.text('DPI')), findsOneWidget);
    expect(inPanel(find.text('600')), findsOneWidget);
    expect(inPanel(find.text(h.t('qr.output.hint'))), findsOneWidget);

    await h.tap(generateOf(QrKind.orgOrder));
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).single), {
      'card': 'true',
      'dpi': '600',
    });

    // DPI 300: the code on screen is made again, no second press.
    await h.tap(inPanel(find.byKey(const ValueKey('qr-dpi'))));
    await h.tap(find.text('300').last);
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).last), {
      'card': 'true',
      'dpi': '300',
    });

    // Card off: the DPI select goes, the DPI still rides along.
    await h.tap(inPanel(find.byKey(const ValueKey('qr-card'))));
    expect(inPanel(find.text('DPI')), findsNothing);
    expect(inPanel(find.text(h.t('qr.output.cardOff'))), findsOneWidget);
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).last), {
      'card': 'false',
      'dpi': '300',
    });

    // Unbranded: only what the plain code reads; the card switch steps
    // aside and the DPI comes back.
    await h.tap(inPanel(find.byKey(const ValueKey('qr-unbranded'))));
    expect(inPanel(find.byKey(const ValueKey('qr-card'))), findsNothing);
    expect(inPanel(find.text('DPI')), findsOneWidget);
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).last), {
      'unbranded': 'true',
      'centre_logo': 'true',
      'dpi': '300',
    });
    await h.tap(inPanel(find.byKey(const ValueKey('qr-centre-logo'))));
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).last), {
      'unbranded': 'true',
      'centre_logo': 'false',
      'dpi': '300',
    });

    await pickBranch(h, SeedIds.heliopolis);
    await h.tap(generateOf(QrKind.branchOrder));
    expect(queryOf(h.server.callsTo(QrRoutes.branchQr).last), {
      'unbranded': 'true',
      'centre_logo': 'false',
      'dpi': '300',
    });
  });

  testWidgets('SET-QR-004 SET-QR-006 SET-QR-038 the whole-organization '
      'section\'s four cards and the branch section\'s three', (tester) async {
    final h = await pumpQr(tester);
    expect(inQr(find.text('For the whole organization')), findsOneWidget);
    expect(inQr(find.text('For one branch')), findsOneWidget);
    for (final (kind, title, description) in [
      (QrKind.orgLinks, 'qr.links.title', 'qr.links.description'),
      (
        QrKind.orgMenuDisplay,
        'qr.menuDisplay.title',
        'qr.menuDisplay.description',
      ),
      (QrKind.orgOrder, 'qr.org.title', 'qr.org.description'),
      (QrKind.orgBooking, 'qr.orgBooking.title', 'qr.orgBooking.description'),
      (QrKind.branchOrder, 'qr.standard.title', 'qr.standard.description'),
      (
        QrKind.branchBooking,
        'qr.branchBooking.title',
        'qr.branchBooking.description',
      ),
      (QrKind.branchOrderInMall, 'qr.inMall.title', 'qr.inMall.description'),
    ]) {
      expect(inKind(kind, find.text(h.t(title))), findsOneWidget);
      expect(inKind(kind, find.text(h.t(description))), findsOneWidget);
    }
    expect(
      inKind(QrKind.orgOrder, find.text('All-branches QR')),
      findsOneWidget,
    );
    // In the web's order: the shop's own codes first.
    final tops = [
      for (final k in QrKind.values)
        tester.getTopLeft(find.byKey(ValueKey('qr-kind-${k.name}'))).dy,
    ];
    expect(tops, [...tops]..sort());
  });

  testWidgets('SET-QR-038 the links page and menu codes: any scope, the '
      'links page\'s own endpoint', (tester) async {
    final h = await pumpQr(tester, query: atBranch(SeedIds.maadi));
    await h.tap(generateOf(QrKind.orgLinks));
    await h.tap(generateOf(QrKind.orgMenuDisplay));
    expect(resultOf(QrKind.orgLinks), findsOneWidget);
    expect(resultOf(QrKind.orgMenuDisplay), findsOneWidget);
    final full = h.server
        .callsTo(QrRoutes.linksQr)
        .where((c) => c.query['dpi']?.single == '600')
        .map(queryOf)
        .toList();
    expect(full, [
      {'card': 'true', 'dpi': '600'},
      {'card': 'true', 'dpi': '600', 'target': 'menu_display'},
    ]);
    expect(
      find.descendant(
        of: resultOf(QrKind.orgMenuDisplay),
        matching: find.text('https://sabah-coffee.madar-pos.cloud/menu'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SET-QR-005 SET-QR-007 org cards need All branches; branch '
      'cards (and the in-mall fields) need a branch', (tester) async {
    final h = await pumpQr(tester);
    // All branches: org cards on, branch cards dimmed and disabled.
    expect(_button(tester, generateOf(QrKind.orgOrder)).onPressed, isNotNull);
    expect(_button(tester, generateOf(QrKind.orgLinks)).onPressed, isNotNull);
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
    // The shop's own codes work in any scope.
    for (final k in [QrKind.orgLinks, QrKind.orgMenuDisplay]) {
      expect(
        _button(tester, generateOf(k)).onPressed,
        isNotNull,
        reason: k.name,
      );
    }
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

  testWidgets('SET-QR-013 a failure clears on the next press; generating '
      'again keeps the code up while it is made again', (tester) async {
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
    expect(_button(tester, generateOf(QrKind.orgBooking)).loading, isTrue);
    expect(_button(tester, generateOf(QrKind.orgBooking)).onPressed, isNull);
    expect(_button(tester, generateOf(QrKind.orgOrder)).loading, isFalse);
    expect(_button(tester, generateOf(QrKind.orgOrder)).onPressed, isNotNull);
    gate.release();
    await h.settle();
    expect(resultOf(QrKind.orgBooking), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-error-orgBooking')), findsNothing);

    // A second press asks the server again (the card is redrawn from the
    // current brand); the code stays up, veiled, until the new one lands.
    final asked = m.server.callsTo(QrRoutes.orgBooking).length;
    final again = m.server.hold('GET', QrRoutes.orgBooking);
    await tester.tap(generateOf(QrKind.orgBooking));
    await tester.pump();
    expect(resultOf(QrKind.orgBooking), findsOneWidget);
    expect(veiled(tester, resultOf(QrKind.orgBooking)), isTrue);
    expect(m.server.callsTo(QrRoutes.orgBooking), hasLength(asked + 1));
    again.release();
    await h.settle();
    expect(resultOf(QrKind.orgBooking), findsOneWidget);
    expect(veiled(tester, resultOf(QrKind.orgBooking)), isFalse);
  });

  testWidgets('SET-QR-014 a failure shows inline, in the server\'s words, '
      'no toast', (tester) async {
    final m = setupMockServer();
    // Zamalek has rules but bookings are switched off.
    final h = await pumpQr(
      tester,
      backend: m,
      query: atBranch(SeedIds.zamalek),
    );
    await h.tap(generateOf(QrKind.branchBooking));
    final words = h.refusalWords(
      MockResponse.conflict('Bookings are switched off for this branch'),
    );
    expect(inKind(QrKind.branchBooking, find.text(words)), findsOneWidget);
    expect(resultOf(QrKind.branchBooking), findsNothing);
    expect(find.text(words), findsOneWidget, reason: 'no toast');

    // Switched on: the next press asks again (a refusal is not kept).
    m.db['booking_settings'].firstWhere(
      (r) => r['branch_id'] == SeedIds.zamalek,
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
    // The output switches sit under the code.
    expect(
      inDialog(find.byKey(const ValueKey('qr-output-controls'))),
      findsOneWidget,
    );
    expect(inDialog(find.text('Print')), findsOneWidget);
    expect(inDialog(find.text('Share')), findsOneWidget);
    await h.tap(inDialog(find.text('Copy link')));
    expect(inDialog(find.text('Copied!')), findsOneWidget);
    await h.tap(inDialog(find.text('Download')));
    expect(h.files.saved.single.filename, 'qr-${qr.shortCode}.png');
    await h.tap(inDialog(find.text('Share')));
    expect(h.files.shared.single.filename, 'qr-${qr.shortCode}.png');
    expect(h.files.shared.single.text, qr.shortUrl);
    await h.flushTimers();
    expect(inDialog(find.text('Copy link')), findsOneWidget);
  });

  testWidgets('SET-QR-015 SET-QR-018 below 1024 the result sits under the '
      'controls; Copy link on its own row, Print and Download under it', (
    tester,
  ) async {
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
    final print = find.descendant(
      of: result,
      matching: find.byKey(const ValueKey('qr-print')),
    );
    expect(
      tester.getTopLeft(download).dy,
      greaterThan(tester.getBottomLeft(copy).dy),
    );
    expect(tester.getTopLeft(print).dy, tester.getTopLeft(download).dy);
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

  testWidgets('SET-QR-018 Download saves qr-<code>.png, the server\'s '
      'image untouched', (tester) async {
    final h = await pumpQr(tester, query: atBranch(SeedIds.zamalek));
    await h.tap(generateOf(QrKind.branchOrder));
    final qr = mockQrResponse(
      look: MockQrLook.card,
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

  testWidgets('SET-QR-027 moving the header branch drops the branch '
      'cards\' codes and errors; back again, the code is shown again; org '
      'codes and typed fields stay', (tester) async {
    final h = await pumpQr(tester);
    await h.tap(generateOf(QrKind.orgOrder));
    await pickBranch(h, SeedIds.zamalek);
    // The org code goes with All branches; the shop's own codes stay.
    expect(resultOf(QrKind.orgOrder), findsNothing);
    await h.tap(generateOf(QrKind.orgLinks));
    await h.tap(generateOf(QrKind.branchOrder));
    await h.tap(generateOf(QrKind.branchBooking)); // Zamalek: switched off
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

    await pickBranch(h, SeedIds.maadi);
    expect(resultOf(QrKind.branchOrder), findsNothing);
    expect(find.byKey(const ValueKey('qr-error-branchBooking')), findsNothing);
    expect(resultOf(QrKind.orgLinks), findsOneWidget);
    expect(
      inKind(QrKind.branchOrderInMall, find.text('Ground Floor')),
      findsOneWidget,
    );
    // Maadi's code is never made unasked.
    expect(
      h.server
          .callsTo(QrRoutes.branchQr)
          .where((c) => c.path.contains(SeedIds.maadi)),
      isEmpty,
    );

    // Back on Zamalek, its code is Zamalek's: shown again, not made again.
    final made = h.server.callsTo(QrRoutes.branchQr).length;
    await pickBranch(h, SeedIds.zamalek);
    expect(resultOf(QrKind.branchOrder), findsOneWidget);
    expect(h.server.callsTo(QrRoutes.branchQr), hasLength(made));
    await pickBranch(h, null);
    expect(resultOf(QrKind.orgOrder), findsOneWidget);
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
    final m = setupMockServer(persona: Persona.manager);
    // Zamalek's online bookings are off in the seed: switch them on.
    m.db['booking_settings'].firstWhere(
      (r) => r['branch_id'] == SeedIds.zamalek,
    )!['enabled'] = true;
    final h = await pumpQr(
      tester,
      backend: m,
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
    expect(find.byKey(const ValueKey('qr-output-panel')), findsNothing);
    expect(h.server.callsTo(QrRoutes.tables), isEmpty);
    expect(h.server.callsTo(QrRoutes.orgQr), isEmpty);
    expect(h.server.callsTo(QrRoutes.linksQr), isEmpty);
  });
}
