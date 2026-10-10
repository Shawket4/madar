// The floor's pure rules, ported from the web's own tests (`util.test.ts`,
// `selection.test.ts`, `history.test.ts`, `viewport.test.ts`,
// `gestures.test.ts`, `table-glyph.test.tsx`), plus the page rules
// (spawn spot, capacity, transfer candidates, seats parsing).
import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_sell/src/floor/floor_dialogs.dart';
import 'package:dashboard_sell/src/floor/floor_util.dart';
import 'package:dashboard_sell/src/floor/table_glyph.dart';
import 'package:flutter_test/flutter_test.dart';

GeoItem item(
  String id,
  double x,
  double y, [
  double w = 100,
  double h = 60,
  double rot = 0,
]) => GeoItem(id: id, x: x, y: y, w: w, h: h, rot: rot);

void main() {
  group('SELL-FLR-026 toneFor', () {
    test('a checked-out table needs a bus, never reads available', () {
      expect(toneFor('dirty', null), TableTone.dirty);
      expect(needsClearing('dirty', null), isTrue);
    });
    test('free and held (a teller hold) stay available', () {
      expect(toneFor('free', null), TableTone.available);
      expect(toneFor('held', null), TableTone.available);
    });
    test('seated is taken; a live occupant takes a free or dirty table', () {
      expect(toneFor('seated', null), TableTone.seated);
      expect(toneFor('free', 'Sara'), TableTone.seated);
      expect(toneFor('dirty', 'Sara'), TableTone.seated);
      expect(needsClearing('dirty', 'Sara'), isFalse);
    });
    test('a begun hold reads reserved only on a table nobody occupies', () {
      expect(toneFor('free', null, held: true), TableTone.held);
      expect(toneFor('seated', null, held: true), TableTone.seated);
      expect(toneFor('dirty', null, held: true), TableTone.dirty);
    });
    test('SELL-FLR-079 a hold begins at held_from, confirmed only', () {
      final at = DateTime.utc(2026, 10, 8, 7);
      expect(isHeldNow(status: 'confirmed', heldFrom: at, now: at), isTrue);
      expect(
        isHeldNow(
          status: 'confirmed',
          heldFrom: at,
          now: at.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(isHeldNow(status: 'seated', heldFrom: at, now: at), isFalse);
    });
  });

  group('SELL-FLR-029 marquee', () {
    test('catches a table it merely touches; ignores one outside', () {
      expect(marqueeHits(const FloorRect(0, 0, 20, 20), [item('a', 10, 10)]), [
        'a',
      ]);
      expect(
        marqueeHits(const FloorRect(0, 0, 20, 20), [item('a', 500, 500)]),
        isEmpty,
      );
    });
    test('works dragged up and left', () {
      expect(
        marqueeHits(const FloorRect(200, 200, -180, -180), [
          item('a', 100, 100),
        ]),
        ['a'],
      );
    });
    test('uses the rotation envelope', () {
      final turned = item('a', 100, 100, 120, 20, 90);
      expect(envelopeOf(turned).h, greaterThan(turned.h));
      expect(marqueeHits(const FloorRect(100, 60, 40, 40), [turned]), ['a']);
    });
  });

  group('SELL-FLR-046 align and distribute', () {
    test('left flush reports only what moved', () {
      final moved = alignItems([
        item('a', 0, 0),
        item('b', 50, 100),
        item('c', 0, 200),
      ], FloorAlignment.left);
      expect(moved.map((m) => m.id), ['b']);
      expect(moved.single.x, 0);
    });
    test('centres about the selection', () {
      final moved = alignItems([
        item('a', 0, 0, 100, 100),
        item('b', 200, 0, 100, 100),
      ], FloorAlignment.hcenter);
      expect(moved.map((m) => m.x + m.w / 2).toSet(), hasLength(1));
    });
    test('fewer than two does nothing', () {
      expect(alignItems([item('a', 5, 5)], FloorAlignment.left), isEmpty);
    });
    test('equal gaps, the outermost held', () {
      final items = [
        item('a', 0, 0, 100, 50),
        item('b', 120, 0, 100, 50),
        item('c', 600, 0, 100, 50),
      ];
      final moved = distributeItems(items);
      expect(moved.map((m) => m.id), ['b']);
      final byId = {
        for (final i in items) i.id: i,
        for (final m in moved) m.id: m,
      };
      final [a, b, c] = [
        for (final id in ['a', 'b', 'c']) envelopeOf(byId[id]!),
      ];
      expect(b.x - (a.x + a.w), closeTo(c.x - (b.x + b.w), 1e-6));
      expect(distributeItems([item('a', 0, 0), item('b', 100, 0)]), isEmpty);
    });
  });

  group('SELL-FLR-044/045 clipboard', () {
    const meta = [
      (label: 'T1', seats: 2, shape: 'rect'),
      (label: 'T2', seats: 4, shape: 'circle'),
    ];
    final geo = [item('a', 300, 200), item('b', 400, 260)];
    test('round-trips, offsets from the selection top-left', () {
      final parsed = parseClipboard(serializeTables(meta, geo))!;
      expect(parsed, hasLength(2));
      expect((parsed[0].dx, parsed[0].dy), (0, 0));
      expect((parsed[1].dx, parsed[1].dy), (100, 60));
      expect(parsed[1].seats, 4);
      expect(
        serializeTables(meta, geo),
        contains('"kind":"madar.floor.tables.v1"'),
      );
    });
    test('anything else is ignored, never thrown', () {
      for (final s in [
        'just some text',
        '{}',
        '{"kind":"other.app","tables":[]}',
        '',
        null,
      ]) {
        expect(parseClipboard(s), isNull, reason: '$s');
      }
    });
    test('unique labels never stack suffixes', () {
      expect(uniqueLabel('T1', {}), 'T1');
      expect(uniqueLabel('12', {'12'}), '12 (2)');
      expect(uniqueLabel('12', {'12', '12 (2)'}), '12 (3)');
      expect(uniqueLabel('12 (2)', {'12', '12 (2)'}), '12 (3)');
    });
  });

  group('SELL-FLR-054 undo history', () {
    test('one gesture per press, back to the very first', () {
      var h = const UndoHistory<String>();
      h = pushHistory(h, 'a');
      h = pushHistory(h, 'b');
      final first = applyUndo(h, 'c')!;
      expect(first.value, 'b');
      final second = applyUndo(first.history, first.value)!;
      expect(second.value, 'a');
      expect(applyUndo(second.history, second.value), isNull);
      expect(applyRedo(const UndoHistory<String>(), 'a'), isNull);
    });
    test('a new edit drops the redo branch', () {
      final undone = applyUndo(
        pushHistory(const UndoHistory<String>(), 'a'),
        'b',
      )!;
      expect(applyRedo(undone.history, undone.value)!.value, 'b');
      final after = pushHistory(undone.history, 'a');
      expect(after.future, isEmpty);
    });
    test('bounded at 100 steps, newest kept', () {
      var h = const UndoHistory<String>();
      for (var i = 0; i < kHistoryLimit + 40; i++) {
        h = pushHistory(h, 's$i');
      }
      expect(h.past, hasLength(kHistoryLimit));
      expect(h.past.last, 's${kHistoryLimit + 39}');
    });
  });

  group('SELL-FLR-034 viewport', () {
    const nowhere = FloorRect(0, 0, 100, 100);
    test('bounds cover negative space and a rotation sweep', () {
      final b = boundsOf([item('a', -300, -200, 100, 100)], nowhere);
      expect(b.x, lessThan(0));
      expect(
        boundsOf([item('a', 0, 0, 100, 100)], nowhere).w,
        closeTo(math.sqrt(2) * 100, 1e-5),
      );
      expect(boundsOf(const [], nowhere), nowhere);
    });
    test('fit centres, frames far content, clamps an enormous room', () {
      const bounds = FloorRect(0, 0, 400, 300);
      final v = fitView(bounds, 1000, 600);
      expect(v.x + 1000 / (2 * v.zoom), closeTo(200, 1e-5));
      expect(v.y + 600 / (2 * v.zoom), closeTo(150, 1e-5));
      final far = viewRect(
        fitView(const FloorRect(-5000, -4000, 400, 300), 1000, 600),
        1000,
        600,
      );
      expect(far.x, lessThanOrEqualTo(-5000));
      expect(far.x + far.w, greaterThanOrEqualTo(-4600));
      final big = viewRect(
        fitView(const FloorRect(0, 0, 2400, 1600), 1000, 600),
        1000,
        600,
      );
      expect(big.w, greaterThanOrEqualTo(2400 + kFitPadding));
      expect(
        fitView(const FloorRect(0, 0, 500000, 500000), 1000, 600).zoom,
        kZoomMin,
      );
    });
    test('SELL-FLR-033 zoom holds its anchor and stops at 10%–400%', () {
      const view = FloorView(x: 0, y: 0, zoom: 1);
      final after = zoomAt(view, 2, 300, 200);
      expect((300 - after.x) * after.zoom, closeTo(300, 1e-5));
      final back = zoomAt(after, 0.5, 300, 200);
      expect(back.x, closeTo(0, 1e-5));
      final atMax = zoomAt(
        const FloorView(x: 0, y: 0, zoom: kZoomMax),
        4,
        10,
        10,
      );
      expect((atMax.zoom, atMax.x, atMax.y), (kZoomMax, 0, 0));
      expect(clampZoom(99), kZoomMax);
      expect(clampZoom(0.0001), kZoomMin);
    });
  });

  group('SELL-FLR-033 gestures', () {
    test('a two-finger scroll pans; ctrl/⌘ zooms, reversibly', () {
      final pan = wheelIntent(deltaX: 12, deltaY: -40);
      expect(pan, isA<WheelPan>());
      expect(((pan as WheelPan).dx, pan.dy), (12, -40));
      final zin =
          wheelIntent(deltaX: 0, deltaY: -25, ctrlOrMeta: true) as WheelZoom;
      final zout =
          wheelIntent(deltaX: 0, deltaY: 25, ctrlOrMeta: true) as WheelZoom;
      expect(zin.factor, greaterThan(1));
      expect(zin.factor * zout.factor, closeTo(1, 1e-10));
      final lines = wheelIntent(deltaX: 0, deltaY: 3, deltaMode: 1) as WheelPan;
      expect(lines.dy, greaterThan(3));
    });
    test('pinch factor is the distance ratio, 1 on a first move', () {
      expect(pinchFactor(100, 200), 2);
      expect(pinchFactor(0, 120), 1);
    });
  });

  group('SELL-FLR-025 the glyph', () {
    Map<String, int> sides(double w, double h, int n) {
      final acc = {'top': 0, 'bottom': 0, 'left': 0, 'right': 0};
      for (final s in seatSlots('rect', w, h, n)) {
        final k = s.y < 0
            ? 'top'
            : s.y > h
            ? 'bottom'
            : s.x < 0
            ? 'left'
            : 'right';
        acc[k] = acc[k]! + 1;
      }
      return acc;
    }

    test('chairs in facing pairs, an odd seat at the head', () {
      expect(sides(140, 100, 4), {
        'top': 1,
        'bottom': 1,
        'left': 1,
        'right': 1,
      });
      expect(sides(160, 120, 6), {
        'top': 2,
        'bottom': 2,
        'left': 1,
        'right': 1,
      });
      expect(sides(260, 120, 8), {
        'top': 3,
        'bottom': 3,
        'left': 1,
        'right': 1,
      });
      expect(sides(140, 100, 5), {
        'top': 1,
        'bottom': 1,
        'left': 1,
        'right': 2,
      });
      expect(sides(100, 140, 5), {
        'top': 1,
        'bottom': 2,
        'left': 1,
        'right': 1,
      });
    });
    test('one chair a seat, none past 12', () {
      for (final n in [1, 2, 3, 4, 6, 8, 12]) {
        expect(seatSlots('rect', 140, 100, n), hasLength(n));
        expect(seatSlots('circle', 90, 90, n), hasLength(n));
      }
      expect(seatSlots('rect', 400, 120, 13), isEmpty);
      expect(seatSlots('rect', 400, 120, 0), isEmpty);
    });
    test('the chip: occupant wins, a reservation unless dirty, cut to fit', () {
      expect(
        chipTextFor(
          w: 120,
          occupant: 'T-1',
          reservation: 'Nada',
          tone: TableTone.seated,
        ),
        'T-1',
      );
      expect(
        chipTextFor(
          w: 120,
          occupant: null,
          reservation: 'Nada',
          tone: TableTone.dirty,
        ),
        isNull,
      );
      // 120 wide: (108 - 16) / 8 = 11 characters, the 11th an ellipsis.
      expect(
        chipTextFor(
          w: 120,
          occupant: null,
          reservation: 'Marwan Kamal · 10:15 AM',
          tone: TableTone.held,
        ),
        'Marwan Kam…',
      );
    });
    test('constants shared with the POS kTable* and the web TABLE_*', () {
      expect(kTableCorner, 10);
      expect((kTableRingFree, kTableRing, kTableRingReady), (1.5, 2, 3));
      expect((kTableFillSeated, kTableFillBill), (0.10, 0.22));
      expect((kTableDash, kTableDashGap), (6, 4));
      expect((kTableLabelSize, kTableChipSize), (18, 12));
      expect((kSeatRenderCap, kSeatAllowance), (12, 22));
    });
  });

  group('page rules', () {
    test('SELL-FLR-023 a new table lands beside its section, snapped', () {
      expect(spawnPosition(const []), (x: 0.0, y: 0.0));
      // Six siblings: leftmost 40, lowest bottom 270; cascade 6 % 5 × 30.
      final six = [
        for (var i = 0; i < 6; i++)
          (
            x: 40.0 + (i % 3) * 180,
            y: 40.0 + (i ~/ 3) * 140,
            h: i == 4 ? 90.0 : 80.0,
          ),
      ];
      expect(spawnPosition(six), (x: 70.0, y: 290.0));
      expect(defaultTableSize('circle'), (w: 90.0, h: 90.0));
      expect(defaultTableSize('rect'), (w: 120.0, h: 80.0));
      expect(suggestLabel(['T1', 't7', 'Bar 1', 'T3 (2)']), 'T8');
    });
    test('SELL-FLR-056 capacity counts taken seats and tables to clear', () {
      final cap = capacityOf([
        (seats: 4, status: 'free', occupant: 'T-1'),
        (seats: 2, status: 'seated', occupant: null),
        (seats: 6, status: 'dirty', occupant: null),
        (seats: 4, status: 'dirty', occupant: 'Sara'),
        (seats: 2, status: 'free', occupant: null),
      ]);
      expect(cap, (seats: 18, free: 8, dirty: 1));
    });
    test('SELL-FLR-091 candidates: free active tables matching the wish', () {
      FloorTable tb(
        String id, {
        String status = 'free',
        bool active = true,
        String? section,
      }) => FloorTable(
        id: id,
        orgId: 'o',
        branchId: 'b',
        sectionId: section,
        label: id,
        seats: 2,
        shape: 'rect',
        posX: 0,
        posY: 0,
        width: 80,
        height: 80,
        rotation: 0,
        isActive: active,
        status: status,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final tables = [
        tb('a', section: 's'),
        tb('b', section: 's', status: 'held'),
        tb('c', section: 's', active: false),
        tb('d'),
      ];
      TransferView tr({String? table, String? section}) => TransferView(
        id: 't',
        branchId: 'b',
        occupantKind: 'open_ticket',
        occupantId: 'k',
        targetTableId: table,
        targetSectionId: section,
        status: 'waiting',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      List<String> ids(TransferView t) => [
        for (final x in transferCandidates(t, tables)) x.id,
      ];
      expect(ids(tr()), ['a', 'd']);
      expect(ids(tr(section: 's')), ['a']);
      expect(ids(tr(table: 'b')), isEmpty);
      expect(ids(tr(table: 'gone', section: 's')), isEmpty);
    });
    test('SELL-FLR-020 seats: a whole 0–99, blank reads 0', () {
      expect(parseSeats('4'), 4);
      expect(parseSeats(''), 0);
      expect(parseSeats(' 12 '), 12);
      expect(parseSeats('2.5'), isNull);
      expect(parseSeats('100'), isNull);
      expect(parseSeats('-1'), isNull);
      expect(parseSeats('x'), isNull);
    });
  });
}
