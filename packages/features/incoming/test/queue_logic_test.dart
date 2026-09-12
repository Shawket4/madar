// The Queue's sequencing, against a recording bridge: what Accept sends,
// in what order; that Decline restocks; that a 409 flips the card in place
// with the server's sentence; that an unreachable server keeps the last
// list. No business rules are asserted here — those are the core's — only
// that the till calls it the way the wire expects.

import 'package:app_core/app_core.dart';
import 'package:feature_incoming/feature_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

DeliveryOrderView _order(String id, String status) => DeliveryOrderView(
  id: id,
  orderRef: '#$id',
  channel: 'in_mall',
  status: status,
  customerName: 'Mona',
  customerPhone: '0100',
  subtotalMinor: 10000,
  discountMinor: 0,
  deliveryFeeMinor: 1500,
  totalMinor: 11500,
  itemCount: 1,
  lines: const [],
  createdAt: '2026-09-10T19:00:00Z',
  isTerminal: status == 'cancelled' || status == 'rejected',
);

TicketView _ticket(String id, String status, String at) => TicketView(
  id: id,
  ticketRef: id,
  status: status,
  subtotalMinor: 1000,
  openedAt: at,
  queuedOffline: false,
  lines: const [],
);

class _Recorder implements MadarBridge {
  final calls = <String>[];
  List<DeliveryOrderView> orders = [_order('d1', 'received')];
  Object? listFailure;
  Object? advanceFailure;
  Object? prepFailure;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    if (name == #tr) return args[#key] as String;
    if (name == #humanMessage) {
      final e = invocation.positionalArguments.first;
      return e is MadarError_Server ? e.detail : 'error';
    }
    if (name == #currentSession) return null;
    if (name == #listDeliveryOrders) {
      calls.add('list');
      final f = listFailure;
      if (f != null) return Future<List<DeliveryOrderView>>.error(f);
      return Future<List<DeliveryOrderView>>.value(orders);
    }
    if (name == #deliverySettings) {
      return Future<DeliverySettingsView>.value(
        const DeliverySettingsView(
          inMallEnabled: true,
          inMallOverride: 'auto',
          inMallFeeMinor: 1500,
          outsideEnabled: false,
          outsideOverride: 'auto',
          prepTimeMinutes: 20,
        ),
      );
    }
    if (name == #deliveryAdvanceStatus) {
      calls.add('advance ${args[#id]} from ${args[#current]}');
      final f = advanceFailure;
      if (f != null) return Future<DeliveryOrderView>.error(f);
      return Future<DeliveryOrderView>.value(
        _order(args[#id] as String, 'confirmed'),
      );
    }
    if (name == #deliverySetPrepTime) {
      calls.add('prep ${args[#id]} +${args[#extraMinutes]}');
      final f = prepFailure;
      if (f != null) return Future<DeliveryOrderView>.error(f);
      return Future<DeliveryOrderView>.value(
        _order(args[#id] as String, 'confirmed'),
      );
    }
    if (name == #deliveryCancel) {
      calls.add(
        'cancel ${args[#id]} reason=${args[#reason]} '
        'restock=${args[#restoreInventory]}',
      );
      return Future<DeliveryOrderView>.value(
        _order(args[#id] as String, 'rejected'),
      );
    }
    if (name == #deliveryOrderDetail) {
      calls.add('detail ${args[#id]}');
      return Future<DeliveryOrderView>.value(
        _order(args[#id] as String, 'preparing'),
      );
    }
    return null;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _Recorder bridge;
  late ProviderContainer container;

  setUp(() {
    bridge = _Recorder();
    container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
  });

  group('state', () {
    test('ready-in chips sit on the branch base, base first', () {
      const s = IncomingState(
        deliverySettings: DeliverySettingsView(
          inMallEnabled: true,
          inMallOverride: 'auto',
          inMallFeeMinor: 0,
          outsideEnabled: true,
          outsideOverride: 'auto',
          prepTimeMinutes: 20,
        ),
      );
      expect(s.prepChoices, [20, 30, 45, 60]);
      expect(const IncomingState().prepChoices, isNull);
    });

    test('bills sort kitchen-ready first, then oldest', () {
      final s = IncomingState(
        openTickets: [
          _ticket('c', 'open', '2026-09-10T19:30:00Z'),
          _ticket('a', 'open', '2026-09-10T19:00:00Z'),
          _ticket('b', 'ready', '2026-09-10T19:20:00Z'),
          _ticket('z', 'settled', '2026-09-10T18:00:00Z'),
        ],
      );
      expect(s.settleableTickets.map((t) => t.id), ['b', 'a', 'c']);
    });

    test('the badge counts what needs a human: new online + bills ready', () {
      final s = IncomingState(
        openTickets: [_ticket('a', 'open', '1'), _ticket('b', 'ready', '2')],
        deliveryOrders: [
          _order('d1', 'received'),
          _order('d2', 'received'),
          _order('d3', 'preparing'),
        ],
      );
      expect(s.queueBadge, 3);
    });
  });

  group('accept', () {
    test('a chip above the base = confirm, then the extra on top', () async {
      final n = container.read(incomingProvider.notifier);
      await n.loadDeliveryOrders();
      await n.acceptDelivery(_order('d1', 'received'), readyInMinutes: 30);
      expect(bridge.calls.where((c) => !c.startsWith('list')), [
        'advance d1 from received',
        'prep d1 +10',
      ]);
      expect(
        container.read(incomingProvider).deliveryOrders.single.status,
        'confirmed',
      );
      expect(container.read(incomingProvider).busyOrderIds, isEmpty);
    });

    test('the base chip = confirm only; extra 0 is nothing to say', () async {
      final n = container.read(incomingProvider.notifier);
      await n.loadDeliveryOrders();
      await n.acceptDelivery(_order('d1', 'received'), readyInMinutes: 20);
      expect(bridge.calls.where((c) => !c.startsWith('list')), [
        'advance d1 from received',
      ]);
    });

    test(
      'a failed prep after a landed accept pins the reason on the card',
      () async {
        bridge.prepFailure = const MadarError.server(
          status: 422,
          code: 'bad_prep',
          detail: 'Prep time must be a multiple of 5',
        );
        final n = container.read(incomingProvider.notifier);
        await n.loadDeliveryOrders();
        await n.acceptDelivery(_order('d1', 'received'), readyInMinutes: 45);
        final s = container.read(incomingProvider);
        expect(s.deliveryOrders.single.status, 'confirmed');
        expect(s.notices['d1'], 'Prep time must be a multiple of 5');
      },
    );

    test(
      "a 409 flips the card to the server's state with its sentence",
      () async {
        bridge.advanceFailure = const MadarError.server(
          status: 409,
          code: 'conflict',
          detail: 'Order already accepted on another till',
        );
        final n = container.read(incomingProvider.notifier);
        await n.loadDeliveryOrders();
        await n.acceptDelivery(_order('d1', 'received'), readyInMinutes: 20);
        final s = container.read(incomingProvider);
        expect(bridge.calls, contains('detail d1'));
        expect(s.deliveryOrders.single.status, 'preparing');
        expect(s.notices['d1'], 'Order already accepted on another till');
        // A race is not an error banner.
        expect(s.error, isNull);
      },
    );
  });

  test(
    'decline = cancel-from-received with the reason, stock restored',
    () async {
      final n = container.read(incomingProvider.notifier);
      await n.loadDeliveryOrders();
      final ok = await n.declineDelivery(
        _order('d1', 'received'),
        reason: 'out of halloumi',
      );
      expect(ok, isTrue);
      expect(
        bridge.calls,
        contains('cancel d1 reason=out of halloumi restock=true'),
      );
      // The rejected order leaves the board.
      expect(container.read(incomingProvider).deliveryOrders, isEmpty);
    },
  );

  test('unreachable = keep the last list and say it is stale', () async {
    final n = container.read(incomingProvider.notifier);
    await n.loadDeliveryOrders();
    expect(container.read(incomingProvider).deliveryOrders, hasLength(1));
    bridge.listFailure = const MadarError.offline(detail: 'no network');
    await n.loadDeliveryOrders();
    await _settle();
    final s = container.read(incomingProvider);
    expect(s.deliveryOrders, hasLength(1));
    expect(s.onlineStale, isTrue);
    expect(s.error, isNull);
  });
}
