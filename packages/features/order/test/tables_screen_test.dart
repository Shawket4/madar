// TablesScreen must ALWAYS render its chrome — header, title, and a working
// back button — no matter what the floor mirror holds. A blank page with no
// way back is the worst failure this screen can have, so it is pinned here.
//
// The bridge is faked through `noSuchMethod`, so these are pure widget tests:
// no Rust, no database, no network.

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/tables_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

FloorTableStateView _table({
  required String id,
  String? sectionId,
  String label = 'T1',
  double x = 0,
  String status = 'free',
}) => FloorTableStateView(
  id: id,
  sectionId: sectionId,
  label: label,
  seats: 4,
  shape: 'rect',
  status: status,
  posX: x,
  posY: 0,
  width: 80,
  height: 80,
  rotation: 0,
  heldLockedByOther: false,
);

/// A permissive stand-in for the Rust bridge: `tr` echoes its key (so finders
/// can match on the key), and every call the order surface makes during a
/// render answers with an empty value.
class _FakeBridge implements MadarBridge {
  _FakeBridge(this.layout, {this.tickets = const []});

  final FloorLayoutView layout;

  /// Live bills, so a test can put one on a table and reach the ticket sheet.
  final List<TicketView> tickets;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) return invocation.namedArguments[#key] as String? ?? '';
    if (name == #floorLayout) return Future<FloorLayoutView>.value(layout);
    if (name == #refreshFloor) return Future<void>.value();
    if (name == #listTransferQueue) {
      return Future<List<TransferQueueView>>.value(const []);
    }
    if (name == #listArrivals) return Future<List<BookingView>>.value(const []);
    if (name == #refreshArrivals) return Future<void>.value();
    if (name == #listDrafts) return Future<List<DraftView>>.value(const []);
    // The floor loads its bills now — both roles, since which tables have
    // ordered is part of the room's state.
    if (name == #listOpenTickets) {
      return Future<List<TicketView>>.value(tickets);
    }
    if (name == #cartLines) return Future<List<CartLineView>>.value(const []);
    if (name == #currentSession) return null;
    if (name == #clockSkewMinutes) return 0;
    if (name == #formatTime) return '19:00';
    return null;
  }
}

/// A phone, in logical pixels. Small enough to be honest: this is the width
/// the header has already overflowed once.
const Size _phone = Size(360, 780);

Future<void> _pump(
  WidgetTester tester,
  FloorLayoutView layout, {
  Size? surface,
  List<TicketView> tickets = const [],
}) async {
  if (surface != null) {
    // Set the VIEW, not just the surface, and pin the pixel ratio to 1 — the
    // test binding defaults to 3.0, so `setSurfaceSize(360x780)` alone would
    // hand the widgets 120x260 logical pixels and test a phone nobody sells.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bridgeProvider.overrideWithValue(_FakeBridge(layout, tickets: tickets)),
      ],
      child: MaterialApp(
        theme: MadarTheme.light(),
        home: Builder(
          // A route BELOW the screen, so `maybePop` has somewhere to go —
          // exactly how the order screen pushes it.
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TablesScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a busy room fits a phone without overflowing', (tester) async {
    // Thirty tables spread across a wide room — the shape that scales to 0.18
    // on a phone and used to draw fourteen-pixel tables.
    final tables = [
      for (var i = 0; i < 30; i++)
        _table(id: 't$i', label: 'T$i', x: (i % 6) * 320),
    ];
    await _pump(
      tester,
      FloorLayoutView(sections: const [], tables: tables),
      surface: _phone,
    );
    // A RenderFlex overflow throws here, which is how the header's own
    // overflow was caught the first time.
    expect(tester.takeException(), isNull);
    expect(find.text('tables.title'), findsOneWidget);
  });

  testWidgets('the empty room fits a phone too', (tester) async {
    await _pump(
      tester,
      const FloorLayoutView(sections: [], tables: []),
      surface: _phone,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('tables.empty_title'), findsOneWidget);
  });

  testWidgets('renders chrome and pops back when the floor is EMPTY', (
    tester,
  ) async {
    await _pump(tester, const FloorLayoutView(sections: [], tables: []));
    expect(tester.takeException(), isNull);
    // The screen is on stage with its title + empty state (not a blank page).
    expect(find.text('tables.title'), findsOneWidget);
    expect(find.text('tables.empty_title'), findsOneWidget);

    // …and the back button actually leaves.
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is MadarGlyphTile && w.glyph == MadarGlyph.chevronBack,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('tables.title'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('renders tables that belong to no section, and pops back', (
    tester,
  ) async {
    await _pump(
      tester,
      FloorLayoutView(
        sections: const [
          FloorSectionInfo(
            id: 'sec-in',
            name: 'Inside',
            ordering: 0,
            canvasW: 1000,
            canvasH: 700,
          ),
        ],
        // The regression: section-less tables used to be filtered out of
        // every tab, leaving an empty canvas.
        tables: [
          _table(id: 't1', label: 'A1'),
          _table(id: 't2', label: 'A2', x: 300),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is MadarGlyphTile && w.glyph == MadarGlyph.chevronBack,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('multiple sections move between them on a tap', (tester) async {
    // A shop with a terrace and a bar: each area's tables must show ONLY when
    // its own tab is active, and switching never leaves the other area's
    // tables lingering on screen.
    await _pump(
      tester,
      FloorLayoutView(
        sections: const [
          FloorSectionInfo(
            id: 'sec-terrace',
            name: 'Terrace',
            ordering: 0,
            canvasW: 500,
            canvasH: 400,
          ),
          FloorSectionInfo(
            id: 'sec-bar',
            name: 'Bar',
            ordering: 1,
            canvasW: 500,
            canvasH: 400,
          ),
        ],
        tables: [
          _table(id: 't1', sectionId: 'sec-terrace'),
          _table(id: 't2', sectionId: 'sec-bar', label: 'T2'),
        ],
      ),
    );
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('T2'), findsNothing);

    await tester.tap(find.text('Bar · 1'));
    await tester.pumpAndSettle();
    expect(find.text('T2'), findsOneWidget);
    expect(find.text('T1'), findsNothing);
  });

  testWidgets('abandoning a live unpaid bill from the floor confirms first', (
    tester,
  ) async {
    // Destructive: it walks away from a bill nobody paid. It must not fire
    // on the one tap that opens the sheet — a rushed hand would abandon a
    // real tab with no way back.
    final tickets = [
      TicketView(
        id: 'tk-1',
        tableId: 't1',
        status: 'open',
        subtotalMinor: 4500,
        openedAt: DateTime.now().toUtc().toIso8601String(),
        queuedOffline: false,
        lines: const [],
      ),
    ];
    await _pump(
      tester,
      FloorLayoutView(
        sections: const [],
        tables: [_table(id: 't1', status: 'seated')],
      ),
      tickets: tickets,
    );

    // A live bill: tapping the table opens it, not the menu.
    await tester.tap(find.text('T1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tables.free_it'));
    await tester.pumpAndSettle();

    // The void sheet is up — not an immediate abandon. It IS the
    // confirmation, and it asks the question a Yes/No cannot: why. (The
    // plain confirm this used to show sat in front of a call that refuses
    // outright when a live ticket is passed, so the teller confirmed an
    // irreversible act and was then told to settle the bill instead.)
    expect(find.text('void.title'), findsOneWidget);
    expect(find.text('void.reason'), findsOneWidget);
    expect(find.text('void.confirm'), findsOneWidget);

    // Backing out leaves it exactly there: the sheet closes, nothing fired.
    await tester.tap(find.text('void.cancel'));
    await tester.pumpAndSettle();
    expect(find.text('void.title'), findsNothing);
  });
}
