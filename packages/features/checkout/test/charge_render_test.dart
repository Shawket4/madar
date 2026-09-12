// Renders Charge and the Done card to PNG so they can be LOOKED at.
//
// Charge is the drawer every sale ends in, and it is judged on how it looks
// with a customer waiting. There is no simulator here, so this paints it:
// `MADAR_RENDER=true` writes `build/render/charge-*.png` — the bill on an
// iPad with a member attached, the cart in split mode, the bill on a phone in
// Arabic (mirrored), an online order, the shift-less bar, and the Done card
// in both its variants. Without the flag it still builds every board and
// fails on any layout exception, which is what CI needs from it.
//
// The strings in here are fixture text; the app's own words come through
// `bridge.tr`, and the fake below answers with real words so the picture
// shows what a person would read.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

/// The iPad, landscape — the primary target.
const Size _ipad = Size(1194, 834);

/// A phone — the real fallback.
const Size _phone = Size(390, 844);

// ── Fixtures ───────────────────────────────────────────────────────────

const _methods = [
  PaymentMethodView(
    id: 'cash',
    name: 'Cash',
    isCash: true,
    icon: 'cash',
    color: '#178A4C',
  ),
  PaymentMethodView(
    id: 'card',
    name: 'Card',
    isCash: false,
    icon: 'card',
    color: '#0F7A8A',
  ),
  PaymentMethodView(
    id: 'wallet',
    name: 'Wallet',
    isCash: false,
    icon: 'wallet',
    color: '#BF5F07',
  ),
];

const _discounts = [
  DiscountView(
    id: 'staff',
    name: 'Staff',
    dtype: 'percentage',
    value: 0.10,
    isActive: true,
  ),
  DiscountView(
    id: 'friday',
    name: 'Friday 20',
    dtype: 'fixed',
    value: 2000,
    isActive: true,
  ),
];

TicketLineView _line(
  String id,
  String item,
  String name,
  int qty,
  int minor,
  int round,
) => TicketLineView(
  id: id,
  menuItemId: item,
  name: name,
  qty: qty,
  modifiers: const [],
  lineTotalMinor: minor,
  voided: false,
  roundNumber: round,
  roundFiredAt: '2026-09-10T19:02:00Z',
);

final _ticket = TicketView(
  id: 'tk-412',
  ticketRef: 'T-0412',
  tableId: 't5',
  status: 'ready',
  customerName: 'Omar',
  waiterName: 'Sara',
  guestCount: 4,
  subtotalMinor: 17500,
  openedAt: '2026-09-10T18:30:00Z',
  queuedOffline: false,
  lines: [
    _line('l1', 'latte', 'Latte', 2, 9000, 1),
    _line('l2', 'espresso', 'Espresso', 1, 3500, 2),
    _line('l3', 'flat', 'Flat white', 1, 5000, 2),
  ],
);

const _member = LoyaltyMemberView(
  id: 'm-omar',
  name: 'Omar Adel',
  phone: '0100 555 1234',
  mode: 'points',
  balance: 240,
  nextRewardCost: 200,
  rewardsReady: 1,
  progressToNext: 40,
  pointsToNextReward: 160,
  canRedeem: true,
  progressLabel: '240 / 200',
  balanceLabel: 'pts',
);

const _scan = LoyaltyScanView(
  member: _member,
  rewards: [
    LoyaltyRewardView(
      menuItemId: 'latte',
      name: 'Latte',
      priceMinor: 4500,
      costCurrency: 'points',
      costAmount: 200,
      costLabel: '200 pts',
    ),
  ],
  recent: [],
  anyItem: false,
  anyItemCost: 0,
);

const _online = DeliveryOrderView(
  id: 'd-118',
  orderRef: '#D-118',
  channel: 'outside',
  status: 'ready',
  customerName: 'Nour Hassan',
  customerPhone: '0122 333 4455',
  address: '12 Brazil St, Zamalek',
  subtotalMinor: 15000,
  discountMinor: 0,
  deliveryFeeMinor: 2500,
  totalMinor: 17500,
  itemCount: 3,
  lines: [],
  createdAt: '2026-09-10T19:40:00Z',
  isTerminal: false,
);

ReceiptView _receipt({required bool queued, int? number}) => ReceiptView(
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
);

const _session = SessionSnapshot(
  userId: 'u1',
  displayName: 'Sara',
  role: 'teller',
  currencyCode: 'EGP',
  taxRate: 0.14,
  taxInclusive: true,
  serviceChargeRate: 0,
  serviceChargeTaxable: false,
  requireTableForOrders: true,
  online: true,
  permissionsLoaded: true,
);

class _FakeBridge implements MadarBridge {
  _FakeBridge({
    this.rtl = false,
    this.shiftOpen = true,
    this.loyaltyEnabled = true,
  });

  /// The branch runs a loyalty programme. Off, every loyalty control leaves
  /// the tender screen.
  final bool loyaltyEnabled;

  final bool rtl;
  final bool shiftOpen;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      final words = rtl ? _ar : _en;
      return words[key] ?? key;
    }
    if (name == #isRtl) return rtl;
    if (name == #locale) return rtl ? 'ar' : 'en';
    if (name == #currentSession) return _session;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #deviceConfig) {
      return const DeviceConfigView(
        branchName: 'Rue Zamalek',
        tillId: 'till-1',
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #orgLogoLocalPath) return null;
    if (name == #listPaymentMethods) {
      return Future<List<PaymentMethodView>>.value(_methods);
    }
    if (name == #listDiscounts) {
      return Future<List<DiscountView>>.value(_discounts);
    }
    if (name == #loyaltySettings) {
      return Future<LoyaltyProgrammeView>.value(
        LoyaltyProgrammeView(
          enabled: loyaltyEnabled,
          mode: 'points',
          programName: rtl ? 'مكافآت رو' : 'Rue Rewards',
          balanceLabel: 'points',
        ),
      );
    }
    if (name == #cartDiscountId) return Future<String?>.value();
    if (name == #cartTotals) {
      return Future<CartTotals>.value(
        const CartTotals(
          itemCount: 4,
          subtotalMinor: 17500,
          discountMinor: 0,
          taxMinor: 2407,
          serviceChargeMinor: 0,
          totalMinor: 17500,
        ),
      );
    }
    if (name == #cartLines) {
      return Future<List<CartLineView>>.value(const []);
    }
    if (name == #currentShift) {
      return Future<ShiftView?>.value(
        shiftOpen
            ? const ShiftView(
                id: 'sh-1',
                branchId: 'b1',
                tellerId: 'u1',
                tellerName: 'Sara',
                openingCashMinor: 50000,
                openedAt: '2026-09-10T09:00:00Z',
                status: 'open',
                isOpen: true,
              )
            : null,
      );
    }
    if (name == #loyaltyLookup) return Future<LoyaltyScanView>.value(_scan);
    if (name == #loyaltyAwardWindowOpen) return true;
    if (name == #clearTable) return Future<void>.value();
    return null;
  }
}

// Real words, so the picture shows what a person would read. Only the keys
// the Charge surfaces ask the core for; the feature's own new keys come
// from its fallback table, which is what ships until the core has them.
const _en = {
  'order.total': 'Total',
  'order.subtotal': 'Subtotal',
  'order.discount': 'Discount',
  'order.no_discount': 'No discount',
  'order.tax': 'Tax',
  'order.service_charge': 'Service',
  'order.tip': 'Tip',
  'order.exact': 'Exact',
  'order.change': 'Change',
  'order.short_by': 'Short by',
  'order.cash_received': 'Cash received',
  'order.split_payment': 'Split',
  'order.split_remaining': 'Remaining',
  'loyalty.scan_card': 'Scan card',
  'loyalty.remove': 'Remove',
  'loyalty.left': 'left',
  'loyalty.nothing_claimable': 'Nothing here can be claimed yet',
  'loyalty.add_points': 'Add points',
  'waiter.need_shift': 'Open a shift to settle',
  'receipt.delivery_fee': 'Delivery fee',
  'receipt.print_failed': "Couldn't reach the printer",
  'receipt.printing': 'Printing…',
  'sync.queued': 'Queued',
  'common.cancel': 'Cancel',
  'delivery.outside': 'Outside',
};

const _ar = {
  'order.total': 'الإجمالي',
  'order.subtotal': 'المجموع الفرعي',
  'order.discount': 'خصم',
  'order.no_discount': 'بدون خصم',
  'order.tax': 'الضريبة',
  'order.service_charge': 'الخدمة',
  'order.tip': 'البقشيش',
  'order.exact': 'بالضبط',
  'order.change': 'الباقي',
  'order.short_by': 'ناقص',
  'order.cash_received': 'النقد المستلم',
  'order.split_payment': 'تقسيم',
  'order.split_remaining': 'المتبقي',
  'loyalty.scan_card': 'مسح البطاقة',
  'loyalty.remove': 'إزالة',
  'loyalty.left': 'متبقٍ',
  'loyalty.nothing_claimable': 'لا يوجد ما يمكن استبداله هنا بعد',
  'loyalty.add_points': 'إضافة نقاط',
  'waiter.need_shift': 'افتح وردية للتسوية',
  'receipt.delivery_fee': 'رسوم التوصيل',
  'receipt.print_failed': 'تعذّر الوصول إلى الطابعة',
  'receipt.printing': 'جارٍ الطباعة…',
  'sync.queued': 'في الانتظار',
  'common.cancel': 'إلغاء',
  'delivery.outside': 'خارجي',
};

// ── Harness ────────────────────────────────────────────────────────────

/// A stand-in for the Floor behind the drawer, so the scrim and the Done
/// card have something to sit over.
class _Host extends StatelessWidget {
  const _Host({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.lg,
          children: [
            Text(
              title,
              style: MadarType.h1.copyWith(color: colors.textPrimary),
            ),
            Expanded(
              child: MadarCard(
                child: Center(
                  child: Text(
                    '(the floor)',
                    style: MadarType.body.copyWith(color: colors.textMuted),
                  ),
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
  required Size size,
  required MadarBridge bridge,
  ThemeData? theme,
  bool rtl = false,
  String hostTitle = 'Floor',
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
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
          theme: theme ?? MadarTheme.light(),
          // Wrapping the Navigator, not `home`: pushed routes must mirror too.
          builder: (context, child) => Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
          home: _Host(title: hostTitle),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Let the session start, the modal animate in, and the state settle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(MotionSpec.standardDuration);
  await tester.pump(MotionSpec.gentleDuration);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Writes the current frame to `build/render/<name>.png` when rendering.
Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');
  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  // `toImage` completes on the real event loop; inside the binding's fake
  // async zone a later `pump` can wedge behind it. `runAsync` is the door.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/render')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// The sheet's own session, reachable while the sheet is up.
CheckoutNotifier _session0(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ChargeSheet)),
).read(checkoutProvider.notifier);

/// Loads the design system's Plex faces so the boards render real type.
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

ChargeOutcome _saleOutcome() => ChargeOutcome(
  target: ChargeTarget.bill(_ticket, tableLabel: 'T5'),
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
  printState: PrintState.printed,
);

ChargeOutcome _queuedOutcome() => ChargeOutcome(
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
  printState: PrintState.noPrinter,
);

void main() {
  setUpAll(_loadFonts);

  testWidgets(
    'a bill on an iPad: member attached, a reward ticked, 200 given',
    (tester) async {
      await _mount(tester, size: _ipad, bridge: _FakeBridge());
      final host = tester.element(find.byType(_Host));
      final pending = showCharge(
        host,
        ChargeTarget.bill(_ticket, tableLabel: 'T5'),
        presentDoneCard: false,
      );
      await _settle(tester);
      expect(find.text('Cash'), findsOneWidget);
      // The card comes out, one latte goes on it, and two hundred is handed
      // over: the drawer the design draws.
      final session = _session0(tester);
      await session.scanLoyalty(token: 'tok');
      await _settle(tester);
      session.toggleReward(0);
      await tester.tap(find.text('200'));
      await _settle(tester);
      expect(find.text('Omar Adel · 240 pts'), findsOneWidget);
      await _capture(tester, 'charge-bill-tablet');
      // Close it so the future resolves without a charge.
      Navigator.of(tester.element(find.byType(ChargeSheet))).pop();
      await _settle(tester);
      expect(await pending, isNull);
    },
  );

  testWidgets('a shop with no programme is offered no card to scan', (
    tester,
  ) async {
    await _mount(
      tester,
      size: _ipad,
      bridge: _FakeBridge(loyaltyEnabled: false),
    );
    final host = tester.element(find.byType(_Host));
    final pending = showCharge(
      host,
      ChargeTarget.bill(_ticket, tableLabel: 'T5'),
      presentDoneCard: false,
    );
    await _settle(tester);
    // The tender screen is otherwise whole — this is a missing feature, not
    // a broken screen.
    expect(find.text('Cash'), findsOneWidget);
    // Nothing loyalty anywhere on it: not the drawer's Scan card button, not
    // the quiet row that names the programme.
    expect(find.text('Scan card'), findsNothing);
    expect(find.text('Rue Rewards'), findsNothing);
    Navigator.of(tester.element(find.byType(ChargeSheet))).pop();
    await _settle(tester);
    expect(await pending, isNull);
  });

  testWidgets('the programme names its own row', (tester) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge());
    final host = tester.element(find.byType(_Host));
    final pending = showCharge(
      host,
      ChargeTarget.bill(_ticket, tableLabel: 'T5'),
      presentDoneCard: false,
    );
    await _settle(tester);
    // "Rue Rewards", not the generic "Member" — the shop named it.
    expect(find.text('Rue Rewards'), findsOneWidget);
    Navigator.of(tester.element(find.byType(ChargeSheet))).pop();
    await _settle(tester);
    expect(await pending, isNull);
  });

  testWidgets('a bill on an iPad, in the dark', (tester) async {
    await _mount(
      tester,
      size: _ipad,
      bridge: _FakeBridge(),
      theme: MadarTheme.dark(),
    );
    final host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(
        host,
        ChargeTarget.bill(_ticket, tableLabel: 'T5'),
        presentDoneCard: false,
      ),
    );
    await _settle(tester);
    await _capture(tester, 'charge-bill-tablet-dark');
  });

  testWidgets('a cart on an iPad in split mode', (tester) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge(), hostTitle: 'Sell');
    final host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(host, const ChargeTarget.cart(), presentDoneCard: false),
    );
    await _settle(tester);
    await tester.tap(find.text('Split'));
    await _settle(tester);
    _session0(tester)
      ..setSplitAmount('cash', 10000)
      ..setSplitAmount('card', 7500);
    await _settle(tester);
    expect(find.text('Remaining'), findsOneWidget);
    await _capture(tester, 'charge-cart-split-tablet');
  });

  testWidgets('a bill on a phone, in Arabic, mirrored', (tester) async {
    await _mount(
      tester,
      size: _phone,
      bridge: _FakeBridge(rtl: true),
      rtl: true,
      hostTitle: 'الصالة',
    );
    final host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(
        host,
        ChargeTarget.bill(_ticket, tableLabel: 'T5'),
        presentDoneCard: false,
      ),
    );
    await _settle(tester);
    await _session0(tester).scanLoyalty(token: 'tok');
    await _settle(tester);
    expect(find.text('بالضبط'), findsOneWidget);
    await _capture(tester, 'charge-bill-phone-ar');
  });

  testWidgets('an online order on an iPad: methods only, nothing picked', (
    tester,
  ) async {
    await _mount(
      tester,
      size: _ipad,
      bridge: _FakeBridge(),
      hostTitle: 'Queue',
    );
    final host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(
        host,
        const ChargeTarget.online(_online),
        presentDoneCard: false,
      ),
    );
    await _settle(tester);
    expect(find.text('Cash received'), findsNothing);
    expect(find.text('Add tip'), findsNothing);
    await _capture(tester, 'charge-online-tablet');
  });

  testWidgets('a cart on a phone with no shift open says so on the bar', (
    tester,
  ) async {
    await _mount(
      tester,
      size: _phone,
      bridge: _FakeBridge(shiftOpen: false),
      hostTitle: 'Sell',
    );
    final host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(host, const ChargeTarget.cart(), presentDoneCard: false),
    );
    await _settle(tester);
    expect(find.text('Open a shift to settle'), findsOneWidget);
    await _capture(tester, 'charge-cart-phone-noshift');
  });

  testWidgets('the Done card over the floor: the happy sale', (tester) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge());
    final host = tester.element(find.byType(_Host));
    final pending = showDoneCard(host, _saleOutcome());
    await _settle(tester);
    expect(find.text('Cleared'), findsOneWidget);
    await _capture(tester, 'done-card-sale-tablet');
    // A tap on the floor behind it dismisses it — and means "not yet".
    await tester.tapAt(const Offset(200, 700));
    await _settle(tester);
    expect(await pending, DoneCardResult.notYet);
    expect(find.byType(DoneCard), findsNothing);
  });

  testWidgets('the Done card: queued, offline, no printer, on a phone', (
    tester,
  ) async {
    await _mount(
      tester,
      size: _phone,
      bridge: _FakeBridge(),
      hostTitle: 'Sell',
    );
    final host = tester.element(find.byType(_Host));
    unawaited(showDoneCard(host, _queuedOutcome()));
    await _settle(tester);
    expect(find.textContaining('Queued'), findsOneWidget);
    expect(find.text('Cleared'), findsNothing);
    await _capture(tester, 'done-card-queued-phone');
  });

  testWidgets('the Done card: queued, on an iPad', (tester) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge(), hostTitle: 'Sell');
    final host = tester.element(find.byType(_Host));
    unawaited(showDoneCard(host, _queuedOutcome()));
    await _settle(tester);
    await _capture(tester, 'done-card-queued-tablet');
  });

  testWidgets('Cleared on the Done card clears the table and resolves', (
    tester,
  ) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge());
    final host = tester.element(find.byType(_Host));
    final pending = showDoneCard(host, _saleOutcome());
    await _settle(tester);
    await tester.tap(find.text('Cleared'));
    await _settle(tester);
    expect(await pending, DoneCardResult.cleared);
  });
}
