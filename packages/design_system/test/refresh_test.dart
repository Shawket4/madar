// Pull to refresh (refresh.dart): a short list still pulls, a body that does
// not scroll pulls through MadarPullable, a nested list pulls only when the
// wrapper is nested, a sideways strip never pulls, and the ring stays up
// until the refresh completes.

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget body) => MaterialApp(
  theme: MadarTheme.light(),
  home: Scaffold(body: body),
);

/// A pull: a drag down from near the top, then the ring's settle.
Future<void> _pull(WidgetTester tester, Finder from) async {
  await tester.fling(from, const Offset(0, 300), 1000);
  await tester.pump();
  // The indicator snaps and calls onRefresh on its own clock.
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('a list shorter than the screen still pulls', (tester) async {
    var pulls = 0;
    await tester.pumpWidget(
      _app(
        MadarRefresh(
          onRefresh: () async => pulls++,
          child: ListView(
            physics: MadarRefresh.physics,
            children: const [Text('one row')],
          ),
        ),
      ),
    );
    await _pull(tester, find.text('one row'));
    expect(pulls, 1);
  });

  testWidgets('without the physics a short list does not pull', (tester) async {
    var pulls = 0;
    await tester.pumpWidget(
      _app(
        MadarRefresh(
          onRefresh: () async => pulls++,
          child: ListView(primary: false, children: const [Text('one row')]),
        ),
      ),
    );
    await _pull(tester, find.text('one row'));
    expect(pulls, 0, reason: 'why every pullable list takes the physics');
  });

  testWidgets('MadarPullable: a column with an Expanded body pulls', (
    tester,
  ) async {
    var pulls = 0;
    await tester.pumpWidget(
      _app(
        MadarRefresh(
          onRefresh: () async => pulls++,
          child: const MadarPullable(
            child: Column(
              children: [
                Text('bar'),
                Expanded(child: SizedBox.expand(key: ValueKey('body'))),
              ],
            ),
          ),
        ),
      ),
    );
    // The Expanded body got the rest of the viewport.
    expect(
      tester.getSize(find.byKey(const ValueKey('body'))).height,
      greaterThan(400),
    );
    await _pull(tester, find.text('bar'));
    expect(pulls, 1);
  });

  Widget nestedList({required bool nested, required VoidCallback onPull}) =>
      MadarRefresh(
        nested: nested,
        onRefresh: () async => onPull(),
        child: MadarPullable(
          child: Column(
            children: [
              const Text('bar'),
              SizedBox(
                height: 60,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [for (var i = 0; i < 30; i++) Text('chip $i  ')],
                ),
              ),
              Expanded(
                child: ListView(
                  physics: MadarRefresh.physics,
                  children: const [Text('inner row')],
                ),
              ),
            ],
          ),
        ),
      );

  testWidgets('nested: a pull on an inner list refreshes', (tester) async {
    var pulls = 0;
    await tester.pumpWidget(
      _app(nestedList(nested: true, onPull: () => pulls++)),
    );
    await _pull(tester, find.text('inner row'));
    expect(pulls, 1);
  });

  testWidgets('not nested: only the nearest scrollable pulls', (tester) async {
    var pulls = 0;
    await tester.pumpWidget(
      _app(nestedList(nested: false, onPull: () => pulls++)),
    );
    await _pull(tester, find.text('inner row'));
    expect(pulls, 0);
    await _pull(tester, find.text('bar'));
    expect(pulls, 1);
  });

  testWidgets('a sideways strip never pulls', (tester) async {
    var pulls = 0;
    await tester.pumpWidget(
      _app(nestedList(nested: true, onPull: () => pulls++)),
    );
    await tester.fling(find.text('chip 0  '), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(pulls, 0);
  });

  testWidgets('the ring stays up until the refresh completes', (tester) async {
    final done = Completer<void>();
    await tester.pumpWidget(
      _app(
        MadarRefresh(
          onRefresh: () => done.future,
          child: ListView(
            physics: MadarRefresh.physics,
            children: const [Text('one row')],
          ),
        ),
      ),
    );
    await _pull(tester, find.text('one row'));
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });
}
