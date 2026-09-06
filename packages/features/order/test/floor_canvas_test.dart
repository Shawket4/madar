// The floor canvas is pure geometry over plain data — no bridge, no providers —
// so it is directly testable. These tests pin the two failures that made the
// tables screen unusable:
//
//  1. A ZOOMABLE canvas laid out inside an unbounded (scrolling) parent threw
//     during layout, which blanks the whole screen — including the header and
//     its back button.
//  2. Tables that belong to no section must still render (QR-era rows carry
//     `section_id = NULL`).

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/tables_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

FloorTableStateView _table({
  required String id,
  String? sectionId,
  String label = 'T1',
  double x = 0,
  double y = 0,
  String status = 'free',
  double width = 80,
}) => FloorTableStateView(
  id: id,
  sectionId: sectionId,
  label: label,
  seats: 4,
  shape: 'rect',
  status: status,
  posX: x,
  posY: y,
  width: width,
  height: 80,
  rotation: 0,
  heldLockedByOther: false,
);

const _section = FloorSectionInfo(
  id: 'sec-in',
  name: 'Inside',
  ordering: 0,
  canvasW: 1000,
  canvasH: 700,
);

Widget _host(Widget child) => MaterialApp(
  theme: MadarTheme.light(),
  home: Scaffold(body: child),
);

/// The canvas needs the translated state vocabulary; tests use plain words so
/// a failure reads as a layout problem, never a translation one.
const _words = TableStatusWords(
  free: 'Free',
  held: 'Held',
  seated: 'Seated',
  needsClearing: 'Needs clearing',
  reserved: 'Reserved',
);

void main() {
  group('reserved tables', () {
    FloorTableStateView t({
      String? bookingStatus,
      String? heldFrom,
      String status = 'free',
    }) => FloorTableStateView(
      id: 't1',
      label: 'T1',
      seats: 4,
      shape: 'rect',
      status: status,
      posX: 0,
      posY: 0,
      width: 80,
      height: 80,
      rotation: 0,
      heldLockedByOther: false,
      bookingId: bookingStatus == null ? null : 'bk1',
      bookingGuest: bookingStatus == null ? null : 'Ahmed',
      bookingParty: 4,
      bookingStartsAt: '2026-09-10T16:30:00Z',
      bookingHeldFrom: heldFrom,
      bookingStatus: bookingStatus,
    );
    final now = DateTime.parse('2026-09-10T16:20:00Z');

    test('a confirmed booking reserves the table once its hold begins', () {
      expect(
        tableIsReserved(
          t(bookingStatus: 'confirmed', heldFrom: '2026-09-10T16:15:00Z'),
          now: now,
        ),
        isTrue,
      );
      expect(
        tableIsReserved(
          t(bookingStatus: 'confirmed', heldFrom: '2026-09-10T16:25:00Z'),
          now: now,
        ),
        isFalse,
        reason: 'not yet in the hold window',
      );
      expect(tableIsReserved(t(), now: now), isFalse);
    });

    test('a seated booking reads as taken; the words follow', () {
      final seated = t(
        bookingStatus: 'seated',
        heldFrom: '2026-09-10T16:15:00Z',
      );
      expect(tableBookingSeated(seated), isTrue);
      expect(tableIsReserved(seated, now: now), isFalse);
      expect(_words.wordFor(seated, occupied: false), 'Seated');
      expect(tableStatusIcon(seated, occupied: false), 'person.2');
      // The icon has no injected clock: a hold that began long ago is live.
      final reserved = t(
        bookingStatus: 'confirmed',
        heldFrom: '2000-01-01T00:00:00Z',
      );
      expect(tableStatusIcon(reserved, occupied: false), 'calendar.days');
      expect(_words.wordFor(reserved, occupied: false), 'Reserved');
      // A dirty table owes a bus first, whatever is booked on it.
      expect(
        tableStatusIcon(
          t(
            bookingStatus: 'confirmed',
            heldFrom: '2000-01-01T00:00:00Z',
            status: 'dirty',
          ),
          occupied: false,
        ),
        'sparkles',
      );
    });
  });

  group('elapsedLabel', () {
    final now = DateTime.utc(2026, 8, 17, 12);
    String? at(Duration ago) =>
        elapsedLabel(now.subtract(ago).toIso8601String(), now: now);

    test('reads as a glanceable time-on-table', () {
      expect(at(const Duration(seconds: 20)), 'now');
      expect(at(const Duration(minutes: 45)), '45m');
      expect(at(const Duration(hours: 2)), '2h');
      expect(at(const Duration(hours: 2, minutes: 10)), '2h 10m');
    });

    test('stays silent when there is nothing honest to show', () {
      expect(elapsedLabel(null), isNull);
      expect(elapsedLabel(''), isNull);
      expect(elapsedLabel('not-a-date'), isNull);
      // A future stamp (clock skew) must not render "-5m".
      expect(
        elapsedLabel(
          now.add(const Duration(hours: 1)).toIso8601String(),
          now: now,
        ),
        'now',
      );
    });
  });

  testWidgets('the room does NOT mirror in Arabic', (tester) async {
    // A floor plan is physical space. Laying it out with `start` rather than
    // `left` mirrors the whole room under an RTL locale, so the table by the
    // door renders by the window and the POS contradicts the layout the
    // dashboard authored. LEFT is left, in every language.
    Future<Offset> originOf(TextDirection dir) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MadarTheme.light(),
          home: Directionality(
            textDirection: dir,
            child: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: FloorCanvas(
                  section: _section,
                  tables: [
                    _table(id: 't1', sectionId: 'sec-in', label: 'LEFT'),
                    _table(
                      id: 't2',
                      sectionId: 'sec-in',
                      label: 'RIGHT',
                      x: 800,
                    ),
                  ],
                  tickets: const [],
                  seatsWord: 'seats',
                  words: _words,
                  onTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getTopLeft(find.text('LEFT'));
    }

    final ltr = await originOf(TextDirection.ltr);
    final rtl = await originOf(TextDirection.rtl);
    expect(rtl.dx, closeTo(ltr.dx, 0.5));
    // …and the table authored at x=0 really is the left-most one in Arabic.
    expect(
      tester.getTopLeft(find.text('LEFT')).dx,
      lessThan(tester.getTopLeft(find.text('RIGHT')).dx),
    );
  });

  group('unbounded floor', () {
    // The dashboard's canvas is an UNBOUNDED plane: tables may sit at negative
    // coordinates or far past the section's stored size, which nothing authors
    // any more. The POS used to scale by that stored width and anchor at (0,0),
    // so anything outside it was silently clipped and the two surfaces stopped
    // showing the same room.
    testWidgets('shows a table placed in negative space', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 800,
            height: 600,
            child: FloorCanvas(
              section: _section,
              tables: [
                _table(
                  id: 't1',
                  sectionId: 'sec-in',
                  label: 'FAR',
                  x: -600,
                  y: -400,
                ),
              ],
              tickets: const [],
              seatsWord: 'seats',
              words: _words,
              onTap: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('FAR'), findsOneWidget);
      final origin = tester.getTopLeft(find.text('FAR'));
      expect(origin.dx, greaterThanOrEqualTo(0));
      expect(origin.dy, greaterThanOrEqualTo(0));
    });

    testWidgets('shows a table placed far beyond the old canvas size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 800,
            height: 600,
            child: FloorCanvas(
              section: _section,
              tables: [
                _table(id: 't1', sectionId: 'sec-in', label: 'NEAR'),
                _table(id: 't2', sectionId: 'sec-in', label: 'OUT', x: 4000),
              ],
              tickets: const [],
              seatsWord: 'seats',
              words: _words,
              onTap: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Both are on screen, and the far one really is to the right of the near.
      expect(find.text('NEAR'), findsOneWidget);
      expect(find.text('OUT'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('OUT')).dx,
        greaterThan(tester.getTopLeft(find.text('NEAR')).dx),
      );
      expect(tester.getTopLeft(find.text('OUT')).dx, lessThan(800));
    });

    test('frames the content, chairs included, not the stored canvas', () {
      final bounds = floorBounds([
        (table: _table(id: 't1', x: -100, y: -50), x: -100, y: -50),
      ]);
      // Reaches past the table on every side to leave room for the chairs.
      expect(bounds.left, lessThan(-100));
      expect(bounds.top, lessThan(-50));
      expect(bounds.width, greaterThan(80));
    });

    test('falls back to a sane frame when the room is empty', () {
      final bounds = floorBounds([]);
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
    });
  });

  group('seat geometry', () {
    // The chairs are what make a rectangle read as a TABLE, and this algorithm
    // is duplicated in the dashboard's `table-glyph.tsx`. These cases are the
    // contract between the two — if they drift, the same room stops looking
    // like the same room.
    Map<String, int> sides(double w, double h, int n) {
      final slots = seatSlots('rect', w, h, n);
      final m = seatMetrics(w, h);
      final off = m.gap + m.thick / 2;
      var top = 0;
      var bottom = 0;
      var left = 0;
      var right = 0;
      for (final s in slots) {
        if ((s.y + off).abs() < 0.01) {
          top++;
        } else if ((s.y - (h + off)).abs() < 0.01) {
          bottom++;
        } else if ((s.x + off).abs() < 0.01) {
          left++;
        } else {
          right++;
        }
      }
      return {'top': top, 'bottom': bottom, 'left': left, 'right': right};
    }

    test('seats people in pairs, facing each other', () {
      // A 4-top: one chair per side.
      expect(sides(140, 100, 4), {
        'top': 1,
        'bottom': 1,
        'left': 1,
        'right': 1,
      });
      // A 6-top: pairs down the long sides, one at each end.
      expect(sides(160, 120, 6), {
        'top': 2,
        'bottom': 2,
        'left': 1,
        'right': 1,
      });
      // A long 8-top: three a side, one at each head.
      expect(sides(260, 120, 8), {
        'top': 3,
        'bottom': 3,
        'left': 1,
        'right': 1,
      });
    });

    test('an odd seat takes the head of the table', () {
      // Wide table → the head is an end (right).
      expect(sides(140, 100, 5), {
        'top': 1,
        'bottom': 1,
        'left': 1,
        'right': 2,
      });
      // Tall table → the head is the bottom.
      expect(sides(100, 140, 5), {
        'top': 1,
        'bottom': 2,
        'left': 1,
        'right': 1,
      });
    });

    test('always renders exactly as many chairs as the table seats', () {
      for (final n in [1, 2, 3, 4, 5, 6, 7, 8, 10, 12]) {
        expect(seatSlots('rect', 140, 100, n).length, n, reason: 'rect n=$n');
        expect(seatSlots('circle', 90, 90, n).length, n, reason: 'circle n=$n');
      }
    });

    test('a circle spaces its chairs evenly, starting due north', () {
      final slots = seatSlots('circle', 100, 100, 4);
      // First chair sits above the table centre.
      expect(slots.first.x, closeTo(50, 0.01));
      expect(slots.first.y, lessThan(0));
      // Opposite chair mirrors it below.
      expect(slots[2].x, closeTo(50, 0.01));
      expect(slots[2].y, greaterThan(100));
    });

    test('stops drawing chairs on a banquet-sized table', () {
      // Past the cap the rim is a smear; the seat COUNT carries it instead.
      expect(seatSlots('rect', 400, 120, 13), isEmpty);
      expect(seatSlots('rect', 400, 120, 0), isEmpty);
    });
  });

  group('needs clearing', () {
    // The state the checkout flow now depends on: a paid table that has NOT
    // been bussed. It must never read as available, and it must be legible
    // without relying on colour.
    testWidgets('says so in words when the table is wide enough', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          FloorCanvas(
            section: _section,
            tables: [
              _table(
                id: 't1',
                sectionId: 'sec-in',
                status: 'dirty',
                width: 200,
              ),
            ],
            tickets: const [],
            seatsWord: 'seats',
            words: _words,
            onTap: (_) {},
          ),
        ),
      );
      expect(find.text('Needs clearing'), findsOneWidget);
    });

    testWidgets('a narrow table still is not colour-only', (tester) async {
      // The words do not fit on a small table, and a half-rendered
      // "Needs cleari…" is worse than none — so the glyph, the hatch, and the
      // screen-reader label carry the state instead. Both platforms drop the
      // pill on exactly the same tables (same estimator), so neither shows a
      // word the other hides.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          FloorCanvas(
            section: _section,
            tables: [_table(id: 't1', sectionId: 'sec-in', status: 'dirty')],
            tickets: const [],
            seatsWord: 'seats',
            words: _words,
            onTap: (_) {},
          ),
        ),
      );
      expect(find.text('Needs clearing'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'T1, Needs clearing',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('reads its state out to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          FloorCanvas(
            section: _section,
            tables: [_table(id: 't1', sectionId: 'sec-in', status: 'dirty')],
            tickets: const [],
            seatsWord: 'seats',
            words: _words,
            onTap: (_) {},
          ),
        ),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'T1, Needs clearing',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a table with an order on it is never "needs clearing"', (
      tester,
    ) async {
      // `dirty` + a live occupant is a contradiction the mirror can briefly
      // hold mid-sync; the occupant always wins.
      await tester.pumpWidget(
        _host(
          FloorCanvas(
            section: _section,
            tables: const [
              FloorTableStateView(
                id: 't1',
                sectionId: 'sec-in',
                label: 'T1',
                seats: 4,
                shape: 'rect',
                status: 'dirty',
                posX: 0,
                posY: 0,
                width: 80,
                height: 80,
                rotation: 0,
                heldOrderId: 'h1',
                heldOrderName: 'Sara',
                heldLockedByOther: false,
              ),
            ],
            tickets: const [],
            seatsWord: 'seats',
            words: _words,
            onTap: (_) {},
          ),
        ),
      );
      expect(find.text('Needs clearing'), findsNothing);
      expect(find.text('Sara'), findsOneWidget);
    });
  });

  testWidgets('zoomable canvas lays out inside a bounded parent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            Expanded(
              child: FloorCanvas(
                section: _section,
                tables: [_table(id: 't1', sectionId: 'sec-in')],
                tickets: const [],
                seatsWord: 'seats',
                words: _words,
                zoomable: true,
                onTap: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('T1'), findsOneWidget);
  });

  testWidgets('zoomable canvas survives an UNBOUNDED (scrolling) parent', (
    tester,
  ) async {
    // The regression: a zoomable canvas inside a SingleChildScrollView gets
    // infinite height. It must not throw — a layout exception here takes the
    // entire screen down, back button included.
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: FloorCanvas(
            section: _section,
            tables: [_table(id: 't1', sectionId: 'sec-in')],
            tickets: const [],
            seatsWord: 'seats',
            words: _words,
            zoomable: true,
            onTap: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('T1'), findsOneWidget);
  });

  testWidgets('tables with no section still render', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 600,
          child: FloorCanvas(
            section: null, // the "unassigned" tab passes no section
            tables: [
              _table(id: 't1', label: 'A1'),
              _table(id: 't2', label: 'A2', x: 200),
            ],
            tickets: const [],
            seatsWord: 'seats',
            words: _words,
            onTap: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
  });

  testWidgets('stacked never-arranged tables are spread apart', (tester) async {
    // Every QR-era table carries the same default geometry; without the
    // display-spread they pile up as one square.
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 600,
          child: FloorCanvas(
            section: null,
            tables: [
              _table(id: 't1', label: 'A1'),
              _table(id: 't2', label: 'A2'),
              _table(id: 't3', label: 'A3'),
            ],
            tickets: const [],
            seatsWord: 'seats',
            words: _words,
            onTap: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final a1 = tester.getTopLeft(find.text('A1'));
    final a2 = tester.getTopLeft(find.text('A2'));
    expect(a1 == a2, isFalse, reason: 'stacked tables must not overlap');
  });

  testWidgets('a taken table is marked by its OCCUPANT PILL, not a solid body', (
    tester,
  ) async {
    // The floor and the dashboard's authoring canvas draw the same glyph: every
    // table is a quiet status-tinted surface at the same strength, and the
    // SOLID mark is the occupant pill riding the bottom edge. Painting busy
    // tables solid instead made the POS and the dashboard disagree about what
    // the same room looked like.
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 600,
          child: FloorCanvas(
            section: null,
            tables: [
              _table(id: 't1', label: 'FREE'),
              const FloorTableStateView(
                id: 't2',
                label: 'BUSY',
                seats: 4,
                shape: 'rect',
                status: 'seated',
                posX: 300,
                posY: 0,
                width: 80,
                height: 80,
                rotation: 0,
                heldOrderId: 'h1',
                heldOrderName: 'Sara',
                heldLockedByOther: false,
              ),
            ],
            tickets: const [],
            seatsWord: 'seats',
            words: _words,
            onTap: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    Color fillOf(String label) {
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    const colors = MadarColors.light;
    // Both bodies carry the SAME tint strength — only the hue differs.
    expect(fillOf('BUSY'), colors.accent.withValues(alpha: kTableFillOpacity));
    expect(fillOf('FREE'), colors.success.withValues(alpha: kTableFillOpacity));
    // The occupant is what marks the table, and it names who is on it.
    expect(find.text('Sara'), findsOneWidget);
  });
}
