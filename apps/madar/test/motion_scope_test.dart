// The Animations setting reaches every widget through
// `MediaQuery.disableAnimations`, applied above the navigator by the shell.
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/shell.dart';

void main() {
  Future<bool> reducedUnder(
    WidgetTester tester,
    MotionChoice choice, {
    required bool platform,
  }) async {
    late bool seen;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: platform),
        child: Builder(
          builder: (context) => motionScope(
            context,
            choice,
            Builder(
              builder: (inner) {
                seen = motionReduced(inner);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    return seen;
  }

  testWidgets('Full animates even when the platform asks for less', (
    tester,
  ) async {
    expect(
      await reducedUnder(tester, MotionChoice.full, platform: true),
      false,
    );
  });

  testWidgets('Reduced tones down even when the platform does not', (
    tester,
  ) async {
    expect(
      await reducedUnder(tester, MotionChoice.reduced, platform: false),
      true,
    );
  });

  testWidgets('System follows the platform', (tester) async {
    expect(
      await reducedUnder(tester, MotionChoice.system, platform: true),
      true,
    );
    expect(
      await reducedUnder(tester, MotionChoice.system, platform: false),
      false,
    );
  });
}
