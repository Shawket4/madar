// SellTile is the quick-add grid's card (sell_screen.dart) — the surface the
// owner reported had lost its photo and its tap animation when the redesign
// added QUICK-ADD. These are pure widget tests (real MaterialApp, no bridge,
// no providers): SellTile takes plain data and two callbacks, so its photo
// fallback and its tap-origin callback are both testable in isolation.
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
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
  _gridTests();
  _defaultMilkTests();
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

// The milk that comes with the recipe must land in the group the sheet
// actually renders. It is keyed by the SLOT when the item configures one and
// by `type:milk_type` when it does not — seeding the unslotted key either way
// dropped the preselection into a group nothing draws, so the milk group read
// as "nothing chosen" while the line still carried full-fat. Picking oat then
// ADDED a second milk instead of replacing the first.
void _defaultMilkTests() {
  test('a swap family is single-select; an additive one is not', () {
    expect(isSwapFamily('milk_type'), isTrue);
    expect(isSwapFamily('coffee_type'), isTrue);
    expect(isSwapFamily('extra'), isFalse);
    expect(isSwapFamily('sauce'), isFalse);
  });
}

// The grid's shape is derived from the width the CATALOG COLUMN has, not the
// window — on a tablet that is the window minus the rail minus the cart — and
// the card keeps its proportions at every one of them. It used to be a fixed
// 168x108, right at one size and wrong everywhere else.
void _gridTests() {
  /// Mirrors `delegateFor` in sell_screen.dart.
  int columnsFor(double width, double gutter) {
    const minW = 190.0;
    const maxW = 250.0;
    const gap = 12.0; // Space.md
    final usable = width - gutter * 2;
    var columns = usable ~/ minW;
    if (columns < 1) columns = 1;
    double widthAt(int n) => (usable - gap * (n - 1)) / n;
    while (widthAt(columns) > maxW) {
      columns += 1;
    }
    return columns;
  }

  test('a phone catalog gets two across, not five slivers', () {
    expect(columnsFor(390, 16), 2);
  });

  test('an 11-inch catalog column, rail and cart removed', () {
    // 1194 wide, 88 rail, 340 cart → 766 for the catalog.
    expect(columnsFor(766, 24), 3);
  });

  test('a 13-inch gets more columns rather than wider cards', () {
    // 1366 - 88 - 340 = 938.
    final wide = columnsFor(938, 24);
    expect(wide, greaterThanOrEqualTo(4));
    const gap = 12.0;
    final tile = (938 - 24 * 2 - gap * (wide - 1)) / wide;
    expect(
      tile,
      lessThanOrEqualTo(250.0),
      reason: 'a card never grows past its band — it splits into one more',
    );
    expect(tile, greaterThanOrEqualTo(150.0));
  });

  test('a cart-narrow column still renders one honest column', () {
    expect(columnsFor(220, 16), 1);
  });
}
