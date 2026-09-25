// The app's one toast: what it keeps, what takes it down, and that the host
// draws it over a route pushed on the navigator below it.
import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a dismiss takes down its own toast and never a later one', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final toasts = c.read(appToastProvider.notifier);
    // The new-order alert, then a screen's message on top of it.
    final alert = toasts.show('New order', sticky: true);
    // Looking at the Queue takes down the ALERT — which is no longer shown.
    toasts
      ..show('Being edited on another till')
      ..dismiss(alert);
    expect(c.read(appToastProvider)?.text, 'Being edited on another till');
  });

  test('an action runs once, and a label with no action is not offered', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final toasts = c.read(appToastProvider.notifier);
    var ran = 0;
    toasts.show('Moved', actionLabel: 'Undo', action: () => ran += 1);
    expect(c.read(appToastProvider)?.actionLabel, 'Undo');
    toasts
      ..runAction()
      ..runAction();
    expect(ran, 1);
    expect(c.read(appToastProvider), isNull);

    toasts.show('Saved', actionLabel: 'Undo');
    expect(
      c.read(appToastProvider)?.actionLabel,
      isNull,
      reason: 'a tap that does nothing is its own silent failure',
    );
  });

  testWidgets('the layer draws the toast over a route pushed below it, and '
      'the toast leaves on its own', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          navigatorKey: nav,
          theme: MadarTheme.light(),
          builder: (context, child) => AppToastLayer(child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    nav.currentState!.push(
      DialogRoute<void>(
        context: nav.currentContext!,
        builder: (_) => const Text('a dialog in front'),
      ),
    );
    await tester.pumpAndSettle();
    c.read(appToastProvider.notifier).show('Sent to kitchen');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.descendant(
        of: find.byType(ToastHost),
        matching: find.text('Sent to kitchen'),
      ),
      findsOneWidget,
    );
    // The host's own timer takes it down after its seconds.
    await tester.pump(const Duration(seconds: 3));
    expect(c.read(appToastProvider), isNull);
    await tester.pumpAndSettle();
  });
}
