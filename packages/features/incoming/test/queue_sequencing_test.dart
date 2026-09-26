// The Queue's reads land in order, and its banner does not outlive its cause.
//
// A slow online pull that began before an Accept used to land after it and
// put the card back to "received" with Accept live again; a failure on one
// segment stayed on screen for the other, forever.

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:feature_incoming/feature_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

DeliveryOrderView _order(String status) => DeliveryOrderView(
  id: 'd-1',
  orderRef: '#D-1',
  channel: 'outside',
  status: status,
  customerName: 'Nour',
  customerPhone: '0100',
  subtotalMinor: 1000,
  discountMinor: 0,
  deliveryFeeMinor: 0,
  totalMinor: 1000,
  itemCount: 1,
  lines: const [],
  createdAt: '2026-09-13T10:00:00Z',
  extraPrepMinutes: 0,
  isTerminal: false,
  contactOverride: false,
);

class _Fake implements MadarBridge {
  final List<Completer<List<DeliveryOrderView>>> reads = [];
  bool failReads = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    if (name == #tr || name == #trChecked) {
      return coreWord(invocation.namedArguments[#key] as String? ?? '');
    }
    if (name == #humanMessage) return 'refused';
    if (name == #currentSession) return null;
    if (name == #listDeliveryOrders) {
      if (failReads) {
        return Future<List<DeliveryOrderView>>.error(
          const MadarError.server(status: 500, code: 'boom', detail: 'boom'),
        );
      }
      final c = Completer<List<DeliveryOrderView>>();
      reads.add(c);
      return c.future;
    }
    if (name == #deliverySettings) {
      return Future<Never>.error(const MadarError.offline(detail: 'no'));
    }
    if (name == #deliverySetStatus) {
      return Future<DeliveryOrderView>.value(_order('confirmed'));
    }
    return null;
  }
}

void main() {
  test('a pull that began before an Accept cannot undo it', () async {
    final bridge = _Fake();
    final c = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(c.dispose);
    final queue = c.read(incomingProvider.notifier);

    // A board with one new order.
    final seed = queue.loadDeliveryOrders();
    bridge.reads.single.complete([_order('received')]);
    await seed;

    // A pull starts, then the teller accepts while it is still out.
    final slow = queue.loadDeliveryOrders();
    await queue.acceptDelivery(_order('received'));
    expect(c.read(incomingProvider).deliveryOrders.single.status, 'confirmed');

    // The stale answer lands last: it must not put the card back.
    bridge.reads.last.complete([_order('received')]);
    await slow;
    expect(c.read(incomingProvider).deliveryOrders.single.status, 'confirmed');
    expect(c.read(incomingProvider).isLoadingDelivery, isFalse);
  });

  test(
    'a failure clears on the next good read and on a segment switch',
    () async {
      final bridge = _Fake()..failReads = true;
      final c = ProviderContainer(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
      );
      addTearDown(c.dispose);
      final queue = c.read(incomingProvider.notifier);

      await queue.loadDeliveryOrders();
      expect(c.read(incomingProvider).error, isNotNull);
      queue.setSegment(QueueSegment.bills);
      expect(c.read(incomingProvider).error, isNull);

      await queue.loadDeliveryOrders();
      expect(c.read(incomingProvider).error, isNotNull);
      bridge.failReads = false;
      final ok = queue.loadDeliveryOrders();
      bridge.reads.single.complete([_order('received')]);
      await ok;
      expect(c.read(incomingProvider).error, isNull);
    },
  );
}
