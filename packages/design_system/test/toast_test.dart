// The toast renders at the app root, above the routes and any sheet (the
// staff app mounts it in MaterialApp.builder, outside every Material). There
// the only ambient text style is Flutter's error fallback: red-ish, with a
// yellow double underline. The E2E run (requests area) showed every staff-app
// toast underlined in yellow; the toast must carry its own text style.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a toast at the app root is not underlined', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        builder: (context, child) => Stack(
          children: [
            child!,
            const ToastHost(
              ToastData(
                id: 1,
                text: 'Sent to your manager',
                actionLabel: 'Undo',
              ),
            ),
          ],
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['Sent to your manager', 'Undo']) {
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(ToastHost),
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == label,
          ),
        ),
      );
      final style = rich.text.style;
      expect(
        style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: '"$label" must not inherit the fallback underline',
      );
      expect(style?.fontFamily, isNot('monospace'));
    }
  });
}
