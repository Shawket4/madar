// Orders tells "no till" from "could not read", keeps a stable newest-first
// order by the instant, and under All keeps paging to find a search.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:feature_history/feature_history.dart';
import 'package:feature_history/src/widgets.dart' show saleNumberText;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _till = TillView(
  id: 'sh-1',
  branchId: 'br-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: 0,
  openedAt: '2026-09-12T15:02:00Z',
  status: 'open',
  isOpen: true,
  verification: 'server',
  openedWhileAnotherOpen: false,
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
  displayNumber: '',
);

class _Bridge implements MadarBridge {
  TillView? till = _till;
  bool figuresVisible = true;
  bool failList = false;
  int listCalls = 0;

  /// The ungated shift totals must never be reached from this screen.
  int plainStatsCalls = 0;
  List<OrderSummaryView> rows = const [];
  final List<int> pages = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #tillFiguresVisible) return figuresVisible;
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    // The core's drawer and Orders decisions (till_views), in miniature.
    if (name == #paymentMethodLabel) {
      final code = invocation.namedArguments[#code] as String;
      return code.isEmpty ? code : code[0].toUpperCase() + code.substring(1);
    }
    if (name == #tillCashSalesMinor) {
      final r = invocation.namedArguments[#report] as TillReportView;
      return r.expectedCashMinor -
          r.openingCashMinor -
          r.cashInMinor +
          r.cashOutMinor;
    }
    if (name == #closeCountCheck) {
      final expected = invocation.namedArguments[#expectedMinor] as int;
      final counted = invocation.namedArguments[#countedMinor] as int?;
      final v = counted == null ? 0 : counted - expected;
      return CloseCountCheck(
        entered: counted != null,
        varianceMinor: v,
        verdict: counted == null
            ? 'pending'
            : v == 0
            ? 'matches'
            : v > 0
            ? 'over'
            : 'short',
        needsReason: counted != null && v != 0,
      );
    }
    if (name == #saleTaxInclusive) {
      final a = invocation.namedArguments;
      final before =
          (a[#subtotalMinor] as int) -
          (a[#discountMinor] as int) +
          (a[#serviceMinor] as int) +
          (a[#deliveryMinor] as int);
      return (a[#taxMinor] as int) > 0 && a[#totalMinor] == before;
    }
    if (name == #refundMethodPlan) {
      final method = invocation.namedArguments[#orderPaymentMethod] as String;
      const options = [
        PaymentMethodChoice(code: 'cash', label: 'Cash', isCash: true),
        PaymentMethodChoice(code: 'card', label: 'Card', isCash: false),
      ];
      return RefundMethodPlan(
        options: options,
        defaultCode: options
            .where((o) => o.code == method.toLowerCase())
            .firstOrNull
            ?.code,
        crossesTill: false,
      );
    }
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
    // The one owner's sync read: this person's OWN open till, or none.
    if (name == #ownOpenTill) {
      final t = till;
      return (t?.isOpen ?? false) ? t : null;
    }
    if (name == #currentTill) return Future<TillView?>.value(till);
    if (name == #listTillOrders) {
      listCalls++;
      return failList
          ? Future<List<OrderSummaryView>>.error(
              const MadarError.offline(detail: 'x'),
            )
          : Future<List<OrderSummaryView>>.value(rows);
    }
    if (name == #tillStatsChecked) {
      // The core's one gate: the shift totals are refused without
      // `till.cash_spot_check`, exactly as `till_stats_checked` does.
      return figuresVisible
          ? Future<TillStatsView>.value(
              const TillStatsView(salesMinor: 62300, orderCount: 7),
            )
          : Future<TillStatsView>.error(
              const MadarError.forbidden(
                resource: 'till',
                action: 'spot.blind',
              ),
            );
    }
    if (name == #tillStats) {
      plainStatsCalls++;
      return Future<TillStatsView>.value(
        const TillStatsView(salesMinor: 62300, orderCount: 7),
      );
    }
    if (name == #syncStatus) {
      return SyncStatusView(
        repairedTypes: const [],
        catalogFreshness: const FreshnessView(state: 'fresh'),
        blockedClose: false,
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

  // Owner decision 3 (2026-09-19): widening `till.cash_spot_check` must not
  // reach PAST ORDERS — not the list, not a sale's own total, not its items,
  // payments, receipt or reprint. The header's SHIFT AGGREGATE is the one
  // exception (owner, 2026-09-19): it is a till money figure and is hidden.
  test(
    'past orders keep their figures when the till figures are hidden',
    () async {
      final bridge = _Bridge()
        ..figuresVisible = false
        ..rows = [_o('o1', 12, '2026-09-19T09:00:00Z')];
      final container = ProviderContainer(
        overrides: [bridgeProvider.overrideWithValue(bridge)],
      );
      addTearDown(container.dispose);
      container.listen(historyProvider, (_, _) {});
      await _settle();
      final s = container.read(historyProvider);
      expect(s.rows.single.totalMinor, 1000, reason: "the sale's own total");
      expect(s.rows, hasLength(1), reason: 'the list itself is never gated');
      expect(
        s.stats,
        isNull,
        reason: 'the shift aggregate goes through the one gate',
      );
      expect(s.error, isNull, reason: 'a hidden aggregate is not an error');
    },
  );

  // With the grant the same header carries the shift total and count again,
  // and it comes from the CHECKED call, never the plain one.
  test('the shift aggregate comes back with till.cash_spot_check', () async {
    final bridge = _Bridge()
      ..figuresVisible = true
      ..rows = [_o('o1', 12, '2026-09-19T09:00:00Z')];
    final container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
    addTearDown(container.dispose);
    container.listen(historyProvider, (_, _) {});
    await _settle();
    final s = container.read(historyProvider);
    expect(s.stats?.orderCount, 7);
    expect(s.stats?.salesMinor, 62300);
    expect(bridge.plainStatsCalls, 0, reason: 'never the ungated call');
  });

  test('a sale reads by its device number, then the server number', () {
    final server = _o('o-1', 12, '2026-09-12T15:10:00Z');
    expect(saleNumberText(server), '12');
    OrderSummaryView withDisplay(String d) => OrderSummaryView(
      id: server.id,
      orderNumber: server.orderNumber,
      subtotalMinor: server.subtotalMinor,
      taxMinor: server.taxMinor,
      totalMinor: server.totalMinor,
      paymentLabel: server.paymentLabel,
      status: server.status,
      createdAt: server.createdAt,
      queued: false,
      orderType: server.orderType,
      priceFlagged: false,
      displayNumber: d,
    );
    expect(saleNumberText(withDisplay('36B-12')), '36B-12');
    expect(saleNumberText(withDisplay('36B-12~AB12')), '36B-12~AB12');
  });

  setUp(() {
    bridge = _Bridge();
    container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
  });
  tearDown(() => container.dispose());

  test('no shift is a state: no list call, no toast, no error', () async {
    bridge.till = null;
    container.listen(historyProvider, (_, _) {});
    await _settle();
    final s = container.read(historyProvider);
    expect(container.read(shellProvider).tillOpen, isFalse);
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
    expect(container.read(shellProvider).tillOpen, isTrue);
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
