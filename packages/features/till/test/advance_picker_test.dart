// The pay-out's "Expense advance to" picker lists the branch's people. On
// the till (E2E posnotif, iPad) it opened while the amount's keyboard was up,
// in a sheet shorter than the list: the rows overflowed and the last people
// could not be reached. The list scrolls.
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.namedArguments;
    if (name == #tr) return args[#key];
    if (name == #listCashMovements) {
      return Future<List<CashMovementView>>.value(const []);
    }
    if (name == #tillFiguresVisible) return true;
    if (name == #formatMoney) return '${args[#minor]}';
    if (name == #branchPeople) {
      return Future<List<BranchPersonView>>.value([
        for (var i = 1; i <= 14; i++)
          BranchPersonView(employeeId: 'e$i', name: 'Person $i'),
      ]);
    }
    return null;
  }
}

void main() {
  testWidgets('a long branch list scrolls in the picker, nothing overflows', (
    tester,
  ) async {
    // A short window: the till's sheet with the keyboard up.
    tester.view
      ..physicalSize = const Size(1000, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bridgeProvider.overrideWithValue(_Bridge())],
        child: MaterialApp(
          theme: MadarTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: CashInOutPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('cash.expense_advance'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Person 1'), findsOneWidget);
    // The last person is reachable and can be picked.
    await tester.scrollUntilVisible(
      find.text('Person 14'),
      100,
      // The picker's own list: the newest Scrollable, on top of the panel.
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Person 14'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text('Person 14'),
      findsOneWidget,
      reason: 'picked: shown as the value',
    );
  });
}
