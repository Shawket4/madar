// The Sell tile's name: the owner's iPad screenshot showed "Affogat/o",
// "Americ/ano" and "Blende/d Latte" — names split mid-word because the old
// horizontal card left the text a sliver beside its photo. These pin the
// vertical card's promise: at every width the grid can hand a tile, in
// English and Arabic, at a large text scale, a name breaks BETWEEN words or
// not at all, and nothing overflows.
//
// `MADAR_RENDER=true` also writes `build/render/sell-tiles-<case>.png` so the
// card can be looked at (the repo's render convention, not pixel goldens).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/sell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

const _names = [
  'Affogato',
  'Americano',
  'Blended Latte',
  'Caramel Macchiato',
  'Iced Spanish Latte with Oat Milk',
  'Supercalifragilisticexpialidocious',
  'قهوة مثلجة بالكراميل',
  'موكا',
];

MenuItemView _item(String name, int i) => MenuItemView(
  id: 'i$i',
  name: name,
  basePriceMinor: 4500 + i * 1250,
  isActive: true,
  allowedAddonIds: const [],
  sizes: const [],
  addonSlots: const [],
  optionalFields: const [],
  recipes: const [],
  recipeSteps: const [],
);

Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  const dir = '../../design_system/assets/fonts';
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('$dir/$family-$cut.ttf');
      if (!file.existsSync()) return;
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

/// Every place a line of [p] ends that is not the end of its text, and is
/// not an ellipsized last line.
List<int> _midWordBreaks(RenderParagraph p, String text) {
  final breaks = <int>[];
  double lineOf(int i) =>
      p.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
  for (var i = 1; i < text.length; i++) {
    // A new line starts at i while both neighbours are letters: the word
    // was split.
    if (lineOf(i + 1 > text.length ? i : i) > lineOf(i - 1) + 1 &&
        text[i - 1].trim().isNotEmpty &&
        text[i].trim().isNotEmpty) {
      breaks.add(i);
    }
  }
  return breaks;
}

Future<void> _board(
  WidgetTester tester, {
  required double catalogWidth,
  required String name,
  bool rtl = false,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(catalogWidth, 900);
  addTearDown(tester.view.reset);
  const gutter = Space.lg;
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MadarTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, c) {
              final usable = c.maxWidth - gutter * 2;
              final columns = sellGridColumns(usable);
              final w = (usable - kSellTileGap * (columns - 1)) / columns;
              return GridView.builder(
                padding: const EdgeInsets.all(gutter),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: sellTileExtent(
                    w,
                    MediaQuery.textScalerOf(context),
                  ),
                  mainAxisSpacing: kSellTileGap,
                  crossAxisSpacing: kSellTileGap,
                ),
                itemCount: _names.length,
                itemBuilder: (context, i) => SellTile(
                  item: _item(_names[i], i),
                  currency: 'EGP',
                  inCart: i == 2 ? 3 : 0,
                  accent: const Color(0xFF8A5A2B),
                  onTap: (_) {},
                  onLongPress: () {},
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull, reason: '$name laid out cleanly');

  for (final n in _names) {
    final finder = find.descendant(
      of: find.byType(SellTileName),
      matching: find.text(n),
    );
    if (finder.evaluate().isEmpty) continue; // scrolled off
    final p = tester.renderObject<RenderParagraph>(finder);
    expect(
      _midWordBreaks(p, n),
      isEmpty,
      reason: '"$n" must break between words only ($name)',
    );
  }

  if (!_render) return;
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/render')..createSync(recursive: true);
    File(
      '${dir.path}/sell-tiles-$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('iPad landscape catalog column', (tester) async {
    // 1194 − 88 rail − 340 cart.
    await _board(tester, catalogWidth: 766, name: 'ipad');
  });

  testWidgets('iPad catalog column, Arabic', (tester) async {
    await _board(tester, catalogWidth: 766, name: 'ipad-rtl', rtl: true);
  });

  testWidgets('a phone at 130% text', (tester) async {
    await _board(
      tester,
      catalogWidth: 390,
      name: 'phone-large',
      textScale: 1.3,
    );
  });

  testWidgets('the narrowest band a tile can get', (tester) async {
    await _board(tester, catalogWidth: 360, name: 'narrow');
  });

  testWidgets('a word too long for any line stays whole on one line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 110,
              child: SellTileName(
                'Supercalifragilisticexpialidocious',
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(
      find.text('Supercalifragilisticexpialidocious'),
    );
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    expect(tester.takeException(), isNull);
  });
}
