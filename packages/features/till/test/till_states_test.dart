// The drawer screens tell a failure from an empty result, the close count
// starts blank, and a just-closed till's Z report is its own report.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _till = TillView(
  id: 'sh-1',
  branchId: 'br-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: 85000,
  openedAt: '2026-09-12T15:02:00Z',
  status: 'open',
  isOpen: true,
  verification: 'server',
  openedWhileAnotherOpen: false,
);

TillReportView _report(int expected) => TillReportView(
  tellerName: 'Sara',
  openedAt: _till.openedAt,
  printedAt: _till.openedAt,
  isOpen: true,
  expectedCashMinor: expected,
  openingCashMinor: 85000,
  openingCashWasEdited: false,
  totalPaymentsMinor: 0,
  netPaymentsMinor: 0,
  voidedAmountMinor: 0,
  refundsIssuedMinor: 0,
  refundsIssuedCashMinor: 0,
  refundsIssuedCount: 0,
  cashInRefundedSalesMinor: 0,
  cashMovementsNetMinor: 0,
  cashInMinor: 0,
  cashOutMinor: 0,
  paymentLines: const [],
  cashMovements: const [],
  fromServer: true,
  reconciliation: const [],
  verification: 'server',
  spotViews: const [],
  openedWhileAnotherOpen: false,
  serviceChargeWaivedCount: 0,
  serviceChargeWaivedMinor: 0,
  totalServiceChargeMinor: 0,
  totalTaxMinor: 0,
);

const _offline = MadarError.offline(detail: 'offline');

class _Bridge implements MadarBridge {
  bool failReport = false;
  bool blind = false;
  int reportReads = 0;
  bool failTills = false;
  bool failOrders = false;
  bool failMovements = false;
  final List<int> closes = [];
  final List<String> reportsFor = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #tillFiguresVisible) return !blind;
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    if (name == #tillReport) reportReads += 1;
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
    if (name == #currentSession) return null;
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #currentTill || name == #refreshTill) {
      return Future<TillView?>.value(_till);
    }
    if (name == #tillReport) {
      return failReport
          ? Future<TillReportView>.error(_offline)
          : Future<TillReportView>.value(_report(100000));
    }
    if (name == #tillReportFor) {
      reportsFor.add(args[#tillId] as String);
      return failReport
          ? Future<TillReportView>.error(_offline)
          : Future<TillReportView>.value(_report(100000));
    }
    if (name == #listTillOrders) {
      return Future<List<OrderSummaryView>>.value(const []);
    }
    if (name == #listOrdersForTill) {
      return failOrders
          ? Future<List<OrderSummaryView>>.error(_offline)
          : Future<List<OrderSummaryView>>.value(const []);
    }
    if (name == #tillStats) {
      return Future<TillStatsView>.value(
        const TillStatsView(salesMinor: 0, orderCount: 0),
      );
    }
    if (name == #listTills) {
      return failTills
          ? Future<List<TillSummaryView>>.error(_offline)
          : Future<List<TillSummaryView>>.value(const []);
    }
    if (name == #listCashMovements) {
      return failMovements
          ? Future<List<CashMovementView>>.error(_offline)
          : Future<List<CashMovementView>>.value(const []);
    }
    if (name == #closeTill) {
      closes.add(args[#closingCashMinor] as int);
      return Future<CloseTillOutcomeView>.value(
        const CloseTillOutcomeView(queued: false, reconciliation: []),
      );
    }
    if (name == #listTills) return Future<List<TillView>>.value(const []);
    return null;
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
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

  group('close shift', () {
    test(
      'the count starts blank: no difference, no reason, no close',
      () async {
        container.listen(closeTillProvider, (_, _) {});
        await _settle();
        final s = container.read(closeTillProvider);
        expect(s.report?.expectedCashMinor, 100000);
        expect(s.countedMinor, isNull);
        expect(s.needsReason, isFalse);
        expect(s.canClose, isFalse);

        final notifier = container.read(closeTillProvider.notifier);
        expect(await notifier.close(note: 'reason'), isFalse);
        expect(bridge.closes, isEmpty, reason: 'nothing counted, nothing sent');
        expect(
          container.read(closeTillProvider).error,
          const UiText.key('till.count_required'),
        );
      },
    );

    test(
      'without the grant the count is blind: no figures read, closes on the count',
      () async {
        bridge.blind = true;
        container.listen(closeTillProvider, (_, _) {});
        await _settle();
        final s = container.read(closeTillProvider);
        expect(s.blind, isTrue);
        expect(s.report, isNull, reason: 'the expected drawer is never read');
        expect(bridge.reportReads, 0);
        final notifier = container.read(closeTillProvider.notifier)
          ..setCounted(90000);
        expect(container.read(closeTillProvider).needsReason, isFalse);
        expect(container.read(closeTillProvider).canClose, isTrue);
        expect(await notifier.close(note: ''), isTrue);
        expect(bridge.closes, [90000]);
      },
    );

    test('an off count asks for the CLOSING reason, then closes', () async {
      container.listen(closeTillProvider, (_, _) {});
      await _settle();
      final notifier = container.read(closeTillProvider.notifier)
        ..setCounted(90000);
      expect(container.read(closeTillProvider).needsReason, isTrue);
      expect(await notifier.close(note: ' '), isFalse);
      expect(
        container.read(closeTillProvider).error,
        const UiText.key('till.closing_reason_required'),
      );
      expect(await notifier.close(note: 'change for the bakery'), isTrue);
      expect(bridge.closes, [90000]);
      expect(container.read(closeTillProvider).closedTillId, 'sh-1');
    });

    test('a report that cannot be read is an error with a retry', () async {
      bridge.failReport = true;
      container.listen(closeTillProvider, (_, _) {});
      await _settle();
      expect(container.read(closeTillProvider).loadError, isNotNull);
      bridge.failReport = false;
      await container.read(closeTillProvider.notifier).retry();
      final s = container.read(closeTillProvider);
      expect(s.loadError, isNull);
      expect(s.report, isNotNull);
    });
  });

  test(
    'the closed shift Z sheet reads that shift, and says when it cannot',
    () async {
      const request = TillReportRequest(tillId: 'sh-1');
      bridge.failReport = true;
      container.listen(tillReportProvider(request), (_, _) {});
      await _settle();
      expect(bridge.reportsFor, ['sh-1']);
      expect(container.read(tillReportProvider(request)).loadError, isNotNull);
      bridge.failReport = false;
      container.read(tillReportProvider(request).notifier).retry();
      await _settle();
      expect(container.read(tillReportProvider(request)).report, isNotNull);
    },
  );

  test(
    'past shifts: a failed list and failed orders are errors, not empty',
    () async {
      bridge
        ..failTills = true
        ..failOrders = true;
      container.listen(tillHistoryProvider, (_, _) {});
      await _settle();
      expect(container.read(tillHistoryProvider).loadError, isNotNull);
      await container
          .read(tillHistoryProvider.notifier)
          .toggleTillOrders('sh-0');
      final s = container.read(tillHistoryProvider);
      expect(s.ordersErrors['sh-0'], isNotNull);
      expect(s.ordersByTill.containsKey('sh-0'), isFalse);
    },
  );

  test('cash movements that cannot be read are an error', () async {
    bridge.failMovements = true;
    container.listen(cashMovementsProvider, (_, _) {});
    await _settle();
    expect(container.read(cashMovementsProvider).loadError, isNotNull);
  });
}
