// The hold hint: a text cut off on screen shows its whole self on a long
// press, a text that fits carries no hint at all, and a long press that
// already belongs to something else keeps belonging to it. The owner's ask
// (2026-09-26): "hold should display a hint text, and that goes for all
// truncated items only across the whole app".

import 'dart:io';
import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// The app's real faces: the test font draws every glyph as a square, which
/// makes texts overflow (or fit) where they never would on a device.
Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('assets/fonts/$family-$cut.ttf');
      if (!file.existsSync()) return;
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

const _long = 'Chocolate cake with salted caramel and cream';
const _short = 'Latte';
const _arLong = 'كعكة الشوكولاتة بالكراميل المملح والكريمة الطازجة';
const _arShort = 'لاتيه';

Widget _app(
  Widget child, {
  TextDirection dir = TextDirection.ltr,
  double scale = 1,
  bool dark = false,
}) => MaterialApp(
  theme: dark ? MadarTheme.dark() : MadarTheme.light(),
  home: Directionality(
    textDirection: dir,
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  ),
);

/// A one-line name in a box [width] wide — a tile's, a chip's.
Widget _name(String text, {double width = 160, String? hint}) => SizedBox(
  width: width,
  child: MadarClippedText(
    text,
    key: const ValueKey('name'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    hint: hint,
    style: MadarType.title,
  ),
);

/// Lays the screen out and lets the text report what it measured.
Future<void> _pumpApp(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump();
}

/// Every Text on screen carrying exactly [text] — the one in place plus,
/// while a hint is up, the one in its bubble.
Finder _exactly(String text) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? w.textSpan?.toPlainText()) == text,
  description: 'text "$text"',
);

/// The hint bubble showing [text]: the tooltip's own `Text.rich`, free to
/// wrap — never the text in place, which is a plain or a line-capped one.
Finder _bubble(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      w.data == null &&
      w.maxLines == null &&
      w.textSpan?.toPlainText() == text,
  description: 'hint bubble "$text"',
);

/// Past the hint's linger and its fade.
Future<void> _waitOut(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  group('MadarClippedText', () {
    testWidgets('a cut-off name shows its whole self on a long press', (
      tester,
    ) async {
      await _pumpApp(tester, _app(_name(_long)));
      expect(find.byType(Tooltip), findsOneWidget);
      expect(_bubble(_long), findsNothing);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('name'))),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      // Still holding: the hold itself shows it, not the release.
      await tester.pump(const Duration(milliseconds: 200));
      expect(_bubble(_long), findsOneWidget);
      await gesture.up();
      await tester.pump();
      // It stays long enough to be read after the finger lifts…
      await tester.pump(const Duration(seconds: 1));
      expect(_bubble(_long), findsOneWidget);
      // …and then goes.
      await _waitOut(tester);
      expect(_bubble(_long), findsNothing);
    });

    testWidgets('a name that fits carries no hint and no gesture', (
      tester,
    ) async {
      await _pumpApp(tester, _app(_name(_short)));
      expect(find.byType(Tooltip), findsNothing);
      expect(
        find.descendant(
          of: find.byType(MadarClippedText),
          matching: find.byType(Listener),
        ),
        findsNothing,
      );
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump();
      expect(_exactly(_short), findsOneWidget);
    });

    testWidgets('a short form that fits still says what it stands for', (
      tester,
    ) async {
      // A parked chip showing "#2" for "Mona Adel": the name was dropped for
      // room, like a word dropped for an icon, so the hold says it.
      await _pumpApp(
        tester,
        _app(
          const SizedBox(
            key: ValueKey('name'),
            width: 160,
            child: MadarClippedText(
              '#2',
              hint: 'Mona Adel',
              shortened: true,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
      expect(find.byType(Tooltip), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_bubble('Mona Adel'), findsOneWidget);
      await _waitOut(tester);
    });

    testWidgets('a hint says what it is given, when told', (tester) async {
      await _pumpApp(tester, _app(_name(_long, hint: 'Cake · Food')));
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump();
      expect(_bubble('Cake · Food'), findsOneWidget);
    });

    testWidgets('Arabic: the whole Arabic name, laid out right to left', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        _app(_name(_arLong, width: 140), dir: TextDirection.rtl),
      );
      expect(find.byType(Tooltip), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump();
      final bubble = _bubble(_arLong);
      expect(bubble, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: bubble, matching: find.byType(RichText)),
      );
      expect(paragraph.textDirection, TextDirection.rtl);
      // On screen, and over the name it explains.
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final rect = tester.getRect(bubble);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(screen.width));
      final name = tester.getRect(find.byKey(const ValueKey('name')));
      expect(rect.bottom, lessThanOrEqualTo(name.top));
      expect(
        (rect.center.dx - name.center.dx).abs(),
        lessThan(rect.width / 2 + 1),
      );
    });

    testWidgets('an Arabic name that fits carries no hint', (tester) async {
      await _pumpApp(
        tester,
        _app(_name(_arShort, width: 140), dir: TextDirection.rtl),
      );
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('a bigger text size that cuts a name gives it a hint, and a '
        'smaller one that fits it again takes it away', (tester) async {
      const name = 'Iced caramel latte';
      await _pumpApp(tester, _app(_name(name, width: 190)));
      expect(find.byType(Tooltip), findsNothing, reason: 'fits at 1×');

      await _pumpApp(tester, _app(_name(name, width: 190), scale: 1.6));
      expect(find.byType(Tooltip), findsOneWidget, reason: 'cut at 1.6×');
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump();
      expect(_bubble(name), findsOneWidget);
      await _waitOut(tester);

      await _pumpApp(tester, _app(_name(name, width: 190)));
      expect(find.byType(Tooltip), findsNothing, reason: 'fits again');
    });

    testWidgets('a name that changes under a fixed box re-measures', (
      tester,
    ) async {
      // A box tight on both axes makes the paragraph its own relayout
      // boundary: its layout no longer passes through the probe's.
      Widget boxed(String text) => _app(
        SizedBox(
          width: 150,
          height: 24,
          child: MadarClippedText(
            text,
            key: const ValueKey('name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.title,
          ),
        ),
      );
      await _pumpApp(tester, boxed(_short));
      expect(find.byType(Tooltip), findsNothing);
      await _pumpApp(tester, boxed(_long));
      expect(find.byType(Tooltip), findsOneWidget);
      await _pumpApp(tester, boxed(_short));
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('two lines: cut only when the third line would be needed', (
      tester,
    ) async {
      Widget two(String text) => _app(
        SizedBox(
          width: 150,
          child: MadarClippedText(
            text,
            key: const ValueKey('name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MadarType.title,
          ),
        ),
      );
      await _pumpApp(tester, two('Chocolate cake'));
      expect(find.byType(Tooltip), findsNothing);
      await _pumpApp(tester, two('$_long, and a very long note after it'));
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('a clipped (not ellipsised) label that ran past its box', (
      tester,
    ) async {
      Widget clip(String text) => _app(
        SizedBox(
          width: 40,
          child: MadarClippedText(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: MadarType.title,
          ),
        ),
      );
      await _pumpApp(tester, clip('T5'));
      expect(find.byType(Tooltip), findsNothing);
      await _pumpApp(tester, clip('Terrace 12'));
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('rich text with a figure set in a WidgetSpan: the hint reads '
        'the figure, not a placeholder', (tester) async {
      await _pumpApp(
        tester,
        _app(
          SizedBox(
            width: 150,
            child: MadarClippedText.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Charge · '),
                  WidgetSpan(child: Text('T-0412', style: MadarType.moneyLg)),
                  const TextSpan(text: ' Terrace by the window'),
                ],
              ),
              key: const ValueKey('name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump();
      expect(_bubble('Charge · T-0412 Terrace by the window'), findsOneWidget);
    });

    testWidgets('rich text: the hint is its plain text', (tester) async {
      const span = TextSpan(
        children: [
          TextSpan(text: '#1043 '),
          TextSpan(text: 'Mohamed Abdelrahman El-Sayed'),
        ],
      );
      await _pumpApp(
        tester,
        _app(
          const SizedBox(
            width: 150,
            child: MadarClippedText.rich(
              span,
              key: ValueKey('name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump();
      expect(_bubble('#1043 Mohamed Abdelrahman El-Sayed'), findsOneWidget);
    });

    testWidgets('a screen reader hears the whole name, once', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpApp(tester, _app(_name(_long)));
      // The whole name, never the ellipsised run…
      expect(find.bySemanticsLabel(_long), findsOneWidget);
      // …and not a second time as a tooltip.
      final node = tester.getSemantics(find.bySemanticsLabel(_long));
      expect(node.tooltip, isEmpty);
      handle.dispose();
    });

    testWidgets('no Overlay above it (a bare widget test): no hint, no '
        'crash', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: _name(_long)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('a long press that belongs to something else', () {
    testWidgets('inside MadarHoldHints.off: the owner keeps its long press', (
      tester,
    ) async {
      var held = 0;
      await _pumpApp(
        tester,
        _app(
          GestureDetector(
            onLongPress: () => held++,
            child: MadarHoldHints.off(child: _name(_long)),
          ),
        ),
      );
      expect(find.byType(Tooltip), findsNothing);
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump();
      expect(held, 1);
      expect(_bubble(_long), findsNothing);
    });

    testWidgets('TactileScale with a long press turns the hints under it '
        'off', (tester) async {
      var held = 0;
      await _pumpApp(
        tester,
        _app(
          TactileScale(
            onTap: () {},
            onLongPress: () => held++,
            child: _name(_long),
          ),
        ),
      );
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump();
      expect(held, 1);
      expect(_bubble(_long), findsNothing);
    });

    testWidgets('a tap-only parent: the hold shows the hint and does not '
        'tap; a tap still taps', (tester) async {
      var taps = 0;
      await _pumpApp(
        tester,
        _app(TactileScale(onTap: () => taps++, child: _name(_long))),
      );
      await tester.longPress(find.byKey(const ValueKey('name')));
      await tester.pump();
      expect(_bubble(_long), findsOneWidget);
      expect(taps, 0);
      await _waitOut(tester);
      await tester.tap(find.byKey(const ValueKey('name')));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('MadarRow with a long press keeps it', (tester) async {
      var held = 0;
      await _pumpApp(
        tester,
        _app(
          SizedBox(
            width: 220,
            child: MadarRow(
              title: _long,
              onTap: () {},
              onLongPress: () => held++,
            ),
          ),
        ),
      );
      expect(find.byType(Tooltip), findsNothing);
      await tester.longPress(find.byType(MadarRow));
      await tester.pump();
      expect(held, 1);
    });

    testWidgets('MadarButton with a long press keeps it; without one, a cut '
        'label shows itself', (tester) async {
      var held = 0;
      await _pumpApp(
        tester,
        _app(
          SizedBox(
            width: 140,
            child: MadarButton(
              label: _long,
              onTap: () {},
              onLongPress: () => held++,
            ),
          ),
        ),
      );
      await tester.longPress(find.byType(MadarButton));
      await tester.pump();
      expect(held, 1);
      expect(_bubble(_long), findsNothing);

      await _pumpApp(
        tester,
        _app(
          SizedBox(
            width: 140,
            child: MadarButton(label: _long, onTap: () {}),
          ),
        ),
      );
      await tester.longPress(find.byType(MadarButton));
      await tester.pump();
      expect(_bubble(_long), findsOneWidget);
    });
  });

  group('MadarRevealHints: the answer to a long press someone else owns', () {
    /// The bubble a reveal draws: a plain Text (not a line-capped one).
    Finder revealed(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.data == text && w.maxLines == null,
      description: 'revealed "$text"',
    );

    testWidgets('shows every cut text at once, one bubble, a line each — even '
        'under an inner off', (tester) async {
      await _pumpApp(
        tester,
        _app(
          MadarRevealHints(
            child: MadarHoldHints.off(
              child: SizedBox(
                width: 160,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _name(_long),
                    const MadarClippedText(
                      'Ahmed Abdelrahman El-Sayed',
                      hint: 'Started by Ahmed Abdelrahman El-Sayed',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const MadarClippedText('Fits', maxLines: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        revealed('$_long\nStarted by Ahmed Abdelrahman El-Sayed'),
        findsOneWidget,
      );
      // No press is taken: no tooltip, no recogniser.
      expect(find.byType(Tooltip), findsNothing);
      final bubble = tester.getRect(
        revealed('$_long\nStarted by Ahmed Abdelrahman El-Sayed'),
      );
      final column = tester.getRect(find.byType(Column));
      expect(bubble.bottom, lessThanOrEqualTo(column.top));
    });

    testWidgets('nothing cut, nothing shown', (tester) async {
      await _pumpApp(tester, _app(MadarRevealHints(child: _name(_short))));
      await tester.pump();
      expect(revealed(_short), findsNothing);
      expect(_exactly(_short), findsOneWidget);
    });

    testWidgets('goes when the surface goes', (tester) async {
      await _pumpApp(tester, _app(MadarRevealHints(child: _name(_long))));
      await tester.pump();
      expect(revealed(_long), findsOneWidget);
      await _pumpApp(tester, _app(const SizedBox.shrink()));
      await tester.pump();
      expect(revealed(_long), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic, right to left', (tester) async {
      await _pumpApp(
        tester,
        _app(
          MadarRevealHints(child: _name(_arLong, width: 140)),
          dir: TextDirection.rtl,
        ),
      );
      await tester.pump();
      final bubble = revealed(_arLong);
      expect(bubble, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: bubble, matching: find.byType(RichText)),
      );
      expect(paragraph.textDirection, TextDirection.rtl);
    });
  });

  group('icon-only controls: the hint is the word they dropped', () {
    testWidgets('a glyph tile says its word on a long press, not on a tap', (
      tester,
    ) async {
      var taps = 0;
      await _pumpApp(
        tester,
        _app(
          MadarGlyphTile(
            glyph: MadarGlyph.bag,
            semanticLabel: 'Park',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.longPress(find.byType(MadarGlyphTile));
      await tester.pump();
      expect(_bubble('Park'), findsOneWidget);
      expect(taps, 0);
    });

    testWidgets('Arabic: the tile says its Arabic word', (tester) async {
      await _pumpApp(
        tester,
        _app(
          MadarGlyphTile(
            glyph: MadarGlyph.bag,
            semanticLabel: 'اركن الطلب',
            onTap: () {},
          ),
          dir: TextDirection.rtl,
        ),
      );
      await tester.longPress(find.byType(MadarGlyphTile));
      await tester.pump();
      expect(_bubble('اركن الطلب'), findsOneWidget);
    });

    testWidgets('a glyph tile whose long press does something keeps it', (
      tester,
    ) async {
      var held = 0;
      await _pumpApp(
        tester,
        _app(
          MadarGlyphTile(
            glyph: MadarGlyph.printer,
            semanticLabel: 'Kitchen',
            onTap: () {},
            onLongPress: () => held++,
          ),
        ),
      );
      await tester.longPress(find.byType(MadarGlyphTile));
      await tester.pump();
      expect(held, 1);
      expect(_bubble('Kitchen'), findsNothing);
    });

    testWidgets('a glyph-only button says its tooltip on a long press', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        _app(
          MadarButton(
            label: '2',
            tooltip: 'Parked',
            glyph: MadarGlyph.bag,
            size: MadarButtonSize.compact,
            onTap: () {},
          ),
        ),
      );
      await tester.longPress(find.byType(MadarButton));
      await tester.pump();
      expect(_bubble('Parked'), findsOneWidget);
    });

    testWidgets('the compact outbox pill says the word it dropped', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        _app(
          MadarOutboxPill(
            state: OutboxState.offline,
            label: 'Offline',
            count: 3,
            onTap: () {},
            compact: true,
          ),
        ),
      );
      await tester.longPress(find.byType(MadarOutboxPill));
      await tester.pump();
      expect(_bubble('Offline'), findsOneWidget);
    });

    testWidgets('the full outbox pill has nothing to hint', (tester) async {
      await _pumpApp(
        tester,
        _app(
          MadarOutboxPill(
            state: OutboxState.offline,
            label: 'Offline',
            count: 3,
            onTap: () {},
          ),
        ),
      );
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('the kit controls hint their own cut words', () {
    testWidgets('a chip, a tag, a section header, a row', (tester) async {
      await _pumpApp(
        tester,
        _app(
          SizedBox(
            width: 150,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MadarChip(
                  key: const ValueKey('chip'),
                  label: 'Mohamed Abdelrahman',
                  onTap: () {},
                ),
                const MadarTag(
                  key: ValueKey('tag'),
                  label: 'Offline price applied',
                ),
                const MadarSectionHeader(
                  key: ValueKey('header'),
                  text: 'Choose your milk and sweetener',
                ),
                MadarRow(
                  key: const ValueKey('row'),
                  title: 'Terrace table by the window',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(Tooltip), findsNWidgets(4));
      await tester.longPress(find.byKey(const ValueKey('chip')));
      await tester.pump();
      expect(_bubble('Mohamed Abdelrahman'), findsOneWidget);
    });

    testWidgets('the same controls with room: no hints at all', (tester) async {
      await _pumpApp(
        tester,
        _app(
          SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MadarChip(label: 'Ahmed', onTap: () {}),
                const MadarTag(label: 'New'),
                const MadarSectionHeader(text: 'Milk'),
                MadarRow(title: 'T5', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(Tooltip), findsNothing);
    });
  });
}
