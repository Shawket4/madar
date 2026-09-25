// Split payments on the Charge sheet: 2- and 3-way splits must keep adding
// up to what the sale books when the due moves under them — a discount on the
// cart or the bill, the service charge waived — and never send a zero leg.
// The same flow runs offline: the sheet's figures come from the core's local
// pricing, so these drive the real notifier over a fake bridge.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

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
    color: '#35527A',
  ),
];

const _tenPct = DiscountView(
  id: 'd10',
  name: '10%',
  dtype: 'percentage',
  value: 0.10,
  isActive: true,
);

const _session = SessionSnapshot(
  userId: 'u1',
  displayName: 'Sara',
  role: 'teller',
  currencyCode: 'EGP',
  taxRate: 0,
  taxInclusive: true,
  serviceChargeRate: 0,
  serviceChargeTaxable: false,
  requireTableForOrders: false,
  online: true,
  permissionsLoaded: true,
);

const _openTill = TillView(
  id: 'sh-1',
  branchId: 'b1',
  tellerId: 'u1',
  tellerName: 'Sara',
  openingCashMinor: 0,
  openedAt: '2026-09-13T09:00:00Z',
  status: 'open',
  isOpen: true,
  verification: 'server',
  openedWhileAnotherOpen: false,
);

const _ticket = TicketView(
  id: 'tk-1',
  ticketRef: 'T-0001',
  tableId: 't1',
  status: 'ready',
  ready: true,
  subtotalMinor: 10000,
  openedAt: '2026-09-13T10:00:00Z',
  queuedOffline: false,
  lines: [],
  bill: TicketBillView(
    subtotalMinor: 10000,
    discountMinor: 0,
    serviceChargeMinor: 1000,
    taxMinor: 0,
    totalMinor: 11000,
    taxRate: 0,
    serviceChargeRate: 0.10,
    taxInclusive: true,
    serviceChargeTaxable: false,
    serviceChargeWaivedMinor: 0,
  ),
);

ReceiptView _receipt(int total) => ReceiptView(
  localOrderId: 'order-1',
  isVoided: false,
  lines: const [],
  paymentLabel: 'Cash',
  subtotalMinor: total,
  discountMinor: 0,
  taxMinor: 0,
  serviceChargeMinor: 0,
  deliveryFeeMinor: 0,
  totalMinor: total,
  tipMinor: 0,
  amountTenderedMinor: 0,
  changeMinor: 0,
  isCash: false,
  isDelivery: false,
  queuedOffline: true,
  createdAt: '2026-09-13T10:05:00Z',
  payments: const [],
  displayNumber: '',
  serviceChargeWaivedMinor: 0,
  taxInclusive: true,
  taxRate: 0,
);

/// A bridge that prices like the core: a 10,000 cart (9,000 with the 10%
/// discount), and a 10,000 table bill carrying a 10% service charge that the
/// discount comes off before and the waiver removes.
class _Fake implements MadarBridge {
  bool cartDiscounted = false;
  CheckoutInput? checkedOut;
  List<CheckoutSplit>? settledSplits;

  /// The customer row this till holds for a member id, as the core answers.
  final memberRows = <String, CustomerView>{};

  /// Every `attachCustomer(orderId, customerId)` the session made, in order.
  final attached = <(String, String?)>[];

  /// The customers this till's list holds, as `customerById` answers.
  final customers = <String, CustomerView>{};

  /// Every `setTicketCustomer(ticketId, customerId)`, in order: what the core
  /// keeps for an open bill.
  final billCustomers = <(String, String?)>[];

  /// Who the last settle named, and whether one happened.
  String? settledCustomer;

  /// The online orders finalized, by id.
  final finalized = <String>[];

  /// What the last loyalty read was asked for.
  String? refreshedMember;

  int get _cartTotal => cartDiscounted ? 9000 : 10000;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #tr) return coreWord(a[#key] as String);
    if (name == #canWaiveServiceCharge) return true;
    if (name == #cartRewardLines || name == #ticketRewardLines) {
      return const <RewardLineInput>[];
    }
    if (name == #isRtl) return false;
    if (name == #locale) return 'en';
    if (name == #currentSession) return _session;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #deviceConfig) {
      return const DeviceConfigView(
        branchName: 'Rue',
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #orgLogoLocalPath) return null;
    if (name == #receiptFooter) return 'Thank you!';
    if (name == #humanMessage) return 'refused';
    if (name == #availablePaymentMethods) {
      return Future<List<PaymentMethodView>>.value(_methods);
    }
    if (name == #listDiscounts) {
      return Future<List<DiscountView>>.value(const [_tenPct]);
    }
    if (name == #loyaltySettings) {
      return Future<LoyaltyProgrammeView>.value(
        const LoyaltyProgrammeView(
          enabled: false,
          mode: 'points',
          programName: '',
          balanceLabel: '',
        ),
      );
    }
    if (name == #cartSetDiscount) {
      cartDiscounted = true;
      return Future<void>.value();
    }
    if (name == #cartClearDiscount) {
      cartDiscounted = false;
      return Future<void>.value();
    }
    if (name == #cartDiscount) {
      return Future<CartDiscountView>.value(
        const CartDiscountView(kind: '', offMinor: 0),
      );
    }
    if (name == #cartDiscountId) {
      return Future<String?>.value(cartDiscounted ? 'd10' : null);
    }
    if (name == #cartTotals) {
      return Future<CartTotals>.value(
        CartTotals(
          itemCount: 1,
          subtotalMinor: 10000,
          discountMinor: 10000 - _cartTotal,
          taxMinor: 0,
          serviceChargeMinor: 0,
          totalMinor: _cartTotal,
        ),
      );
    }
    if (name == #billWithRewards) {
      final pct = a[#discountType] == 'percentage'
          ? (a[#discountValue] as double)
          : 0.0;
      final discount = (10000 * pct).round();
      final waived = a[#waiveService] as bool;
      final service = ((10000 - discount) * 0.10).round();
      return TicketBillView(
        subtotalMinor: 10000,
        discountMinor: discount,
        serviceChargeMinor: waived ? 0 : service,
        taxMinor: 0,
        totalMinor: 10000 - discount + (waived ? 0 : service),
        taxRate: 0,
        serviceChargeRate: 0.10,
        taxInclusive: true,
        serviceChargeTaxable: false,
        serviceChargeWaivedMinor: waived ? service : 0,
      );
    }
    if (name == #cartLines) return Future<List<CartLineView>>.value(const []);
    // The one owner's sync read: this person's OWN open till, or none.
    if (name == #ownOpenTill) return _openTill;
    if (name == #currentTill) return Future<TillView?>.value(_openTill);
    if (name == #checkout) {
      checkedOut = a[#input] as CheckoutInput;
      return Future<ReceiptView>.value(_receipt(_cartTotal));
    }
    if (name == #settleTicket) {
      settledSplits = a[#splits] as List<CheckoutSplit>;
      settledCustomer = a[#customerId] as String?;
      return Future<String?>.value(); // queued offline
    }
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
    if (name == #tenderSummary) {
      final due = a[#dueMinor] as int;
      final tip = a[#tipMinor] as int;
      final allocated = (a[#splits] as List<CheckoutSplit>).fold(
        0,
        (sum, l) => sum + l.amountMinor,
      );
      return TenderSummaryView(
        chargeTotalMinor: due + tip,
        dueCashMinor: due,
        changeMinor: 0,
        shortMinor: 0,
        splitAllocatedMinor: allocated,
        splitRemainingMinor: due - allocated,
        dueLabelKey: 'order.total',
        dueIsSubtotal: false,
        showsChange: false,
      );
    }
    if (name == #cashQuickTenders) return const <CashQuickTenderView>[];
    if (name == #loyaltyLookup) {
      return Future<LoyaltyScanView>.value(_scan('m-1'));
    }
    if (name == #loyaltyRefresh) {
      refreshedMember = a[#customerId] as String;
      return Future<LoyaltyScanView>.value(_scan(refreshedMember!));
    }
    if (name == #customerForMember) return memberRows[a[#memberId]];
    if (name == #customerById) return customers[a[#id]];
    if (name == #setTicketCustomer) {
      billCustomers.add((a[#ticketId] as String, a[#customerId] as String?));
      return null;
    }
    // The receipt of a sale finalized a moment ago: not held here yet. The
    // charge stands without it (a reprint from history).
    if (name == #orderReceiptView) {
      return Future<ReceiptView>.error(
        const MadarError.offline(detail: 'not on this device yet'),
      );
    }
    if (name == #deliveryFinalize) {
      finalized.add(a[#id] as String);
      return Future<DeliveryFinalizeView>.value(
        const DeliveryFinalizeView(orderId: 'o-900', warnings: []),
      );
    }
    if (name == #attachCustomer) {
      attached.add((a[#orderId] as String, a[#customerId] as String?));
      return true;
    }
    if (name == #rewardBoard) {
      return const RewardBoardView(
        lines: [],
        picks: [],
        cost: 0,
        balanceAfter: 120,
        unitsClaimed: 0,
        coveredMinor: 0,
      );
    }
    if (name == #rewardRedemptions) return const <CheckoutRedemption>[];
    return null;
  }
}

LoyaltyScanView _scan(String memberId) => LoyaltyScanView(
  member: LoyaltyMemberView(
    id: memberId,
    name: 'Mona',
    phone: '201001234567',
    mode: 'points',
    balance: 120,
    nextRewardCost: 100,
    rewardsReady: 1,
    progressToNext: 20,
    pointsToNextReward: 80,
    canRedeem: true,
    progressLabel: '',
    balanceLabel: '120 points',
  ),
  rewards: const [],
  recent: const [],
  anyItem: false,
  anyItemCost: 0,
);

const _mona = CustomerView(
  id: 'm-1',
  name: 'Mona',
  phoneHint: '•••• 4567',
  loyaltyCustomerId: 'm-1',
  pending: false,
  isMember: true,
  balanceLabel: '120 points',
);

const _hana = CustomerView(
  id: 'c-1',
  name: 'Hana',
  pending: false,
  isMember: false,
);

DeliveryOrderView _onlineFor(String? customerId) => DeliveryOrderView(
  id: 'd-118',
  orderRef: '#D-118',
  channel: 'outside',
  status: 'ready',
  customerName: 'Nour Hassan',
  customerPhone: '0122 333 4455',
  subtotalMinor: 15000,
  discountMinor: 0,
  deliveryFeeMinor: 2500,
  totalMinor: 17500,
  itemCount: 3,
  lines: const [],
  createdAt: '2026-09-10T19:40:00Z',
  extraPrepMinutes: 0,
  isTerminal: false,
  customerId: customerId,
  contactOverride: false,
);

/// [_ticket], already for someone.
TicketView _billFor(String customerId) => TicketView(
  id: _ticket.id,
  ticketRef: _ticket.ticketRef,
  tableId: _ticket.tableId,
  status: _ticket.status,
  ready: _ticket.ready,
  customerId: customerId,
  subtotalMinor: _ticket.subtotalMinor,
  bill: _ticket.bill,
  openedAt: _ticket.openedAt,
  queuedOffline: _ticket.queuedOffline,
  lines: _ticket.lines,
);

Future<(ProviderContainer, CheckoutNotifier)> _session_(
  WidgetTester tester,
  _Fake bridge,
  ChargeTarget target,
) async {
  final container = ProviderContainer(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: MadarTheme.light(), home: const SizedBox()),
    ),
  );
  final keep = container.listen(checkoutProvider, (_, _) {});
  addTearDown(keep.close);
  final session = container.read(checkoutProvider.notifier);
  await session.start(target);
  return (container, session);
}

Map<String, int> _legs(List<CheckoutSplit> legs) => {
  for (final l in legs) l.paymentMethodId: l.amountMinor,
};

void main() {
  testWidgets('an attached customer rides the counter sale, and clears', (
    tester,
  ) async {
    final bridge = _Fake();
    final (c, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.cart(),
    );
    const hana = CustomerView(
      id: 'c-1',
      name: 'Hana',
      phoneHint: '•••• 4444',
      pending: true,
      isMember: false,
    );
    session.attachCustomer(hana);
    expect(c.read(checkoutProvider).customer?.id, 'c-1');
    session.selectMethod('card');
    await session.charge();
    expect(bridge.checkedOut!.customerId, 'c-1');
    expect(bridge.checkedOut!.customerName, 'Hana');

    session.clearCustomer();
    expect(c.read(checkoutProvider).customer, isNull);
  });

  testWidgets('a scan attaches the member AS the customer: one person', (
    tester,
  ) async {
    final bridge = _Fake()..memberRows['m-1'] = _mona;
    final (c, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.cart(),
    );
    // Somebody else was picked first; the member decides who the sale is for.
    session.attachCustomer(_hana);
    expect(await session.scanLoyalty(token: 'tok'), isTrue);
    var s = c.read(checkoutProvider);
    expect(s.loyaltyMember?.id, 'm-1');
    expect(s.customer?.id, 'm-1');

    session.selectMethod('card');
    await session.charge();
    expect(bridge.checkedOut!.customerId, 'm-1');

    // Picking a different customer takes the member off with them.
    await session.start(const ChargeTarget.cart());
    await session.scanLoyalty(token: 'tok');
    session.attachCustomer(_hana);
    s = c.read(checkoutProvider);
    expect(s.customer?.id, 'c-1');
    expect(s.loyaltyMember, isNull);

    // Removing either removes the person.
    await session.scanLoyalty(token: 'tok');
    session.clearCustomer();
    s = c.read(checkoutProvider);
    expect(s.customer, isNull);
    expect(s.loyaltyMember, isNull);
    await session.scanLoyalty(token: 'tok');
    session.clearLoyalty();
    expect(c.read(checkoutProvider).customer, isNull);
  });

  testWidgets(
    'a member unknown to this till drops a customer who is not them',
    (tester) async {
      final bridge = _Fake();
      final (c, session) = await _session_(
        tester,
        bridge,
        const ChargeTarget.cart(),
      );
      session.attachCustomer(_hana);
      await session.scanLoyalty(token: 'tok');
      final s = c.read(checkoutProvider);
      expect(s.loyaltyMember?.id, 'm-1');
      expect(s.customer, isNull);
    },
  );

  testWidgets("a picked member's rewards open with no second scan", (
    tester,
  ) async {
    final bridge = _Fake()..memberRows['m-1'] = _mona;
    final (c, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.cart(),
    );
    session.attachCustomer(_hana);
    expect(await session.useCustomerLoyalty(), isFalse);
    session.attachCustomer(_mona);
    expect(await session.useCustomerLoyalty(), isTrue);
    expect(bridge.refreshedMember, 'm-1');
    final s = c.read(checkoutProvider);
    expect(s.loyaltyMember?.id, 'm-1');
    expect(s.customer?.id, 'm-1');
  });

  // Wave 2: the settle itself says who the bill is for. The pick is kept in
  // the core the moment it is made (it survives the drawer closing, and the
  // app), and NO attach follows the settle — two ops naming the customer is
  // how they could come to disagree.
  testWidgets("a bill's customer is kept at once and rides the settle", (
    tester,
  ) async {
    final bridge = _Fake();
    final (_, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.bill(_ticket, tableLabel: 'T1'),
    );
    session.attachCustomer(_hana);
    expect(bridge.billCustomers, [('tk-1', 'c-1')]);
    session.selectMethod('card');
    await session.charge();
    expect(bridge.settledSplits, isNotNull);
    expect(bridge.settledCustomer, 'c-1');
    expect(bridge.attached, isEmpty);
  });

  testWidgets('a bill opens with the customer it already has', (tester) async {
    final bridge = _Fake()..customers['c-1'] = _hana;
    final (c, session) = await _session_(
      tester,
      bridge,
      ChargeTarget.bill(_billFor('c-1'), tableLabel: 'T1'),
    );
    expect(c.read(checkoutProvider).customer?.id, 'c-1');
    expect(bridge.billCustomers, isEmpty, reason: 'reading is not choosing');
    // Taken off: the core is told, and the settle names nobody.
    session.clearCustomer();
    expect(bridge.billCustomers, [('tk-1', null)]);
    session.selectMethod('card');
    await session.charge();
    expect(bridge.settledCustomer, isNull);
    expect(bridge.attached, isEmpty);
  });

  // An online order arrives with its customer linked, and finalize carries
  // them onto the sale by itself. Only a CHANGE made on the sheet follows the
  // finalize, as the attach (or the removal) queued behind the sale.
  group('an online order finalized', () {
    testWidgets('with its own customer untouched: no attach', (tester) async {
      final bridge = _Fake()..customers['c-1'] = _hana;
      final (c, session) = await _session_(
        tester,
        bridge,
        ChargeTarget.online(_onlineFor('c-1')),
      );
      expect(c.read(checkoutProvider).customer?.id, 'c-1');
      session.selectMethod('card');
      await session.charge();
      expect(bridge.finalized, ['d-118']);
      expect(bridge.attached, isEmpty);
      expect(bridge.billCustomers, isEmpty, reason: 'not a bill');
    });

    testWidgets('a customer this till does not hold is left alone', (
      tester,
    ) async {
      final bridge = _Fake();
      final (c, session) = await _session_(
        tester,
        bridge,
        ChargeTarget.online(_onlineFor('c-unknown')),
      );
      expect(c.read(checkoutProvider).customer, isNull);
      session.selectMethod('card');
      await session.charge();
      expect(bridge.finalized, ['d-118']);
      expect(
        bridge.attached,
        isEmpty,
        reason: 'not shown is not removed: the server still has them',
      );
    });

    testWidgets('a customer picked on the sheet is attached to the new sale', (
      tester,
    ) async {
      final bridge = _Fake();
      final (_, session) = await _session_(
        tester,
        bridge,
        ChargeTarget.online(_onlineFor(null)),
      );
      session
        ..attachCustomer(_hana)
        ..selectMethod('card');
      await session.charge();
      // By the ORDER finalize made, not by the delivery order's id.
      expect(bridge.attached, [('o-900', 'c-1')]);
    });

    testWidgets('picking the customer it already has attaches nothing', (
      tester,
    ) async {
      final bridge = _Fake()..customers['c-1'] = _hana;
      final (_, session) = await _session_(
        tester,
        bridge,
        ChargeTarget.online(_onlineFor('c-1')),
      );
      session
        ..clearCustomer()
        ..attachCustomer(_hana)
        ..selectMethod('card');
      await session.charge();
      expect(bridge.attached, isEmpty);
    });

    testWidgets('taking its customer off removes them after the sale', (
      tester,
    ) async {
      final bridge = _Fake()..customers['c-1'] = _hana;
      final (_, session) = await _session_(
        tester,
        bridge,
        ChargeTarget.online(_onlineFor('c-1')),
      );
      session
        ..clearCustomer()
        ..selectMethod('card');
      await session.charge();
      expect(bridge.attached, [('o-900', null)]);
    });
  });

  testWidgets('a bill with no customer queues no attach', (tester) async {
    final bridge = _Fake();
    final (_, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.bill(_ticket, tableLabel: 'T1'),
    );
    session.selectMethod('card');
    await session.charge();
    expect(bridge.attached, isEmpty);
  });

  testWidgets('a 2-way cart split follows a discount applied after it', (
    tester,
  ) async {
    final bridge = _Fake();
    final (c, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.cart(),
    );
    session
      ..toggleSplit()
      ..setSplitAmount('cash', 4000);
    expect(c.read(checkoutProvider).splitAmounts['card'], isNull);
    session.setSplitAmount('card', 6000);
    await session.setDiscount('d10');
    var s = c.read(checkoutProvider);
    expect(s.dueMinor, 9000);
    // Both legs were typed: nothing is overwritten, the sheet says what's off.
    expect(s.splitRemaining, -1000);
    expect(s.block, ChargeBlock.needTender);

    session.fillSplitRest('card');
    s = c.read(checkoutProvider);
    expect(_legs(s.splitLegs), {'cash': 4000, 'card': 5000});
    expect(s.block, ChargeBlock.none);
    await session.charge();
    final sent = bridge.checkedOut!.splits;
    expect(_legs(sent), {'cash': 4000, 'card': 5000});
    expect(sent.every((l) => l.amountMinor > 0), isTrue);
    expect(bridge.checkedOut!.amountTenderedMinor, 0);
  });

  testWidgets('a 3-way cart split: the auto-filled leg follows the discount', (
    tester,
  ) async {
    final bridge = _Fake();
    final (c, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.cart(),
    );
    session
      ..toggleSplit()
      ..setSplitAmount('cash', 3000)
      ..setSplitAmount('card', 3000);
    expect(c.read(checkoutProvider).splitAmounts['wallet'], 4000);
    await session.setDiscount('d10');
    final s = c.read(checkoutProvider);
    expect(_legs(s.splitLegs), {'cash': 3000, 'card': 3000, 'wallet': 3000});
    expect(s.splitRemaining, 0);
    await session.charge();
    final sent = bridge.checkedOut!.splits;
    expect(sent.fold(0, (x, l) => x + l.amountMinor), 9000);
    expect(sent.every((l) => l.amountMinor > 0), isTrue);
  });

  testWidgets('typing over the rest leg keeps what was typed', (tester) async {
    final bridge = _Fake();
    final (c, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.cart(),
    );
    session
      ..toggleSplit()
      ..setSplitAmount('cash', 3000)
      ..setSplitAmount('card', 3000) // wallet auto-fills 4000
      ..setSplitAmount('wallet', 2500);
    await session.setDiscount('d10');
    expect(c.read(checkoutProvider).splitAmounts['wallet'], 2500);
  });

  testWidgets('a 2-way table split with a discount and the service waived, '
      'settled offline', (tester) async {
    final bridge = _Fake();
    final (c, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.bill(_ticket, tableLabel: 'T1'),
    );
    session
      ..toggleSplit()
      ..setSplitAmount('card', 5000);
    // 10,000 + 10% service = 11,000; cash takes the rest.
    expect(c.read(checkoutProvider).splitAmounts['cash'], isNull);
    session.fillSplitRest('cash');
    expect(c.read(checkoutProvider).splitAmounts['cash'], 6000);

    session.setBillDiscount(_tenPct); // 9,000 + 900 service = 9,900
    expect(c.read(checkoutProvider).splitAmounts['cash'], 4900);
    session.setWaiveService(waive: true); // 9,000
    final s = c.read(checkoutProvider);
    expect(_legs(s.splitLegs), {'card': 5000, 'cash': 4000});
    expect(s.block, ChargeBlock.none);
    await session.charge();
    expect(_legs(bridge.settledSplits!), {'card': 5000, 'cash': 4000});
  });

  testWidgets('a 3-way table split with a discount and the waiver', (
    tester,
  ) async {
    final bridge = _Fake();
    final (c, session) = await _session_(
      tester,
      bridge,
      const ChargeTarget.bill(_ticket, tableLabel: 'T1'),
    );
    session
      ..toggleSplit()
      ..setSplitAmount('cash', 2000)
      ..setSplitAmount('card', 3000); // wallet: 11,000 − 5,000 = 6,000
    expect(c.read(checkoutProvider).splitAmounts['wallet'], 6000);
    session
      ..setBillDiscount(_tenPct) // 9,900
      ..setWaiveService(waive: true); // 9,000
    final s = c.read(checkoutProvider);
    expect(_legs(s.splitLegs), {'cash': 2000, 'card': 3000, 'wallet': 4000});
    await session.charge();
    final sent = bridge.settledSplits!;
    expect(sent.fold(0, (x, l) => x + l.amountMinor), 9000);
    expect(sent.every((l) => l.amountMinor > 0), isTrue);
  });
}
