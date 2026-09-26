// The Sell redesign matrix: every Sell state at iPad landscape and portrait,
// desktop and phone, in English and Arabic, light and dark — so the screen can
// be LOOKED at beside the spec renders.
//
// `MADAR_RENDER=true` writes `build/render/sell-<scene>-<device>-<lang>-<theme>.png`.
// Without it every frame still lays out and fails on any exception.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart'
    show CartKitchenChitSheet, ChargeOutcome, ChargeSheet, KitchenChitSheet;
import 'package:feature_order/feature_order.dart';
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

/// The iPad 9th generation (10.2", 4:3): the smallest iPad the till ships on.
const Size _ipad9 = Size(1080, 810);
const Size _ipad9Portrait = Size(810, 1080);

/// An 8" Android tablet, portrait.
const Size _tab8 = Size(800, 1280);

/// A Lenovo Tab (M8 rotated, M10/M11 natural) in landscape.
const Size _lenovo = Size(1280, 800);

const _devices = <(String, Size)>[
  ('ipad', _ipad),
  ('ipadp', _ipadPortrait),
  ('ipad9', _ipad9),
  ('ipad9p', _ipad9Portrait),
  ('tab8', _tab8),
  ('lenovo', _lenovo),
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
  group('a tap after Clear', _clearThenTapMain);
  group('a tap is never answered with nothing', _neverNothingMain);
  group('the keyboard up on an iPad in landscape', _keyboardMain);

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
      expect(c.read(appToastProvider)?.text, 'Held on T6');
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
      expect(c.read(appToastProvider)?.text, 'Held on T6');
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
      await _selectLine(tester, 'k-espresso');
      expect(
        find.bySemanticsLabel(coreWord('sell.kitchen_row_hint')),
        findsWidgets,
        reason:
            'the button says what it does, distinct from the cart-level one',
      );
      await tester.tap(find.byKey(tile));
      await _settle(tester);
      expect(bridge.chitsBuilt, ['k-espresso'], reason: 'just that line');
      expect(bridge.chitsSent.map((s) => s.$1), ['10.0.0.5']);
      expect(find.byType(KitchenChitSheet), findsNothing);
      expect(c.read(appToastProvider)?.text, coreWord('printing.chit_sent'));
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
        await _selectLine(tester, 'k-espresso');
        await tester.longPress(find.byKey(tile));
        await _settle(tester);
        expect(
          find.text('Espresso'),
          findsWidgets,
          reason: 'titled with the item',
        );
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
      await _selectLine(tester, 'k-espresso');
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

    testWidgets(
      'setting it shows on the line, and it clears once that line prints',
      (tester) async {
        final bridge = _FakeBridge();
        await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: _ipad,
          bridge: bridge,
        );
        await _selectLine(tester, 'k-espresso');
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
        // On the line, and on the still-open row sheet's note chip, which
        // now follows the line it was opened for.
        expect(find.textContaining('no ice'), findsNWidgets(2));

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
      },
    );
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

  group('a bill round on the small iPad', () {
    for (final (label, size) in const [
      ('ipad9', _ipad9),
      ('lenovo', _lenovo),
    ]) {
      testWidgets('both lines of the round are in view on the $label', (
        tester,
      ) async {
        final bridge = _FakeBridge();
        bridge.carts['t2'] = List.of(_cart);
        await _mount(
          tester,
          screen: const TableOrderScreen(tableId: 't2'),
          size: size,
          bridge: bridge,
        );
        await _settle(tester);
        final cart = tester.getRect(find.byType(SellCart));
        // Every round line whole inside the cart: the footer no longer leaves
        // the list one line and a half tall.
        for (final key in ['round-k-espresso', 'round-k-flat']) {
          final line = tester.getRect(find.byKey(ValueKey(key)));
          expect(
            line.bottom <= cart.bottom && line.top >= cart.top,
            isTrue,
            reason: '$key is fully in view ($line within $cart)',
          );
        }
        // The dense footer: the compact kitchen button with the note as a
        // tile beside it — nothing hidden, the note still one tap away.
        expect(find.byKey(const ValueKey('cart-kitchen-note')), findsOneWidget);
        expect(
          tester
              .widget<MadarButton>(
                find.byKey(const ValueKey('print-cart-kitchen')),
              )
              .size,
          MadarButtonSize.compact,
        );
        // The controls sit on the selected line only.
        expect(find.byType(MadarStepper), findsNothing);
        await _selectLine(tester, 'k-espresso');
        await _selectLine(tester, 'k-flat');
        expect(find.byType(MadarStepper), findsNWidgets(2));
        for (final stepper in find.byType(MadarStepper).evaluate()) {
          expect(
            tester.getSize(find.byWidget(stepper.widget)).height,
            Metrics.stepperDense,
            reason: "the cart line's dense stepper",
          );
        }
        await _capture(tester, 'sell-round-$label-inview');
      });
    }

    testWidgets(
      'in portrait the catalog keeps three columns beside a 300 cart',
      (tester) async {
        await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: const Size(722, 1024),
          bridge: _FakeBridge(),
        );
        expect(tester.getSize(find.byType(SellCart)).width, 300);
        final tiles = find.byType(SellTile);
        final firstRowY = tester.getTopLeft(tiles.first).dy;
        final inFirstRow = tiles
            .evaluate()
            .where(
              (e) => tester.getTopLeft(find.byWidget(e.widget)).dy == firstRowY,
            )
            .length;
        expect(inFirstRow, 3);
        // Park keeps its word above Charge in the narrow column.
        expect(
          tester.widget(find.byKey(const ValueKey('cart-park'))),
          isA<MadarButton>(),
        );
        await _capture(tester, 'sell-counter-narrow-column');
      },
    );
  });

  group('Fast mode', () {
    Finder inCart(Finder f) =>
        find.descendant(of: find.byType(SellCart), matching: f);

    /// Fast mode's menu opens on the category boxes: open one.
    Future<void> openCategory(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(ValueKey('category-box-$id')));
      await _settle(tester);
    }

    testWidgets('the menu is category boxes; one opens, back returns', (
      tester,
    ) async {
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        layout: SellLayout.fast,
      );
      expect(find.byType(SellTile), findsNothing);
      for (final id in ['hot', 'cold', 'food']) {
        expect(find.byKey(ValueKey('category-box-$id')), findsOneWidget);
      }
      await openCategory(tester, 'cold');
      expect(find.byType(SellTile), findsNWidgets(2));
      expect(find.text('Iced latte'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('category-back')));
      await _settle(tester);
      expect(find.byType(SellTile), findsNothing);
      expect(find.byKey(const ValueKey('category-box-cold')), findsOneWidget);
    });

    testWidgets('a page in the panel closes from its back bar', (tester) async {
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        layout: SellLayout.fast,
      );
      await tester.tap(inCart(find.text(coreWord('sell.charge'))).last);
      await _settle(tester);
      expect(find.byType(ChargeSheet), findsOneWidget);
      expect(find.text(coreWord('sell.back_to_menu')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('panel-back')));
      await _settle(tester);
      expect(find.byType(ChargeSheet), findsNothing);
      expect(find.byKey(const ValueKey('category-box-hot')), findsOneWidget);
    });

    /// The page that holds [f]: a panel page, a sheet, or the screen.
    Route<Object?>? routeOf(WidgetTester tester, Finder f) =>
        ModalRoute.of(tester.element(f.first));

    testWidgets('the cart comes first and the menu sits at the end', (
      tester,
    ) async {
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        layout: SellLayout.fast,
      );
      final cart = tester.getRect(find.byType(SellCart));
      final menu = tester.getRect(find.byType(MenuGrid));
      expect(cart.left, lessThan(menu.left));
      expect(cart.right, lessThanOrEqualTo(menu.left + 1));
      await _capture(tester, 'fast-counter-order');
    });

    testWidgets('in Arabic the cart comes first from the right', (
      tester,
    ) async {
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: _FakeBridge(rtl: true),
        layout: SellLayout.fast,
      );
      final cart = tester.getRect(find.byType(SellCart));
      final menu = tester.getRect(find.byType(MenuGrid));
      expect(cart.left, greaterThan(menu.left));
    });

    testWidgets("an item's choices replace the menu, and close back to it", (
      tester,
    ) async {
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        layout: SellLayout.fast,
      );
      final menu = tester.getRect(find.byType(MenuGrid));
      await openCategory(tester, 'hot');
      await tester.longPress(find.byType(SellTile).at(1));
      await _settle(tester);

      final sheet = find.byType(ItemDetailSheet);
      expect(sheet, findsOneWidget);
      expect(routeOf(tester, sheet), isA<MadarPanelRoute<Object?>>());
      // It fills the panel beside the cart, not a sheet over the window.
      final rect = tester.getRect(sheet);
      expect(rect.left, closeTo(menu.left, 1));
      expect(rect.right, closeTo(menu.right, 1));
      expect(find.byType(SellCart), findsOneWidget);
      // The footer sits at the panel's foot.
      expect(
        tester.getRect(find.byType(ItemSheetFooter)).bottom,
        closeTo(rect.bottom, 1),
      );
      await _capture(tester, 'fast-item-open');

      // Close: the menu is back.
      await tester.tap(
        find
            .descendant(
              of: find.byType(ItemSheetHeader),
              matching: find.byType(TactileScale),
            )
            .last,
      );
      await _settle(tester);
      expect(find.byType(ItemDetailSheet), findsNothing);
      expect(find.byType(SellTile), findsWidgets);
      expect(tester.getRect(find.byType(MenuGrid)), menu);
    });

    testWidgets(
      'a cart line opens in the panel, and another line replaces it',
      (tester) async {
        await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: _ipad,
          layout: SellLayout.fast,
        );
        await tester.tap(inCart(find.text('Espresso')).first);
        await _settle(tester);
        expect(find.byType(ItemDetailSheet), findsOneWidget);
        expect(
          tester.widget<ItemDetailSheet>(find.byType(ItemDetailSheet)).item.id,
          'espresso',
        );
        expect(
          find.text(coreWord('order.update_item')),
          findsOneWidget,
          reason: 'editing the line, not adding a new one',
        );

        // The cart is still in reach: the next line replaces the choices.
        await tester.tap(inCart(find.text('Flat white')).first);
        await _settle(tester);
        expect(find.byType(ItemDetailSheet), findsOneWidget);
        expect(
          tester.widget<ItemDetailSheet>(find.byType(ItemDetailSheet)).item.id,
          'flat',
        );
        await _capture(tester, 'fast-line-edit');
      },
    );

    testWidgets('Charge opens in the panel and locks the cart meanwhile', (
      tester,
    ) async {
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        layout: SellLayout.fast,
      );
      final menu = tester.getRect(find.byType(MenuGrid));
      await tester.tap(inCart(find.text(coreWord('sell.charge'))).last);
      await _settle(tester);

      final charge = find.byType(ChargeSheet);
      expect(charge, findsOneWidget);
      expect(routeOf(tester, charge), isA<MadarPanelRoute<ChargeOutcome>>());
      expect(tester.getRect(charge).left, closeTo(menu.left, 1));
      final lock = tester.widget<AbsorbPointer>(
        find
            .ancestor(
              of: find.byType(SellCart),
              matching: find.byType(AbsorbPointer),
            )
            .first,
      );
      expect(lock.absorbing, isTrue, reason: 'no cart edits mid-charge');
      await _capture(tester, 'fast-charge');

      // Put away without taking money: the menu and the cart are back.
      MadarSheet.close<ChargeOutcome>(tester.element(charge));
      await _settle(tester);
      expect(find.byType(ChargeSheet), findsNothing);
      expect(find.byKey(const ValueKey('category-box-hot')), findsOneWidget);
      expect(
        tester
            .widget<AbsorbPointer>(
              find
                  .ancestor(
                    of: find.byType(SellCart),
                    matching: find.byType(AbsorbPointer),
                  )
                  .first,
            )
            .absorbing,
        isFalse,
      );
    });

    testWidgets('a phone ignores the setting: the cart is still its bar', (
      tester,
    ) async {
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _phone,
        layout: SellLayout.fast,
      );
      expect(find.byType(SellBar), findsOneWidget);
      expect(find.byType(MadarPanelHost), findsNothing);
    });

    testWidgets('the standard layout still opens the item as a sheet', (
      tester,
    ) async {
      await _mount(tester, screen: const TakeawaySellScreen(), size: _ipad);
      expect(find.byType(MadarPanelHost), findsNothing);
      await tester.longPress(find.byType(SellTile).at(1));
      await _settle(tester);
      expect(
        routeOf(tester, find.byType(ItemDetailSheet)),
        isA<MadarSheetRoute<Object?>>(),
      );
    });

    testWidgets('a table round sells in Fast mode too', (tester) async {
      final bridge = _FakeBridge();
      bridge.carts['t2'] = List.of(_cart);
      await _mount(
        tester,
        screen: const TableOrderScreen(tableId: 't2'),
        size: _ipad,
        bridge: bridge,
        layout: SellLayout.fast,
      );
      await _settle(tester);
      expect(find.byType(MadarPanelHost), findsOneWidget);
      expect(
        tester.getRect(find.byType(SellCart)).left,
        lessThan(tester.getRect(find.byType(MenuGrid)).left),
      );
    });

    for (final (device, size) in _devices) {
      if (size == _phone) continue;
      for (final ar in [false, true]) {
        for (final dark in [false, true]) {
          final tag = '$device-${ar ? 'ar' : 'en'}-${dark ? 'dark' : 'light'}';
          testWidgets('fast mode counter and item $tag', (tester) async {
            await _mount(
              tester,
              screen: const TakeawaySellScreen(),
              size: size,
              dark: dark,
              bridge: _FakeBridge(rtl: ar),
              layout: SellLayout.fast,
            );
            await _capture(tester, 'fast-counter-$tag');
            await openCategory(tester, 'hot');
            await tester.longPress(find.byType(SellTile).at(1));
            await _settle(tester);
            expect(find.byType(ItemDetailSheet), findsOneWidget);
            await _capture(tester, 'fast-item-$tag');
          });
        }
      }
    }
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
      }
    }
  }
}

/// Select a cart line: its stepper and actions open under it.
Future<void> _selectLine(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey('line-tap-$key')));
  await tester.pumpAndSettle();
}

/// T2 B3 (POS 0.9/0.10 on the iPad): after "Make it a meal" and a Clear, a
/// tap on the Latte tile did nothing at all — no line, no sheet, no toast.
///
/// The ⋯ sheet's Clear closed itself with `Navigator.maybePop()` and raised
/// the confirm in the same tick. `maybePop` is async and drops the pop when
/// the navigator's history changed meanwhile — which the confirm always
/// does — so the ⋯ sheet stayed up after "Clear cart", and its scrim
/// swallowed the next tap on the menu.
void _clearThenTapMain() {
  Finder latte() => find
      .descendant(of: find.byType(SellTile), matching: find.text('Latte'))
      .hitTestable();

  Future<void> clearFromTheMenu(WidgetTester tester) async {
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is MadarGlyphTile && w.glyph == MadarGlyph.more,
          )
          .hitTestable()
          .first,
    );
    await _settle(tester);
    await tester.tap(find.text(coreWord('order.clear')).last);
    await _settle(tester);
    await tester.tap(find.text(coreWord('order.clear_cart')).last);
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    "Clear closes the cart's ⋯ sheet: nothing is left over the menu",
    (tester) async {
      final bridge = _FakeBridge();
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      await clearFromTheMenu(tester);
      expect(bridge.cleared, 1);
      expect(
        find.byWidgetPredicate((w) => w is MadarButton && w.label == 'Clear'),
        findsNothing,
        reason: "the ⋯ sheet's Clear button is gone with its sheet",
      );
      expect(latte(), findsOneWidget, reason: 'the menu takes taps again');
    },
  );

  testWidgets('the Latte tile still sells after a meal and a Clear (T2 B3)', (
    tester,
  ) async {
    final bridge = _MealBridge()..latency = const Duration(milliseconds: 40);
    bridge.carts[null] = [];
    final container = await _mount(
      tester,
      screen: const TakeawaySellScreen(),
      size: _ipad,
      bridge: bridge,
    );
    // Long press → the item sheet → "Make it a meal" → the combo sheet → Add.
    await tester.longPress(latte().first);
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('make-it-a-meal')));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('combo-save')));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(bridge.combosAdded, 1, reason: 'the meal went into the cart');

    await clearFromTheMenu(tester);
    expect(bridge.carts[null], isEmpty);
    expect(container.read(cartProvider(null)).lines, isEmpty);

    await tester.tap(latte().first);
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(bridge.configuredAdds, [
      'latte',
    ], reason: 'the tap reached the cart');
    expect(bridge.carts[null]!.map((l) => l.itemId), ['latte']);
  });
}

/// T2 B3's rule: whatever stops a tap on the Sell screen, the teller is told.
void _neverNothingMain() {
  Finder tile(String name) => find
      .descendant(of: find.byType(SellTile), matching: find.text(name))
      .hitTestable();

  Future<(ProviderContainer, _MealBridge)> mount(WidgetTester tester) async {
    final bridge = _MealBridge();
    bridge.carts[null] = [];
    final container = await _mount(
      tester,
      screen: const TakeawaySellScreen(),
      size: _ipad,
      bridge: bridge,
    );
    return (container, bridge);
  }

  String? toast(ProviderContainer c) => c.read(appToastProvider)?.text;

  testWidgets('a tap that fails unexpectedly says so', (tester) async {
    final (container, bridge) = await mount(tester);
    bridge.breakAdd = StateError('the bridge fell over');
    await tester.tap(tile('Latte').first);
    await _settle(tester);
    expect(toast(container), "Couldn't add Latte. Try again.");
    expect(
      tester.takeException(),
      isA<StateError>(),
      reason: 'still reported, as an uncaught error would be',
    );
    expect(bridge.configuredAdds, isEmpty);

    // …and the next tap is taken as usual.
    await tester.tap(tile('Latte').first);
    await _settle(tester);
    expect(bridge.configuredAdds, ['latte']);
  });

  testWidgets('a tap held behind a slow one says so; a double tap does not', (
    tester,
  ) async {
    final (container, bridge) = await mount(tester);
    bridge.slowGroups = Completer<List<ModifierGroupView>>();
    await tester.tap(tile('Latte').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(tile('Espresso').first);
    await tester.pump();
    expect(toast(container), isNull, reason: 'a double tap is not news');

    await tester.pump(const Duration(seconds: 2));
    await tester.tap(tile('Espresso').first);
    await tester.pump();
    expect(
      toast(container),
      'One moment, the last tap is still going through.',
    );

    bridge.slowGroups!.complete(const []);
    bridge.slowGroups = null;
    await _settle(tester);
    expect(bridge.configuredAdds, ['latte'], reason: 'the slow one lands');
  });

  testWidgets('editing a line whose item left the menu says so', (
    tester,
  ) async {
    final (container, bridge) = await mount(tester);
    bridge.carts[null] = [_cartLine('gone', 'Pumpkin latte', 6000, 1)];
    await container.read(cartProvider(null).notifier).load();
    await _settle(tester);
    // 0.11.0's cart: a tap selects the line, its edit tile opens the sheet.
    await _selectLine(tester, 'k-gone');
    await tester.tap(find.byKey(const ValueKey('edit-k-gone')));
    await _settle(tester);
    expect(toast(container), "Couldn't open Pumpkin latte. Try again.");
  });

  testWidgets('a combo this till cannot show says so', (tester) async {
    final (container, bridge) = await mount(tester);
    bridge.comboGone = true;
    await tester.tap(tile('Coffee & Treat').first);
    await _settle(tester);
    expect(toast(container), "This combo isn't available right now.");
  });
}

/// T2 B1: on an iPad in landscape with the on-screen keyboard up (the staff
/// drink's note), the sheet overflowed and its "Mark as staff drink" sat under
/// the keyboard, and the cart beside it overflowed too: ~300 px were left above
/// the keyboard and neither could scroll.
void _keyboardMain() {
  /// What T2's shot measures: the iPad's keyboard with its suggestion bar.
  const keyboard = 430.0;

  for (final ar in [false, true]) {
    final lang = ar ? 'ar' : 'en';
    Future<_StaffBridge> mount(WidgetTester tester) async {
      final bridge = _StaffBridge(rtl: ar);
      bridge.carts[null] = [_StaffBridge._combo, _StaffBridge._latte];
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      return bridge;
    }

    void keyboardUp(WidgetTester tester) {
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
    }

    testWidgets('the cart fits and scrolls above the keyboard · $lang', (
      tester,
    ) async {
      await mount(tester);
      expect(tester.takeException(), isNull, reason: 'fits with no keyboard');
      keyboardUp(tester);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'no overflow over it');
      // The cart's action is still there to reach: it scrolls into view.
      final charge = find.text(coreWord('sell.charge', arabic: ar));
      expect(charge, findsWidgets);
      await tester.dragUntilVisible(
        charge.first,
        find.byType(SellCart),
        const Offset(0, -120),
      );
      expect(charge.hitTestable(), findsWidgets);
      await tester.pump(const Duration(milliseconds: 500));
      await _capture(tester, 'sell-keyboard-cart-$lang');
    });

    testWidgets('an empty cart fits above the keyboard too · $lang', (
      tester,
    ) async {
      final bridge = _StaffBridge(rtl: ar);
      bridge.carts[null] = [];
      await _mount(
        tester,
        screen: const TakeawaySellScreen(),
        size: _ipad,
        bridge: bridge,
      );
      // The menu's search raises the same keyboard.
      await tester.tap(find.byType(MadarGlyphTile).first);
      await _settle(tester);
      keyboardUp(tester);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'sell-keyboard-empty-$lang');
    });

    testWidgets('the staff drink sheet keeps its button above the keyboard · '
        '$lang', (tester) async {
      await mount(tester);
      // 0.11.0's cart: the staff-drink tile is on the selected line.
      await _selectLine(tester, 'k-latte');
      await tester.tap(find.byKey(const ValueKey('staff-drink-k-latte')));
      await _settle(tester);
      keyboardUp(tester);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'the sheet fits');
      final save = find.byKey(const ValueKey('staff-drink-save'));
      expect(save.hitTestable(), findsOneWidget, reason: 'not under the keys');
      expect(
        tester.getRect(save).bottom,
        lessThanOrEqualTo(_ipad.height - keyboard),
        reason: 'the whole button is above the keyboard',
      );
      await tester.enterText(
        find.byKey(const ValueKey('staff-drink-note')),
        'Sara, closing shift',
      );
      await _settle(tester);
      expect(tester.widget<MadarButton>(save).enabled, isTrue);
      await _capture(tester, 'sell-keyboard-staff-sheet-$lang');
    });
  }
}
