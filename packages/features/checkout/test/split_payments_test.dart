// Split payments on the Charge sheet: 2- and 3-way splits must keep adding
// up to what the sale books when the due moves under them — a discount on the
// cart or the bill, the service charge waived — and never send a zero leg.
// The same flow runs offline: the sheet's figures come from the core's local
// pricing, so these drive the real notifier over a fake bridge.

import 'dart:async';

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

  int get _cartTotal => cartDiscounted ? 9000 : 10000;

  @override
  dynamic noSuchMethod(Invocation invocation) {
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
    if (name == #currentTill) return Future<TillView?>.value(_openTill);
    if (name == #checkout) {
      checkedOut = a[#input] as CheckoutInput;
      return Future<ReceiptView>.value(_receipt(_cartTotal));
    }
    if (name == #settleTicket) {
      settledSplits = a[#splits] as List<CheckoutSplit>;
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
    return null;
  }
}

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
