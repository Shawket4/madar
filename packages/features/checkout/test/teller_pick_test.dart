// "Who's serving?" — the gate at the top of the Charge sheet, on a branch that
// asks (`pick_teller_at_checkout`). The core decides who is listed and how
// (Focused / All) and refuses a sale without the person; the sheet's job is
// the lock: no tender until someone is picked, every caller, every
// container. A branch that does not ask sees the sheet exactly as before.

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
  userId: 'u-sara',
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
  tellerId: 'u-sara',
  tellerName: 'Sara',
  openingCashMinor: 0,
  openedAt: '2026-10-30T09:00:00Z',
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
  openedAt: '2026-10-30T10:00:00Z',
  queuedOffline: false,
  lines: [],
);

const _online = DeliveryOrderView(
  id: 'd-118',
  orderRef: '#D-118',
  channel: 'outside',
  status: 'ready',
  customerName: 'Nour Hassan',
  customerPhone: '0122 333 4455',
  subtotalMinor: 10000,
  discountMinor: 0,
  deliveryFeeMinor: 0,
  totalMinor: 10000,
  itemCount: 1,
  lines: [],
  createdAt: '2026-10-30T09:40:00Z',
  extraPrepMinutes: 0,
  isTerminal: false,
  contactOverride: false,
);

const _mona = PickPerson(
  userId: 'u-mona',
  name: 'Mona',
  onShiftSince: '2026-10-30T07:58:00Z',
);
const _karim = PickPerson(
  userId: 'u-karim',
  name: 'Karim',
  onShiftSince: '2026-10-30T08:02:00Z',
);
const _aya = PickPerson(userId: 'u-aya', name: 'Aya');
const _sara = PickPerson(userId: 'u-sara', name: 'Sara');

/// Karim and Mona clocked in; Aya and Sara behind More.
const _focused = TellerPick(
  required_: true,
  mode: PickMode.focused,
  primary: [_karim, _mona],
  more: [_aya, _sara],
);

/// No good Dawam data: everyone at once.
const _all = TellerPick(
  required_: true,
  mode: PickMode.all,
  primary: [_aya, _karim, _mona, _sara],
  more: [],
);

ReceiptView _receipt() => const ReceiptView(
  deals: [],
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
  createdAt: '2026-10-30T10:05:00Z',
  payments: [],
  displayNumber: '',
  serviceChargeWaivedMinor: 0,
  taxInclusive: false,
  taxRate: 0,
);

class _Fake implements MadarBridge {
  _Fake(this.pick);

  final TellerPick pick;

  /// Every money call, with the person it named.
  final List<(Symbol, String?)> charged = [];
  CheckoutInput? lastInput;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final picked = fakeTellerPickInvocation(invocation, pick);
    if (picked != null) return picked;
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #tr) return coreWord(a[#key] as String);
    if (name == #canWaiveServiceCharge) return false;
    if (name == #cartRewardLines || name == #ticketRewardLines) {
      return const <RewardLineInput>[];
    }
    if (name == #isRtl) return false;
    if (name == #locale) return 'en';
    if (name == #currentSession) return _session;
    if (name == #appRoute) return AppRoute.order;
    if (name == #deviceConfig) {
      return const DeviceConfigView(
        branchName: 'Rue',
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #orgLogoLocalPath) return null;
    if (name == #receiptFooter) return 'Thank you!';
    if (name == #availablePaymentMethods) {
      return Future<List<PaymentMethodView>>.value(_methods);
    }
    if (name == #listDiscounts) {
      return Future<List<DiscountView>>.value(const []);
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
    if (name == #cartDiscount) {
      return Future<CartDiscountView>.value(
        const CartDiscountView(kind: '', offMinor: 0),
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
    if (name == #ownOpenTill) return _openTill;
    if (name == #currentTill) return Future<TillView?>.value(_openTill);
    if (name == #checkout) {
      lastInput = a[#input] as CheckoutInput;
      charged.add((name, lastInput!.soldBy));
      return Future<ReceiptView>.value(_receipt());
    }
    if (name == #settleTicket) {
      charged.add((name, a[#soldBy] as String?));
      return Future<String?>.value('order-9');
    }
    if (name == #deliveryFinalize) {
      charged.add((name, a[#soldBy] as String?));
      return Future<DeliveryFinalizeView>.value(
        const DeliveryFinalizeView(orderId: 'order-7', warnings: []),
      );
    }
    if (name == #orderReceiptView) return Future<ReceiptView>.value(_receipt());
    if (name == #splitRestHere) {
      final legs = a[#legs] as List<CheckoutSplit>;
      final sum = legs.fold(0, (x, l) => x + l.amountMinor);
      final own = legs
          .where((l) => l.paymentMethodId == a[#target])
          .fold(0, (x, l) => x + l.amountMinor);
      final rest = own + (a[#dueMinor] as int) - sum;
      return rest < 0 ? 0 : rest;
    }
    if (name == #splitAutoFill) return null;
    if (name == #tenderSummary) {
      final due = a[#dueMinor] as int;
      final tip = a[#tipMinor] as int;
      final tendered = a[#tenderedMinor] as int;
      final allocated = (a[#splits] as List<CheckoutSplit>).fold(
        0,
        (sum, l) => sum + l.amountMinor,
      );
      return TenderSummaryView(
        chargeTotalMinor: due + tip,
        dueCashMinor: due,
        changeMinor: tendered > due ? tendered - due : 0,
        shortMinor: due > tendered ? due - tendered : 0,
        splitAllocatedMinor: allocated,
        splitRemainingMinor: due - allocated,
        dueLabelKey: 'order.total',
        dueIsSubtotal: false,
        showsChange: true,
      );
    }
    if (name == #cashQuickTenders) return const <CashQuickTenderView>[];
    if (name == #formatMoney) return '${a[#minor]}';
    if (name == #decideBillDiscount) {
      return const ActDecisionView(outcome: 'allow', reason: '');
    }
    return null;
  }
}

class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

Future<ProviderContainer> _mount(WidgetTester tester, _Fake bridge) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1194, 834);
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [bridgeProvider.overrideWithValue(bridge)],
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

/// Open Charge for [target] and let its session load; the record holds
/// what `showCharge` will resolve with.
Future<(Future<ChargeOutcome?>,)> _open(
  WidgetTester tester,
  ChargeTarget target,
) async {
  final host = tester.element(find.byType(_Host));
  final pending = showCharge(host, target, presentDoneCard: false);
  await _settle(tester);
  return (pending,);
}

Finder _tile(PickPerson p) => find.byKey(ValueKey('teller-pick-${p.userId}'));

bool _selected(WidgetTester tester, PickPerson p) =>
    tester.widget<Semantics>(_tile(p)).properties.selected ?? false;

/// Tap [f] where it is — scrolled into view first. A locked control is
/// still on the screen, and the tap must not reach it: no hit-test warning.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f, warnIfMissed: false);
  await _settle(tester);
}

final Finder _bar = find.byType(MadarMoneyBar);
final Finder _hint = find.text(coreWord('charge.pick_hint'));
final Finder _title = find.text(coreWord('charge.who_serving'));

void main() {
  testWidgets('a branch that does not ask sees the sheet exactly as before', (
    tester,
  ) async {
    final bridge = _Fake(kTellerPickOff);
    final container = await _mount(tester, bridge);
    await _open(tester, const ChargeTarget.cart());
    expect(_title, findsNothing);
    expect(_hint, findsNothing);
    expect(find.text(coreWord('charge.on_shift_now')), findsNothing);
    // Exact charges at once, naming nobody.
    await _tap(tester, find.text('Cash'));
    expect(container.read(checkoutProvider).selectedMethodId, 'cash');
    await _tap(tester, find.text(coreWord('order.exact')));
    expect(bridge.charged, [(#checkout, null)]);
  });

  group('the tender stays locked until someone is picked', () {
    testWidgets('cart: methods, Exact and the bar', (tester) async {
      final bridge = _Fake(_all);
      final container = await _mount(tester, bridge);
      await _open(tester, const ChargeTarget.cart());
      expect(_title, findsOneWidget);
      expect(_hint, findsOneWidget);
      // The total is still on the screen while the tender is locked: the
      // hero, and the bar shows its figure rather than a reason.
      expect(find.byType(AnimatedMoneyText), findsWidgets);
      final bar = tester.widget<MadarMoneyBar>(_bar);
      expect((bar.enabled, bar.reason, bar.amountMinor), (false, null, 10000));

      await _tap(tester, find.text('Cash'));
      expect(container.read(checkoutProvider).selectedMethodId, isNull);
      // Even with cash in hand (a tender the sheet already held), neither
      // Exact nor the bar takes the money.
      container.read(checkoutProvider.notifier)
        ..selectMethod('cash')
        ..setTendered(10000);
      await _settle(tester);
      expect(container.read(checkoutProvider).block, ChargeBlock.none);
      expect(find.text(coreWord('order.exact')), findsOneWidget);
      await _tap(tester, find.text(coreWord('order.exact')));
      await _tap(tester, _bar);
      expect(bridge.charged, isEmpty, reason: 'no tender before a person');
      expect(tester.widget<MadarMoneyBar>(_bar).enabled, isFalse);

      // Nothing is preselected; one tap picks.
      for (final p in _all.primary) {
        expect(_selected(tester, p), isFalse);
      }
      await _tap(tester, _tile(_mona));
      expect(_selected(tester, _mona), isTrue);
      expect(_hint, findsNothing);
      // Tapping someone else changes the pick.
      await _tap(tester, _tile(_karim));
      expect(_selected(tester, _karim), isTrue);
      expect(_selected(tester, _mona), isFalse);

      await _tap(tester, find.text(coreWord('order.exact')));
      expect(bridge.charged, [(#checkout, 'u-karim')]);
    });

    testWidgets('cart: split', (tester) async {
      final bridge = _Fake(_all);
      final container = await _mount(tester, bridge);
      await _open(tester, const ChargeTarget.cart());
      await _tap(tester, find.text(coreWord('order.split_payment')));
      expect(container.read(checkoutProvider).splitMode, isFalse);

      await _tap(tester, _tile(_aya));
      await _tap(tester, find.text(coreWord('order.split_payment')));
      expect(container.read(checkoutProvider).splitMode, isTrue);
      container.read(checkoutProvider.notifier)
        ..setSplitAmount('cash', 4000)
        ..setSplitAmount('card', 6000);
      await _settle(tester);
      await _tap(tester, _bar);
      expect(bridge.charged, [(#checkout, 'u-aya')]);
      expect(bridge.lastInput!.splits, hasLength(2));
    });

    testWidgets('bill settle', (tester) async {
      final bridge = _Fake(_all);
      final container = await _mount(tester, bridge);
      await _open(tester, const ChargeTarget.bill(_ticket, tableLabel: 'T1'));
      expect(_title, findsOneWidget);
      await _tap(tester, find.text('Card'));
      await _tap(tester, _bar);
      expect(bridge.charged, isEmpty);
      expect(container.read(checkoutProvider).selectedMethodId, isNull);

      await _tap(tester, _tile(_sara));
      await _tap(tester, find.text('Card'));
      await _tap(tester, _bar);
      expect(bridge.charged, [(#settleTicket, 'u-sara')]);
    });

    testWidgets('an online order charged at the till', (tester) async {
      final bridge = _Fake(_all);
      final container = await _mount(tester, bridge);
      await _open(tester, const ChargeTarget.online(_online));
      expect(_title, findsOneWidget);
      await _tap(tester, find.text('Card'));
      await _tap(tester, _bar);
      expect(bridge.charged, isEmpty);
      expect(container.read(checkoutProvider).selectedMethodId, isNull);

      await _tap(tester, _tile(_mona));
      await _tap(tester, find.text('Card'));
      await _tap(tester, _bar);
      expect(bridge.charged, [(#deliveryFinalize, 'u-mona')]);
    });
  });

  testWidgets('Focused: the people on shift, and More reveals the rest', (
    tester,
  ) async {
    final bridge = _Fake(_focused);
    await _mount(tester, bridge);
    await _open(tester, const ChargeTarget.cart());
    expect(find.text(coreWord('charge.on_shift_now')), findsOneWidget);
    expect(_tile(_karim), findsOneWidget);
    expect(_tile(_mona), findsOneWidget);
    expect(_tile(_aya), findsNothing);
    expect(_tile(_sara), findsNothing);
    final more = find.text(
      coreWord('charge.pick_more').replaceAll('{count}', '2'),
    );
    expect(more, findsOneWidget);

    await _tap(tester, more);
    expect(_tile(_aya), findsOneWidget);
    expect(_tile(_sara), findsOneWidget);
    expect(find.text(coreWord('charge.pick_fewer')), findsOneWidget);
    // Someone from the rest can be picked like anyone else.
    await _tap(tester, _tile(_sara));
    expect(_selected(tester, _sara), isTrue);

    await _tap(tester, find.text(coreWord('charge.pick_fewer')));
    expect(_tile(_aya), findsNothing);
    expect(more, findsOneWidget);
  });

  testWidgets('All: everyone at once, no More', (tester) async {
    final bridge = _Fake(_all);
    await _mount(tester, bridge);
    await _open(tester, const ChargeTarget.cart());
    for (final p in _all.primary) {
      expect(_tile(p), findsOneWidget);
    }
    expect(find.text(coreWord('charge.on_shift_now')), findsNothing);
    expect(find.text(coreWord('charge.pick_fewer')), findsNothing);
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('the pick is never carried into the next opening', (
    tester,
  ) async {
    final bridge = _Fake(_all);
    await _mount(tester, bridge);
    final (first,) = await _open(tester, const ChargeTarget.cart());
    await _tap(tester, _tile(_mona));
    expect(_selected(tester, _mona), isTrue);
    await Navigator.of(tester.element(find.byType(ChargeSheet))).maybePop();
    await _settle(tester);
    expect(await first, isNull, reason: 'closed without charging');

    await _open(tester, const ChargeTarget.cart());
    expect(_selected(tester, _mona), isFalse);
    expect(_hint, findsOneWidget);
  });
}
