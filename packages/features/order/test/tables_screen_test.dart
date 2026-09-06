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
}) => FloorTableStateView(
  id: id,
  sectionId: sectionId,
  label: label,
  seats: 4,
  shape: 'rect',
  status: 'free',
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
  _FakeBridge(this.layout);

  final FloorLayoutView layout;

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
    if (name == #cartLines) return Future<List<CartLineView>>.value(const []);
    if (name == #currentSession) return null;
    if (name == #clockSkewMinutes) return 0;
    return null;
  }
}

Future<void> _pump(WidgetTester tester, FloorLayoutView layout) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(_FakeBridge(layout))],
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
  testWidgets('renders chrome and pops back when the floor is EMPTY', (
    tester,
  ) async {
    await _pump(tester, const FloorLayoutView(sections: [], tables: []));
    expect(tester.takeException(), isNull);
    // The screen is on stage with its title + empty state (not a blank page).
    expect(find.text('tables.title'), findsOneWidget);
    expect(find.text('tables.empty_title'), findsOneWidget);

    // …and the back button actually leaves.
    await tester.tap(find.byIcon(madarIconCatalog['chevron.backward']!));
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

    await tester.tap(find.byIcon(madarIconCatalog['chevron.backward']!));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
