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
  String? heldOrderId,
  String? bookingStatus,
  String? bookingHeldFrom,
  String? seatedAt,
  int? covers,
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
  bookingStatus: bookingId == null ? null : (bookingStatus ?? 'confirmed'),
  bookingHeldFrom: bookingId == null
      ? null
      : (bookingHeldFrom ?? '2026-09-09T19:45:00Z'),
  heldOrderId: heldOrderId,
  seatedAt: seatedAt,
  covers: covers,
);

TicketView _ticket({
  required String tableId,
  required String openedAt,
  String status = 'open',
  int subtotal = 0,
}) => TicketView(
  id: 'tk-$tableId',
  tableId: tableId,
  status: status == 'ready' ? 'open' : status,
  ready: status == 'ready',
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

  test('a booking reserves its table only once its hold has begun', () {
    final rows = rowsFor([
      _table(id: 'a', bookingId: 'bk-1'),
      _table(
        id: 'b',
        label: 'T2',
        bookingId: 'bk-2',
        bookingHeldFrom: '2026-09-09T23:00:00Z',
      ),
      _table(id: 'c', label: 'T3', bookingId: 'bk-3', bookingStatus: 'seated'),
    ], const {});
    final by = {for (final r in rows) r.table.id: r.urgency};
    expect(by['a'], FloorUrgency.reserved, reason: 'the hold has begun');
    expect(by['b'], FloorUrgency.free, reason: 'tonight is not now');
    expect(by['c'], FloorUrgency.seated, reason: 'the party is at the table');
  });

  test(
    'the seating clock orders the seated, and the row shows the bill total',
    () {
      final rows = rowsFor(
        [
          // Sat an hour ago with no bill yet: the table's own clock.
          _table(
            id: 'a',
            status: 'seated',
            seatedAt: '2026-09-09T19:00:00Z',
            covers: 3,
          ),
          // A bill opened 20 minutes ago.
          _table(id: 'b', label: 'T2', status: 'seated'),
        ],
        {
          'b': const TicketView(
            id: 'tk-b',
            tableId: 'b',
            status: 'open',
            ready: false,
            subtotalMinor: 1000,
            bill: TicketBillView(
              subtotalMinor: 1000,
              discountMinor: 0,
              serviceChargeMinor: 0,
              taxMinor: 140,
              totalMinor: 1140,
              taxRate: 0.14,
              serviceChargeRate: 0,
              taxInclusive: false,
              serviceChargeTaxable: true,
              serviceChargeWaivedMinor: 0,
            ),
            openedAt: '2026-09-09T19:40:00Z',
            queuedOffline: false,
            lines: [],
          ),
        },
      );
      expect(rows.first.table.id, 'a', reason: 'the longest-seated leads');
      expect(rows.first.model.covers, 3);
      expect(
        rows.last.model.billTotalMinor,
        1140,
        reason: 'the total, not 1000',
      );
    },
  );

  test(
    'an occupied table always offers its bill; every state offers history',
    () {
      // Seated, but this device has not heard of a bill (stale list).
      final stale = FloorTableModel(
        table: _table(id: 'a', status: 'seated'),
        ticket: null,
      );
      expect(stale.actions(canCharge: true), contains(FloorAction.openBill));
      expect(stale.actions(canCharge: true), contains(FloorAction.unseat));
      for (final status in ['free', 'dirty', 'seated']) {
        expect(
          FloorTableModel(
            table: _table(id: 'x', status: status),
            ticket: null,
          ).actions(canCharge: false),
          contains(FloorAction.history),
          reason: status,
        );
      }
    },
  );

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

  test('a parked draft occupies its table even with no ticket on it', () {
    // The cart's Hold button parks an order against its table. There is no
    // ticket, so every "is anyone there" check that looks only at tickets
    // reads the table as FREE — and offers it to a second party while
    // somebody's order is still waiting on it.
    final rows = rowsFor([_table(id: 'a', heldOrderId: 'h1')], {});
    expect(rows.single.urgency, FloorUrgency.seated);
    expect(rows.single.urgency, isNot(FloorUrgency.free));
  });

  test('a draft parked on another till occupies its table here too', () {
    // The other till keeps the ORDER — its lines, its money, its name — and
    // pushes only the occupancy, so all this device ever sees is `seated`:
    // no ticket, no draft of its own. Reading that as free was how a second
    // party got seated on top of somebody's waiting order.
    final rows = rowsFor([_table(id: 'a', status: 'seated')], {});
    expect(rows.single.urgency, FloorUrgency.seated);
    expect(rows.single.urgency, isNot(FloorUrgency.free));
  });

  test("a round fired with no network is still somebody's bill", () {
    // `queued` is what a fire looks like before it drains. Every "is anyone
    // there" check used to look only for open/ready, so the floor read a table
    // it had JUST taken as empty — and the tap handler, finding no ticket on a
    // table the mirror said was seated, dead-ended on "taken on another till".
    expect(
      isLiveTicket(
        _ticket(
          tableId: 'a',
          status: 'queued',
          openedAt: '2026-09-09T19:00:00Z',
        ),
      ),
      isTrue,
    );
    final rows = rowsFor(
      [_table(id: 'a')],
      {
        'a': _ticket(
          tableId: 'a',
          status: 'queued',
          openedAt: '2026-09-09T19:00:00Z',
        ),
      },
    );
    expect(rows.single.urgency, FloorUrgency.seated);
  });

  test('a settled or voided ticket is not a live bill', () {
    for (final status in ['settled', 'voided']) {
      expect(
        isLiveTicket(
          _ticket(
            tableId: 'a',
            status: status,
            openedAt: '2026-09-09T19:00:00Z',
          ),
        ),
        isFalse,
        reason: '$status is over',
      );
    }
  });

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
