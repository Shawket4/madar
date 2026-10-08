// The purchasing screenshot matrix: each tab's default state at {phone,
// tablet, desktop} x {en light, ar dark}; every dialog and state at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// the pages still render (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scrolls = find.byType(Scrollable);
  ScrollableState? state;
  for (final e in scrolls.evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0) {
      state = s;
      break;
    }
  }
  if (state == null) {
    await h.shot('purchasing/$name-1');
    return;
  }
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('purchasing/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('orders, all branches, $tag', (tester) async {
        final h = await pumpPurchasing(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'orders-all');
      });
      testWidgets('orders, Zamalek, $tag', (tester) async {
        final h = await pumpPurchasing(
          tester,
          path: purchasingAt(SeedIds.zamalek),
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'orders-zamalek');
      });
      testWidgets('suppliers, $tag', (tester) async {
        final h = await pumpPurchasing(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.tap(find.text(h.t('inventory.purchasing.suppliers')).first);
        await shootPage(h, 'suppliers');
      });
      testWidgets('reorder, Zamalek, $tag', (tester) async {
        final h = await pumpPurchasing(
          tester,
          path: purchasingAt(SeedIds.zamalek),
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.tap(find.text(h.t('inventory.purchasing.reorder')).first);
        await shootPage(h, 'reorder-zamalek');
      });
    }
  }
}
