// The floor list is a WORKLIST, and its order is the whole point of it. These
// pin the two decisions a person would notice immediately if they were wrong:
// what comes first, and how table labels sort.

import 'package:feature_order/src/floor_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

FloorTableStateView _table({
  required String id,
  String label = 'T1',
  String status = 'free',
  String? bookingId,
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
  bookingId: bookingId,
);

TicketView _ticket({
  required String tableId,
  required String openedAt,
  String status = 'open',
  int subtotal = 0,
}) => TicketView(
  id: 'tk-$tableId',
  tableId: tableId,
  status: status,
  subtotalMinor: subtotal,
  openedAt: openedAt,
  queuedOffline: false,
  lines: const [],
);

void main() {
  final now = DateTime.utc(2026, 9, 9, 20);

  List<FloorRow> rowsFor(
    List<FloorTableStateView> tables,
    Map<String, TicketView> tickets,
  ) => buildFloorRows(
    tables: tables,
    ticketOn: (id) => tickets[id],
    sectionName: (_) => null,
    now: now,
  );

  test('what owes the room work comes first', () {
    final tables = [
      _table(id: 'a'),
      _table(id: 'b', label: 'T2'),
      _table(id: 'c', label: 'T3', status: 'dirty'),
      _table(id: 'd', label: 'T4', bookingId: 'bk-1'),
    ];
    final rows = rowsFor(tables, {
      'b': _ticket(
        tableId: 'b',
        status: 'ready',
        openedAt: '2026-09-09T19:30:00Z',
      ),
    });

    expect(rows.map((r) => r.urgency).toList(), [
      FloorUrgency.needsClearing, // owes the room work
      FloorUrgency.foodReady, // the kitchen is waiting on somebody
      FloorUrgency.reserved, // a party is due
      FloorUrgency.free, // nothing to do
    ], reason: 'a list is worked down, so what needs a person comes first');
  });

  test('the longest-seated table is the one to look at first', () {
    final tables = [_table(id: 'a'), _table(id: 'b', label: 'T2')];
    final rows = rowsFor(tables, {
      // Seated two minutes ago.
      'a': _ticket(tableId: 'a', openedAt: '2026-09-09T19:58:00Z'),
      // Seated an hour ago — this one has been waiting.
      'b': _ticket(tableId: 'b', openedAt: '2026-09-09T19:00:00Z'),
    });
    expect(rows.first.table.label, 'T2');
    expect(formatSeatedFor(rows.first.seatedFor(now)!), '1h 00m');
    expect(formatSeatedFor(rows.last.seatedFor(now)!), '2m');
  });

  test('T10 sorts after T9, not between T1 and T2', () {
    // A plain string sort puts T10 second in a room that goes up to T12, which
    // reads as a bug every single time somebody looks for a table.
    final tables = [
      _table(id: 'c', label: 'T10'),
      _table(id: 'a'),
      _table(id: 'b', label: 'T9'),
      _table(id: 'd', label: 'T2'),
    ];
    final rows = rowsFor(tables, {});
    expect(rows.map((r) => r.table.label).toList(), ['T1', 'T2', 'T9', 'T10']);
  });

  test('a live occupant outranks a stale dirty status', () {
    // This happens honestly: a party seated onto a table the last one left
    // unbussed, or a status write that lost a race. Telling a teller to clear
    // it would have them bus people who are still eating — which is what the
    // list said before the guard was restored.
    final rows = rowsFor(
      [_table(id: 'a', status: 'dirty')],
      {'a': _ticket(tableId: 'a', openedAt: '2026-09-09T19:00:00Z')},
    );
    expect(rows.single.urgency, FloorUrgency.seated);
    expect(rows.single.urgency, isNot(FloorUrgency.needsClearing));
  });

  test('food ready outranks a stale dirty status too', () {
    final rows = rowsFor(
      [_table(id: 'a', status: 'dirty')],
      {
        'a': _ticket(
          tableId: 'a',
          status: 'ready',
          openedAt: '2026-09-09T19:00:00Z',
        ),
      },
    );
    expect(rows.single.urgency, FloorUrgency.foodReady);
  });

  test(
    'a booking on an occupied table does not outrank the party sitting there',
    () {
      // A table can carry a future booking while the current party is still on
      // it. The people in the room win.
      final rows = rowsFor(
        [_table(id: 'a', bookingId: 'bk-1')],
        {'a': _ticket(tableId: 'a', openedAt: '2026-09-09T19:00:00Z')},
      );
      expect(rows.single.urgency, FloorUrgency.seated);
    },
  );

  test('a table with no ticket is never described as seated', () {
    final rows = rowsFor([_table(id: 'a')], {});
    expect(rows.single.urgency, FloorUrgency.free);
    expect(rows.single.seatedFor(now), isNull);
  });

  test('durations read the way a person says them', () {
    expect(formatSeatedFor(const Duration(seconds: 30)), '0m');
    expect(formatSeatedFor(const Duration(minutes: 42)), '42m');
    expect(formatSeatedFor(const Duration(minutes: 65)), '1h 05m');
    expect(formatSeatedFor(const Duration(hours: 3)), '3h 00m');
  });
}
