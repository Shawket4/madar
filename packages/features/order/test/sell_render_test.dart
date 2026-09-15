// The Sell redesign matrix: every Sell state at iPad landscape and portrait,
// desktop and phone, in English and Arabic, light and dark — so the screen can
// be LOOKED at beside the spec renders.
//
// `MADAR_RENDER=true` writes `build/render/sell-<scene>-<device>-<lang>-<theme>.png`.
// Without it every frame still lays out and fails on any exception.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart'
    show CartKitchenChitSheet, KitchenChitSheet;
import 'package:feature_order/feature_order.dart';
import 'package:feature_order/src/bundle_detail_sheet.dart';
import 'package:feature_order/src/held_orders_strip.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/sell_cart.dart';
import 'package:feature_order/src/sell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

part 'sell_harness.dart';

const Size _ipadPortrait = Size(834, 1194);
const Size _desktop = Size(1280, 800);

const _devices = <(String, Size)>[
  ('ipad', _ipad),
  ('ipadp', _ipadPortrait),
  ('desktop', _desktop),
  ('phone', _phone),
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(_loadFonts);

  group('assigning a held order to a table', () {
    Future<void> assignVia(WidgetTester tester, String chip) async {
      // Invoked: the strip draws the pencil on the chip in hand only.
      final tab = tester
          .widget<HeldOrdersStrip>(find.byType(HeldOrdersStrip))
          .tabs
          .firstWhere((t) => t.key == chip);
      tab.onRename!();
      await _settle(tester);
      await tester.tap(find.text(coreWord('tables.assign')).last);
      await _settle(tester);
      await tester.tap(find.text('T6').last);
      await _settle(tester);
    }

    testWidgets('the order in hand parks ON the table, and says so', (
      tester,
    ) async {
      final bridge = _FakeBridge();
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      final lines = c.read(orderProvider).drafts.length;
      expect(lines, 1);
      await assignVia(tester, '__current__');
      expect(bridge.parked, ['t6'], reason: 'the lines go to the table');
      expect(
        bridge.carts['t6'] ?? const [],
        isEmpty,
        reason: 'the Sell tab never becomes the table',
      );
      expect(bridge.carts[null], isEmpty, reason: 'the lines left takeaway');
      expect(c.read(orderProvider).toast?.text, 'Held on T6');
    });

    testWidgets('a parked order moves to the table, and says so', (
      tester,
    ) async {
      final bridge = _FakeBridge();
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await assignVia(tester, 'd1');
      expect(bridge.assigned, ['t6']);
      expect(c.read(orderProvider).toast?.text, 'Held on T6');
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('a cart line prints its own kitchen chit', () {
    const tile = ValueKey('kitchen-k-espresso');

    testWidgets('a tap prints at once, with no sheet', (tester) async {
      final bridge = _FakeBridge();
      final c = await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      expect(
        find.bySemanticsLabel(coreWord('sell.kitchen_row_hint')),
        findsWidgets,
        reason: 'the button says what it does, distinct from the cart-level one',
      );
      await tester.tap(find.byKey(tile));
      await _settle(tester);
      expect(bridge.chitsBuilt, ['k-espresso'], reason: 'just that line');
      expect(bridge.chitsSent.map((s) => s.$1), ['10.0.0.5']);
      expect(find.byType(KitchenChitSheet), findsNothing);
      expect(c.read(orderProvider).toast?.text, coreWord('printing.chit_sent'));
      expect(bridge.carts[null]!.map((l) => l.key), [
        'k-espresso',
        'k-flat',
      ], reason: 'printing a chit changes nothing in the cart');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'a long press opens the row sheet, titled with the item, with its own note/preview/print',
      (tester) async {
        final bridge = _FakeBridge();
        await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: _ipad,
          bridge: bridge,
        );
        await tester.longPress(find.byKey(tile));
        await _settle(tester);
        expect(find.text('Espresso'), findsWidgets, reason: 'titled with the item');
        expect(
          find.text(coreWord('sell.kitchen_row_sheet_preview')),
          findsOneWidget,
        );
        expect(
          find.text(coreWord('sell.kitchen_row_sheet_print')),
          findsOneWidget,
        );

        // Preview opens the shared chit sheet; it prints nothing by itself.
        await tester.tap(find.text(coreWord('sell.kitchen_row_sheet_preview')));
        await _settle(tester);
        expect(find.byType(KitchenChitSheet), findsOneWidget);
        expect(find.text('1x k-espresso'), findsOneWidget);
        expect(bridge.chitsSent, isEmpty, reason: 'a preview prints nothing');

        await tester.tap(
          find.descendant(
            of: find.byType(KitchenChitSheet),
            matching: find.text(coreWord('printing.chit')),
          ),
        );
        await _settle(tester);
        expect(bridge.chitsSent.map((s) => s.$1), ['10.0.0.5']);
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets("the sheet's Print for kitchen prints without a preview", (
      tester,
    ) async {
      final bridge = _FakeBridge();
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await tester.longPress(find.byKey(tile));
      await _settle(tester);
      await tester.tap(find.text(coreWord('sell.kitchen_row_sheet_print')));
      await _settle(tester);
      expect(bridge.chitsSent.map((s) => s.$1), ['10.0.0.5']);
      expect(find.byType(KitchenChitSheet), findsNothing);
    });
  });

  group('a kitchen note is local, print-only, and clears on print', () {
    const tile = ValueKey('kitchen-k-espresso');

    testWidgets('setting it shows on the line, and it clears once that line prints', (
      tester,
    ) async {
      final bridge = _FakeBridge();
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await tester.longPress(find.byKey(tile));
      await _settle(tester);
      await tester.tap(find.text(coreWord('sell.kitchen_row_sheet_note')));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'no ice');
      await tester.tap(find.text(coreWord('common.save')));
      await _settle(tester);

      expect(
        bridge.lineKitchenNotes[null]?['k-espresso'],
        'no ice',
        reason: 'the core keeps it, keyed by cart line',
      );
      expect(find.textContaining('no ice'), findsOneWidget);

      // Print from the still-open row sheet (the note-edit sheet popped back
      // to it) — the same "Print for kitchen" action the row's own tile
      // triggers on a short press.
      await tester.tap(find.text(coreWord('sell.kitchen_row_sheet_print')));
      await _settle(tester);
      expect(
        bridge.lineKitchenNotes[null]?.containsKey('k-espresso'),
        isNot(true),
        reason: 'a printed chit is done with its note',
      );
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('the whole cart prints one kitchen job', () {
    const cartPrintButton = ValueKey('print-cart-kitchen');

    testWidgets('a tap builds and sends the whole-cart chit at once', (
      tester,
    ) async {
      final bridge = _FakeBridge();
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      expect(
        find.textContaining(coreWord('sell.kitchen_cart_button')),
        findsWidgets,
      );
      await tester.tap(find.byKey(cartPrintButton));
      await _settle(tester);
      expect(bridge.cartKitchenChitsBuilt, 1);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a long press previews the whole cart before printing', (
      tester,
    ) async {
      final bridge = _FakeBridge();
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await tester.longPress(find.byKey(cartPrintButton));
      await _settle(tester);
      expect(find.byType(CartKitchenChitSheet), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('destructive acts confirm', () {
    testWidgets('clearing the cart asks, and Cancel keeps it', (tester) async {
      final bridge = _FakeBridge();
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      Future<void> openClear() async {
        // Invoked directly: the tap lands on the header, not the glyph tile.
        tester
            .widget<MadarGlyphTile>(
              find
                  .byWidgetPredicate(
                    (w) => w is MadarGlyphTile && w.glyph == MadarGlyph.more,
                  )
                  .first,
            )
            .onTap();
        await _settle(tester);
        await tester.tap(find.text(coreWord('order.clear')).last);
        await _settle(tester);
      }

      await openClear();
      expect(find.textContaining('items from the cart?'), findsOneWidget);
      expect(bridge.cleared, 0, reason: 'nothing goes before the answer');
      await tester.tap(find.text(coreWord('common.cancel')).last);
      await _settle(tester);
      expect(bridge.cleared, 0, reason: 'Cancel keeps the cart');

      await openClear();
      await tester.tap(find.text(coreWord('order.clear_cart')).last);
      await _settle(tester);
      expect(bridge.cleared, 1);
    });

    testWidgets('discarding a parked order asks, and Cancel keeps it', (
      tester,
    ) async {
      final bridge = _FakeBridge();
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      Future<void> tapClose() async {
        await tester.tap(
          find
              .byWidgetPredicate((w) => w is MadarIcon && w.name == 'xmark')
              .first,
        );
        await _settle(tester);
      }

      await tapClose();
      expect(find.text('Discard Ahmed?'), findsOneWidget);
      await tester.tap(find.text(coreWord('common.cancel')).last);
      await _settle(tester);
      expect(bridge.discarded, isEmpty);

      await tapClose();
      await tester.tap(find.text(coreWord('drafts.discard')).last);
      await _settle(tester);
      expect(bridge.discarded, ['d1']);
    });
  });

  for (final (device, size) in _devices) {
    for (final ar in [false, true]) {
      for (final dark in [false, true]) {
        final tag = '$device-${ar ? 'ar' : 'en'}-${dark ? 'dark' : 'light'}';

        testWidgets('sell counter $tag', (tester) async {
          await _mount(
            tester,
            screen: const TakeawaySellScreen(),
            size: size,
            dark: dark,
            bridge: _FakeBridge(rtl: ar),
          );
          await _capture(tester, 'sell-counter-$tag');
          if (size == _phone) {
            await tester.tap(
              find
                  .descendant(
                    of: find.byType(SellBar),
                    matching: find.byType(Nudge),
                  )
                  .last,
            );
            await _settle(tester);
            await _capture(tester, 'sell-cartsheet-$tag');
          }
        });

        if (dark) continue;

        testWidgets('sell round on a bill $tag', (tester) async {
          final bridge = _FakeBridge(rtl: ar);
          bridge.carts['t2'] = List.of(_cart);
          await _mount(
            tester,
            screen: const TableOrderScreen(tableId: 't2'),
            size: size,
            bridge: bridge,
          );
          await _settle(tester);
          await _capture(tester, 'sell-round-$tag');
        });

        testWidgets('sell with no shift $tag', (tester) async {
          await _mount(
            tester,
            screen: const TakeawaySellScreen(),
            size: size,
            bridge: _FakeBridge(rtl: ar, tillOpen: false),
          );
          expect(find.byType(SellNoTillNotice), findsOneWidget);
          await _capture(tester, 'sell-noshift-$tag');
        });

        testWidgets('sell item sheet $tag', (tester) async {
          await _mount(
            tester,
            screen: const TakeawaySellScreen(),
            size: size,
            bridge: _FakeBridge(rtl: ar),
          );
          await tester.longPress(find.byType(SellTile).at(1));
          await _settle(tester);
          expect(find.byType(ItemDetailSheet), findsOneWidget);
          await _capture(tester, 'sell-item-$tag');
        });

        testWidgets('sell bundle sheet $tag', (tester) async {
          await _mount(
            tester,
            screen: const TakeawaySellScreen(),
            size: size,
            bridge: _FakeBridge(rtl: ar, bundles: const [_combo]),
          );
          await tester.tap(
            find.widgetWithText(
              MadarChip,
              coreWord('order.combos', arabic: ar),
            ),
          );
          await _settle(tester);
          await tester.tap(find.text('Breakfast combo').last);
          await _settle(tester);
          expect(find.byType(BundleDetailSheet), findsOneWidget);
          await _capture(tester, 'sell-bundle-$tag');
        });
      }
    }
  }
}

const _combo = BundleView(
  id: 'combo',
  name: 'Breakfast combo',
  priceMinor: 9000,
  isAvailable: true,
  components: [
    BundleComponentView(
      itemId: 'croissant',
      itemName: 'Croissant',
      quantity: 1,
    ),
  ],
);
