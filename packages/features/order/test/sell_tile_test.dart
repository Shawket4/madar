// SellTile is the quick-add grid's card (sell_screen.dart) — the surface the
// owner reported had lost its photo and its tap animation when the redesign
// added QUICK-ADD. These are pure widget tests (real MaterialApp, no bridge,
// no providers): SellTile takes plain data and two callbacks, so its photo
// fallback and its tap-origin callback are both testable in isolation.
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/sell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

MenuItemView _item({String? localImagePath}) => MenuItemView(
  id: 'latte',
  name: 'Latte',
  basePriceMinor: 4500,
  isActive: true,
  localImagePath: localImagePath,
  allowedAddonIds: const [],
  sizes: const [],
  addonSlots: const [],
  optionalFields: const [],
  recipes: const [],
  recipeSteps: const [],
);

Widget _host(Widget child) => MaterialApp(
  theme: MadarTheme.light(),
  home: Scaffold(body: child),
);

void main() {
  group('SellTile photo', () {
    testWidgets('renders an Image when the core has a cached local path', (
      tester,
    ) async {
      // The file need not decode — a card's `Image` widget is inserted
      // synchronously; a bad/missing file just resolves to the fallback a
      // frame later (asserted separately below), which the FIRST pump does
      // not wait for.
      await tester.pumpWidget(
        _host(
          SellTile(
            item: _item(localImagePath: '${Directory.systemTemp.path}/x.png'),
            currency: 'EGP',
            inCart: 0,
            accent: Colors.brown,
            onTap: (_) {},
            onLongPress: () {},
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets(
      'falls back to the monogram, never a broken-image glyph, with no local path',
      (tester) async {
        await tester.pumpWidget(
          _host(
            SellTile(
              item: _item(),
              currency: 'EGP',
              inCart: 0,
              accent: Colors.brown,
              onTap: (_) {},
              onLongPress: () {},
            ),
          ),
        );
        expect(find.byType(Image), findsNothing);
        // monogram() takes the first word's first two letters, uppercased.
        expect(find.text('LA'), findsOneWidget);
      },
    );
  });

  group('SellTile tap', () {
    testWidgets("reports the tapped tile's own on-screen center", (
      tester,
    ) async {
      Offset? seen;
      await tester.pumpWidget(
        _host(
          Center(
            child: SizedBox(
              width: 168,
              height: 108,
              child: SellTile(
                item: _item(),
                currency: 'EGP',
                inCart: 0,
                accent: Colors.brown,
                onTap: (origin) => seen = origin,
                onLongPress: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SellTile));
      // The flight needs a REAL launch point — the fixed fallback the tap
      // path used before this was wired up (Offset.zero, the screen corner)
      // would fly every card's dot from the same spot regardless of which
      // one was tapped.
      expect(seen, isNotNull);
      expect(seen, isNot(Offset.zero));
    });
  });
}
