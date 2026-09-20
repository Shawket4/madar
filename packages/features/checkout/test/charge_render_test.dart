// Renders Charge and the Done card to PNG so they can be LOOKED at.
//
// Charge is the drawer every sale ends in, and it is judged on how it looks
// with a customer waiting. There is no simulator here, so this paints it:
// `MADAR_RENDER=true` writes `build/render/charge-*.png` — the bill on an
// iPad with a member attached, the cart in split mode, the bill on a phone in
// Arabic (mirrored), an online order, the till-less bar, and the Done card
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
import 'package:app_core/testing.dart';
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

// A shop with many methods, some with long or Arabic names, and one with a
// custom icon token the app has never seen — the exact shape the owner
// described as unrenderable. Used only by the overflow/flagging test below;
// every other test keeps the plain three-method fixture above.
const _manyMethods = [
  PaymentMethodView(
    id: 'cash',
    name: 'Cash',
    isCash: true,
    icon: 'cash',
    color: '#178A4C',
  ),
  PaymentMethodView(
    id: 'visa',
    name: 'Visa / Mastercard',
    isCash: false,
    icon: 'card',
    color: '#0F7A8A',
  ),
  PaymentMethodView(
    id: 'instapay',
    name: 'InstaPay',
    isCash: false,
    icon: 'instapay',
    color: '#6C2BD9',
  ),
  PaymentMethodView(
    id: 'vodafone',
    name: 'فودافون كاش',
    isCash: false,
    icon: 'vodafone',
    color: '#E4002B',
  ),
  PaymentMethodView(
    id: 'giftcard',
    name: 'Rue Zamalek Gift Card',
    isCash: false,
    icon: 'gift_card',
    color: '#B08900',
  ),
  PaymentMethodView(
    id: 'rue-pay',
    name: 'برنامج رو للدفع الخاص بالفرع',
    isCash: false,
    icon: 'rue_pay_v2', // a token this app has never seen
    color: '#2D6CDF',
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
  ready: true,
  customerName: 'Omar',
  waiterName: 'Sara',
  guestCount: 4,
  subtotalMinor: 17500,
  // Priced by the server, so the hero reads its Total.
  bill: const TicketBillView(
    subtotalMinor: 15351,
    discountMinor: 0,
    serviceChargeMinor: 0,
    taxMinor: 2149,
    totalMinor: 17500,
    taxRate: 0.14,
    serviceChargeRate: 0,
    taxInclusive: true,
    serviceChargeTaxable: true,
    serviceChargeWaivedMinor: 0,
  ),
  openedAt: '2026-09-10T18:30:00Z',
  queuedOffline: false,
  lines: [
    _line('l1', 'latte', 'Latte', 2, 9000, 1),
    _line('l2', 'espresso', 'Espresso', 1, 3500, 2),
    _line('l3', 'flat', 'Flat white', 1, 5000, 2),
  ],
);

/// The same bill with a 10.00 service charge on it.
final _serviceTicket = TicketView(
  id: 'tk-412',
  ticketRef: 'T-0412',
  tableId: 't5',
  status: 'ready',
  ready: true,
  customerName: 'Omar',
  waiterName: 'Sara',
  guestCount: 4,
  subtotalMinor: 17500,
  // Priced by the server, so the hero reads its Total.
  bill: const TicketBillView(
    subtotalMinor: 15351,
    discountMinor: 0,
    serviceChargeMinor: 1000,
    taxMinor: 2149,
    totalMinor: 17500,
    taxRate: 0.14,
    serviceChargeRate: 0,
    taxInclusive: true,
    serviceChargeTaxable: true,
    serviceChargeWaivedMinor: 0,
  ),
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
  extraPrepMinutes: 0,
  isTerminal: false,
  contactOverride: false,
);

ReceiptView _receipt({required bool queued, int? number}) => ReceiptView(
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
    this.tillOpen = true,
    this.loyaltyEnabled = true,
    this.canWaive = false,
    List<PaymentMethodView>? methods,
  }) : methods = methods ?? _methods;

  /// The signed-in user's effective `orders:waive_service` grant.
  final bool canWaive;

  /// The named arguments of the last `settleTicket`, for what the till sends.
  Map<Symbol, dynamic>? settled;

  /// The branch runs a loyalty programme. Off, every loyalty control leaves
  /// the tender screen.
  final bool loyaltyEnabled;

  final bool rtl;
  final bool tillOpen;

  /// Defaults to the three-method fixture; overridden by the overflow test
  /// to stand up a shop with many, long, and Arabic-named methods.
  final List<PaymentMethodView> methods;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      // The core's REAL tables first (read out of i18n.rs), so the PNGs show
      // the words that ship; the fixtures only cover a key the core lacks.
      final real = coreWord(key, arabic: rtl);
      if (real != key) return real;
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
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #orgLogoLocalPath) return null;
    if (name == #receiptFooter) return 'Thank you!';
    // The core's effective set (branch ∩ teller ∩ device); the full org
    // list is never what Charge shows.
    if (name == #availablePaymentMethods) {
      return Future<List<PaymentMethodView>>.value(methods);
    }
    if (name == #listPaymentMethods) {
      throw StateError('Charge must list only available methods');
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
    if (name == #cartDiscount) {
      return Future<CartDiscountView>.value(
        const CartDiscountView(kind: '', offMinor: 0),
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
    if (name == #currentTill) {
      return Future<TillView?>.value(
        tillOpen
            ? const TillView(
                id: 'sh-1',
                branchId: 'b1',
                tellerId: 'u1',
                tellerName: 'Sara',
                openingCashMinor: 50000,
                openedAt: '2026-09-10T09:00:00Z',
                status: 'open',
                isOpen: true,
                verification: 'server',
                openedWhileAnotherOpen: false,
              )
            : null,
      );
    }
    if (name == #loyaltyLookup) return Future<LoyaltyScanView>.value(_scan);
    // The reward rules are the core's (tested there); the fake keeps one
    // shape — the bill's first line claimable, a tap adds a unit.
    if (name == #ticketRewardLines || name == #cartRewardLines) {
      return [
        for (final l in _ticket.lines)
          RewardLineInput(
            name: l.name,
            ticketLineId: l.id,
            menuItemId: l.menuItemId,
            qty: l.qty,
            lineTotalMinor: l.lineTotalMinor,
            isBundle: false,
          ),
      ];
    }
    if (name == #toggleReward) {
      final picks = a[#picks] as List<RewardPick>;
      final line = a[#line] as int;
      final had = picks.where((p) => p.line == line).firstOrNull;
      return [
        ...picks.where((p) => p.line != line),
        RewardPick(line: line, units: (had?.units ?? 0) + 1),
      ];
    }
    if (name == #rewardBoard) {
      final lines = a[#lines] as List<RewardLineInput>;
      final picks = a[#picks] as List<RewardPick>;
      final units = {for (final p in picks) p.line: p.units};
      final cost = picks.fold(0, (x, p) => x + 200 * p.units);
      return RewardBoardView(
        lines: [
          for (var i = 0; i < lines.length; i++)
            RewardLineState(
              line: i,
              claimable: lines[i].menuItemId == 'latte',
              unitCost: 200,
              units: units[i] ?? 0,
              canAdd: lines[i].menuItemId == 'latte' && cost + 200 <= 240,
              blockedReason: lines[i].menuItemId == 'latte' && cost + 200 > 240
                  ? 'Not enough on the card for another'
                  : null,
              coveredMinor: 4500 * (units[i] ?? 0),
              costLabel: '200 pts',
            ),
        ],
        picks: picks,
        cost: cost,
        balanceAfter: 240 - cost,
        unitsClaimed: picks.fold(0, (x, p) => x + p.units),
        coveredMinor: picks.fold(0, (x, p) => x + 4500 * p.units),
      );
    }
    if (name == #rewardRedemptions) {
      final lines = a[#lines] as List<RewardLineInput>;
      return [
        for (final p in a[#picks] as List<RewardPick>)
          CheckoutRedemption(
            itemIndex: 0,
            ticketLineId: lines[p.line].ticketLineId,
            units: p.units,
          ),
      ];
    }
    if (name == #canWaiveServiceCharge) return canWaive;
    if (name == #settleTicket) {
      settled = a;
      return Future<String?>.value();
    }
    if (name == #billWithRewards) {
      // Rewards first, then the discount on what is left, as the core does;
      // the waiver takes a 10% service charge off (the fixture bill's charge
      // sits inside its 17500 for these figures).
      final r = a[#redemptions] as List<CheckoutRedemption>;
      final covered = r.fold(0, (x, p) => x + 4500 * p.units);
      final left = 17500 - covered;
      final dt = a[#discountType] as String?;
      final dv = a[#discountValue] as double?;
      final discount = switch (dt) {
        'percentage' => (left * dv!).round(),
        'fixed' => dv!.round().clamp(0, left),
        _ => 0,
      };
      final waived = (a[#waiveService] as bool) ? 1000 : 0;
      return TicketBillView(
        subtotalMinor: 15351,
        discountMinor: discount,
        serviceChargeMinor: 0,
        taxMinor: 2149,
        totalMinor: left - discount - waived,
        taxRate: 0.14,
        serviceChargeRate: 0,
        taxInclusive: true,
        serviceChargeTaxable: true,
        serviceChargeWaivedMinor: waived,
      );
    }
    if (name == #loyaltyAwardWindowOpen) return true;
    if (name == #clearTable) return Future<void>.value();
    if (name == #splitRestHere) {
      final legs = a[#legs] as List<CheckoutSplit>;
      final sum = legs.fold(0, (x, l) => x + l.amountMinor);
      final own = legs
          .where((l) => l.paymentMethodId == a[#target])
          .fold(0, (x, l) => x + l.amountMinor);
      final rest = own + (a[#dueMinor] as int) - sum;
      return rest < 0 ? 0 : rest;
    }
    if (name == #splitAutoFill) {
      final legs = a[#legs] as List<CheckoutSplit>;
      final typed = a[#typed] as List<String>;
      final open = legs
          .where(
            (l) =>
                l.paymentMethodId != a[#typedId] &&
                !typed.contains(l.paymentMethodId),
          )
          .toList();
      if (open.length != 1) return null;
      final sum = legs.fold(0, (x, l) => x + l.amountMinor);
      final rest = open.single.amountMinor + (a[#dueMinor] as int) - sum;
      return CheckoutSplit(
        paymentMethodId: open.single.paymentMethodId,
        amountMinor: rest < 0 ? 0 : rest,
      );
    }
    if (name == #tenderSummary) return fakeTenderSummary(invocation);
    if (name == #cashQuickTenders) return fakeCashQuickTenders(invocation);
    return null;
  }
}

/// The core's `tender_summary`, restated for a test double (the Rust side is
/// pinned by its own tests in checkout.rs).
TenderSummaryView fakeTenderSummary(Invocation invocation) {
  final a = invocation.namedArguments;
  final due = a[#dueMinor] as int;
  final tip = a[#tipMinor] as int;
  final tipIsCash = a[#tipIsCash] as bool;
  final tendered = a[#tenderedMinor] as int;
  final splits = a[#splits] as List<CheckoutSplit>;
  final dueCash = due + (tipIsCash ? tip : 0);
  final allocated = splits
      .map((l) => l.amountMinor)
      .where((m) => m > 0)
      .fold(0, (x, y) => x + y);
  return TenderSummaryView(
    chargeTotalMinor: due + tip,
    dueCashMinor: dueCash,
    changeMinor: tendered > dueCash ? tendered - dueCash : 0,
    shortMinor: dueCash > tendered ? dueCash - tendered : 0,
    splitAllocatedMinor: allocated,
    splitRemainingMinor: due - allocated,
    dueLabelKey: (a[#duePriced] as bool) ? 'order.total' : 'order.subtotal',
    dueIsSubtotal: !(a[#duePriced] as bool),
    showsChange: (a[#duePriced] as bool) || !(a[#addsOnTop] as bool),
  );
}

/// The core's `cash_quick_tenders` for two-digit currencies.
List<CashQuickTenderView> fakeCashQuickTenders(Invocation invocation) {
  final due = invocation.namedArguments[#dueMinor] as int;
  if (due <= 0) return const [];
  return [
    for (final note in const [5, 10, 20, 50, 100, 200, 500, 1000, 2000])
      if (note * 100 >= due)
        CashQuickTenderView(amountMinor: note * 100, label: '$note'),
  ].take(2).toList();
}

// Real words, so the picture shows what a person would read. Only the keys
// the Charge surfaces ask the core for; the feature's own new keys come
// from its fallback table, which is what ships until the core has them.
const _en = {
  'charge.change_short': 'change',
  'charge.cleared_q': 'cleared?',
  'charge.not_printed': 'Not printed — no printer',
  'charge.not_yet': 'Not yet',
  'charge.printed': 'Printed',
  'charge.reprint': 'Reprint',
  'charge.sale': 'Sale',
  'charge.will_send': 'Will send when back online',
  // These five moved out of the feature's own fallback table and into the
  // core, so the fake has to answer them like the core does.
  'charge.kind_cash': 'Cash',
  'charge.kind_card': 'Card',
  'charge.kind_wallet': 'Wallet',
  'charge.kind_custom': 'Custom',
  'charge.cleared': 'Cleared',
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
  'loyalty.unit_points': 'pts',
  'loyalty.unit_orders': 'orders',
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
  'charge.change_short': 'الباقي',
  'charge.cleared_q': 'تم تنظيفها؟',
  'charge.not_printed': 'لم تُطبع — لا توجد طابعة',
  'charge.not_yet': 'ليس بعد',
  'charge.printed': 'طُبع',
  'charge.reprint': 'إعادة طباعة',
  'charge.sale': 'بيع',
  'charge.will_send': 'سيُرسل عند عودة الاتصال',
  'charge.kind_cash': 'نقدي',
  'charge.kind_card': 'بطاقة',
  'charge.kind_wallet': 'محفظة',
  'charge.kind_custom': 'مخصص',
  'charge.cleared': 'تم التنظيف',
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
  'loyalty.unit_points': 'نقاط',
  'loyalty.unit_orders': 'طلبات',
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
CheckoutState _state0(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ChargeSheet)),
).read(checkoutProvider);

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
  loyaltyOffered: true,
  printState: PrintState.printed,
);

ChargeOutcome _counterOutcome() => ChargeOutcome(
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
  loyaltyOffered: true,
  printState: PrintState.noPrinter,
);

void main() {
  setUpAll(_loadFonts);

  testWidgets('a discount picked on a BILL moves the due', (tester) async {
    final bridge = _FakeBridge();
    await _mount(tester, size: _ipad, bridge: bridge);
    final host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(
        host,
        ChargeTarget.bill(_ticket, tableLabel: 'T5'),
        presentDoneCard: false,
      ),
    );
    await _settle(tester);
    expect(_state0(tester).dueMinor, 17500);

    // Staff 10%: the hero, the tender and the discount row all move.
    _session0(tester).setBillDiscount(_discounts.first);
    await _settle(tester);
    expect(_state0(tester).dueMinor, 15750);
    expect(_state0(tester).summary.discountMinor, 1750);
    expect(find.textContaining('17.50'), findsWidgets);

    // A fixed amount.
    _session0(tester).setBillDiscount(_discounts[1]);
    await _settle(tester);
    expect(_state0(tester).dueMinor, 15500);

    // "No discount" clears it, and the settle is told `none`.
    _session0(tester).setBillDiscount(null);
    await _settle(tester);
    expect(_state0(tester).dueMinor, 17500);
    expect(_state0(tester).billDiscountCleared, isTrue);

    // A split fills its open leg to the DISCOUNTED due.
    _session0(tester).setBillDiscount(_discounts.first);
    await _settle(tester);
    await tester.tap(find.text('Split'));
    await _settle(tester);
    _session0(tester)
      ..setSplitAmount('cash', 5000)
      ..fillSplitRest('card');
    await _settle(tester);
    final legs = _state0(tester).splitAmounts;
    expect(legs.values.fold(0, (x, v) => x + v), 15750, reason: '$legs');
    // Moving the discount re-fills the open leg to the new due.
    _session0(tester).setBillDiscount(_discounts[1]);
    await _settle(tester);
    expect(_state0(tester).splitAmounts.values.fold(0, (x, v) => x + v), 15500);
    Navigator.of(tester.element(find.byType(ChargeSheet))).pop();
    await _settle(tester);
  });

  testWidgets('removing the service charge needs the permission', (
    tester,
  ) async {
    // Without the grant: no row, and the notifier refuses the waiver.
    await _mount(tester, size: _ipad, bridge: _FakeBridge());
    var host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(
        host,
        ChargeTarget.bill(_serviceTicket, tableLabel: 'T5'),
        presentDoneCard: false,
      ),
    );
    await _settle(tester);
    expect(find.text(coreWord('checkout.remove_service')), findsNothing);
    _session0(tester).setWaiveService(waive: true);
    await _settle(tester);
    expect(_state0(tester).waiveService, isFalse);
    Navigator.of(tester.element(find.byType(ChargeSheet))).pop();
    await _settle(tester);

    // With it: the row offers it, the due drops, the settle carries it.
    final bridge = _FakeBridge(canWaive: true);
    await _mount(tester, size: _ipad, bridge: bridge);
    host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(
        host,
        ChargeTarget.bill(_serviceTicket, tableLabel: 'T5'),
        presentDoneCard: false,
      ),
    );
    await _settle(tester);
    await tester.tap(find.text(coreWord('checkout.remove_service')));
    await _settle(tester);
    expect(_state0(tester).waiveService, isTrue);
    expect(_state0(tester).dueMinor, 16500);
    expect(find.text(coreWord('checkout.keep_service')), findsOneWidget);
    await _session0(tester).chargeExact();
    await _settle(tester);
    expect(bridge.settled?[#waiveService], isTrue);
  });

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
      await _settle(tester);
      // The free latte is off the figure Charge collects, not only the paper.
      expect(_state0(tester).dueMinor, 13000);
      expect(_state0(tester).rewardRedemptions.single.ticketLineId, 'l1');
      await tester.tap(find.text('200'));
      await _settle(tester);
      expect(
        find.text('Omar Adel · 240 ${coreWord('loyalty.unit_points')}'),
        findsOneWidget,
      );
      await _capture(tester, 'charge-bill-tablet');
      // Close it so the future resolves without a charge.
      Navigator.of(tester.element(find.byType(ChargeSheet))).pop();
      await _settle(tester);
      expect(await pending, isNull);
    },
  );

  // The smaller tablets: the iPad 9th generation both ways and an 8" Android.
  for (final (label, size) in const [
    ('ipad9', Size(1080, 810)),
    ('ipad9p', Size(810, 1080)),
    ('tab8', Size(800, 1280)),
    ('lenovo', Size(1280, 800)),
  ]) {
    for (final rtl in [false, true]) {
      testWidgets('a bill charge on the $label${rtl ? ' in Arabic' : ''}', (
        tester,
      ) async {
        await _mount(
          tester,
          size: size,
          bridge: _FakeBridge(rtl: rtl),
          rtl: rtl,
        );
        final host = tester.element(find.byType(_Host));
        final pending = showCharge(
          host,
          ChargeTarget.bill(_ticket, tableLabel: 'T5'),
          presentDoneCard: false,
        );
        await _settle(tester);
        await tester.tap(find.text('200'));
        await _settle(tester);
        await _capture(tester, 'charge-bill-$label${rtl ? '-ar' : ''}');
        Navigator.of(tester.element(find.byType(ChargeSheet))).pop();
        await _settle(tester);
        expect(await pending, isNull);
      });
    }
  }

  for (final (label, size) in const [
    ('ipad9', Size(1080, 810)),
    ('lenovo', Size(1280, 800)),
  ]) {
    testWidgets('the Charge bar stays above the keyboard on the $label', (
      tester,
    ) async {
      // The 10.2" iPad in landscape with its keyboard up: 810 tall, the keys
      // take the bottom ~320. A 700-tall card centred in the window would put
      // Charge under them; the card shrinks instead.
      await _mount(tester, size: size, bridge: _FakeBridge());
      final host = tester.element(find.byType(_Host));
      final pending = showCharge(
        host,
        ChargeTarget.bill(_ticket, tableLabel: 'T5'),
        presentDoneCard: false,
      );
      await _settle(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await _settle(tester);
      await tester.pump(MotionSpec.standardDuration);
      final bar = find.byType(MadarMoneyBar);
      expect(bar, findsOneWidget);
      await _capture(tester, 'charge-bill-$label-keyboard');
      expect(
        tester.getBottomLeft(bar).dy,
        lessThanOrEqualTo(size.height - 320),
        reason: 'Charge is reachable with the keyboard up',
      );
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await _settle(tester);
      Navigator.of(tester.element(find.byType(ChargeSheet))).pop();
      await _settle(tester);
      expect(await pending, isNull);
    });
  }

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

  testWidgets('charge_sheet_lists_only_available_methods', (tester) async {
    // The core narrowed the org's methods to this teller on this device:
    // cash only. Charge offers exactly that, never the rest of the org's.
    await _mount(
      tester,
      size: _ipad,
      bridge: _FakeBridge(methods: [_methods.first]),
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
    expect(find.text(_methods.first.name), findsWidgets);
    for (final other in _methods.skip(1)) {
      expect(find.text(other.name), findsNothing);
    }
    await _capture(tester, 'charge-available-methods-only');
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

  testWidgets('six methods, long English/Arabic names and an unknown icon: no '
      'overflow, each still flagged by name', (tester) async {
    await _mount(
      tester,
      size: _phone,
      bridge: _FakeBridge(methods: _manyMethods),
      hostTitle: 'Sell',
    );
    final host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(host, const ChargeTarget.cart(), presentDoneCard: false),
    );
    await _settle(tester);
    // Every name is on screen as its own widget, even the two Arabic
    // ones and the longest English one — a Wrap never drops or hides a
    // method behind a scroll, it only grows the number of rows.
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Visa / Mastercard'), findsOneWidget);
    expect(find.text('InstaPay'), findsOneWidget);
    expect(find.text('فودافون كاش'), findsOneWidget);
    expect(find.text('Rue Zamalek Gift Card'), findsOneWidget);
    expect(find.text('برنامج رو للدفع الخاص بالفرع'), findsOneWidget);
    // Flagged by kind, not just by name or icon: a branded name like
    // "InstaPay" or "فودافون كاش" still says "Wallet" underneath, and
    // both the gift card and the never-seen 'rue_pay_v2' icon token read
    // as "Custom" rather than silently passing for Cash or a Card.
    expect(find.text('Wallet'), findsNWidgets(2));
    expect(find.text('Custom'), findsNWidgets(2));
    // The one genuinely redundant caption — "Cash" named "Cash" — is
    // skipped, so it does not double up with the name above it.
    expect(find.text('Cash'), findsOneWidget);
    // No RenderFlex overflow, no Flexible-under-unbounded-width assert:
    // this is the layout exception CI is here to catch.
    expect(tester.takeException(), isNull);
    await _capture(tester, 'charge-cart-phone-many-methods');
  });

  testWidgets('a cart on a phone with no shift open says so on the bar', (
    tester,
  ) async {
    await _mount(
      tester,
      size: _phone,
      bridge: _FakeBridge(tillOpen: false),
      hostTitle: 'Sell',
    );
    final host = tester.element(find.byType(_Host));
    unawaited(
      showCharge(host, const ChargeTarget.cart(), presentDoneCard: false),
    );
    await _settle(tester);
    expect(find.text(coreWord('waiter.need_shift')), findsOneWidget);
    await _capture(tester, 'charge-cart-phone-noshift');
  });

  testWidgets('the Done card over the floor: the happy sale', (tester) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge());
    final host = tester.element(find.byType(_Host));
    final pending = showDoneCard(host, _saleOutcome());
    await _settle(tester);
    expect(find.text('T5 · Cleared'), findsOneWidget);
    expect(find.text('New sale'), findsOneWidget);
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
    expect(find.textContaining('Cleared'), findsNothing);
    await _capture(tester, 'done-card-queued-phone');
  });

  testWidgets('the Done card: queued, on an iPad', (tester) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge(), hostTitle: 'Sell');
    final host = tester.element(find.byType(_Host));
    unawaited(showDoneCard(host, _queuedOutcome()));
    await _settle(tester);
    await _capture(tester, 'done-card-queued-tablet');
  });

  testWidgets('the Done card for a counter sale steps aside by itself', (
    tester,
  ) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge(), hostTitle: 'Sell');
    final host = tester.element(find.byType(_Host));
    final pending = showDoneCard(host, _counterOutcome());
    await _settle(tester);
    expect(find.byType(DoneCard), findsOneWidget);
    await _capture(tester, 'done-card-counter-tablet');
    await tester.pump(const Duration(seconds: 7));
    await _settle(tester);
    expect(await pending, DoneCardResult.notYet);
    expect(find.byType(DoneCard), findsNothing);
  });

  testWidgets('Cleared on the Done card clears the table and resolves', (
    tester,
  ) async {
    await _mount(tester, size: _ipad, bridge: _FakeBridge());
    final host = tester.element(find.byType(_Host));
    final pending = showDoneCard(host, _saleOutcome());
    await _settle(tester);
    await tester.tap(find.text('T5 · Cleared'));
    await _settle(tester);
    expect(await pending, DoneCardResult.cleared);
  });

  // ── Sheet over sheet ────────────────────────────────────────────────
  //
  // The flows that glitched: a sheet opened from the Done card rendered
  // UNDER it and died with it on the next tap; a sheet over Charge dimmed a
  // second time or not at all; a pick closed with a hard cut; the scanner's
  // hidden field raised a keyboard that jumped both sheets.

  for (final (label, size) in [('phone', _phone), ('tablet', _ipad)]) {
    testWidgets('charge -> scan member on a $label: one dim, no keyboard', (
      tester,
    ) async {
      debugResetScrim();
      await _mount(tester, size: size, bridge: _FakeBridge());
      final host = tester.element(find.byType(_Host));
      final pending = showCharge(
        host,
        ChargeTarget.bill(_ticket, tableLabel: 'T5'),
        presentDoneCard: false,
      );
      await _settle(tester);
      expect(_visibleDims(tester), 1);
      await tester.tap(find.text('Scan card').first);
      await _settle(tester);
      expect(find.byType(LoyaltyScanSheet), findsOneWidget);
      expect(
        _visibleDims(tester),
        1,
        reason: 'the sheet over Charge adds none',
      );
      final wedge = tester
          .widgetList<TextField>(find.byType(TextField))
          .where((f) => f.keyboardType == TextInputType.none);
      expect(wedge, isNotEmpty, reason: 'the wedge sink raises no keyboard');
      // The scan sheet's own barrier: only it goes.
      await tester.tapAt(const Offset(8, 8));
      await _settle(tester);
      expect(find.byType(LoyaltyScanSheet), findsNothing);
      expect(find.byType(ChargeSheet), findsOneWidget);
      expect(_visibleDims(tester), 1);
      MadarSheet.close<void>(tester.element(find.byType(ChargeSheet)));
      await _settle(tester);
      expect(await pending, isNull);
      await tester.pump(MotionSpec.gentleDuration);
      expect(_visibleDims(tester), 0);
      debugResetScrim();
    });

    testWidgets('charge -> discount picker on a $label animates out', (
      tester,
    ) async {
      debugResetScrim();
      await _mount(tester, size: size, bridge: _FakeBridge());
      final host = tester.element(find.byType(_Host));
      final pending = showCharge(
        host,
        ChargeTarget.bill(_ticket, tableLabel: 'T5'),
        presentDoneCard: false,
      );
      await _settle(tester);
      final chip = find.descendant(
        of: find.byType(MadarChip),
        matching: find.text('No discount'),
      );
      await tester.tap(find.text('Discount').first);
      await _settle(tester);
      expect(chip, findsOneWidget);
      expect(_visibleDims(tester), 1);
      await tester.tap(chip);
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        chip,
        findsOneWidget,
        reason: 'the picker slides out, it is not cut',
      );
      await _settle(tester);
      expect(chip, findsNothing);
      expect(find.byType(ChargeSheet), findsOneWidget);
      expect(_visibleDims(tester), 1);
      MadarSheet.close<void>(tester.element(find.byType(ChargeSheet)));
      await _settle(tester);
      expect(await pending, isNull);
      debugResetScrim();
    });

    testWidgets('done card -> add points on a $label stacks above the card', (
      tester,
    ) async {
      debugResetScrim();
      await _mount(tester, size: size, bridge: _FakeBridge());
      final host = tester.element(find.byType(_Host));
      // Keep a session alive so the programme is known, as it is the instant
      // Charge hands over to the card.
      final charge = showCharge(
        host,
        ChargeTarget.bill(_ticket, tableLabel: 'T5'),
        presentDoneCard: false,
      );
      await _settle(tester);
      final done = showDoneCard(host, _saleOutcome());
      await _settle(tester);
      expect(find.byType(DoneCard), findsOneWidget);
      await tester.tap(find.text('Add points'));
      await _settle(tester);
      expect(find.byType(LoyaltyAwardSheet), findsOneWidget);
      expect(_visibleDims(tester), 1);
      // The award sheet is the top of the stack: its content takes the tap,
      // and neither it nor the card is torn down by it.
      await tester.tap(find.byType(LoyaltyAwardSheet), warnIfMissed: false);
      await _settle(tester);
      expect(find.byType(LoyaltyAwardSheet), findsOneWidget);
      expect(find.byType(DoneCard), findsOneWidget);
      MadarSheet.close<void>(tester.element(find.byType(LoyaltyAwardSheet)));
      await _settle(tester);
      expect(find.byType(LoyaltyAwardSheet), findsNothing);
      expect(find.byType(DoneCard), findsOneWidget, reason: 'the card stays');
      await tester.tap(find.text('New sale'));
      await _settle(tester);
      expect(await done, DoneCardResult.notYet);
      MadarSheet.close<void>(tester.element(find.byType(ChargeSheet)));
      await _settle(tester);
      expect(await charge, isNull);
      debugResetScrim();
    });
  }
}

/// The shared dims actually visible now.
int _visibleDims(WidgetTester tester) {
  var n = 0;
  for (final e in find.byType(ColoredBox).evaluate()) {
    final box = e.widget as ColoredBox;
    if (box.color != StackScrim.color) continue;
    final fade = e.findAncestorWidgetOfExactType<FadeTransition>();
    if (fade == null || fade.opacity.value > 0) n++;
  }
  return n;
}
