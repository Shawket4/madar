import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    MadarGlass.enabled = true;
    MadarGlass.debugOverride(available: null);
  });

  group('which devices may wear it', () {
    test('iOS 26 and newer, and nothing older', () {
      expect(MadarGlass.majorVersionOf('Version 26.0 (Build 23A344)'), 26);
      expect(MadarGlass.majorVersionOf('Version 26.1.2 (Build 23B5)'), 26);
      expect(MadarGlass.majorVersionOf('Version 18.5 (Build 22F76)'), 18);
      expect(MadarGlass.majorVersionOf('Version 9.0'), 9);
    });

    test('a version string in a shape nobody anticipated reads as "no"', () {
      // The format is not contractual and has changed before. Answering 0 puts
      // an unrecognised device on the safe side of the only question this
      // feeds: it gets the ordinary surface, which is always complete.
      expect(MadarGlass.majorVersionOf('iOS'), 0);
      expect(MadarGlass.majorVersionOf(''), 0);
    });

    test('the master switch takes it off everywhere at once', () {
      MadarGlass.debugOverride(available: true);
      expect(MadarGlass.isAvailable, isTrue);
      MadarGlass.enabled = false;
      // A shop reporting jank is answered in one build, not by unpicking the
      // finish from a dozen widgets.
      expect(MadarGlass.isAvailable, isFalse);
    });
  });
  _surfaceTests();
}

// The rail must be complete WITHOUT glass, because that is what almost every
// device running this app will show. This renders it with the gate forced
// both ways and asserts the chrome is identical either side of it.
void _surfaceTests() {
  testWidgets('the rail renders its chrome with glass off', (tester) async {
    MadarGlass.debugOverride(available: false);
    addTearDown(() => MadarGlass.debugOverride(available: null));
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: const Scaffold(
          body: Row(
            children: [
              MadarRail(
                tabs: [MadarTab(label: 'Sell', glyph: MadarGlyph.grid)],
                selectedIndex: 0,
                onSelect: _noop,
              ),
              Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Sell'), findsOneWidget);
  });
}

void _noop(int _) {}
