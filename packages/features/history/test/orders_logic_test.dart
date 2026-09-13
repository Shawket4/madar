// Orders tells "no shift" from "could not read", keeps a stable newest-first
// order by the instant, and under All keeps paging to find a search.

import 'package:app_core/app_core.dart';
import 'package:feature_history/feature_history.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _shift = ShiftView(
  id: 'sh-1',
  branchId: 'br-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: 0,
  openedAt: '2026-09-12T15:02:00Z',
  status: 'open',
  isOpen: true,
);

OrderSummaryView _o(String id, int number, String at) => OrderSummaryView(
  id: id,
  orderNumber: number,
  subtotalMinor: 1000,
  taxMinor: 0,
  totalMinor: 1000,
  paymentLabel: 'cash',
  status: 'completed',
  createdAt: at,
  queued: false,
  orderType: 'takeaway',
  priceFlagged: false,
);

class _Bridge implements MadarBridge {
  ShiftView? shift = _shift;
  bool failList = false;
  int listCalls = 0;
  List<OrderSummaryView> rows = const [];
  final List<int> pages = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    if (name == #tr || name == #trChecked) {
      return args[#key] ?? invocation.positionalArguments.first;
    }
    if (name == #appRoute) return const AppRoute.order();
    if (name == #currentSession) return null;
    if (name == #humanMessage) return 'failed';
    if (name == #loyaltySettings) {
      return Future<LoyaltyProgrammeView>.error(
        const MadarError.offline(detail: 'x'),
      );
    }
    if (name == #currentShift) return Future<ShiftView?>.value(shift);
    if (name == #listShiftOrders) {
      listCalls++;
      return failList
          ? Future<List<OrderSummaryView>>.error(
              const MadarError.offline(detail: 'x'),
            )
          : Future<List<OrderSummaryView>>.value(rows);
    }
    if (name == #shiftStats) {
      return Future<ShiftStatsView>.value(
        const ShiftStatsView(salesMinor: 0, orderCount: 0),
      );
    }
    if (name == #syncStatus) {
      return Future<SyncStatusView>.value(
        const SyncStatusView(
          pending: 0,
          failed: 0,
          blocked: 0,
          online: true,
          authPaused: false,
        ),
      );
    }
    if (name == #searchOrders) {
      final page = args[#page] as int;
      pages.add(page);
      return Future<OrderSearchPage>.value(
        OrderSearchPage(
          orders: [
            // The sale being looked for is on page 3.
            _o(
              'p$page',
              page == 3 ? 777 : page,
              '2026-09-1${9 - page}T10:00:00Z',
            ),
          ],
          page: page,
          total: 10,
          hasMore: page < 10,
        ),
      );
    }
    return null;
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Bridge bridge;
  late ProviderContainer container;

  setUp(() {
    bridge = _Bridge();
    container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
  });
  tearDown(() => container.dispose());

  test('no shift is a state: no list call, no toast, no error', () async {
    bridge.shift = null;
    container.listen(historyProvider, (_, _) {});
    await _settle();
    final s = container.read(historyProvider);
    expect(s.hasShift, isFalse);
    expect(s.loading, isFalse);
    expect(s.toast, isNull);
    expect(s.error, isNull);
    expect(bridge.listCalls, 0);
  });

  test('a shift list that cannot be read is an error, not empty', () async {
    bridge.failList = true;
    container.listen(historyProvider, (_, _) {});
    await _settle();
    final s = container.read(historyProvider);
    expect(s.error, isNotNull);
    expect(s.toast, isNull);
    expect(s.hasShift, isTrue);
  });

  test('rows sort by the instant, not the text, and ties keep order', () async {
    bridge.rows = [
      // 20:30+02:00 is 18:30Z — EARLIER than 19:00Z though it sorts later
      // as text.
      _o('a', 1, '2026-09-12T20:30:00+02:00'),
      _o('b', 2, '2026-09-12T19:00:00Z'),
      _o('c', 3, '2026-09-12T19:00:00Z'),
    ];
    container.listen(historyProvider, (_, _) {});
    await _settle();
    expect(container.read(historyProvider).filtered.map((o) => o.id), [
      'b',
      'c',
      'a',
    ]);
  });

  test('a search under All pages on until it finds the sale', () async {
    container.listen(historyProvider, (_, _) {});
    await _settle();
    container.read(historyProvider.notifier).setScope(OrdersScope.all);
    await _settle();
    container.read(historyProvider.notifier).setSearch('777');
    await _settle();
    final s = container.read(historyProvider);
    expect(s.filtered.map((o) => o.orderNumber), [777]);
    expect(bridge.pages, [1, 2, 3], reason: 'stops once found');
  });
}
