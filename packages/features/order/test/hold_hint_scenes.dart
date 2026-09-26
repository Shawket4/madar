// Hold hints on the Sell screen at real sizes, EN and AR (the owner,
// 2026-09-26: "hold should display a hint text, and that goes for all
// truncated items only across the whole app").
//
// A name cut off on the cart, a parked chip, an icon-only control: a long
// press shows the whole of it; a name that fits shows nothing. And every
// long press that already did something still does it — the menu tile opens
// its item (the sheet is titled with the whole name), the cart line's
// kitchen tile opens its sheet, the whole-cart kitchen button previews, a
// parked chip is picked up to be dragged (and the chip it lifts says its
// whole name).
part of 'sell_render_test.dart';

const _longItem =
    'Chocolate fudge cake with salted caramel, pistachio cream and '
    'fresh berries';
const _longItemAr =
    'كعكة الشوكولاتة الغنية بالكراميل المملح وكريمة الفستق والتوت الطازج '
    'مع صوص البندق';
const _longGuest = 'Mohamed Abdelrahman El-Sayed El-Sharkawy';
const _longGuestAr = 'محمد عبد الرحمن السيد الشرقاوي';

/// The devices the owner named: the two iPads, the small one both ways, the
/// 8" Android in portrait, the Lenovo in landscape, and the phone.
const _hintDevices = <(String, Size)>[
  ('ipad', _ipad),
  ('ipad9', _ipad9),
  ('ipad9p', _ipad9Portrait),
  ('tab8', _tab8),
  ('lenovo', _lenovo),
  ('phone', _phone),
];

/// The fixtures, with one long name on the menu, one on the cart and one on
/// a parked order (and a short parked name beside it).
class _LongNamesBridge extends _FakeBridge {
  _LongNamesBridge({super.rtl}) {
    carts[null] = [
      _cartLine('cake-long', longItem, 9500, 1),
      ...List.of(_cart),
    ];
  }

  String get longItem => rtl ? _longItemAr : _longItem;
  String get longGuest => rtl ? _longGuestAr : _longGuest;

  @override
  List<DraftView> get drafts => [
    DraftView(
      id: 'd-long',
      name: longGuest,
      itemCount: 2,
      totalMinor: 9000,
      createdAt: '2026-09-12T18:40:00Z',
      lockedByOther: false,
      byOther: false,
    ),
    const DraftView(
      id: 'd-ali',
      name: 'Ali',
      itemCount: 1,
      totalMinor: 3500,
      createdAt: '2026-09-12T18:45:00Z',
      lockedByOther: false,
      byOther: false,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #previewConfiguredLine &&
        invocation.namedArguments[#itemId] == 'cake-long') {
      final qty = invocation.namedArguments[#qty] as int;
      return Future<LinePreviewView>.value(
        LinePreviewView(
          unitTotalMinor: 9500,
          extrasMinor: 0,
          lineTotalMinor: 9500 * qty,
          qty: qty,
          baseMinor: 9500,
          sizeDeltaMinor: 0,
          paid: const [],
          summary: const [],
        ),
      );
    }
    if (invocation.memberName == #listMenuItems) {
      // First, so its tile is on screen without a scroll.
      return Future<List<MenuItemView>>.value([
        _item('cake-long', longItem, 9500, cat: 'food'),
        ..._items,
      ]);
    }
    return super.noSuchMethod(invocation);
  }
}

/// The kit's hint bubble (hold or reveal) saying exactly [text]: a text
/// inside the bubble's own box — ink on paper — never the text in place.
Finder _bubble(String text) {
  final look = BoxDecoration(
    color: MadarColors.light.textPrimary,
    borderRadius: BorderRadius.circular(Radii.sm),
  );
  return find.byElementPredicate((e) {
    final w = e.widget;
    if (w is! Text || (w.data ?? w.textSpan?.toPlainText()) != text) {
      return false;
    }
    var inBubble = false;
    e.visitAncestorElements((a) {
      final box = a.widget;
      if (box is DecoratedBox && box.decoration == look) {
        inBubble = true;
        return false;
      }
      return true;
    });
    return inBubble;
  }, description: 'hint bubble "$text"');
}

/// Whether [text] carries a hold hint: a Tooltip over it.
bool _hinted(WidgetTester tester, Finder text) => find
    .ancestor(of: text, matching: find.byType(Tooltip))
    .evaluate()
    .isNotEmpty;

/// Past the bubble's linger and fade, so the next scene starts clean.
Future<void> _hintGone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await _settle(tester);
}

/// The phone keeps its cart in a sheet: open it from the bottom bar.
Future<void> _openPhoneCart(WidgetTester tester) async {
  await tester.tap(
    find
        .descendant(of: find.byType(SellBar), matching: find.byType(Nudge))
        .last,
  );
  await _settle(tester);
}

void _holdHintsMain() {
  for (final (device, size) in _hintDevices) {
    for (final ar in [false, true]) {
      final tag = '$device-${ar ? 'ar' : 'en'}';

      testWidgets('a long item name on a cart line shows whole on a hold; a '
          'short one carries no hint ($tag)', (tester) async {
        final bridge = _LongNamesBridge(rtl: ar);
        await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: size,
          bridge: bridge,
        );
        if (size == _phone) await _openPhoneCart(tester);
        final name = find.descendant(
          of: find.byKey(const ValueKey('round-k-cake-long')),
          matching: find.text(bridge.longItem),
        );
        expect(name, findsOneWidget);
        expect(_hinted(tester, name), isTrue, reason: 'cut on this cart');
        final short = find.descendant(
          of: find.byKey(const ValueKey('round-k-espresso')),
          matching: find.text('Espresso'),
        );
        expect(_hinted(tester, short), isFalse, reason: 'it fits');

        await tester.longPress(name);
        await tester.pump();
        expect(_bubble(bridge.longItem), findsOneWidget);
        if (_render) {
          await tester.pump(const Duration(milliseconds: 300));
          await _writeFrame(tester, 'hint-cartline-$tag');
        }
        // The hold is the hint's: it did not select (open) the line.
        expect(find.byKey(const ValueKey('kitchen-k-cake-long')), findsNothing);
        await _hintGone(tester);
        expect(_bubble(bridge.longItem), findsNothing);

        await tester.longPress(short);
        await tester.pump();
        expect(_bubble('Espresso'), findsNothing);
        await _capture(tester, 'hint-cartline-after-$tag');
      });

      testWidgets('a long parked name: the hold lifts the chip AND says the '
          'whole name; the drag still reorders; a short name says nothing '
          '($tag)', (tester) async {
        final bridge = _LongNamesBridge(rtl: ar);
        final c = await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: size,
          bridge: bridge,
        );
        if (size == _phone) {
          // The phone's door to the parked strip: the header's parked
          // button (its word dropped for room — see the icon-only scene).
          await tester.tap(
            find.byWidgetPredicate(
              (w) => w is MadarButton && w.glyph == MadarGlyph.bag,
            ),
          );
          await _settle(tester);
        }
        final chip = find.text(bridge.longGuest);
        expect(chip, findsOneWidget);
        // Its long press is the drag's: no hold hint of its own.
        expect(_hinted(tester, chip), isFalse);

        final hold = await tester.startGesture(tester.getCenter(chip));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          _bubble(bridge.longGuest),
          findsOneWidget,
          reason: 'the lifted chip says the whole name',
        );
        // The reveal has no fade: the frame is the lifted chip as it is.
        if (_render) await _writeFrame(tester, 'hint-parked-lifted-$tag');
        // Drag it past "Ali": the order changes, so the drag kept the press.
        final ali = tester.getCenter(find.text('Ali'));
        final from = tester.getCenter(chip.first);
        final step = (ali.dx - from.dx + (ar ? -40 : 40)) / 8;
        for (var i = 0; i < 8; i++) {
          await hold.moveBy(Offset(step, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await hold.up();
        await _settle(tester);
        final order = c.read(heldStripOrderProvider);
        expect(
          order.indexOf('d-long'),
          greaterThan(order.indexOf('d-ali')),
          reason: 'the long-named chip now sits after Ali',
        );
        expect(_bubble(bridge.longGuest), findsNothing);

        // Ali fits: lifting it says nothing.
        final lift = await tester.startGesture(
          tester.getCenter(find.text('Ali')),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(_bubble('Ali'), findsNothing);
        await lift.up();
        await _settle(tester);
        await _capture(tester, 'hint-parked-after-$tag');
      });

      testWidgets('a long item name on a menu tile: the hold still opens the '
          'item, whose sheet shows the whole name ($tag)', (tester) async {
        final bridge = _LongNamesBridge(rtl: ar);
        await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: size,
          bridge: bridge,
        );
        final tile = find.ancestor(
          of: find.text(bridge.longItem),
          matching: find.byType(SellTile),
        );
        expect(tile, findsOneWidget);
        final onTile = find.descendant(
          of: tile,
          matching: find.text(bridge.longItem),
        );
        // Cut on the tile, but its long press is the tile's own.
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: onTile, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isTrue, reason: 'cut on the tile');
        expect(_hinted(tester, onTile), isFalse);

        await tester.longPress(tile);
        await _settle(tester);
        expect(find.byType(ItemDetailSheet), findsOneWidget);
        expect(_bubble(bridge.longItem), findsNothing);
        final title = find.descendant(
          of: find.byType(ItemDetailSheet),
          matching: find.text(bridge.longItem),
        );
        expect(title, findsOneWidget);
        final whole = tester.renderObject<RenderParagraph>(
          find.descendant(of: title, matching: find.byType(RichText)),
        );
        expect(
          whole.didExceedMaxLines || whole.textSize.width > whole.size.width,
          isFalse,
          reason: 'the sheet reads the whole name',
        );
        await _capture(tester, 'hint-menu-tile-$tag');
      });

      testWidgets('icon-only controls say the word they dropped; a tap still '
          'acts ($tag)', (tester) async {
        final bridge = _LongNamesBridge(rtl: ar);
        await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: size,
          bridge: bridge,
        );
        if (size == _phone) {
          // The header's parked button: a bag and a count, "Parked" dropped.
          final parked = find.byWidgetPredicate(
            (w) => w is MadarButton && w.glyph == MadarGlyph.bag,
          );
          expect(parked, findsOneWidget);
          final word = bridge.trChecked('sell.parked');
          await tester.longPress(parked);
          await tester.pump();
          expect(_bubble(word), findsOneWidget);
          if (_render) {
            await tester.pump(const Duration(milliseconds: 300));
            await _writeFrame(tester, 'hint-icon-$tag');
          }
          await _hintGone(tester);
          await _capture(tester, 'hint-icon-after-$tag');
          return;
        }
        // The cart's toolbar on a tablet: whichever of its controls is a
        // bare glyph at this width — Park beside Charge, the kitchen note
        // beside the kitchen button — says its word on a hold.
        final tiles = <(String, String)>[
          ('cart-park', bridge.tr(key: 'drafts.hold')),
          (
            'cart-kitchen-note',
            bridge.trChecked('sell.kitchen_cart_note_field'),
          ),
        ];
        var seen = 0;
        for (final (key, word) in tiles) {
          final tile = find.byWidgetPredicate(
            (w) => w is MadarGlyphTile && w.key == ValueKey(key),
          );
          if (tile.evaluate().isEmpty) continue;
          seen++;
          await tester.longPress(tile);
          await tester.pump();
          expect(_bubble(word), findsOneWidget, reason: key);
          if (_render) {
            await tester.pump(const Duration(milliseconds: 300));
            await _writeFrame(tester, 'hint-icon-$key-$tag');
          }
          await _hintGone(tester);
        }
        expect(seen, greaterThan(0), reason: 'a glyph-only control is here');
        // And the hold did not act: nothing was parked.
        expect(bridge.parked, isEmpty);
        final park = find.byWidgetPredicate(
          (w) => w is MadarGlyphTile && w.key == const ValueKey('cart-park'),
        );
        if (park.evaluate().isNotEmpty) {
          await tester.tap(park);
          await _settle(tester);
          expect(bridge.parked, [null], reason: 'a tap still parks');
        }
        await _capture(tester, 'hint-icon-after-$tag');
      });

      testWidgets("the cart line's kitchen tile and the whole-cart kitchen "
          'button keep their long press ($tag)', (tester) async {
        final bridge = _LongNamesBridge(rtl: ar);
        await _mount(
          tester,
          screen: const TakeawaySellScreen(),
          size: size,
          bridge: bridge,
        );
        if (size == _phone) await _openPhoneCart(tester);
        // The line's kitchen tile: its sheet, titled with the whole name.
        await _selectLine(tester, 'k-cake-long');
        await tester.longPress(
          find.byKey(const ValueKey('kitchen-k-cake-long')),
        );
        await _settle(tester);
        expect(
          find.text(coreWord('sell.kitchen_row_sheet_preview', arabic: ar)),
          findsOneWidget,
          reason: 'the row sheet opened',
        );
        final sheet = find
            .ancestor(
              of: find.widgetWithText(
                MadarButton,
                coreWord('sell.kitchen_row_sheet_preview', arabic: ar),
              ),
              matching: find.byType(Column),
            )
            .first;
        final sheetTitle = find.descendant(
          of: sheet,
          matching: find.text(bridge.longItem),
        );
        expect(sheetTitle, findsOneWidget, reason: 'titled with the item');
        final titled = tester.renderObject<RenderParagraph>(
          find.descendant(of: sheetTitle, matching: find.byType(RichText)),
        );
        expect(
          titled.didExceedMaxLines || titled.textSize.width > titled.size.width,
          isFalse,
          reason: 'the sheet reads the whole name',
        );
        expect(
          _bubble(bridge.trChecked('sell.kitchen_row_hint')),
          findsNothing,
        );
        MadarSheet.close<void>(
          tester.element(
            find.text(coreWord('sell.kitchen_row_sheet_preview', arabic: ar)),
          ),
        );
        await _settle(tester);

        // The whole cart's kitchen button: a long press previews.
        await tester.longPress(
          find.byKey(const ValueKey('print-cart-kitchen')),
        );
        await _settle(tester);
        expect(find.byType(CartKitchenChitSheet), findsOneWidget);
        await _capture(tester, 'hint-kitchen-keeps-$tag');
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
