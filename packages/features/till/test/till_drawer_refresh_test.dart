// Recording a pay in / pay out on the Till must move the Till's expected
// cash at once — not only after a trip to the close-till screen.
//
// The bug: the Till reloaded on `shellProvider`, and `record()` "refreshed"
// the shell — but the shell only emits when the route or session changes,
// which a cash movement never does. The fake core here recomputes expected
// cash from the movements it holds (queued or acked alike, as madar-core's
// `till_report` does), so the test pins the signal, not a fixture number.

import 'package:app_core/app_core.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _opening = 85000;

const _till = TillView(
  id: 'sh-1',
  branchId: 'br-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: _opening,
  openedAt: '2026-09-12T15:02:00Z',
  status: 'open',
  isOpen: true,
  verification: 'server',
  openedWhileAnotherOpen: false,
);

class _CoreBridge implements MadarBridge {
  final List<CashMovementView> movements = [];
  int reportReads = 0;

  TillReportView _report() {
    final net = movements.fold<int>(0, (a, m) => a + m.amountMinor);
    return TillReportView(
      tellerName: 'Sara',
      openedAt: _till.openedAt,
      printedAt: _till.openedAt,
      isOpen: true,
      expectedCashMinor: _opening + net,
      openingCashMinor: _opening,
      openingCashWasEdited: false,
      totalPaymentsMinor: 0,
      netPaymentsMinor: 0,
      voidedAmountMinor: 0,
      refundsIssuedMinor: 0,
      refundsIssuedCashMinor: 0,
      refundsIssuedCount: 0,
      cashInRefundedSalesMinor: 0,
      cashMovementsNetMinor: net,
      cashInMinor: movements
          .where((m) => m.amountMinor > 0)
          .fold(0, (a, m) => a + m.amountMinor),
      cashOutMinor: movements
          .where((m) => m.amountMinor < 0)
          .fold(0, (a, m) => a - m.amountMinor),
      paymentLines: const [],
      cashMovements: const [],
      fromServer: false,
      reconciliation: const [],
      verification: 'server',
      openedWhileAnotherOpen: false,
      serviceChargeWaivedCount: 0,
      serviceChargeWaivedMinor: 0,
      totalServiceChargeMinor: 0,
      totalTaxMinor: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
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
        requireTableForOrders: true,
        online: false,
        permissionsLoaded: true,
      );
    }
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #currentTill || name == #refreshTill) {
      return Future<TillView?>.value(_till);
    }
    if (name == #tillReport) {
      reportReads++;
      return Future<TillReportView>.value(_report());
    }
    if (name == #listTillOrders) {
      return Future<List<OrderSummaryView>>.value(const []);
    }
    if (name == #tillStats) {
      return Future<TillStatsView>.value(
        const TillStatsView(salesMinor: 0, orderCount: 0),
      );
    }
    if (name == #listCashMovements) {
      return Future<List<CashMovementView>>.value(List.of(movements));
    }
    if (name == #recordCashMovement) {
      // Queued in the outbox (offline): the core's report counts it anyway.
      final m = CashMovementView(
        id: 'cm-${movements.length}',
        kind: (args[#amountMinor] as int) < 0 ? 'pay_out' : 'pay_in',
        amountMinor: args[#amountMinor] as int,
        note: args[#note] as String,
        movedByName: 'Sara',
        createdAt: _till.openedAt,
      );
      movements.insert(0, m);
      return Future<CashMovementView>.value(m);
    }
    if (name == #listTills) return Future<List<TillView>>.value(const []);
    if (name == #syncStatus) {
      return SyncStatusView(
        pendingOutbox: 1,
        deadOutbox: 0,
        blocked: 0,
        freshness: const FreshnessView(state: 'fresh'),
        online: false,
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
    return null;
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _CoreBridge bridge;
  late ProviderContainer container;

  setUp(() {
    bridge = _CoreBridge();
    container = ProviderContainer(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
    );
  });
  tearDown(() => container.dispose());

  Future<void> record({required bool isIn, required int minor}) async {
    final cash = container.read(cashMovementsProvider.notifier)
      ..setDirection(isIn: isIn)
      ..setAmount(minor)
      ..setNote('milk');
    expect(await cash.record(), isTrue);
    await _settle();
  }

  test('a pay out moves the Till expected cash immediately', () async {
    final sub = container.listen(tillProvider, (_, _) {});
    container.listen(cashMovementsProvider, (_, _) {});
    await _settle();
    expect(container.read(tillProvider).report?.expectedCashMinor, _opening);

    await record(isIn: false, minor: 9000);

    final till = container.read(tillProvider);
    expect(till.report?.expectedCashMinor, _opening - 9000);
    expect(till.movements, hasLength(1));
    sub.close();
  });

  test('a pay in moves the Till expected cash immediately', () async {
    container
      ..listen(tillProvider, (_, _) {})
      ..listen(cashMovementsProvider, (_, _) {});
    await _settle();

    await record(isIn: true, minor: 20000);

    expect(
      container.read(tillProvider).report?.expectedCashMinor,
      _opening + 20000,
    );
  });

  test('Till and close shift show the same expected cash', () async {
    container
      ..listen(tillProvider, (_, _) {})
      ..listen(closeTillProvider, (_, _) {})
      ..listen(cashMovementsProvider, (_, _) {});
    await _settle();

    await record(isIn: false, minor: 4500);

    final till = container.read(tillProvider).report?.expectedCashMinor;
    final close = container.read(closeTillProvider).report?.expectedCashMinor;
    expect(till, _opening - 4500);
    expect(close, till);
  });

  test('a sale elsewhere (drawer tick) reloads the Till', () async {
    container.listen(tillProvider, (_, _) {});
    await _settle();
    final before = bridge.reportReads;

    container.read(drawerTickProvider.notifier).bump();
    await _settle();

    expect(bridge.reportReads, greaterThan(before));
  });
}
