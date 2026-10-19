// The Setup page's screenshots: a new shop, ready and live, at {phone,
// desktop} x {en, ar} x {light, dark}, scrolled through the page; the
// tablet sheet, an app's card and the home card. Written only with
// FDASH_SHOTS set; the pages still render (and must not overflow) without.
import 'package:dashboard_api/dashboard_api.dart' show Readiness;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashButton;
import 'package:dashboard_overview/src/setup/setup_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: find.byType(SetupPage), matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('setup/$name-$i');
    if (y >= position.maxScrollExtent || i >= 5) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  final stages = <String, Readiness Function()>{
    'new-shop': freshShop,
    'ready': readyShop,
    'live': () => readyShop(live: true),
  };
  for (final size in [DashSize.phone, DashSize.desktop]) {
    for (final lang in ['en', 'ar']) {
      for (final dark in [false, true]) {
        for (final MapEntry(key: name, value: r) in stages.entries) {
          testWidgets('$name, ${size.name} $lang ${dark ? 'dark' : 'light'}', (
            tester,
          ) async {
            final h = await pumpSetup(
              tester,
              r(),
              size: size,
              locale: lang,
              dark: dark,
            );
            await shootPage(h, name);
          });
        }
      }
    }
  }

  testWidgets('the entrance, in motion and at rest', (tester) async {
    final h = await pumpSetup(tester, readyShop(), reducedMotion: false);
    await h.shot('setup/entrance-mid');
    await tester.pump(const Duration(seconds: 2));
    await h.shot('setup/entrance-end');
  });

  for (final (size, lang, dark) in [
    (DashSize.desktop, 'en', false),
    (DashSize.phone, 'ar', true),
  ]) {
    testWidgets('the tablet sheet and an app card, ${size.name} $lang', (
      tester,
    ) async {
      final h = await pumpSetup(
        tester,
        freshShop(),
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(find.byKey(const ValueKey('app-tile-cashier')).first);
      await h.shot('setup/app-card');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      final connect = find.byWidgetPredicate(
        (w) => w is DashButton && w.label == h.t('setup.checks.tablet.action'),
      );
      await h.tap(connect);
      await h.shot('setup/tablet-sheet');
    });

    testWidgets('the home card, ${size.name} $lang', (tester) async {
      final s = serving(freshShop());
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('home/setup-card');
    });
  }
}
