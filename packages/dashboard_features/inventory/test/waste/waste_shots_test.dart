// The Waste log screenshot matrix: Zamalek and All branches at {phone,
// tablet, desktop} x {en light, ar dark}; the log's loading, error and empty
// states, the by-reason states, the dialog (filled, over on hand), the
// count-first banner and the open picker at desktop-en-light and
// phone-ar-light. Written only with FDASH_SHOTS set; the pages still render
// (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];
const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  ScrollableState? state;
  for (final e in find
      .ancestor(of: page, matching: find.byType(Scrollable))
      .evaluate()
      .followedBy(
        find.descendant(of: page, matching: find.byType(Scrollable)).evaluate(),
      )) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0) {
      state = s;
      break;
    }
  }
  if (state == null) {
    await h.shot('waste/$name-1');
    return;
  }
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('waste/$name-$i');
    if (y >= position.maxScrollExtent || i >= 5) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

Finder get _ingredientPicker => inDialog(
  find.descendant(
    of: byKey('waste-ingredient'),
    matching: find.byType(DashSelectTrigger),
  ),
);

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, Zamalek, $tag', (tester) async {
        final h = await pumpWaste(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          branch: SeedIds.zamalek,
        );
        await shootPage(h, 'default-zamalek');
      });
      testWidgets('default, all branches, $tag', (tester) async {
        final h = await pumpWaste(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default-all');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    testWidgets('loading, $tag', (tester) async {
      final s = wasteServer();
      final log = s.server.hold('GET', logRoute);
      final report = s.server.hold('GET', reportRoute);
      final h = await pumpWaste(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      await shootPage(h, 'loading');
      log.release();
      report.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = wasteServer();
      s.server.fail('GET', logRoute, MockResponse.error(500, 'Server error'));
      s.server.fail('GET', reportRoute, MockResponse.error(500, 'Server error'));
      final h = await pumpWaste(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
      );
      await shootPage(h, 'failed');
    });

    testWidgets('empty (Heliopolis), $tag', (tester) async {
      final h = await pumpWaste(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.heliopolis,
      );
      await shootPage(h, 'empty');
    });

    testWidgets('dialog, filled and over on hand, $tag', (tester) async {
      final h = await pumpWaste(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await h.tap(inPage(byKey('waste-record')));
      await h.shot('waste/dialog-blank');
      await pickSearch(h, _ingredientPicker, 'Matcha Powder');
      await h.enterText(inDialog(byKey('waste-quantity')), '100');
      await h.enterText(inDialog(byKey('waste-note')), 'Dropped the tin');
      await h.shot('waste/dialog-over');
    });

    testWidgets('dialog, picker open, $tag', (tester) async {
      final h = await pumpWaste(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.zamalek,
      );
      await h.tap(inPage(byKey('waste-record')));
      await h.tap(_ingredientPicker);
      await h.shot('waste/dialog-picker');
    });

    testWidgets('dialog, count first (Heliopolis), $tag', (tester) async {
      final h = await pumpWaste(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        branch: SeedIds.heliopolis,
      );
      await h.tap(inPage(byKey('waste-record')));
      await h.shot('waste/dialog-count-first');
    });
  }
}
