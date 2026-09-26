// An online order's step button: blocking, idempotent, and it resolves once.
//
// The owner watched it jitter: tap "Start preparing", a spinner, then "Mark
// ready", then "Start preparing" again, then "Mark ready". The step's own
// realtime event ticked the board at once, and the board re-read the order's
// row before the pull that event nudged had brought the new step: the core
// never wrote the server's answer into the row. It does now (core test
// `an_answer_to_our_own_write_folds_into_the_row_and_the_feed_still_wins`);
// the fake below keeps that contract — a step's answer lands in its rows —
// and these tests pin the Queue's half:
//
// - a double tap sends ONE step, naming its TARGET, never "next";
// - the button spins, steady, until the answer, then shows the new step's
//   words once — no frame in between shows the old words;
// - a read that lands during the step, or one that began during it and
//   lands after, does not flip the card back;
// - a pickup order walks no steps: once accepted, Charge is its one act;
// - a delivery order still walks each of its steps.

import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_incoming/feature_incoming.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// A phone: one step button per row, no pane repeating it.
const Size _phone = Size(390, 844);

DeliveryOrderView _order(
  String status, {
  String id = 'd-1',
  String channel = 'outside',
}) => DeliveryOrderView(
  id: id,
  orderRef: '#${id.toUpperCase()}',
  channel: channel,
  status: status,
  customerName: 'Nour',
  customerPhone: '0100 000 0000',
  subtotalMinor: 5500,
  discountMinor: 0,
  deliveryFeeMinor: 0,
  totalMinor: 5500,
  itemCount: 1,
  lines: const [],
  createdAt: '2026-09-26T10:00:00Z',
  extraPrepMinutes: 0,
  isTerminal: false,
  contactOverride: false,
);

const _session = SessionSnapshot(
  userId: 'u',
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

const _till = TillView(
  id: 'sh-1',
  branchId: 'b',
  tellerId: 'u',
  tellerName: 'Sara',
  openingCashMinor: 0,
  openedAt: '2026-09-26T08:00:00Z',
  status: 'open',
  isOpen: true,
  verification: 'server',
  openedWhileAnotherOpen: false,
);

/// The core as the Queue sees it. [rows] are the device's local rows (what
/// `listDeliveryOrders` answers); a step's answer is released by the test
/// and, like the core's fold, lands in [rows] as it is answered.
class _Fake implements MadarBridge {
  _Fake(this.rows, {this.arabic = false});

  List<DeliveryOrderView> rows;
  final bool arabic;

  /// Every status change asked of the server: `(order id, target)`.
  final List<(String, String)> steps = [];

  /// The pending answer to the last step; the test completes it.
  Completer<DeliveryOrderView>? stepGate;

  /// When set, a read waits for the test instead of answering at once.
  Completer<List<DeliveryOrderView>>? readGate;

  /// What the charge drawer priced as due, each time it did: it opened.
  final List<int> drawerDue = [];

  void _fold(DeliveryOrderView answer) => rows = [
    for (final o in rows)
      if (o.id == answer.id) answer else o,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => _session.role);
    if (can != null) return can;
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #tr || name == #trChecked) {
      return coreWord(a[#key] as String? ?? '', arabic: arabic);
    }
    if (name == #humanMessage) return 'refused';
    if (name == #isRtl) return arabic;
    if (name == #locale) return arabic ? 'ar' : 'en';
    if (name == #currentSession) return _session;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #listDeliveryOrders) {
      final gate = readGate;
      if (gate != null) return gate.future;
      return Future<List<DeliveryOrderView>>.value(rows);
    }
    if (name == #deliverySetStatus) {
      final id = a[#id] as String;
      final status = a[#status] as String;
      steps.add((id, status));
      final gate = stepGate = Completer<DeliveryOrderView>();
      return gate.future.then((answer) {
        _fold(answer);
        return answer;
      });
    }
    if (name == #deliveryAdvanceStatus) {
      fail('a step names its target; "advance from current" was called');
    }
    if (name == #deliverySettings) {
      return Future<DeliverySettingsView>.value(
        const DeliverySettingsView(
          inMallEnabled: false,
          inMallOverride: 'auto',
          inMallFeeMinor: 0,
          outsideEnabled: true,
          outsideOverride: 'auto',
          prepTimeMinutes: 15,
        ),
      );
    }
    if (name == #listOpenTickets) {
      return Future<List<TicketView>>.value(const []);
    }
    if (name == #floorLayout) {
      return Future<FloorLayoutView>.value(
        const FloorLayoutView(sections: [], tables: []),
      );
    }
    if (name == #ownOpenTill) return _till;
    if (name == #currentTill) return Future<TillView?>.value(_till);
    if (name == #formatTime) return '10:00';
    if (name == #formatElapsedSince) return '1m';
    if (name == #kitchenRoutingMode) return Future<String?>.value();
    if (name == #refreshConnectivity) return Future<bool>.value(true);
    if (name == #isRealtimeSubscribed) return true;
    if (name == #clockSkewMinutes) return 0;
    if (name == #listOutbox) {
      return Future<List<OutboxItemView>>.value(const []);
    }
    // What the charge drawer reads as it opens.
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
    if (name == #deviceConfig) {
      return const DeviceConfigView(
        branchName: 'Rue',
        reconfiguring: false,
        configured: true,
      );
    }
    if (name == #canWaiveServiceCharge) return false;
    if (name == #cartRewardLines || name == #ticketRewardLines) {
      return const <RewardLineInput>[];
    }
    if (name == #orgLogoLocalPath) return null;
    if (name == #listDiscounts) {
      return Future<List<DiscountView>>.value(const []);
    }
    if (name == #availablePaymentMethods) {
      return Future<List<PaymentMethodView>>.value(const []);
    }
    // The charge drawer pricing what is due: it opened, over that sum.
    if (name == #tenderSummary) {
      final due = a[#dueMinor] as int;
      drawerDue.add(due);
      return TenderSummaryView(
        chargeTotalMinor: due,
        dueCashMinor: due,
        changeMinor: 0,
        shortMinor: 0,
        splitAllocatedMinor: 0,
        splitRemainingMinor: due,
        dueLabelKey: 'charge.due',
        dueIsSubtotal: false,
        showsChange: false,
      );
    }
    return null;
  }
}

/// Realtime "connected", so the fallback poll never starts a timer.
class _Connected extends ConnectedNotifier {
  @override
  bool build() => true;
}

Future<void> _pumpQueue(WidgetTester tester, _Fake bridge) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _phone;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bridgeProvider.overrideWithValue(bridge),
        realtimeConnectedProvider.overrideWith(_Connected.new),
      ],
      child: MaterialApp(
        theme: MadarTheme.light(),
        locale: Locale(bridge.arabic ? 'ar' : 'en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Directionality(
          textDirection: bridge.arabic ? TextDirection.rtl : TextDirection.ltr,
          child: const QueueScreen(initialSegment: QueueSegment.online),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// Lands the reads without waiting on a spinner that never stops.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A realtime tick for the delivery table, as the core's watcher sends it.
void _tick(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(QueueScreen)),
).read(deliveryTickProvider.notifier).bump();

Finder _button(String label) => find.widgetWithText(MadarButton, label);

Finder get _spinner => find.descendant(
  of: find.byType(MadarButton),
  matching: find.byType(CircularProgressIndicator),
);

String _w(String key, bool arabic) => coreWord(key, arabic: arabic);

/// The design system's Plex faces, as the render tests load them: the
/// binding's block font is far wider and would overflow the phone's rows.
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

void main() {
  setUpAll(_loadFonts);

  for (final arabic in [false, true]) {
    final lang = arabic ? 'AR' : 'EN';
    final startPreparing = _w('delivery.action.preparing', arabic);
    final markReady = _w('delivery.action.ready', arabic);
    final outForDelivery = _w('delivery.action.out_for_delivery', arabic);
    final charge = _w('queue.charge', arabic);
    final accept = _w('queue.accept', arabic);

    testWidgets('$lang: a double tap sends ONE step, to its target, and the '
        'button spins steady until the answer, then shows the new words once', (
      tester,
    ) async {
      final bridge = _Fake([_order('confirmed')], arabic: arabic);
      await _pumpQueue(tester, bridge);
      expect(_button(startPreparing), findsOneWidget);

      // Two taps before a frame can draw the spinner, and one on it.
      await tester.tap(_button(startPreparing));
      await tester.tap(_button(startPreparing), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byType(MadarButton).last, warnIfMissed: false);
      expect(bridge.steps, [('d-1', 'preparing')]);

      // In flight: one spinner, neither label, frame after frame — and a
      // realtime tick re-reading the (not yet answered) rows changes nothing.
      for (var frame = 0; frame < 30; frame++) {
        if (frame == 10) _tick(tester);
        await tester.pump(const Duration(milliseconds: 16));
        expect(_spinner, findsOneWidget, reason: 'frame $frame');
        expect(find.text(startPreparing), findsNothing, reason: '$frame');
        expect(find.text(markReady), findsNothing, reason: 'frame $frame');
      }

      // The answer: the new words, in the very next frame, and they stay
      // through the tick the step itself sets off.
      bridge.stepGate!.complete(_order('preparing'));
      await tester.pump();
      expect(_spinner, findsNothing);
      expect(_button(markReady), findsOneWidget);
      _tick(tester);
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text(startPreparing), findsNothing, reason: '$frame');
        expect(_button(markReady), findsOneWidget, reason: 'frame $frame');
      }
      expect(bridge.steps, hasLength(1));
    });

    testWidgets('$lang: a read that began mid-step and lands after it does '
        'not flip the card back', (tester) async {
      final bridge = _Fake([_order('preparing')], arabic: arabic);
      await _pumpQueue(tester, bridge);
      await tester.tap(_button(markReady));
      await tester.pump();

      // A tick while the step is out: its read is slow, and carries the
      // order as it was before the step.
      final slow = bridge.readGate = Completer<List<DeliveryOrderView>>();
      _tick(tester);
      await tester.pump();
      bridge.readGate = null;

      bridge.stepGate!.complete(_order('ready'));
      await tester.pump();
      expect(_button(outForDelivery), findsOneWidget);

      slow.complete([_order('preparing')]);
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text(markReady), findsNothing, reason: 'frame $frame');
        expect(_button(outForDelivery), findsOneWidget, reason: '$frame');
      }
    });

    testWidgets('$lang: a read that lands DURING the step leaves the card '
        'as the teller saw it', (tester) async {
      final bridge = _Fake([_order('confirmed')], arabic: arabic);
      await _pumpQueue(tester, bridge);
      await tester.tap(_button(startPreparing));
      await tester.pump();

      // Another till's change reaches the rows while ours is out.
      bridge.rows = [_order('ready')];
      _tick(tester);
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_spinner, findsOneWidget, reason: 'frame $frame');
        expect(find.text(outForDelivery), findsNothing, reason: '$frame');
      }
      bridge.stepGate!.complete(_order('preparing'));
      await tester.pump();
      expect(_button(markReady), findsOneWidget);
    });

    testWidgets('$lang: a pickup order walks no steps — once accepted, '
        'Charge is its one act, and one tap takes it there', (tester) async {
      final bridge = _Fake([
        _order('received', id: 'p-new', channel: 'pickup'),
        _order('confirmed', id: 'p-1', channel: 'pickup'),
      ], arabic: arabic);
      await _pumpQueue(tester, bridge);

      // The new one is still the shop's to accept (or decline).
      expect(_button(accept), findsOneWidget);
      // The accepted one offers Charge, and no step at all.
      expect(_button(charge), findsOneWidget);
      for (final step in [startPreparing, markReady, outForDelivery]) {
        expect(find.text(step), findsNothing, reason: step);
      }
      expect(find.text(_w('queue.picked_up', arabic)), findsNothing);

      await tester.tap(_button(charge));
      await _settle(tester);
      expect(bridge.steps, isEmpty, reason: 'no status step on the way');
      expect(bridge.drawerDue, isNotEmpty, reason: 'the charge drawer opened');
    });

    for (final status in ['preparing', 'ready']) {
      testWidgets('$lang: a pickup order already $status also goes straight '
          'to Charge', (tester) async {
        final bridge = _Fake([
          _order(status, channel: 'pickup'),
        ], arabic: arabic);
        await _pumpQueue(tester, bridge);
        expect(_button(charge), findsOneWidget);
        expect(find.text(markReady), findsNothing);
        expect(find.text(outForDelivery), findsNothing);
      });
    }

    testWidgets('$lang: a delivery order still walks each of its steps', (
      tester,
    ) async {
      final bridge = _Fake([_order('confirmed')], arabic: arabic);
      await _pumpQueue(tester, bridge);
      for (final (from, to, next) in [
        (startPreparing, 'preparing', markReady),
        (markReady, 'ready', outForDelivery),
        (outForDelivery, 'out_for_delivery', charge),
      ]) {
        await tester.tap(_button(from));
        await tester.pump();
        expect(bridge.steps.last, ('d-1', to));
        bridge.stepGate!.complete(_order(to));
        await tester.pump();
        expect(_button(next), findsOneWidget, reason: 'after $to');
      }
      expect(bridge.steps.map((s) => s.$2), [
        'preparing',
        'ready',
        'out_for_delivery',
      ]);
    });
  }

  test('the notifier drops a second step and a second accept while one '
      'is out, and names the target', () async {
    final bridge = _Fake([_order('received'), _order('confirmed', id: 'd-2')]);
    final c = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(c.dispose);
    final queue = c.read(incomingProvider.notifier);
    await queue.loadDeliveryOrders();

    final first = queue.acceptDelivery(_order('received'));
    final second = queue.acceptDelivery(_order('received'));
    await second;
    expect(bridge.steps, [('d-1', 'confirmed')]);
    bridge.stepGate!.complete(_order('confirmed'));
    await first;

    final a = queue.stepDelivery(
      _order('confirmed', id: 'd-2'),
      to: 'preparing',
    );
    final b = queue.stepDelivery(
      _order('confirmed', id: 'd-2'),
      to: 'preparing',
    );
    await b;
    expect(bridge.steps.last, ('d-2', 'preparing'));
    expect(bridge.steps, hasLength(2));
    bridge.stepGate!.complete(_order('preparing', id: 'd-2'));
    await a;
    expect(
      c.read(incomingProvider).deliveryOrders.map((o) => o.status),
      containsAll(['confirmed', 'preparing']),
    );
  });

  test('a race that left the order where the step was taking it is a '
      'success, with nothing to say', () async {
    final bridge = _RaceFake([_order('confirmed')]);
    final c = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(c.dispose);
    final queue = c.read(incomingProvider.notifier);
    await queue.loadDeliveryOrders();

    await queue.stepDelivery(_order('confirmed'), to: 'preparing');
    final s = c.read(incomingProvider);
    expect(s.deliveryOrders.single.status, 'preparing');
    expect(s.notices, isEmpty);
    expect(s.error, isNull);
  });
}

/// Another till moved the order to the same step a moment earlier: the
/// server refuses ours (409) and the order is where ours was taking it.
class _RaceFake extends _Fake {
  _RaceFake(super.rows);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #deliverySetStatus) {
      rows = [_order('preparing')];
      return Future<DeliveryOrderView>.error(
        const MadarError.server(
          status: 409,
          code: 'conflict',
          detail: 'Order changed to preparing while you were working',
        ),
      );
    }
    if (name == #deliveryOrderDetail) {
      return Future<DeliveryOrderView>.value(rows.single);
    }
    return super.noSuchMethod(invocation);
  }
}
