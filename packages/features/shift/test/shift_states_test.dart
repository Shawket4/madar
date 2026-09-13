// The drawer screens tell a failure from an empty result, the close count
// starts blank, and a just-closed shift's Z report is its own report.

import 'package:app_core/app_core.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _shift = ShiftView(
  id: 'sh-1',
  branchId: 'br-1',
  tellerId: 'u-1',
  tellerName: 'Sara',
  openingCashMinor: 85000,
  openedAt: '2026-09-12T15:02:00Z',
  status: 'open',
  isOpen: true,
);

ShiftReportView _report(int expected) => ShiftReportView(
  tellerName: 'Sara',
  openedAt: _shift.openedAt,
  printedAt: _shift.openedAt,
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
);

const _offline = MadarError.offline(detail: 'offline');

class _Bridge implements MadarBridge {
  bool failReport = false;
  bool failShifts = false;
  bool failOrders = false;
  bool failMovements = false;
  final List<int> closes = [];
  final List<String> reportsFor = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    if (name == #tr) return args[#key];
    if (name == #appRoute) return const AppRoute.order();
    if (name == #currentSession) return null;
    if (name == #deviceConfig) {
      return const DeviceConfigView(reconfiguring: false, configured: true);
    }
    if (name == #currentShift || name == #refreshShift) {
      return Future<ShiftView?>.value(_shift);
    }
    if (name == #shiftReport) {
      return failReport
          ? Future<ShiftReportView>.error(_offline)
          : Future<ShiftReportView>.value(_report(100000));
    }
    if (name == #shiftReportFor) {
      reportsFor.add(args[#shiftId] as String);
      return failReport
          ? Future<ShiftReportView>.error(_offline)
          : Future<ShiftReportView>.value(_report(100000));
    }
    if (name == #listShiftOrders) {
      return Future<List<OrderSummaryView>>.value(const []);
    }
    if (name == #listOrdersForShift) {
      return failOrders
          ? Future<List<OrderSummaryView>>.error(_offline)
          : Future<List<OrderSummaryView>>.value(const []);
    }
    if (name == #shiftStats) {
      return Future<ShiftStatsView>.value(
        const ShiftStatsView(salesMinor: 0, orderCount: 0),
      );
    }
    if (name == #listShifts) {
      return failShifts
          ? Future<List<ShiftSummaryView>>.error(_offline)
          : Future<List<ShiftSummaryView>>.value(const []);
    }
    if (name == #listCashMovements) {
      return failMovements
          ? Future<List<CashMovementView>>.error(_offline)
          : Future<List<CashMovementView>>.value(const []);
    }
    if (name == #closeShift) {
      closes.add(args[#closingCashMinor] as int);
      return Future<void>.value();
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
        container.listen(closeShiftProvider, (_, _) {});
        await _settle();
        final s = container.read(closeShiftProvider);
        expect(s.report?.expectedCashMinor, 100000);
        expect(s.countedMinor, isNull);
        expect(s.needsReason, isFalse);
        expect(s.canClose, isFalse);

        final notifier = container.read(closeShiftProvider.notifier);
        expect(await notifier.close(note: 'reason'), isFalse);
        expect(bridge.closes, isEmpty, reason: 'nothing counted, nothing sent');
        expect(
          container.read(closeShiftProvider).error,
          const UiText.key('shift.count_required'),
        );
      },
    );

    test('an off count asks for the CLOSING reason, then closes', () async {
      container.listen(closeShiftProvider, (_, _) {});
      await _settle();
      final notifier = container.read(closeShiftProvider.notifier)
        ..setCounted(90000);
      expect(container.read(closeShiftProvider).needsReason, isTrue);
      expect(await notifier.close(note: ' '), isFalse);
      expect(
        container.read(closeShiftProvider).error,
        const UiText.key('shift.closing_reason_required'),
      );
      expect(await notifier.close(note: 'change for the bakery'), isTrue);
      expect(bridge.closes, [90000]);
      expect(container.read(closeShiftProvider).closedShiftId, 'sh-1');
    });

    test('a report that cannot be read is an error with a retry', () async {
      bridge.failReport = true;
      container.listen(closeShiftProvider, (_, _) {});
      await _settle();
      expect(container.read(closeShiftProvider).loadError, isNotNull);
      bridge.failReport = false;
      await container.read(closeShiftProvider.notifier).retry();
      final s = container.read(closeShiftProvider);
      expect(s.loadError, isNull);
      expect(s.report, isNotNull);
    });
  });

  test(
    'the closed shift Z sheet reads that shift, and says when it cannot',
    () async {
      const request = ShiftReportRequest(shiftId: 'sh-1');
      bridge.failReport = true;
      container.listen(shiftReportProvider(request), (_, _) {});
      await _settle();
      expect(bridge.reportsFor, ['sh-1']);
      expect(container.read(shiftReportProvider(request)).loadError, isNotNull);
      bridge.failReport = false;
      container.read(shiftReportProvider(request).notifier).retry();
      await _settle();
      expect(container.read(shiftReportProvider(request)).report, isNotNull);
    },
  );

  test(
    'past shifts: a failed list and failed orders are errors, not empty',
    () async {
      bridge
        ..failShifts = true
        ..failOrders = true;
      container.listen(shiftHistoryProvider, (_, _) {});
      await _settle();
      expect(container.read(shiftHistoryProvider).loadError, isNotNull);
      await container
          .read(shiftHistoryProvider.notifier)
          .toggleShiftOrders('sh-0');
      final s = container.read(shiftHistoryProvider);
      expect(s.ordersErrors['sh-0'], isNotNull);
      expect(s.ordersByShift.containsKey('sh-0'), isFalse);
    },
  );

  test('cash movements that cannot be read are an error', () async {
    bridge.failMovements = true;
    container.listen(cashMovementsProvider, (_, _) {});
    await _settle();
    expect(container.read(cashMovementsProvider).loadError, isNotNull);
  });
}
