// The floor LIST on a phone.
//
// The list exists because the plan is unreadable in 360 points; a list that
// overflows its own screen would be no better. A row carries a label, a
// section, a subtitle of names, a duration and a money figure — five things
// competing for the same width, which is exactly the shape that overflows.

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _phone = Size(360, 780);

FloorTableStateView _table({
  required String id,
  required String label,
  String status = 'free',
}) => FloorTableStateView(
  id: id,
  label: label,
  seats: 4,
  shape: 'rect',
  status: status,
  posX: 0,
  posY: 0,
  width: 80,
  height: 80,
  rotation: 0,
  heldLockedByOther: false,
);

TicketView _ticket(String tableId) => TicketView(
  id: 'tk-$tableId',
  tableId: tableId,
  ticketRef: 'T-04127',
  status: 'open',
  customerName: 'A rather long customer name indeed',
  waiterName: 'Abdelrahman',
  guestCount: 6,
  subtotalMinor: 1234567,
  openedAt: '2026-09-09T18:00:00Z',
  queuedOffline: false,
  lines: const [],
);

const _words = FloorListWords(
  free: 'Free',
  seated: 'Seated',
  reserved: 'Reserved',
  needsClearing: 'Needs clearing',
  ready: 'Ready',
  seats: 'seats',
  guests: 'guests',
);

Future<void> _pump(WidgetTester tester, List<FloorRow> rows) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _phone;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: MadarTheme.light(),
      home: Scaffold(
        body: FloorListView(
          rows: rows,
          now: DateTime.utc(2026, 9, 9, 20),
          currency: 'EGP',
          words: _words,
          onTap: (_) {},
          onLongPress: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a crowded row fits a phone', (tester) async {
    // Everything at once: a long section, a long customer name, a waiter, a
    // ticket ref and a six-figure bill.
    final rows = buildFloorRows(
      tables: [_table(id: 'a', label: 'Terrace 12', status: 'seated')],
      ticketOn: (_) => _ticket('a'),
      sectionName: (_) => 'Upstairs Terrace (smoking)',
      now: DateTime.utc(2026, 9, 9, 20),
    );
    await _pump(tester, rows);
    expect(tester.takeException(), isNull);
    // The duration is what a teller scans for; it must survive the squeeze.
    expect(find.text('2h 00m'), findsOneWidget);
  });

  testWidgets('a long room of rows scrolls rather than overflowing', (
    tester,
  ) async {
    final rows = buildFloorRows(
      tables: [for (var i = 0; i < 40; i++) _table(id: 't$i', label: 'T$i')],
      ticketOn: (_) => null,
      sectionName: (_) => null,
      now: DateTime.utc(2026, 9, 9, 20),
    );
    await _pump(tester, rows);
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
  });
}
