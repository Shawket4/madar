// The network rule, on the Dart side: provider ticks, pulses and table
// changes re-read the core's LOCAL rows and never call a bridge method that
// can reach the server. (The core side is `madar-core/tests/network_budget.rs`
// and the unit tests in `offline_b_tests.rs`.)
//
// A fake bridge counts every call. The screens' providers are kept alive while
// every tick the app fires (drawer, ticket, kitchen, delivery, floor, booking,
// sync, the connectivity pulse) is bumped many times — the realtime / table
// watcher storm an online idle device sees. Afterwards no method that may
// touch the network has been called by a tick: those run only from a person's
// action (search, a loyalty scan, a manual sync) or the ConnectivityService.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:feature_history/feature_history.dart';
import 'package:feature_incoming/feature_incoming.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Bridge methods whose core implementation may use the network. Every other
/// read answers from the device's rows.
const _networkCapable = <Symbol>{
  #refreshConnectivity,
  #probeConnectivity,
  #syncNow,
  #syncFull,
  #refreshCatalog,
  #searchOrders,
  #loyaltyLookup,
  #loyaltyLookupPhone,
  #tableHistory,
  #deliveryOrderDetail,
  #deliverySetAccepting,
  #setKitchenRoutingMode,
  #forceCloseTill,
  #retryOutbox,
  #listBranches,
  #branchSales,
  #branchSalesTimeseries,
};

const _till = TillView(
  id: 'sh-1',
  branchId: 'br-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: 1000,
  openedAt: '2026-09-12T15:02:00Z',
  status: 'open',
  isOpen: true,
  verification: 'server',
  openedWhileAnotherOpen: false,
);

class _CountingBridge implements MadarBridge {
  final Map<Symbol, int> calls = {};

  int networkCalls() => calls.entries
      .where((e) => _networkCapable.contains(e.key))
      .fold(0, (a, e) => a + e.value);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    calls[name] = (calls[name] ?? 0) + 1;
    final args = invocation.namedArguments;
    if (name == #tr) return args[#key];
    if (name == #appRoute) return const AppRoute.order();
    if (name == #currentSession) {
      return const SessionSnapshot(
        userId: 'u-1',
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
    }
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #syncStatus) {
      return SyncStatusView(
        pendingOutbox: 0,
        deadOutbox: 0,
        blocked: 0,
        freshness: const FreshnessView(state: 'fresh'),
        online: true,
        authPaused: false,
        phase: 'idle',
        assets: AssetSyncView(
          needed: 0,
          missing: 0,
          downloading: false,
          bytesDone: BigInt.zero,
          bytesTotal: BigInt.zero,
        ),
      );
    }
    if (name == #currentTill || name == #refreshTill) {
      return Future<TillView?>.value(_till);
    }
    if (name == #listTillOrders) {
      return Future<List<OrderSummaryView>>.value(const []);
    }
    if (name == #listCashMovements) {
      return Future<List<CashMovementView>>.value(const []);
    }
    if (name == #branchOpenTills) {
      return Future<List<BranchOpenTillView>>.value(const []);
    }
    if (name == #kitchenRoutingMode) return Future<String?>.value('till');
    if (name == #clockSkewMinutes) return 0;
    if (name == #hasPermission) return true;
    // Everything else: a read the device cannot answer here. The providers
    // treat it as they treat an offline core.
    return Future<Never>.error(const MadarError.offline(detail: 'fake'));
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('ticks, pulses and table changes never reach the network', () async {
    final bridge = _CountingBridge();
    final container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    final errors = <Object>[];

    // The screens an idle till keeps mounted.
    void onError(Object e, StackTrace _) => errors.add(e);
    container
      ..listen(tillProvider, (_, _) {}, onError: onError)
      ..listen(cashMovementsProvider, (_, _) {}, onError: onError)
      ..listen(historyProvider, (_, _) {}, onError: onError)
      ..listen(incomingProvider, (_, _) {}, onError: onError)
      ..listen(kitchenRoutingModeProvider, (_, _) {}, onError: onError);
    await _settle();
    final atRest = bridge.networkCalls();

    final ticks = [
      drawerTickProvider,
      ticketTickProvider,
      kitchenTickProvider,
      deliveryTickProvider,
      floorTickProvider,
      bookingTickProvider,
      syncTickProvider,
    ];
    for (var round = 0; round < 50; round++) {
      for (final t in ticks) {
        container.read(t.notifier).bump();
      }
      container.read(connectivityPulseProvider.notifier).pulse();
      await _settle();
    }

    final byTick = bridge.networkCalls() - atRest;
    final named = bridge.calls.entries
        .where((e) => _networkCapable.contains(e.key))
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
    expect(
      byTick,
      0,
      reason: 'network-capable calls after 50 tick rounds: $named',
    );
    // The screens did re-read (the ticks are live), from the rows.
    expect(bridge.calls[#listTillOrders] ?? 0, greaterThan(50));
  });
}
