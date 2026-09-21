// Shared by the app's widget tests: pump the real app for a persona, pump
// real frames, and tear the scope down before the test ends.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_staff/main.dart';
import 'package:madar_staff/shell.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

/// The core's own words, straight from i18n.rs — what a device shows.
void useCoreWords() =>
    words = (key) => coreWord(key, arabic: currentLang == 'ar');

/// Real frames: sheets slide in on a spring and a badge pulses for ever, so
/// pumpAndSettle would never settle.
Future<void> frames(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

late ProviderContainer testContainer;

/// Unmounts and disposes the scope, stopping the store's 30 s clock before
/// the test ends (a pending timer fails the test).
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  testContainer.dispose();
}

/// Pumps the app for [who] (null: signed out) on the given side and tab.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required String lang,
  String? who,
  bool manage = false,
  int tab = 0,
  Size size = const Size(390, 844),
  ThemeChoice theme = ThemeChoice.light,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      localeProvider.overrideWith(() => LocaleNotifier(initial: lang)),
      themeChoiceProvider.overrideWith(
        () => ThemeChoiceNotifier(initial: theme),
      ),
    ],
  );
  testContainer = container;
  container.read(localeProvider);
  final store = container.read(dawamProvider);
  if (who != null) {
    store
      ..privacyAccepted.add(who)
      ..signIn(who);
  }
  final shell = container.read(shellProvider.notifier);
  if (manage) shell.toggle();
  shell.select(tab);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(key: ValueKey('shot'), child: DawamApp()),
    ),
  );
  return container;
}
