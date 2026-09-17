// The held-orders strip after a teller switch: an order someone else started
// says whose it is, to sight and to a screen reader; one's own says nothing.

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/held_orders_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a parked order someone else started shows its author', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MadarTheme.light(),
          home: Scaffold(
            body: HeldOrdersStrip(
              newLabel: 'New',
              tabs: [
                HeldOrderTab(
                  key: 'd-1',
                  sortKey: '2026-09-17T09:00:00Z',
                  title: 'Omar',
                  count: 2,
                  selected: false,
                  onTap: () {},
                  author: 'Ali',
                  authorLabel: 'Started by Ali',
                ),
                HeldOrderTab(
                  key: 'd-2',
                  sortKey: '2026-09-17T09:05:00Z',
                  title: 'Mine',
                  count: 1,
                  selected: false,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Finder spoken(String label) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label,
    );
    expect(find.text('Ali'), findsOneWidget, reason: 'the author, on sight');
    expect(spoken('Started by Ali'), findsOneWidget, reason: 'and spoken');
    expect(find.text('Omar'), findsOneWidget);
    expect(find.text('Mine'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics && (w.properties.label ?? '').startsWith('Started'),
      ),
      findsOneWidget,
      reason: "one's own order names nobody",
    );
    handle.dispose();
  });
}
