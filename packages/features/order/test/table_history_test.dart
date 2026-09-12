// A table's history is the one floor read that is NOT cached, and the sheet
// has to say so rather than showing zeroes. Zeroes read as "this table earns
// nothing"; a table that earns nothing and a table nobody can reach are
// different facts and a manager acts differently on each.
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/table_history_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

TableSittingView _sitting({
  required String ref,
  required int minutes,
  int? covers,
  int? totalMinor,
  String status = 'settled',
  String? who,
}) => TableSittingView(
  ticketId: ref,
  ticketRef: ref,
  openedAt: '2026-09-12T18:00:00Z',
  closedAt: '2026-09-12T19:00:00Z',
  minutes: minutes,
  status: status,
  customerName: who,
  guestCount: covers,
  orderRef: totalMinor == null ? null : '1',
  totalMinor: totalMinor,
);

class _FakeBridge implements MadarBridge {
  _FakeBridge({this.history, this.throws = false});

  final TableHistoryView? history;
  final bool throws;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) return invocation.namedArguments[#key] as String? ?? '';
    if (name == #isRtl) return false;
    if (name == #currentSession) return null;
    if (name == #appRoute) return const AppRoute.order();
    if (name == #tableHistory) {
      if (throws) return Future<TableHistoryView>.error(StateError('offline'));
      return Future<TableHistoryView>.value(history);
    }
    return null;
  }
}

Future<void> _pump(WidgetTester tester, _FakeBridge bridge) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
      child: MaterialApp(
        theme: MadarTheme.light(),
        home: const Scaffold(
          body: TableHistorySheet(tableId: 't1', label: 'T5'),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('offline says so instead of showing zeroes', (tester) async {
    await _pump(tester, _FakeBridge(throws: true));
    expect(find.text('tables.history_offline'), findsOneWidget);
    expect(
      find.text('tables.takings'),
      findsNothing,
      reason: 'a figure nobody could fetch must not be printed as a figure',
    );
  });

  testWidgets('an empty table says nothing sat here, not zero takings', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeBridge(
        history: const TableHistoryView(
          tableId: 't1',
          label: 'T5',
          sittings: [],
          covers: 0,
          settledCount: 0,
          totalMinor: 0,
          averageBillMinor: 0,
          averageMinutes: 0,
          turnsPerDayX100: 0,
        ),
      ),
    );
    expect(find.text('tables.history_empty'), findsOneWidget);
  });

  testWidgets('the figures lead, and a bill that took nothing is flagged', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeBridge(
        history: TableHistoryView(
          tableId: 't1',
          label: 'T5',
          sittings: [
            _sitting(ref: 'T-1', minutes: 62, covers: 2, totalMinor: 5000),
            // Still running: no money yet, and it must not read as zero.
            _sitting(ref: 'T-2', minutes: 12, covers: 4, status: 'open'),
          ],
          covers: 2,
          settledCount: 1,
          totalMinor: 5000,
          averageBillMinor: 5000,
          averageMinutes: 62,
          turnsPerDayX100: 150,
        ),
      ),
    );
    expect(find.text('tables.takings'), findsOneWidget);
    expect(find.text('tables.avg_bill'), findsOneWidget);
    // 150 on the wire is 1.5 turns a day.
    expect(find.text('1.5'), findsOneWidget);
    // The open bill wears a tag where a settled one shows an amount.
    expect(find.text('TABLES.STILL_OPEN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
