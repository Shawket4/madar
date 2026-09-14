// The table flows that must be reachable in one tap: the bill's own doors
// (history, move, unseat, back to the table), seat-and-take-order, and a move
// that explains every refusal and offers Undo only after it moved.
import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/feature_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const Size _ipad = Size(1194, 834);

FloorTableStateView _table(String id, double x, {String status = 'free'}) =>
    FloorTableStateView(
      id: id,
      sectionId: 's',
      label: id.toUpperCase(),
      seats: 4,
      shape: 'rect',
      status: status,
      posX: x,
      posY: 40,
      width: 90,
      height: 90,
      rotation: 0,
      heldLockedByOther: false,
    );

final _layout = FloorLayoutView(
  sections: const [
    FloorSectionInfo(
      id: 's',
      name: 'Inside',
      ordering: 0,
      canvasW: 900,
      canvasH: 400,
    ),
  ],
  tables: [
    _table('t2', 40, status: 'seated'),
    _table('t3', 200, status: 'dirty'),
    _table('t5', 360, status: 'seated'),
    _table('t6', 520),
  ],
);

TicketView _ticket(String id, String table) => TicketView(
  id: id,
  ticketRef: 'R-$id',
  tableId: table,
  status: 'open',
  ready: false,
  subtotalMinor: 5000,
  openedAt: DateTime.now().toUtc().toIso8601String(),
  queuedOffline: false,
  lines: const [],
);

class _Fake implements MadarBridge {
  final List<(String, String)> swaps = [];
  final List<String> seated = [];

  @override
  dynamic noSuchMethod(Invocation i) {
    final n = i.memberName;
    final a = i.namedArguments;
    if (n == #tr || n == #trChecked) {
      final key = (a[#key] ?? i.positionalArguments.firstOrNull) as String;
      return coreWord(key);
    }
    if (n == #isRtl) return false;
    if (n == #locale) return 'en';
    if (n == #currentSession) {
      return const SessionSnapshot(
        userId: 'u',
        displayName: 'S',
        role: 'teller',
        currencyCode: 'EGP',
        taxRate: 0,
        taxInclusive: false,
        serviceChargeRate: 0,
        serviceChargeTaxable: false,
        requireTableForOrders: false,
        online: true,
        permissionsLoaded: true,
      );
    }
    if (n == #currentTill || n == #refreshTill) {
      return Future<TillView?>.value();
    }
    if (n == #floorLayout) return Future<FloorLayoutView>.value(_layout);
    if (n == #listOpenTickets) {
      return Future<List<TicketView>>.value([
        _ticket('tk-2', 't2'),
        _ticket('tk-5', 't5'),
      ]);
    }
    if (n == #swapFloorTables) {
      swaps.add((a[#tableA]! as String, a[#tableB]! as String));
      return Future<void>.value();
    }
    if (n == #seatTable) {
      seated.add(a[#tableId]! as String);
      return Future<void>.value();
    }
    if (n == #listCategories) return Future<List<CategoryView>>.value([]);
    if (n == #listMenuItems) return Future<List<MenuItemView>>.value([]);
    if (n == #availableBundles) return Future<List<BundleView>>.value([]);
    if (n == #listDrafts) return Future<List<DraftView>>.value([]);
    if (n == #listTransferQueue) {
      return Future<List<TransferQueueView>>.value([]);
    }
    if (n == #listArrivals) return Future<List<BookingView>>.value([]);
    if (n == #cartLines) {
      return Future<List<CartLineView>>.value([]);
    }
    if (n == #cartMeta) {
      return Future<CartMeta>.value(const CartMeta(name: ''));
    }
    if (n == #cartSetMeta) return Future<void>.value();
    if (n == #holdCartOnTable) return Future<bool>.value(false);
    if (n == #cartTotals) {
      return Future<CartTotals>.value(
        const CartTotals(
          itemCount: 0,
          subtotalMinor: 0,
          discountMinor: 0,
          taxMinor: 0,
          serviceChargeMinor: 0,
          totalMinor: 0,
        ),
      );
    }
    if (n == #cartBillSoFarMinor) return Future<int>.value(0);
    if (n == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (n == #refreshConnectivity) return Future<bool>.value(true);
    if (n == #syncStatus) {
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
    if (n == #listTillOrders) {
      return Future<List<OrderSummaryView>>.value([]);
    }
    if (n == #tillStats) {
      return Future<TillStatsView>.value(
        const TillStatsView(salesMinor: 0, orderCount: 0),
      );
    }
    if (n == #listItemModifierGroups) {
      return Future<List<ModifierGroupView>>.value([]);
    }
    if (n == #listItemAddons) return Future<List<ItemAddonView>>.value([]);
    if (n == #formatTime) return '19:00';
    if (n == #clockSkewMinutes) return 0;
    if (n == #appRoute) return const AppRoute.order();
    if (n == #isRealtimeSubscribed) return false;
    if (n.toString().contains('"refresh') || n.toString().contains('"cart')) {
      return Future<void>.value();
    }
    return null;
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  Widget screen,
  _Fake fake,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _ipad;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [bridgeProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: MadarTheme.light(), home: screen),
    ),
  );
  await _settle(tester);
  return c;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

String? _toast(ProviderContainer c) => c.read(orderProvider).toast?.text;

void main() {
  testWidgets('the bill carries history, move, unseat and table actions', (
    tester,
  ) async {
    final c = await _mount(tester, const BillScreen(ticketId: 'tk-2'), _Fake());
    for (final k in [
      'bill.history',
      'bill.move',
      'bill.unseat',
      'bill.table_actions',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    // Unseat over a bill says what frees the table, and offers the void.
    await tester.tap(find.byKey(const ValueKey('bill.unseat')));
    await _settle(tester);
    expect(find.text(coreWord('bill.unseat_has_bill')), findsOneWidget);
    expect(c.read(orderProvider).openTickets, isNotEmpty);
  });

  testWidgets('moving a bill onto an occupied table confirms the swap, '
      'then offers Undo', (tester) async {
    final fake = _Fake();
    final c = await _mount(tester, const BillScreen(ticketId: 'tk-2'), fake);
    await tester.tap(find.byKey(const ValueKey('bill.move')));
    await _settle(tester);
    await tester.tap(find.text('T5').last);
    await _settle(tester);
    expect(find.text('${coreWord('tables.swap')} T2 ↔ T5?'), findsOneWidget);
    expect(fake.swaps, isEmpty, reason: 'nothing moves before the yes');
    await tester.tap(find.text(coreWord('tables.swap')).last);
    await _settle(tester);
    expect(fake.swaps, [('t2', 't5')]);
    expect(c.read(orderProvider).toast?.actionLabel, coreWord('order.undo'));
  });

  testWidgets('Seat & take order seats and opens the table order', (
    tester,
  ) async {
    final fake = _Fake();
    await _mount(tester, const FloorScreen(), fake);
    await tester.tap(find.text('T6'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('floor.seat_and_order')));
    await _settle(tester);
    expect(fake.seated, ['t6']);
    final screen = tester.widget<OrderScreen>(find.byType(OrderScreen));
    expect(screen.tableId, 't6', reason: "the table's own screen and cart");
  });

  testWidgets('move mode: same table and a dirty table explain; stays armed', (
    tester,
  ) async {
    final fake = _Fake();
    final c = await _mount(tester, const FloorScreen(), fake);
    await tester.tap(find.text('T2'));
    await _settle(tester);
    // The inspector beside the room: T2 selected, its Move.
    await tester.tap(find.byKey(const ValueKey('floor.action.move')));
    await _settle(tester);
    expect(find.textContaining(coreWord('tables.swap_pick')), findsOneWidget);

    await tester.tap(find.text('T2').first);
    await _settle(tester);
    expect(_toast(c), coreWord('err.move_same'));
    await tester.tap(find.text('T3'));
    await _settle(tester);
    expect(_toast(c), coreWord('err.move_dirty'));
    expect(fake.swaps, isEmpty);
    expect(find.textContaining(coreWord('tables.swap_pick')), findsOneWidget);

    // A free table moves, and only then does Undo appear.
    await tester.tap(find.text('T6'));
    await _settle(tester);
    expect(fake.swaps, [('t2', 't6')]);
    expect(c.read(orderProvider).toast?.actionLabel, coreWord('order.undo'));
    expect(find.textContaining(coreWord('tables.swap_pick')), findsNothing);
  });
}
