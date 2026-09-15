// The Sell flow's safety rails — the P0s of the selling-flow audit.
//
// A double tap must never park one order twice or fire one round twice, and a
// failed edit must never cost the teller the line they were editing. Each
// test drives the real OrderNotifier over a fake bridge whose slow calls wait
// on completers the test releases.

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

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

const _latte = CartLineView(
  key: 'latte|Large|oat:1||',
  itemId: 'latte',
  name: 'Latte',
  sizeLabel: 'Large',
  addons: [],
  optionals: [],
  unitPriceMinor: 6000,
  qty: 1,
  lineTotalMinor: 6000,
  bundleComponents: [],
);

const _totals = CartTotals(
  itemCount: 1,
  subtotalMinor: 6000,
  discountMinor: 0,
  taxMinor: 0,
  serviceChargeMinor: 0,
  totalMinor: 6000,
);

const _draft = DraftView(
  id: 'd-1',
  name: 'Omar',
  itemCount: 1,
  totalMinor: 3000,
  createdAt: '2026-09-13T09:00:00Z',
  lockedByOther: false,
);

const _item = MenuItemView(
  id: 'latte',
  name: 'Latte',
  basePriceMinor: 5000,
  isActive: true,
  allowedAddonIds: [],
  sizes: [],
  addonSlots: [],
  optionalFields: [],
  recipes: [],
  recipeSteps: [],
);

class _Fake implements MadarBridge {
  List<CartLineView> lines = [_latte];
  CartMeta meta = const CartMeta(name: '');

  final Completer<bool> holdGate = Completer<bool>();
  final Completer<DraftSwitchView> switchGate = Completer<DraftSwitchView>();
  final Completer<TicketFiredView> fireGate = Completer<TicketFiredView>();

  int holds = 0;
  int switches = 0;
  int fires = 0;
  int removes = 0;
  int adds = 0;

  /// The edit the core refuses (an item gone from the menu).
  bool refuseReplace = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    final a = invocation.namedArguments;
    if (name == #tr) return coreWord(a[#key] as String);
    if (name == #humanMessage) return 'refused';
    if (name == #currentSession) return _session;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #cartLines) return Future<List<CartLineView>>.value(lines);
    if (name == #cartTotals) return Future<CartTotals>.value(_totals);
    if (name == #cartMeta) return Future<CartMeta>.value(meta);
    if (name == #cartSetMeta) {
      meta = a[#meta]! as CartMeta;
      return Future<void>.value();
    }
    if (name == #listDrafts) {
      return Future<List<DraftView>>.value(const [_draft]);
    }
    if (name == #floorLayout || name == #listTransferQueue) {
      return Future<Never>.error(
        const MadarError.offline(detail: 'no floor here'),
      );
    }
    if (name == #listArrivals || name == #listOpenTickets) {
      return Future<Never>.error(
        const MadarError.offline(detail: 'no floor here'),
      );
    }
    if (name == #holdCartOnTable) {
      holds += 1;
      return holdGate.future.then((v) {
        lines = [];
        return v;
      });
    }
    if (name == #switchToDraft) {
      switches += 1;
      return switchGate.future.then((v) {
        meta = const CartMeta(name: 'Omar', draftId: 'd-1');
        return v;
      });
    }
    if (name == #fireTicket) {
      fires += 1;
      return fireGate.future;
    }
    if (name == #cartRemove) {
      removes += 1;
      lines = [];
      return Future<List<CartLineView>>.value(lines);
    }
    if (name == #cartAddConfigured) {
      adds += 1;
      return Future<List<CartLineView>>.value(lines);
    }
    if (name == #cartReplaceConfigured) {
      if (refuseReplace) {
        return Future<Never>.error(
          const MadarError.validation(field: 'item', detail: 'unknown item'),
        );
      }
      return Future<List<CartLineView>>.value(lines);
    }
    if (name == #listItemModifierGroups) {
      return Future<Never>.error(
        const MadarError.offline(detail: 'catalog unreachable'),
      );
    }
    return null;
  }
}

class _Connectivity extends ConnectivityRefreshNotifier {
  @override
  void reportError(Object error) {}
}

ProviderContainer _container(_Fake bridge) {
  final c = ProviderContainer(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      connectivityRefreshProvider.overrideWith(_Connectivity.new),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a double tap on Park parks the order once', () async {
    final bridge = _Fake();
    final c = _container(bridge);
    final cart = c.read(cartProvider(null).notifier);
    await cart.load();

    final first = cart.hold();
    final second = cart.hold();
    bridge.holdGate.complete(false);
    await Future.wait([first, second]);

    expect(bridge.holds, 1, reason: 'one park, one draft');
  });

  test('a double tap on a parked chip switches once', () async {
    final bridge = _Fake();
    final c = _container(bridge);
    final order = c.read(orderProvider.notifier);
    await c.read(cartProvider(null).notifier).load();
    await order.loadDrafts();

    final first = order.resumeDraft('d-1', parkInHand: true);
    final second = order.resumeDraft('d-1', parkInHand: true);
    bridge.switchGate.complete(
      const DraftSwitchView(
        lines: [_latte],
        name: 'Omar',
        createdAt: '2026-09-13T09:00:00Z',
        tableTaken: false,
      ),
    );
    await Future.wait([first, second]);

    expect(bridge.switches, 1);
    expect(bridge.holds, 0, reason: 'the park rides inside the one call');
    expect(c.read(cartProvider(null)).draftId, 'd-1');
    expect(c.read(cartProvider(null)).name, 'Omar');
  });

  test('a double tap on Fire fires one round', () async {
    final bridge = _Fake();
    final c = _container(bridge);
    final cart = c.read(cartProvider('t1').notifier);
    await cart.load();

    final first = cart.fireOrAddRound();
    final second = cart.fireOrAddRound();
    bridge.fireGate.complete(
      const TicketFiredView(ticketId: 'tk-1', queuedOffline: false),
    );
    await Future.wait([first, second]);

    expect(bridge.fires, 1);
  });

  test('an edit the core refuses keeps the original line', () async {
    final bridge = _Fake()..refuseReplace = true;
    final c = _container(bridge);
    final cart = c.read(cartProvider(null).notifier);
    await cart.load();

    final ok = await cart.addConfigured(
      itemId: 'latte',
      addons: const [],
      optionalIds: const [],
      qty: 2,
      replaceLineKey: _latte.key,
    );

    expect(ok, isFalse);
    expect(bridge.removes, 0, reason: 'nothing is removed before the add');
    expect(c.read(cartProvider(null)).lines, [_latte]);

    // And the sheet stays open: its commit answers false and unlatches.
    final args = ItemSheetArgs(item: _item, addons: const [], editLine: _latte);
    final sheet = c.read(itemConfigProvider(args).notifier);
    expect(await sheet.commit(notes: null), isFalse);
    expect(c.read(itemConfigProvider(args)).committing, isFalse);
  });

  test('options that cannot be read are not "no options"', () async {
    final bridge = _Fake();
    final c = _container(bridge);
    final order = c.read(orderProvider.notifier);
    expect(await order.tryLoadItemModifierGroups('latte'), isNull);
    expect(
      c.read(orderProvider).toast,
      isNotNull,
      reason: 'the teller is told',
    );
  });
}
