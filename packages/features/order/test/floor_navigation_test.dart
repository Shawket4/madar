// How a teller gets between the floor and the order screen.
//
// Two shapes, and the difference matters. Where the order screen is home the
// floor is PUSHED on top of it; where a shop puts every sale on a table the
// floor is home and the order screen is pushed on top of THAT. The same
// buttons have to do the right thing in both, or a teller ends up with two
// copies of the room on the stack and two backs to reach a screen that was one
// back away.

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/tables_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _phone = Size(390, 844);

FloorTableStateView _table({String id = 't1', String label = 'T1'}) =>
    FloorTableStateView(
      id: id,
      label: label,
      seats: 4,
      shape: 'rect',
      status: 'free',
      posX: 0,
      posY: 0,
      width: 80,
      height: 80,
      rotation: 0,
      heldLockedByOther: false,
    );

/// Permissive stand-in: `tr` echoes its key so finders can match on it.
class _FakeBridge implements MadarBridge {
  _FakeBridge(this.layout);
  final FloorLayoutView layout;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) return invocation.namedArguments[#key] as String? ?? '';
    if (name == #floorLayout) return Future<FloorLayoutView>.value(layout);
    if (name == #refreshFloor) return Future<void>.value();
    // The floor loads its bills now — both roles, since which tables have
    // ordered is part of the room's state.
    if (name == #listOpenTickets) {
      return Future<List<TicketView>>.value(const []);
    }
    if (name == #listTransferQueue) {
      return Future<List<TransferQueueView>>.value(const []);
    }
    if (name == #listArrivals) return Future<List<BookingView>>.value(const []);
    if (name == #clockSkewMinutes) return 0;
    return null;
  }
}

Future<void> _pumpHomeFloor(WidgetTester tester, FloorLayoutView layout) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _phone;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(_FakeBridge(layout))],
      child: MaterialApp(
        theme: MadarTheme.light(),
        // No route beneath: this IS home, exactly as the shell mounts it where
        // the shop puts every sale on a table.
        home: const TablesScreen(isHome: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the home floor shows no back button', (tester) async {
    // There is nothing behind it. A back arrow that pops to a black screen is
    // worse than no arrow.
    await _pumpHomeFloor(
      tester,
      FloorLayoutView(sections: const [], tables: [_table()]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('tables.title'), findsOneWidget);
    expect(
      find.byIcon(madarIconCatalog['chevron.backward']!),
      findsNothing,
      reason: 'home has nothing to go back to',
    );
  });

  testWidgets('a pushed floor keeps its back button', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _phone;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeProvider.overrideWithValue(
            _FakeBridge(
              FloorLayoutView(sections: const [], tables: [_table()]),
            ),
          ),
        ],
        child: MaterialApp(
          theme: MadarTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TablesScreen(),
                    ),
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
    expect(tester.takeException(), isNull);
    expect(find.text('tables.title'), findsOneWidget);

    // Pushed from somewhere, so leaving has a destination — and actually goes
    // there. This is the half the home floor deliberately lacks.
    await tester.tap(find.byIcon(madarIconCatalog['chevron.backward']!));
    await tester.pumpAndSettle();
    expect(
      find.text('open'),
      findsOneWidget,
      reason: 'the back button returned to what pushed the floor',
    );
  });

  testWidgets('the home floor survives a system back', (tester) async {
    // Android's gesture/button back reaches a home route too. Popping the last
    // route leaves a black screen, so this must be a no-op rather than a
    // crash or a blank page.
    await _pumpHomeFloor(
      tester,
      FloorLayoutView(sections: const [], tables: [_table()]),
    );
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      popped,
      isFalse,
      reason: 'nothing to pop: the floor is the last route',
    );
    expect(
      find.text('tables.title'),
      findsOneWidget,
      reason: 'still on screen',
    );
  });
}
