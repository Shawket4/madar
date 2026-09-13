// The floor inspector: what each state offers, that every act reports the
// right action (with the party size), the worklist, and a room fitted to the
// window's HEIGHT as well as its width.
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/floor_inspector.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/tables_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

final _now = DateTime.utc(2026, 9, 13, 20);

String _ago(int m) => _now.subtract(Duration(minutes: m)).toIso8601String();

FloorTableStateView _table({
  String status = 'free',
  String? booking,
  double x = 0,
  double y = 0,
  String id = 't1',
}) => FloorTableStateView(
  id: id,
  label: id.toUpperCase(),
  seats: 4,
  shape: 'circle',
  status: status,
  posX: x,
  posY: y,
  width: 90,
  height: 90,
  rotation: 0,
  heldLockedByOther: false,
  seatedAt: status == 'seated' ? _ago(20) : null,
  bookingId: booking == null ? null : 'b1',
  bookingGuest: booking,
  bookingStatus: booking == null ? null : 'confirmed',
  bookingHeldFrom: booking == null ? null : _ago(5),
  bookingStartsAt: booking == null ? null : _ago(-10),
);

TicketView _ticket({bool ready = false}) => TicketView(
  id: 'tk',
  tableId: 't1',
  status: 'open',
  ready: ready,
  subtotalMinor: 12000,
  openedAt: _ago(20),
  queuedOffline: false,
  lines: const [],
);

class _Recorder {
  final List<(FloorAction, int?, bool?)> acts = [];
  void call(FloorAction a, {int? covers, bool? takeOrder}) =>
      acts.add((a, covers, takeOrder));
}

Future<_Recorder> _pumpDetail(
  WidgetTester tester, {
  required FloorTableStateView table,
  TicketView? ticket,
  bool canCharge = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 1200);
  addTearDown(tester.view.reset);
  final rec = _Recorder();
  await tester.pumpWidget(
    MaterialApp(
      theme: MadarTheme.light(),
      home: Scaffold(
        body: FloorTableDetail(
          table: table,
          ticket: ticket,
          now: _now,
          currency: 'EGP',
          locale: 'en',
          word: (k) => k,
          canCharge: canCharge,
          onAction: rec.call,
        ),
      ),
    ),
  );
  return rec;
}

Iterable<String> _actionKeys(WidgetTester tester) => tester
    .widgetList<MadarButton>(find.byType(MadarButton))
    .map((b) => (b.key! as ValueKey<String>).value);

void main() {
  group('inspector actions by state', () {
    testWidgets('free: party size, Seat & take order, Seat', (tester) async {
      final rec = await _pumpDetail(tester, table: _table());
      expect(_actionKeys(tester), [
        'floor.seat_and_order',
        'floor.action.seat',
      ]);
      // The party defaults to the table's seats.
      await tester.tap(find.byKey(const ValueKey('floor.seat_and_order')));
      await tester.tap(find.byKey(const ValueKey('floor.action.seat')));
      expect(rec.acts.first.$1, FloorAction.seat);
      expect(rec.acts.first.$3, isTrue, reason: 'seat & take order');
      expect(rec.acts.last.$3, isNot(isTrue), reason: 'seat alone');
      expect(rec.acts.last.$2, 4);
    });

    testWidgets('seated, no bill: take order, move, open bill, unseat', (
      tester,
    ) async {
      await _pumpDetail(tester, table: _table(status: 'seated'));
      expect(_actionKeys(tester), [
        'floor.action.takeOrder',
        'floor.action.move',
        'floor.action.openBill',
        'floor.action.unseat',
      ]);
    });

    testWidgets('a bill: charge first, then round, move, open, void', (
      tester,
    ) async {
      final rec = await _pumpDetail(
        tester,
        table: _table(status: 'seated'),
        ticket: _ticket(),
      );
      expect(_actionKeys(tester), [
        'floor.action.charge',
        'floor.action.addRound',
        'floor.action.move',
        'floor.action.openBill',
        'floor.action.voidBill',
      ]);
      await tester.tap(find.byKey(const ValueKey('floor.action.charge')));
      expect(rec.acts.single.$1, FloorAction.charge);
    });

    testWidgets('a waiter is never offered Charge', (tester) async {
      await _pumpDetail(
        tester,
        table: _table(status: 'seated'),
        ticket: _ticket(ready: true),
        canCharge: false,
      );
      expect(_actionKeys(tester), isNot(contains('floor.action.charge')));
      expect(_actionKeys(tester), contains('floor.action.addRound'));
    });

    testWidgets('needs clearing: Cleared', (tester) async {
      final rec = await _pumpDetail(tester, table: _table(status: 'dirty'));
      expect(_actionKeys(tester), ['floor.action.cleared']);
      await tester.tap(find.byKey(const ValueKey('floor.action.cleared')));
      expect(rec.acts.single.$1, FloorAction.cleared);
    });

    testWidgets('reserved: seat the party, no-show, walk-in', (tester) async {
      await _pumpDetail(tester, table: _table(booking: 'Omar'));
      expect(_actionKeys(tester), [
        'floor.action.seatBooking',
        'floor.action.noShow',
        'floor.action.walkIn',
      ]);
    });

    testWidgets('every state opens its history', (tester) async {
      final rec = await _pumpDetail(tester, table: _table(status: 'dirty'));
      await tester.tap(find.byKey(const ValueKey('floor.inspector.history')));
      expect(rec.acts.single.$1, FloorAction.history);
    });
  });

  test('the worklist is what owes the room a person, in order', () {
    final tables = [
      _table(id: 'a'),
      _table(id: 'b', status: 'dirty'),
      _table(id: 'c', status: 'seated'),
      _table(id: 'd', booking: 'Omar'),
    ];
    final rows = buildFloorRows(
      tables: tables,
      ticketOn: (id) => id == 'c' ? _ticket(ready: true) : null,
      sectionName: (_) => null,
      now: _now,
    );
    expect(needsAttention(rows, now: _now).map((r) => r.table.id), [
      'b',
      'c',
      'd',
    ]);
  });

  test('a short party is not a long wait; an hour is', () {
    final rows = buildFloorRows(
      tables: [_table(id: 'c', status: 'seated')],
      ticketOn: (_) => null,
      sectionName: (_) => null,
      now: _now,
    );
    expect(needsAttention(rows, now: _now), isEmpty);
    expect(
      needsAttention(rows, now: _now.add(const Duration(hours: 1))),
      hasLength(1),
    );
  });

  group('fit to the window', () {
    test('a short, wide window fits the room by its height', () {
      final scale = floorScale(
        viewportWidth: 1000,
        roomWidth: 500,
        smallestTable: 90,
        viewportHeight: 300,
        roomHeight: 500,
      );
      expect(scale, closeTo(0.6, 1e-9));
    });

    test('without a height the fit is by width, as before', () {
      final scale = floorScale(
        viewportWidth: 400,
        roomWidth: 500,
        smallestTable: 90,
      );
      expect(scale, closeTo(0.8, 1e-9));
    });

    testWidgets('a portrait-tall room is drawn inside the window and centred', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MadarTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 1000,
                height: 400,
                child: FloorCanvas(
                  section: null,
                  tables: [
                    _table(id: 'top'),
                    _table(id: 'bottom', y: 600),
                  ],
                  tickets: const [],
                  seatsWord: 'seats',
                  words: const TableStatusWords(
                    free: 'Free',
                    held: 'Held',
                    seated: 'Seated',
                    needsClearing: 'Needs clearing',
                  ),
                  zoomable: true,
                  onTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final canvas = tester.getRect(find.byType(FloorCanvas));
      final top = tester.getRect(find.text('TOP'));
      final bottom = tester.getRect(find.text('BOTTOM'));
      expect(top.top, greaterThanOrEqualTo(canvas.top));
      expect(bottom.bottom, lessThanOrEqualTo(canvas.bottom));
      // Centred across: the room is far narrower than the window.
      expect(
        (top.center.dx - canvas.center.dx).abs(),
        lessThan(2),
        reason: 'centred both axes',
      );
    });
  });
}
