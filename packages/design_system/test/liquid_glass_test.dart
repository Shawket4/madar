import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    LiquidGlass.enabled = true;
    LiquidGlass.debugOverride(available: null);
  });

  group('which devices may wear it', () {
    test('iOS 26 and newer, and nothing older', () {
      expect(LiquidGlass.majorVersionOf('Version 26.0 (Build 23A344)'), 26);
      expect(LiquidGlass.majorVersionOf('Version 26.1.2 (Build 23B5)'), 26);
      expect(LiquidGlass.majorVersionOf('Version 18.5 (Build 22F76)'), 18);
      expect(LiquidGlass.majorVersionOf('Version 9.0'), 9);
    });

    test('a version string in a shape nobody anticipated reads as "no"', () {
      // The format is not contractual and has changed before. Answering 0 puts
      // an unrecognised device on the safe side of the only question this
      // feeds: it gets the ordinary surface, which is always complete.
      expect(LiquidGlass.majorVersionOf('iOS'), 0);
      expect(LiquidGlass.majorVersionOf(''), 0);
    });

    test('the master switch takes it off everywhere at once', () {
      LiquidGlass.debugOverride(available: true);
      expect(LiquidGlass.isAvailable, isTrue);
      LiquidGlass.enabled = false;
      // A shop reporting jank is answered in one build, not by unpicking the
      // finish from a dozen widgets.
      expect(LiquidGlass.isAvailable, isFalse);
    });
  });
}
