// The Free plan has the floor (bills) but no online orders and no kitchen:
// the delivery feed makes no read at all (the boot-time load was one),
// and a paid plan reads exactly what it always did. The plan is the core's
// answer (`entitlements()`); an unknown one is Paid.

import 'package:app_core/app_core.dart';
import 'package:feature_incoming/feature_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Fake implements MadarBridge {
  _Fake(this.plan);

  final EntitlementsView plan;
  final List<Symbol> calls = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #entitlements) return plan;
    calls.add(name);
    if (name == #listDeliveryOrders) {
      return Future<List<DeliveryOrderView>>.value(const []);
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
    return super.noSuchMethod(invocation);
  }
}

EntitlementsView _free() => const EntitlementsView(
  plan: 'free',
  features: ['floor'],
  realtime: false,
  maxBranches: 1,
  maxPosDevicesPerBranch: 1,
  maxKdsDevices: 0,
  maxWaiterDevices: 0,
  tillInactive: false,
);

void main() {
  test(
    'a Free till reads bills and floor labels but no delivery orders',
    () async {
      final bridge = _Fake(_free());
      final c = ProviderContainer(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
      );
      addTearDown(c.dispose);
      final queue = c.read(incomingProvider.notifier);
      await queue.loadDeliveryOrders();
      await queue.loadOpenTickets();
      await queue.loadFloorLabels();
      expect(bridge.calls, [#listOpenTickets, #floorLayout]);
      final s = c.read(incomingProvider);
      expect(s.deliveryOrders, isEmpty);
      expect(s.ticketsLoaded, isTrue);
    },
  );

  test('a paid till reads all three, as it always did', () async {
    final bridge = _Fake(paidEntitlements);
    final c = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(c.dispose);
    final queue = c.read(incomingProvider.notifier);
    await queue.loadDeliveryOrders();
    await queue.loadOpenTickets();
    await queue.loadFloorLabels();
    expect(
      bridge.calls,
      containsAll([#listDeliveryOrders, #listOpenTickets, #floorLayout]),
    );
  });

  test('a core that cannot answer is Paid: nothing is hidden', () {
    final c = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(_Unanswering())],
    );
    addTearDown(c.dispose);
    final e = c.read(entitlementsProvider);
    expect(e.plan, 'paid');
    for (final f in [
      PlanFeature.floor,
      PlanFeature.online,
      PlanFeature.kitchen,
      PlanFeature.inventory,
    ]) {
      expect(e.has(f), isTrue, reason: f);
    }
    expect(e.tillInactive, isFalse);
  });

  test('Free has the floor only; an unknown key is allowed', () {
    final e = _free();
    expect(e.has(PlanFeature.floor), isTrue);
    expect(e.has(PlanFeature.online), isFalse);
    expect(e.has(PlanFeature.kitchen), isFalse);
    expect(e.has('a_feature_from_the_future'), isTrue);
  });
}

class _Unanswering implements MadarBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
