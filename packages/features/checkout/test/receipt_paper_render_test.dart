// Renders the on-screen receipt paper to PNG (`MADAR_RENDER=true` writes
// `build/render/receipt-*.png`): simple cash, a card+cash split with change,
// service charge + tax + discount + tip, and a voided sale — phone and iPad,
// English and Arabic. Without the flag it still lays each one out and pins
// the lines a customer's money depends on.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/receipt_paper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

class _Bridge implements MadarBridge {
  _Bridge({required this.rtl, this.stub = true, this.getMadar = true});
  final bool rtl;

  /// Settings › Printer's "Powered by madar" stub, and its sub-toggle for the
  /// tagline and QR under it.
  bool stub;
  bool getMadar;

  /// The plan the core answers. On Free the core's device view reads the
  /// footer on whatever the device chose.
  String plan = 'paid';

  @override
  dynamic noSuchMethod(Invocation i) {
    final can = fakeCanInvocation(i, () => currentSession()?.role);
    if (can != null) return can;
    if (i.memberName == #tr) {
      return coreWord(i.namedArguments[#key] as String, arabic: rtl);
    }
    if (i.memberName == #formatTime) return '10 Sep 2026 · 19:45';
    if (i.memberName == #receiptFooter) return 'Thank you!';
    if (i.memberName == #isRtl) return rtl;
    if (i.memberName == #locale) return rtl ? 'ar' : 'en';
    if (i.memberName == #deviceConfig) {
      final free = plan == 'free';
      return DeviceConfigView(
        reconfiguring: false,
        configured: true,
        receiptStub: stub || free,
        receiptGetMadar: getMadar || free,
        receiptFooterLocked: free,
      );
    }
    if (i.memberName == #entitlements) {
      return EntitlementsView(
        plan: plan,
        features: const [],
        realtime: plan == 'paid',
        tillInactive: false,
      );
    }
    return null;
  }
}

const _lines = [
  ReceiptLineView(
    dealMinor: 0,
    kind: 'item',
    parts: [],
    unitPriceMinor: 0,
    name: 'Latte',
    qty: 2,
    sizeLabel: 'L',
    lineTotalMinor: 9000,
    staffCompMinor: 0,
    addons: [ReceiptModifierView(name: 'Oat milk', priceMinor: 1000)],
    optionals: [],
  ),
  ReceiptLineView(
    dealMinor: 0,
    kind: 'item',
    parts: [],
    unitPriceMinor: 0,
    name: 'Croissant',
    qty: 1,
    lineTotalMinor: 6500,
    staffCompMinor: 0,
    addons: [],
    optionals: [],
  ),
];

/// A staff drink (Large latte + a shot): normal price 11000, the pool comps
/// 6500, the rest is charged. The label is the core's word, in the language.
List<ReceiptLineView> _staffLines({required bool arabic}) => [
  ReceiptLineView(
    dealMinor: 0,
    kind: 'item',
    parts: const [],
    unitPriceMinor: 0,
    name: 'Latte',
    qty: 1,
    sizeLabel: 'L',
    lineTotalMinor: 11000,
    staffLabel: coreWord('staff_pool.badge', arabic: arabic),
    staffCompMinor: 6500,
    addons: const [ReceiptModifierView(name: 'Extra shot', priceMinor: 1500)],
    optionals: const [],
  ),
];

/// A combo (C12) and a line in a deal: `1× Lunch deal … 150.00` with its
/// items indented (the Large latte's +10.00, its oat milk under it), and the
/// deal under the subtotal, which reads the lines at their normal prices.
const _comboLines = [
  ReceiptLineView(
    kind: 'combo',
    name: 'Lunch deal',
    qty: 1,
    unitPriceMinor: 15000,
    lineTotalMinor: 17500,
    staffCompMinor: 0,
    dealMinor: 0,
    addons: [],
    optionals: [],
    parts: [
      ReceiptPartView(
        name: 'Burger',
        qty: 1,
        surchargeMinor: 0,
        addons: [],
        optionals: [],
      ),
      ReceiptPartView(
        name: 'Fries',
        qty: 1,
        surchargeMinor: 0,
        addons: [],
        optionals: [],
      ),
      ReceiptPartView(
        name: 'Latte',
        qty: 1,
        sizeLabel: 'Large',
        surchargeMinor: 1000,
        addons: [ReceiptModifierView(name: 'Oat milk', priceMinor: 1500)],
        optionals: [],
      ),
    ],
  ),
  ReceiptLineView(
    kind: 'item',
    name: 'Croissant',
    qty: 2,
    unitPriceMinor: 5500,
    lineTotalMinor: 11000,
    staffCompMinor: 0,
    dealMinor: 2000,
    addons: [],
    optionals: [],
    parts: [],
  ),
];

// A line with its own note, under an order with one.
const _notedLines = [
  ReceiptLineView(
    dealMinor: 0,
    kind: 'item',
    parts: [],
    unitPriceMinor: 0,
    name: 'Latte',
    qty: 1,
    lineTotalMinor: 15500,
    staffCompMinor: 0,
    addons: [],
    optionals: [],
    note: 'no sugar',
  ),
];

ReceiptView _r({
  List<ReceiptLineView>? lines,
  String? note,
  List<ReceiptDealView> deals = const [],
  List<ReceiptPaymentView> payments = const [],
  String label = 'Cash',
  bool cash = true,
  bool voided = false,
  int subtotal = 15500,
  int discount = 0,
  int service = 0,
  int tax = 0,
  int total = 15500,
  int tip = 0,
  int tendered = 20000,
  int change = 4500,
  String display = '',
  String? orderRef,
  bool inclusive = false,
  int waived = 0,
  String? waivedBy,
  double rate = 0.14,
}) => ReceiptView(
  deals: deals,
  payments: payments,
  localOrderId: '8f2a4c1e-x',
  orderNumber: 1042,
  isVoided: voided,
  lines: lines ?? _lines,
  paymentLabel: label,
  subtotalMinor: subtotal,
  discountMinor: discount,
  taxMinor: tax,
  serviceChargeMinor: service,
  deliveryFeeMinor: 0,
  totalMinor: total,
  tipMinor: tip,
  amountTenderedMinor: tendered,
  changeMinor: change,
  isCash: cash,
  isDelivery: false,
  tellerName: 'Sara',
  queuedOffline: false,
  createdAt: '2026-09-10T19:45:00Z',
  displayNumber: display,
  orderRef: orderRef,
  serviceChargeWaivedMinor: waived,
  serviceChargeWaivedByName: waivedBy,
  taxInclusive: inclusive,
  taxRate: rate,
  note: note,
);

final _cases = <String, ReceiptView>{
  'cash': _r(),
  'split': _r(
    payments: const [
      ReceiptPaymentView(label: 'Card', amountMinor: 10000),
      ReceiptPaymentView(label: 'Cash', amountMinor: 5500),
    ],
    label: 'Split',
    cash: false,
    tendered: 6000,
    change: 500,
  ),
  'charges': _r(
    label: 'Card',
    cash: false,
    discount: 1550,
    service: 1395,
    tax: 2148,
    total: 17493,
    tip: 1000,
    tendered: 0,
    change: 0,
  ),
  // An inclusive shop's table bill whose service charge a manager removed:
  // VAT stated as included, the note, and who took the charge off.
  'inclusive-waived': _r(
    discount: 1550,
    tax: 1712,
    total: 13950,
    tendered: 15000,
    change: 1050,
    inclusive: true,
    waived: 1395,
    waivedBy: 'Mona',
  ),
  'void': _r(voided: true),
  // Notes were on the kitchen chit only: the line's under it, the order's
  // once under the items.
  'notes': _r(lines: _notedLines, note: 'Birthday, cake last'),
  // Two devices shared a code offline: the server's ~suffix stays on.
  'device': _r(display: '36B-12~AB12'),
  // The order's reference, under the time: one colon (the word has it).
  'ref': _r(orderRef: 'ARKAN-260926-E38-0001'),
  // A staff drink: see [_staffLines]. (Rebuilt per language in the loop.)
  'staff': _r(subtotal: 4500, total: 4500, tendered: 5000, change: 500),
  'combo': _r(
    lines: _comboLines,
    deals: const [ReceiptDealView(name: 'Two bites', discountMinor: 2000)],
    subtotal: 26500,
    total: 26500,
    tendered: 30000,
    change: 3500,
  ),
};

Future<void> _fonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final f = File('../../design_system/assets/fonts/$family-$cut.ttf');
      loader.addFont(f.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_fonts);

  for (final MapEntry(key: name, value: receipt) in _cases.entries) {
    for (final (device, size) in [
      ('phone', const Size(390, 844)),
      ('tablet', const Size(1194, 834)),
    ]) {
      for (final rtl in [false, true]) {
        final tag = 'receipt-$name-$device-${rtl ? 'ar' : 'en'}';
        testWidgets(tag, (tester) async {
          tester.view
            ..devicePixelRatio = 1
            ..physicalSize = size;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('shot'),
              child: DefaultAssetBundle(
                bundle: _PackageAssets(),
                child: ProviderScope(
                  overrides: [
                    bridgeProvider.overrideWithValue(_Bridge(rtl: rtl)),
                  ],
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: MadarTheme.light(),
                    home: Directionality(
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Scaffold(
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(Space.lg),
                          child: Center(
                            child: ReceiptPaper(
                              receipt: name == 'staff'
                                  ? _r(
                                      lines: _staffLines(arabic: rtl),
                                      subtotal: 4500,
                                      total: 4500,
                                      tendered: 5000,
                                      change: 500,
                                    )
                                  : receipt,
                              storeName: 'Rue Zamalek',
                              currency: 'EGP',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          String w(String k) => coreWord(k, arabic: rtl);
          final change = find.text(w('order.change'));
          switch (name) {
            case 'cash':
              expect(find.text(w('receipt.cash')), findsOneWidget);
              expect(change, findsOneWidget);
            case 'split':
              expect(find.text('Card'), findsOneWidget);
              expect(change, findsOneWidget);
            case 'charges':
              for (final k in [
                'order.discount',
                'order.service_charge',
                'order.tip',
              ]) {
                expect(find.text(w(k)), findsOneWidget, reason: k);
              }
              // The VAT line reads "VAT (14%)" now, exclusive or inclusive.
              expect(find.text('${w('receipt.vat')} (14%)'), findsOneWidget);
              expect(change, findsNothing);
            case 'inclusive-waived':
              expect(find.text('${w('receipt.vat')} (14%)'), findsOneWidget);
              expect(
                find.text('${w('receipt.prices_include_vat')} (14%)'),
                findsOneWidget,
              );
              expect(find.text(w('receipt.service_waived')), findsOneWidget);
              expect(find.text('Mona'), findsOneWidget);
              expect(find.text(w('order.service_charge')), findsNothing);
            case 'void':
              expect(find.textContaining(w('receipt.voided')), findsOneWidget);
            case 'notes':
              expect(
                find.text('  ${w('receipt.notes')} no sugar'),
                findsOneWidget,
              );
              expect(
                find.text('${w('receipt.notes')} Birthday, cake last'),
                findsOneWidget,
              );
            case 'combo':
              // The combo at n×P, its items indented, the extra and the
              // add-on each on their own row.
              expect(find.text('1× Lunch deal'), findsOneWidget);
              expect(find.text('EGP 150.00'), findsOneWidget);
              expect(find.text('  1× Burger'), findsOneWidget);
              expect(find.text('  1× Latte (Large)'), findsOneWidget);
              expect(find.text('+EGP 10.00'), findsOneWidget);
              expect(find.text('    + Oat milk'), findsOneWidget);
              expect(find.text('+EGP 15.00'), findsOneWidget);
              // The subtotal at normal prices, then the deal off it.
              expect(find.text('EGP 285.00'), findsOneWidget);
              expect(find.text('Two bites'), findsOneWidget);
              expect(find.text('−EGP 20.00'), findsOneWidget);
            case 'staff':
              // The line at its NORMAL price, then the comp as a line
              // discount under it — one row, the core's word and figure.
              final row = find.byKey(const ValueKey('receipt-staff-comp'));
              expect(row, findsOneWidget);
              expect(
                find.descendant(
                  of: row,
                  matching: find.textContaining(w('staff_pool.badge')),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: row,
                  matching: find.textContaining('65.00'),
                ),
                findsOneWidget,
              );
            case 'device':
              expect(find.textContaining('#36B-12~AB12'), findsOneWidget);
              expect(find.textContaining('#1042'), findsNothing);
            case 'ref':
              expect(
                find.text('${w('receipt.ref')} ARKAN-260926-E38-0001'),
                findsOneWidget,
              );
              expect(find.textContaining('::'), findsNothing);
          }
          if (!_render) return;
          await _precacheChit(tester);
          final b =
              tester.renderObject(find.byKey(const ValueKey('shot')))
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final img = await b.toImage(pixelRatio: 2);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory('build/render')..createSync(recursive: true);
            File(
              '${dir.path}/$tag.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        });
      }
    }
  }

  // Settings › Printer's "Powered by madar" stub: on by default, and the
  // preview drops it when the device stops printing it. Its sub-toggle drops
  // only the tagline, QR and address under it.
  for (final (stub, getMadar) in const [
    (true, true),
    (true, false),
    (false, true),
  ]) {
    testWidgets('the stub and its footer follow the settings '
        '(stub=$stub, getMadar=$getMadar)', (tester) async {
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _PackageAssets(),
          child: ProviderScope(
            overrides: [
              bridgeProvider.overrideWithValue(
                _Bridge(rtl: false, stub: stub, getMadar: getMadar),
              ),
            ],
            child: MaterialApp(
              theme: MadarTheme.light(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ReceiptPaper(
                    receipt: _cases['cash']!,
                    storeName: 'Rue Zamalek',
                    currency: 'EGP',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      if (stub) await _precacheChit(tester);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.semanticLabel == '${coreWord('receipt.powered_by')} madar',
        ),
        stub ? findsOneWidget : findsNothing,
      );
      // The footer under it needs the stub AND its own sub-toggle.
      for (final line in const [
        'One system for the whole café',
        'سيستم واحد للمكان كله',
        'get.madar-pos.cloud/en',
      ]) {
        expect(
          find.text(line),
          stub && getMadar ? findsOneWidget : findsNothing,
          reason: line,
        );
      }
    });
  }

  // The preview follows the plan the moment it changes: a Paid device with
  // the footer off shows none, a downgrade to Free shows it all, and the
  // upgrade back gives the device's own choice again.
  testWidgets('the footer follows the plan as it changes', (tester) async {
    final bridge = _Bridge(rtl: false, stub: false, getMadar: false);
    final container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _PackageAssets(),
        child: UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: MadarTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReceiptPaper(
                  receipt: _cases['cash']!,
                  storeName: 'Rue Zamalek',
                  currency: 'EGP',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    const url = 'get.madar-pos.cloud/en';
    expect(find.text(url), findsNothing);
    bridge.plan = 'free';
    container.read(syncTickProvider.notifier).bump();
    await tester.pump();
    expect(find.text(url), findsOneWidget, reason: 'Free prints the footer');
    bridge.plan = 'paid';
    container.read(syncTickProvider.notifier).bump();
    await tester.pump();
    expect(find.text(url), findsNothing, reason: "the device's choice is back");
  });
}

/// The app bundles the chit as `packages/feature_checkout/assets/…`; this
/// package's own tests bundle it at the root. Map the one to the other.
class _PackageAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      rootBundle.load(key.replaceFirst('packages/feature_checkout/', ''));
}

/// Loads the chit PNG (failing the test if it doesn't decode) and repaints,
/// so a shot shows it.
Future<void> _precacheChit(WidgetTester tester) async {
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/receipt-chit.png', package: 'feature_checkout'),
      tester.element(find.byType(ReceiptPaper)),
      onError: (e, _) => fail('the chit PNG did not load: $e'),
    ),
  );
  await tester.pump();
}
