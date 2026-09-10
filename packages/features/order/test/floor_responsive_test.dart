// The floor on a PHONE.
//
// Fitting a whole room to the viewport is the right instinct on a desk and
// ruinous in 360 points: a thirty-table dining room scales to about 0.18, which
// draws an 80-unit table at fourteen pixels — smaller than the fingertip meant
// to press it. These pin the floor under that fit, and the header that has
// already overflowed its own screen once.

import 'package:feature_order/src/tables_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

void main() {
  group('floorScale', () {
    test('a big room on a phone stops shrinking and starts scrolling', () {
      // 30 tables across ~2000 units, in a 360-point viewport.
      final scale = floorScale(
        viewportWidth: 360,
        roomWidth: 2000,
        smallestTable: 80,
      );
      // The naive fit would be 0.18 → a 14px table.
      expect(360 / 2000, lessThan(0.2));
      expect(
        80 * scale,
        greaterThanOrEqualTo(kMinTablePx),
        reason: 'the smallest table must stay pressable',
      );
    });

    test('a small room is still not magnified past the ceiling', () {
      // Two tables in a wide window: fitting would draw dinner plates.
      final scale = floorScale(
        viewportWidth: 1400,
        roomWidth: 300,
        smallestTable: 80,
      );
      expect(scale, kMaxFloorScale);
    });

    test('a room that fits is left alone', () {
      final scale = floorScale(
        viewportWidth: 800,
        roomWidth: 1000,
        smallestTable: 200,
      );
      // Fit is 0.8; the minimum (44/200 = 0.22) does not bite, and 0.8 is under
      // the ceiling — so the fit stands.
      expect(scale, closeTo(0.8, 0.0001));
    });

    test('the minimum beats the fit, never the other way round', () {
      // A tiny table in a big room: the floor has to win or it is not a floor.
      final scale = floorScale(
        viewportWidth: 320,
        roomWidth: 5000,
        smallestTable: 40,
      );
      expect(40 * scale, greaterThanOrEqualTo(kMinTablePx));
      expect(
        5000 * scale,
        greaterThan(320),
        reason: 'the canvas is now pannable',
      );
    });

    test('degenerate geometry does not divide by zero', () {
      expect(
        floorScale(viewportWidth: 0, roomWidth: 100, smallestTable: 80),
        1,
      );
      expect(
        floorScale(viewportWidth: 360, roomWidth: 0, smallestTable: 80),
        1,
      );
    });
  });

  group('smallestTableEdge', () {
    test('is set by the worst target in the room, not the average', () {
      // A room is only as usable as the table a finger misses first.
      final placed = [
        _placed(width: 200, height: 200),
        _placed(width: 60, height: 40),
        _placed(width: 120, height: 120),
      ];
      expect(smallestTableEdge(placed), 40);
    });

    test('an empty room falls back rather than returning infinity', () {
      expect(smallestTableEdge(const []), 80);
    });

    test('a zero-sized table is ignored rather than pinning the scale', () {
      // Authored geometry can carry a zero; dividing by it would magnify the
      // room to infinity.
      final placed = [
        _placed(width: 0, height: 0),
        _placed(width: 90, height: 70),
      ];
      expect(smallestTableEdge(placed), 70);
    });
  });
}

PlacedTable _placed({required double width, required double height}) => (
  table: FloorTableStateView(
    id: 't',
    label: 'T',
    seats: 4,
    shape: 'rect',
    status: 'free',
    posX: 0,
    posY: 0,
    width: width,
    height: height,
    rotation: 0,
    heldLockedByOther: false,
  ),
  x: 0,
  y: 0,
);
