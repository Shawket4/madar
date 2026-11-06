// The output switches driving every code live (SET-QR-029 – 039): the
// panel's sample, the logo sub-switch, what is remembered, a code on screen
// re-rendered by a flip, the same switches in a code's preview, the no-logo
// note, Print / Share / Download of what the server made, and Free's locks.
import 'package:dashboard_api/dashboard_api.dart' show QrResponse;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/shared/qr_preview_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qr_support.dart';

const _sample = ValueKey('qr-sample');
const _unbranded = ValueKey('qr-unbranded');
const _logo = ValueKey('qr-centre-logo');

/// The image [f] shows (a [QrImage] under it).
String _image(WidgetTester tester, Finder f) => tester
    .widget<QrImage>(find.descendant(of: f, matching: find.byType(QrImage)))
    .dataUrl;

/// The org's all-branches ordering code as the mock draws it in [look].
QrResponse _orgOrder({MockQrLook look = MockQrLook.card, bool logo = false}) =>
    mockQrResponse(
      kind: 'org_order',
      longUrl: '$mockOrderBase/order/${SeedIds.sabahOrg}',
      key: 'org_order:${SeedIds.sabahOrg}',
      look: look,
      logo: logo,
    );

/// The sample's requests (the links page code at 150 DPI).
List<Map<String, String>> _samples(DashHarness h) => [
  for (final c in h.server.callsTo(QrRoutes.linksQr))
    if (c.query['dpi']?.single == '150') queryOf(c),
];

Finder get _dialog => find.byType(QrPreviewDialog);
Finder _inDialog(Finder f) => find.descendant(of: _dialog, matching: f);

void main() {
  testWidgets('SET-QR-029 the panel: its words, the switches, and a sample '
      'of the links page code at 150 DPI that follows every flip', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    expect(inPanel(find.text(h.t('qr.output.title'))), findsOneWidget);
    expect(inPanel(find.text(h.t('qr.output.hint'))), findsOneWidget);
    expect(inPanel(find.text(h.t('qr.output.preview'))), findsOneWidget);
    expect(_samples(h), [
      {'card': 'true', 'dpi': '150'},
    ]);
    final card = _image(tester, find.byKey(_sample));

    await h.tap(inPanel(find.byKey(_unbranded)));
    expect(_samples(h).last, {
      'unbranded': 'true',
      'centre_logo': 'true',
      'dpi': '150',
    });
    final plain = _image(tester, find.byKey(_sample));
    expect(plain, isNot(card));

    await h.tap(inPanel(find.byKey(_logo)));
    expect(_samples(h).last, {
      'unbranded': 'true',
      'centre_logo': 'false',
      'dpi': '150',
    });
    // No code was made: the sample is the only one asked for.
    expect(h.server.callsTo(QrRoutes.orgQr), isEmpty);
  });

  testWidgets('SET-QR-029 the sample opens the real code, at the chosen '
      'resolution, with the switches under it', (tester) async {
    final h = await pumpQr(tester);
    await h.tap(find.byKey(_sample));
    expect(
      queryOf(
        h.server
            .callsTo(QrRoutes.linksQr)
            .lastWhere((c) => c.query['dpi']?.single != '150'),
      ),
      {'card': 'true', 'dpi': '600'},
    );
    expect(_inDialog(find.text(h.t('links.editor.qrTitle'))), findsOneWidget);
    expect(
      _inDialog(find.byKey(const ValueKey('qr-output-controls'))),
      findsOneWidget,
    );
  });

  testWidgets('SET-QR-031 the logo switch works only under Unbranded', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    DashSwitch logo() => tester.widget(inPanel(find.byKey(_logo)));
    expect(logo().enabled, isFalse);
    expect(logo().value, isTrue);
    expect(inPanel(find.text(h.t('qr.output.centreLogoOff'))), findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: inPanel(find.byKey(_logo)),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      0.6,
    );
    // Its words do nothing either.
    await h.tap(inPanel(find.text(h.t('qr.output.centreLogo'))));
    expect(logo().value, isTrue);
    expect(storedOutput(h), isNull);

    await h.tap(inPanel(find.byKey(_unbranded)));
    expect(logo().enabled, isTrue);
    expect(inPanel(find.text(h.t('qr.output.centreLogoHint'))), findsOneWidget);
    await h.tap(inPanel(find.text(h.t('qr.output.centreLogo'))));
    expect(logo().value, isFalse);
  });

  testWidgets('SET-QR-032 remembered for this shop on this device', (
    tester,
  ) async {
    var h = await pumpQr(tester);
    await h.tap(inPanel(find.byKey(_unbranded)));
    await h.tap(inPanel(find.byKey(_logo)));
    expect(storedOutput(h), const QrOutput(unbranded: true, centreLogo: false));

    // Another visit on this device: the switches as they were left.
    h = await pumpQr(
      tester,
      output: const QrOutput(unbranded: true, centreLogo: false, dpi: 300),
    );
    expect(
      tester.widget<DashSwitch>(inPanel(find.byKey(_unbranded))).value,
      isTrue,
    );
    expect(
      tester.widget<DashSwitch>(inPanel(find.byKey(_logo))).value,
      isFalse,
    );
    expect(_samples(h).single, {
      'unbranded': 'true',
      'centre_logo': 'false',
      'dpi': '150',
    });
    await h.tap(generateOf(QrKind.orgOrder));
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).single), {
      'unbranded': 'true',
      'centre_logo': 'false',
      'dpi': '300',
    });
  });

  testWidgets('SET-QR-033 a code already on screen re-renders when a switch '
      'flips, no second press; the old one stays up, veiled, until the new '
      'one lands', (tester) async {
    final m = setupMockServer();
    final h = await pumpQr(tester, backend: m);
    await h.tap(generateOf(QrKind.orgOrder));
    final result = resultOf(QrKind.orgOrder);
    expect(_image(tester, result), _orgOrder().qrDataUrl);

    final gate = m.server.hold('GET', QrRoutes.orgQr);
    await h.tap(inPanel(find.byKey(_unbranded)));
    expect(result, findsOneWidget);
    expect(_image(tester, result), _orgOrder().qrDataUrl);
    expect(veiled(tester, result), isTrue);
    gate.release();
    await h.settle();
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).last), {
      'unbranded': 'true',
      'centre_logo': 'true',
      'dpi': '600',
    });
    expect(_image(tester, result), _orgOrder(look: MockQrLook.plain).qrDataUrl);
    expect(veiled(tester, result), isFalse);
    // Downloaded, it says which it is.
    await h.tap(
      find.descendant(
        of: result,
        matching: find.byKey(const ValueKey('qr-download')),
      ),
    );
    expect(
      h.files.saved.single.filename,
      'qr-${_orgOrder().shortCode}-unbranded.png',
    );

    // Back to branded: the card again, from the cache.
    final asked = h.server.callsTo(QrRoutes.orgQr).length;
    await h.tap(inPanel(find.byKey(_unbranded)));
    expect(_image(tester, result), _orgOrder().qrDataUrl);
    expect(h.server.callsTo(QrRoutes.orgQr), hasLength(asked));
  });

  testWidgets('SET-QR-034 the switches sit in a code\'s preview too; '
      'flipping them there changes that code, here and on the page', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    await h.tap(generateOf(QrKind.orgOrder));
    await h.tap(
      find.descendant(
        of: resultOf(QrKind.orgOrder),
        matching: find.bySemanticsLabel('Enlarge QR code'),
      ),
    );
    expect(_image(tester, _dialog), _orgOrder().qrDataUrl);

    await h.tap(_inDialog(find.byKey(_unbranded)));
    expect(
      _image(tester, _dialog),
      _orgOrder(look: MockQrLook.plain).qrDataUrl,
    );
    await h.tap(_inDialog(find.byKey(_logo)));
    expect(queryOf(h.server.callsTo(QrRoutes.orgQr).last), {
      'unbranded': 'true',
      'centre_logo': 'false',
      'dpi': '600',
    });
    // One switch: the page's panel and the code on the page follow.
    expect(
      tester.widget<DashSwitch>(inPanel(find.byKey(_unbranded))).value,
      isTrue,
    );
    expect(
      _image(tester, resultOf(QrKind.orgOrder)),
      _orgOrder(look: MockQrLook.plain).qrDataUrl,
    );
    expect(_inDialog(find.byKey(const ValueKey('qr-card'))), findsNothing);
  });

  testWidgets('SET-QR-034 the links page and menu "QR code" buttons open the '
      'same live code', (tester) async {
    final h = await pumpQr(tester);
    await h.tap(find.byKey(const ValueKey('links-qr')));
    expect(_inDialog(find.text(h.t('links.editor.qrTitle'))), findsOneWidget);
    await h.tap(_inDialog(find.byKey(_unbranded)));
    expect(
      queryOf(
        h.server
            .callsTo(QrRoutes.linksQr)
            .lastWhere((c) => c.query['dpi']?.single == '600'),
      ),
      {'unbranded': 'true', 'centre_logo': 'true', 'dpi': '600'},
    );
    await tester.tapAt(const Offset(8, 8));
    await h.settle();

    await h.tap(find.byKey(const ValueKey('menu-display-qr')));
    expect(
      _inDialog(find.text(h.t('menuDisplay.editor.qrTitle'))),
      findsOneWidget,
    );
    expect(queryOf(h.server.callsTo(QrRoutes.linksQr).last), {
      'unbranded': 'true',
      'centre_logo': 'true',
      'dpi': '600',
      'target': 'menu_display',
    });
  });

  testWidgets('SET-QR-035 no logo for codes: the code comes out plain, the '
      'note says so, Brand is one tap away', (tester) async {
    // Sabah has no logo on file.
    final h = await pumpQr(tester, output: const QrOutput(unbranded: true));
    final note = inPanel(find.byKey(const ValueKey('qr-no-logo')));
    expect(note, findsOneWidget);
    expect(
      find.descendant(of: note, matching: find.text(h.t('qr.output.noLogo'))),
      findsOneWidget,
    );
    // Logo off: nothing was asked for, so nothing to say.
    await h.tap(inPanel(find.byKey(_logo)));
    expect(note, findsNothing);
    await h.tap(inPanel(find.byKey(_logo)));
    expect(note, findsOneWidget);
    await h.tap(
      find.descendant(of: note, matching: find.text(h.t('qr.output.addLogo'))),
    );
    expect(h.location.path, '/settings/brand');
  });

  testWidgets('SET-QR-035 a shop with a logo gets it in the middle: no note', (
    tester,
  ) async {
    final m = setupMockServer();
    m.db['orgs'].update(SeedIds.sabahOrg, {
      'logo_url': 'https://cdn.madar-pos.cloud/sabah/logo.png',
    });
    final h = await pumpQr(
      tester,
      backend: m,
      output: const QrOutput(unbranded: true),
    );
    expect(inPanel(find.byKey(const ValueKey('qr-no-logo'))), findsNothing);
    await h.tap(generateOf(QrKind.orgOrder));
    expect(
      _image(tester, resultOf(QrKind.orgOrder)),
      _orgOrder(look: MockQrLook.plain, logo: true).qrDataUrl,
    );
  });

  testWidgets('SET-QR-036 Print on a code prints that code alone: unbranded, '
      'the image and nothing else', (tester) async {
    final printed = capturePrints();
    final h = await pumpQr(
      tester,
      output: const QrOutput(unbranded: true, centreLogo: false),
    );
    await h.tap(generateOf(QrKind.orgOrder));
    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(
          of: resultOf(QrKind.orgOrder),
          matching: find.byKey(const ValueKey('qr-print')),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await h.settle();
    expect(printed, hasLength(1));
    expect(printed.single.$2, h.t('qr.org.title'));
    expect(pdfFacts(printed.single.$1), (
      images: 1,
      text: false,
      dashed: false,
      fonts: false,
    ));

    // And from its preview.
    await h.tap(
      find.descendant(
        of: resultOf(QrKind.orgOrder),
        matching: find.bySemanticsLabel('Enlarge QR code'),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(_inDialog(find.byKey(const ValueKey('qr-print'))));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await h.settle();
    expect(printed, hasLength(2));
    expect(pdfFacts(printed.last.$1).images, 1);
  });

  testWidgets('SET-QR-037 Share only where the platform has a share sheet', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    await h.tap(find.byKey(_sample));
    expect(_inDialog(find.text(h.t('qr.share'))), findsOneWidget);
    await h.tap(_inDialog(find.text(h.t('qr.share'))));
    expect(h.files.shared.single.text, startsWith(mockShortLinkBase));
    await tester.tapAt(const Offset(8, 8));
    await h.settle();

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await h.tap(find.byKey(_sample));
      expect(_inDialog(find.text(h.t('qr.print'))), findsOneWidget);
      expect(_inDialog(find.text(h.t('qr.share'))), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('SET-QR-039 Free: the menu and its code are usable; the '
      'ordering, booking and table codes are one lock, nothing behind it '
      'asked for', (tester) async {
    final h = await pumpQr(
      tester,
      query: atBranch(SeedIds.heliopolis),
      overrides: [freePlan],
    );
    expect(
      find.byKey(const ValueKey('qr-kind-orgMenuDisplay')),
      findsOneWidget,
    );
    for (final k in QrKind.values) {
      if (k == QrKind.orgMenuDisplay) continue;
      expect(find.byKey(ValueKey('qr-kind-${k.name}')), findsNothing);
    }
    expect(inQr(find.text('For one branch')), findsNothing);
    expect(inQr(find.text('For each table')), findsNothing);
    final lock = find.byKey(const ValueKey('paid-lock-online'));
    expect(lock, findsOneWidget);
    Finder inLock(Finder f) => find.descendant(of: lock, matching: f);
    expect(inLock(find.text(h.t('qr.locked.title'))), findsOneWidget);
    for (final key in [
      'qr.org.title',
      'qr.orgBooking.title',
      'qr.standard.title',
      'qr.branchBooking.title',
      'qr.inMall.title',
      'qr.tables.title',
    ]) {
      expect(inLock(find.text(h.t(key))), findsOneWidget, reason: key);
    }
    // The sample is the menu's code.
    expect(
      [for (final c in h.server.callsTo(QrRoutes.linksQr)) queryOf(c)],
      [
        {'card': 'true', 'dpi': '150', 'target': 'menu_display'},
      ],
    );
    expect(h.server.callsTo(QrRoutes.tables), isEmpty);
    expect(h.server.callsTo(QrRoutes.orgQr), isEmpty);
    expect(h.server.callsTo(QrRoutes.branchQr), isEmpty);

    await h.tap(generateOf(QrKind.orgMenuDisplay));
    expect(resultOf(QrKind.orgMenuDisplay), findsOneWidget);

    // No Brand on Free: the note has no link.
    await h.tap(inPanel(find.byKey(_unbranded)));
    expect(inPanel(find.byKey(const ValueKey('qr-no-logo'))), findsOneWidget);
    expect(inPanel(find.text(h.t('qr.output.addLogo'))), findsNothing);
  });
}
