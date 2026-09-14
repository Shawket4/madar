// The Charge session's safety rails — the P0s of the selling-flow audit.
//
// Money must never be lost or taken twice because of how a sheet was put
// away, how slow a printer is, what a previous sale left behind, or how fast
// a teller taps. Each test drives the real notifier and the real sheet over a
// fake bridge whose slow calls are completers the test releases by hand.

import 'dart:async';
import 'dart:typed_data';

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
];

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
);

ReceiptView _receipt() => const ReceiptView(
  localOrderId: 'order-1',
  isVoided: false,
  lines: [],
  paymentLabel: 'Cash',
  subtotalMinor: 10000,
  discountMinor: 0,
  taxMinor: 0,
  serviceChargeMinor: 0,
  deliveryFeeMinor: 0,
  totalMinor: 10000,
  tipMinor: 0,
  amountTenderedMinor: 10000,
  changeMinor: 0,
  isCash: true,
  isDelivery: false,
  queuedOffline: false,
  createdAt: '2026-09-13T10:05:00Z',
  payments: [],
  displayNumber: '',
);

class _Fake implements MadarBridge {
  /// Released by the test: the money call.
  Completer<ReceiptView> checkoutGate = Completer<ReceiptView>();
  Completer<String?> settleGate = Completer<String?>();

  /// Released by the test: the till lookup. Null answers at once.
  Completer<TillView?>? till;

  int checkoutCalls = 0;
  int settleCalls = 0;
  List<CheckoutSplit>? settledSplits;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #tr) return coreWord(a[#key] as String);
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
    // The core's effective set (branch ∩ teller ∩ device); the full org
    // list is never what Charge shows.
    if (name == #availablePaymentMethods) {
      return Future<List<PaymentMethodView>>.value(_methods);
    }
    if (name == #listPaymentMethods) {
      throw StateError('Charge must list only available methods');
    }
    if (name == #listDiscounts) {
      return Future<List<DiscountView>>.value(const []);
    }
    if (name == #loyaltySettings) {
      return Future<LoyaltyProgrammeView>.value(
        const LoyaltyProgrammeView(
          enabled: true,
          mode: 'points',
          programName: 'Rue Rewards',
          balanceLabel: 'points',
        ),
      );
    }
    if (name == #cartDiscountId) return Future<String?>.value();
    if (name == #cartTotals) {
      return Future<CartTotals>.value(
        const CartTotals(
          itemCount: 1,
          subtotalMinor: 10000,
          discountMinor: 0,
          taxMinor: 0,
          serviceChargeMinor: 0,
          totalMinor: 10000,
        ),
      );
    }
    if (name == #cartLines) return Future<List<CartLineView>>.value(const []);
    if (name == #currentTill) {
      return till?.future ?? Future<TillView?>.value(_openTill);
    }
    if (name == #checkout) {
      checkoutCalls += 1;
      return checkoutGate.future;
    }
    if (name == #settleTicket) {
      settleCalls += 1;
      settledSplits = a[#splits] as List<CheckoutSplit>;
      return settleGate.future;
    }
    if (name == #orderReceiptView) return Future<ReceiptView>.value(_receipt());
    if (name == #renderReceipt) {
      return Future<Uint8List>.value(Uint8List.fromList([1, 2, 3]));
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
      final tendered = a[#tenderedMinor] as int;
      final dueCash = due + ((a[#tipIsCash] as bool) ? tip : 0);
      final allocated = (a[#splits] as List<CheckoutSplit>).fold(
        0,
        (sum, l) => sum + l.amountMinor,
      );
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
    if (name == #cashQuickTenders) return const <CashQuickTenderView>[];
    return null;
  }
}

/// A printer bound to a transport that never answers.
class _HangingPrinter extends PrinterService {
  // The service's own parameter is private; a super parameter cannot match.
  // ignore: matching_super_parameters
  _HangingPrinter(super.bridge);

  @override
  PrinterTransport? activeTransport() => _Hang();
}

class _Hang implements PrinterTransport {
  @override
  Future<void> send(Uint8List bytes) => Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Fake bridge, {
  PrinterService Function(MadarBridge)? printer,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1194, 834);
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      if (printer != null)
        printerServiceProvider.overrideWithValue(printer(bridge)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: MadarTheme.light(), home: const _Host()),
    ),
  );
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('closing Charge mid-payment is blocked, and the sale still '
      'reaches the Done flow', (tester) async {
    final bridge = _Fake();
    final container = await _mount(tester, bridge);
    final host = tester.element(find.byType(_Host));
    final pending = showCharge(
      host,
      const ChargeTarget.cart(),
      presentDoneCard: false,
    );
    await _settle(tester);
    final session = container.read(checkoutProvider.notifier)
      ..setTendered(10000);
    unawaited(session.charge());
    await tester.pump();
    expect(container.read(checkoutProvider).block, ChargeBlock.charging);

    // System back / the tablet scrim go through maybePop: refused.
    final sheet = tester.element(find.byType(ChargeSheet));
    await Navigator.of(sheet).maybePop();
    await _settle(tester);
    expect(find.byType(ChargeSheet), findsOneWidget);

    // Even a hard pop that bypasses the lock cannot lose the sale.
    Navigator.of(sheet).pop();
    await _settle(tester);
    expect(find.byType(ChargeSheet), findsNothing);

    bridge.checkoutGate.complete(_receipt());
    await _settle(tester);
    final outcome = await pending;
    expect(outcome, isNotNull, reason: 'the money was taken');
    expect(outcome!.orderKey, 'order-1');
    expect(bridge.checkoutCalls, 1);
  });

  testWidgets('a printer that never answers does not hold the sale', (
    tester,
  ) async {
    final bridge = _Fake()..checkoutGate.complete(_receipt());
    final container = await _mount(
      tester,
      bridge,
      printer: _HangingPrinter.new,
    );
    final host = tester.element(find.byType(_Host));
    final pending = showCharge(
      host,
      const ChargeTarget.cart(),
      presentDoneCard: false,
    );
    await _settle(tester);
    container.read(checkoutProvider.notifier).setTendered(10000);
    await container.read(checkoutProvider.notifier).charge();
    await _settle(tester);
    final outcome = await pending;
    expect(outcome, isNotNull);
    expect(outcome!.printState, PrintState.printing);
    // The job still resolves — as a failure once the timeout passes.
    var printed = PrintState.idle;
    unawaited(outcome.printJob!.then((s) => printed = s));
    await tester.pump(kPrintTimeout + const Duration(seconds: 1));
    expect(printed, PrintState.failed);
  });

  test(
    'a print that throws an Error (not an Exception) still answers',
    () async {
      final bridge = _Fake();
      final result = await printReceiptView(
        bridge,
        _ThrowingPrinter(bridge),
        _receipt(),
        kickDrawer: false,
      );
      expect(result, PrintState.failed);
    },
  );

  testWidgets('split amounts typed and then switched off are not sent', (
    tester,
  ) async {
    final bridge = _Fake()..settleGate.complete('order-9');
    final container = await _mount(tester, bridge);
    final session = container.read(checkoutProvider.notifier);
    final keep = container.listen(checkoutProvider, (_, _) {});
    addTearDown(keep.close);
    await session.start(const ChargeTarget.bill(_ticket, tableLabel: 'T1'));
    session
      ..toggleSplit()
      ..setSplitAmount('cash', 4000)
      ..setSplitAmount('card', 6000)
      ..toggleSplit()
      ..setTendered(10000);
    expect(container.read(checkoutProvider).splitAmounts, isEmpty);
    await session.charge();
    expect(bridge.settleCalls, 1);
    expect(bridge.settledSplits, isEmpty);
  });

  testWidgets('a bill cannot charge before the shift lookup answers', (
    tester,
  ) async {
    final bridge = _Fake()..till = Completer<TillView?>();
    final container = await _mount(tester, bridge);
    final session = container.read(checkoutProvider.notifier);
    final keep = container.listen(checkoutProvider, (_, _) {});
    addTearDown(keep.close);
    final started = session.start(
      const ChargeTarget.bill(_ticket, tableLabel: 'T1'),
    );
    await tester.pump();
    session.setTendered(10000);
    expect(container.read(checkoutProvider).block, ChargeBlock.loading);
    expect(container.read(checkoutProvider).canChargeExact, isFalse);
    await session.charge();
    expect(bridge.settleCalls, 0, reason: 'no shift id to settle against');

    bridge.till!.complete(_openTill);
    await started;
    expect(container.read(checkoutProvider).block, ChargeBlock.none);
  });

  testWidgets('the next sale inherits nothing from the last one', (
    tester,
  ) async {
    final bridge = _Fake();
    final container = await _mount(tester, bridge);
    final session = container.read(checkoutProvider.notifier);
    final keep = container.listen(checkoutProvider, (_, _) {});
    addTearDown(keep.close);
    await session.start(const ChargeTarget.cart());
    session
      ..selectMethod('card')
      ..openTip()
      ..setTip(500)
      ..toggleSplit()
      ..setSplitAmount('card', 100);
    await session.start(const ChargeTarget.cart());
    final s = container.read(checkoutProvider);
    expect(s.selectedMethodId, isNull);
    expect(s.tipMinor, 0);
    expect(s.tipOpen, isFalse);
    expect(s.splitMode, isFalse);
    expect(s.splitAmounts, isEmpty);
    expect(s.effectiveMethodId, 'cash');
  });

  testWidgets('the Done card offers Add points from the outcome alone', (
    tester,
  ) async {
    final bridge = _Fake();
    await _mount(tester, bridge);
    final host = tester.element(find.byType(_Host));
    unawaited(
      showDoneCard(
        host,
        const ChargeOutcome(
          target: ChargeTarget.cart(),
          queued: false,
          amountMinor: 10000,
          methodLabel: 'Cash',
          isCash: true,
          currency: 'EGP',
          createdAt: '2026-09-13T10:05:00Z',
          orderKey: 'order-1',
          loyaltyOffered: true,
        ),
      ),
    );
    await _settle(tester);
    expect(find.text(coreWord('loyalty.add_points')), findsOneWidget);
  });

  testWidgets('in split mode the bar still carries the tip', (tester) async {
    final bridge = _Fake();
    final container = await _mount(tester, bridge);
    final session = container.read(checkoutProvider.notifier);
    final keep = container.listen(checkoutProvider, (_, _) {});
    addTearDown(keep.close);
    await session.start(const ChargeTarget.cart());
    session
      ..openTip()
      ..setTip(1500)
      ..toggleSplit();
    expect(container.read(checkoutProvider).chargeTotalMinor, 11500);
  });
}

class _ThrowingPrinter extends PrinterService {
  // The service's own parameter is private; a super parameter cannot match.
  // ignore: matching_super_parameters
  _ThrowingPrinter(super.bridge);

  @override
  PrinterTransport? activeTransport() => throw StateError('platform channel');
}
