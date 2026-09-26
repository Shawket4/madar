// Fast mode's Done: a PAGE of the menu panel, not a card.
//
// In Fast mode the cart sits on the start edge and the panel on the end edge
// shows the menu, or whatever replaced it (an item's choices, Charge). Once
// Charge takes the money, Done replaces the panel the same way: the sale's
// status, the amount, the tender and the change, "Printed" once the paper is
// out, Add points and Reprint, then "T5 cleared?" on a table's sale or
// "New sale" on a counter's. It is the card's view model (the same state and
// the same calls) drawn as a page.
//
// The standard layout keeps the Done card; its tests are charge_render_test.
//
// `MADAR_RENDER=true` writes `build/render/done-page-*.png`.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

/// The iPad, landscape: Fast mode is a tablet layout.
const Size _ipad = Size(1194, 834);

/// The cart column beside the panel.
const double _cartWidth = 340;

const _session = SessionSnapshot(
  userId: 'u1',
  displayName: 'Sara',
  role: 'teller',
  currencyCode: 'EGP',
  taxRate: 0.14,
  taxInclusive: true,
  serviceChargeRate: 0,
  serviceChargeTaxable: false,
  requireTableForOrders: false,
  online: true,
  permissionsLoaded: true,
);

class _Fake implements MadarBridge {
  _Fake({this.rtl = false});

  final bool rtl;

  /// Every table the Done page cleared, in order.
  final List<String> cleared = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #tr) return coreWord(a[#key] as String? ?? '', arabic: rtl);
    if (name == #isRtl) return rtl;
    if (name == #locale) return rtl ? 'ar' : 'en';
    if (name == #currentSession) return _session;
    if (name == #deviceConfig) {
      return const DeviceConfigView(
        branchName: 'Rue Zamalek',
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #clearTable) {
      cleared.add(a[#tableId] as String);
      return Future<void>.value();
    }
    if (name == #humanMessage) return 'refused';
    if (name == #loyaltyAwardWindowOpen) return true;
    return null;
  }
}

ReceiptView _receipt({required bool queued, int? number}) => ReceiptView(
  deals: const [],
  payments: const [],
  localOrderId: '8f2a4c1e-queued',
  orderNumber: number,
  isVoided: false,
  lines: const [],
  paymentLabel: 'Cash',
  subtotalMinor: 17500,
  discountMinor: 0,
  taxMinor: 2407,
  serviceChargeMinor: 0,
  deliveryFeeMinor: 0,
  totalMinor: 17500,
  tipMinor: 0,
  amountTenderedMinor: 20000,
  changeMinor: 2500,
  isCash: true,
  isDelivery: false,
  queuedOffline: queued,
  createdAt: '2026-09-10T19:45:00Z',
  displayNumber: '',
  serviceChargeWaivedMinor: 0,
  taxInclusive: false,
  taxRate: 0.14,
);

/// A counter sale, printed.
ChargeOutcome _counter({PrintState print = PrintState.printed}) =>
    ChargeOutcome(
      target: const ChargeTarget.cart(),
      queued: false,
      amountMinor: 15390,
      methodLabel: 'Cash',
      isCash: true,
      currency: 'EGP',
      createdAt: '2026-09-10T19:45:00Z',
      receipt: _receipt(queued: false, number: 1043),
      orderId: 'o-1043',
      orderNumber: 1043,
      changeMinor: 4610,
      loyaltyOffered: true,
      printState: print,
    );

/// A table's bill, settled and printed: the floor waits for "cleared?".
ChargeOutcome _table() => ChargeOutcome(
  target: const ChargeTarget.cart(tableId: 't5'),
  queued: false,
  amountMinor: 17500,
  methodLabel: 'Cash',
  isCash: true,
  currency: 'EGP',
  createdAt: '2026-09-10T19:45:00Z',
  receipt: _receipt(queued: false, number: 1042),
  orderId: 'o-1042',
  orderNumber: 1042,
  changeMinor: 2500,
  tableId: 't5',
  tableLabel: 'T5',
  loyaltyOffered: true,
  printState: PrintState.printed,
);

/// A sale rung offline: in the outbox, no printer bound.
ChargeOutcome _queued() => ChargeOutcome(
  target: const ChargeTarget.cart(),
  queued: true,
  amountMinor: 17500,
  methodLabel: 'Cash',
  isCash: true,
  currency: 'EGP',
  createdAt: '2026-09-10T19:45:00Z',
  receipt: _receipt(queued: true),
  orderKey: '8f2a4c1e-queued',
  changeMinor: 2500,
  loyaltyOffered: true,
  printState: PrintState.noPrinter,
);

// ── Harness: Fast mode's body, the cart then the panel ───────────────────

final _panelNav = GlobalKey<NavigatorState>();

class _FastBody extends StatelessWidget {
  const _FastBody({required this.backLabel});

  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: MadarPanelHost(
        navigatorKey: _panelNav,
        backLabel: backLabel,
        child: Row(
          key: const ValueKey('fast-body'),
          children: [
            SizedBox(
              width: _cartWidth,
              child: Center(
                child: Text(
                  '(the cart)',
                  style: MadarType.body.copyWith(color: colors.textMuted),
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: ClipRect(
                child: Navigator(
                  key: _panelNav,
                  pages: [
                    MaterialPage<void>(
                      key: const ValueKey('menu'),
                      child: ColoredBox(
                        color: colors.bg,
                        child: Center(
                          child: Text(
                            '(the menu)',
                            style: MadarType.h2.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  onDidRemovePage: (_) {},
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required _Fake bridge,
  bool dark = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _ipad;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? MadarTheme.dark() : MadarTheme.light(),
          locale: Locale(bridge.rtl ? 'ar' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Directionality(
            textDirection: bridge.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: _FastBody(
              backLabel: coreWord('sell.back_to_menu', arabic: bridge.rtl),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A context under the panel host, as the Sell screen's sheet context is.
BuildContext _hostContext(WidgetTester tester) =>
    tester.element(find.byKey(const ValueKey('fast-body')));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    return await image.toByteData(format: ui.ImageByteFormat.png);
  });
  final dir = Directory('build/render')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('../../design_system/assets/fonts/$family-$cut.ttf');
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

final Finder _page = find.byKey(const ValueKey('done-page'));
final Finder _menu = find.text('(the menu)');

Finder _inPage(Finder f) => find.descendant(of: _page, matching: f);

/// The page's headline, as read: "Sale #1043", "Queued · #8f2a4c1e".
String _headline(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('done-headline')))
    .textSpan!
    .toPlainText();

Finder _money(int minor) =>
    _inPage(find.byWidgetPredicate((w) => w is MoneyText && w.minor == minor));

void main() {
  setUpAll(_loadFonts);

  for (final ar in [false, true]) {
    final lang = ar ? 'ar' : 'en';
    String w(String key) => coreWord(key, arabic: ar);

    group('Fast mode Done page ($lang)', () {
      testWidgets('a counter sale fills the panel as a page; New sale '
          'returns to the menu', (tester) async {
        final bridge = _Fake(rtl: ar);
        await _mount(tester, bridge: bridge);
        final panel = tester.getRect(find.byKey(_panelNav));
        final pending = showDonePage(_hostContext(tester), _counter());
        await _settle(tester);

        // A page of the panel, not a card over the window.
        expect(_page, findsOneWidget);
        expect(find.byType(DoneCard), findsNothing);
        expect(
          ModalRoute.of(tester.element(_page)),
          isA<MadarPanelRoute<DoneCardResult>>(),
        );
        final page = tester.getRect(_page);
        expect(page.left, closeTo(panel.left, 1));
        expect(page.right, closeTo(panel.right, 1));
        expect(page.bottom, closeTo(panel.bottom, 1));
        expect(_menu, findsNothing, reason: 'the page replaces the menu');
        // "Back to menu", as over every page the panel shows.
        expect(find.text(w('sell.back_to_menu')), findsOneWidget);

        // The status, the amount, the tender, the change.
        expect(_headline(tester), startsWith('${w('charge.sale')} '));
        expect(_inPage(find.text('#1043')), findsOneWidget);
        expect(_money(15390), findsOneWidget);
        expect(_inPage(find.textContaining('Cash')), findsWidgets);
        expect(_money(4610), findsOneWidget);
        // Printed, in green.
        final printed = _inPage(find.text(w('charge.printed')));
        expect(printed, findsOneWidget);
        final colors = tester.element(_page).madarColors;
        expect(tester.widget<Text>(printed).style?.color, colors.success);
        // The actions.
        expect(_inPage(find.text(w('loyalty.add_points'))), findsOneWidget);
        expect(_inPage(find.text(w('charge.reprint'))), findsOneWidget);
        // A counter sale: New sale, and no table question.
        expect(_inPage(find.text(w('charge.new_sale'))), findsOneWidget);
        expect(
          _inPage(find.textContaining(w('charge.cleared_q'))),
          findsNothing,
        );
        await _capture(tester, 'done-page-counter-ipad-$lang');

        await tester.tap(find.byKey(const ValueKey('done-new-sale')));
        await _settle(tester);
        expect(await pending, DoneCardResult.notYet);
        expect(_page, findsNothing);
        expect(_menu, findsOneWidget);
      });

      testWidgets('a table sale asks "T5 cleared?"; Cleared clears it and '
          'returns to the menu', (tester) async {
        final bridge = _Fake(rtl: ar);
        await _mount(tester, bridge: bridge);
        final pending = showDonePage(_hostContext(tester), _table());
        await _settle(tester);

        expect(_inPage(find.text('#1042')), findsOneWidget);
        expect(_money(17500), findsOneWidget);
        expect(_inPage(find.textContaining('T5')), findsWidgets);
        expect(
          _inPage(find.textContaining(w('charge.cleared_q'))),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('done-cleared')), findsOneWidget);
        expect(find.byKey(const ValueKey('done-not-yet')), findsOneWidget);
        expect(
          _inPage(find.text(w('charge.cleared'))),
          findsOneWidget,
          reason: 'Cleared says only that',
        );
        expect(_inPage(find.text(w('charge.not_yet'))), findsOneWidget);
        expect(
          find.byKey(const ValueKey('done-new-sale')),
          findsNothing,
          reason: 'the table question is the primary on a table sale',
        );
        // A table's question waits: it never steps aside by itself.
        await tester.pump(const Duration(seconds: 7));
        await _settle(tester);
        expect(_page, findsOneWidget);
        await _capture(tester, 'done-page-table-ipad-$lang');

        await tester.tap(find.byKey(const ValueKey('done-cleared')));
        await _settle(tester);
        expect(bridge.cleared, ['t5']);
        expect(await pending, DoneCardResult.cleared);
        expect(_page, findsNothing);
        expect(_menu, findsOneWidget);
      });

      testWidgets('Not yet leaves the table waiting and returns to the menu', (
        tester,
      ) async {
        final bridge = _Fake(rtl: ar);
        await _mount(tester, bridge: bridge);
        final pending = showDonePage(_hostContext(tester), _table());
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('done-not-yet')));
        await _settle(tester);
        expect(await pending, DoneCardResult.notYet);
        expect(bridge.cleared, isEmpty);
        expect(_menu, findsOneWidget);
      });

      testWidgets('dismissing it (Back to menu) means not yet', (tester) async {
        final bridge = _Fake(rtl: ar);
        await _mount(tester, bridge: bridge);
        final pending = showDonePage(_hostContext(tester), _table());
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('panel-back')));
        await _settle(tester);
        expect(await pending, DoneCardResult.notYet);
        expect(bridge.cleared, isEmpty);
        expect(_menu, findsOneWidget);
      });

      testWidgets('queued offline: "Queued · #ref", will send when back '
          'online', (tester) async {
        final bridge = _Fake(rtl: ar);
        await _mount(tester, bridge: bridge);
        unawaited(showDonePage(_hostContext(tester), _queued()));
        await _settle(tester);
        expect(_inPage(find.textContaining(w('sync.queued'))), findsWidgets);
        expect(_inPage(find.text('#8f2a4c1e')), findsOneWidget);
        // The headline says Queued, never "Sale #".
        expect(_headline(tester), startsWith('${w('sync.queued')} · '));
        expect(_money(17500), findsOneWidget);
        expect(_money(2500), findsOneWidget);
        expect(
          _inPage(find.textContaining(w('charge.will_send'))),
          findsOneWidget,
        );
        expect(_inPage(find.text(w('charge.printed'))), findsNothing);
        await _capture(tester, 'done-page-queued-ipad-$lang');
      });

      testWidgets('Printed shows, in green, only once the print job answers', (
        tester,
      ) async {
        final bridge = _Fake(rtl: ar);
        await _mount(tester, bridge: bridge);
        final job = Completer<PrintState>();
        unawaited(
          showDonePage(
            _hostContext(tester),
            _counter().withPrintJob(job.future),
          ),
        );
        await _settle(tester);
        final printed = _inPage(find.text(w('charge.printed')));
        expect(printed, findsNothing);
        expect(_inPage(find.text(w('receipt.printing'))), findsOneWidget);
        job.complete(PrintState.printed);
        await _settle(tester);
        expect(printed, findsOneWidget);
        final colors = tester.element(_page).madarColors;
        expect(tester.widget<Text>(printed).style?.color, colors.success);
      });

      testWidgets('Add points opens over the page, and closes back to it', (
        tester,
      ) async {
        final bridge = _Fake(rtl: ar);
        await _mount(tester, bridge: bridge);
        unawaited(showDonePage(_hostContext(tester), _table()));
        await _settle(tester);
        await tester.tap(_inPage(find.text(w('loyalty.add_points'))));
        await _settle(tester);
        expect(find.byType(LoyaltyAwardSheet), findsOneWidget);
        MadarSheet.close<void>(tester.element(find.byType(LoyaltyAwardSheet)));
        await _settle(tester);
        expect(find.byType(LoyaltyAwardSheet), findsNothing);
        expect(_page, findsOneWidget, reason: 'the page stays');
      });
    });
  }

  testWidgets('a counter sale steps back to the menu by itself, as the card '
      'does', (tester) async {
    await _mount(tester, bridge: _Fake());
    final pending = showDonePage(_hostContext(tester), _counter());
    await _settle(tester);
    expect(_page, findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await _settle(tester);
    expect(await pending, DoneCardResult.notYet);
    expect(_menu, findsOneWidget);
  });

  testWidgets('no printer: the page waits, as the card does', (tester) async {
    await _mount(tester, bridge: _Fake());
    unawaited(
      showDonePage(_hostContext(tester), _counter(print: PrintState.noPrinter)),
    );
    await _settle(tester);
    await tester.pump(const Duration(seconds: 7));
    await _settle(tester);
    expect(_page, findsOneWidget);
    expect(_inPage(find.text(coreWord('charge.not_printed'))), findsOneWidget);
  });

  testWidgets('dark: the table page lays out', (tester) async {
    await _mount(tester, bridge: _Fake(), dark: true);
    unawaited(showDonePage(_hostContext(tester), _table()));
    await _settle(tester);
    await _capture(tester, 'done-page-table-ipad-en-dark');
  });

  testWidgets('without a panel host it is the Done card', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _ipad;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(_Fake())],
        child: MaterialApp(
          theme: MadarTheme.light(),
          home: const Scaffold(body: SizedBox.expand(key: ValueKey('plain'))),
        ),
      ),
    );
    unawaited(
      showDonePage(
        tester.element(find.byKey(const ValueKey('plain'))),
        _table(),
      ),
    );
    await _settle(tester);
    expect(find.byType(DoneCard), findsOneWidget);
    expect(_page, findsNothing);
  });
}
