// The text-entry rules (`input.dart`) and what MadarField / MadarAmountField
// hand the platform because of them — the iPad/iOS behaviours from the
// owner's report: the right keyboard, no autocorrect on a code or a PIN,
// Arabic-Indic digits folded, figures kept LTR, paste refused on a typed
// manager PIN, a Done bar over a keyboard with no return key, next-field
// traversal, the field scrolled clear of the keys, and a value that survives
// a rebuild.

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// iPad 9 landscape / portrait — the small iPad the POS is drawn for.
const Size _ipad9 = Size(1080, 810);
const Size _ipad9Portrait = Size(810, 1080);

/// The iPad software keyboard, near enough: it takes the lower ~320pt.
const double _keyboard = 320;

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _keyboardUp(WidgetTester tester) {
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard * 1.0);
  addTearDown(tester.view.resetViewInsets);
}

Widget _app(Widget home, {TextDirection dir = TextDirection.ltr}) =>
    MaterialApp(
      theme: MadarTheme.light(),
      home: Directionality(
        textDirection: dir,
        child: Scaffold(body: home),
      ),
    );

/// The app as it is really wired: the Done bar sits in `MaterialApp.builder`,
/// ABOVE every Scaffold — a Scaffold eats the bottom inset for its body, so a
/// bar inside one would never see the keyboard.
Widget _appWithBar(
  Widget home, {
  String label = 'Done',
  TextDirection dir = TextDirection.ltr,
}) => MaterialApp(
  theme: MadarTheme.light(),
  builder: (context, child) =>
      MadarKeyboardDoneBar(label: label, child: child ?? const SizedBox()),
  home: Directionality(
    textDirection: dir,
    child: Scaffold(body: home),
  ),
);

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first);

void main() {
  group('the kind decides what the platform is told', () {
    testWidgets('a quantity takes a number pad, not a text keyboard', (
      tester,
    ) async {
      _size(tester, _ipad9);
      await tester.pumpWidget(
        _app(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'Quantity',
            kind: MadarFieldKind.digits,
          ),
        ),
      );
      expect(_field(tester).keyboardType, TextInputType.number);
      expect(_field(tester).autocorrect, isFalse);
      expect(_field(tester).enableSuggestions, isFalse);
      expect(_field(tester).textCapitalization, TextCapitalization.none);
    });

    testWidgets('a phone takes the phone pad', (tester) async {
      _size(tester, _ipad9);
      await tester.pumpWidget(
        _app(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'Phone',
            kind: MadarFieldKind.phone,
          ),
        ),
      );
      expect(_field(tester).keyboardType, TextInputType.phone);
    });

    testWidgets('a code is never autocorrected or sentence-capitalised', (
      tester,
    ) async {
      _size(tester, _ipad9);
      await tester.pumpWidget(
        _app(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'Activation code',
            kind: MadarFieldKind.code,
          ),
        ),
      );
      final f = _field(tester);
      expect(f.autocorrect, isFalse);
      expect(f.enableSuggestions, isFalse);
      expect(f.textCapitalization, TextCapitalization.characters);
      // A code has letters in it, so it cannot take the number pad.
      expect(f.keyboardType, TextInputType.visiblePassword);
    });

    testWidgets('only a note gets autocorrect and suggestions', (tester) async {
      _size(tester, _ipad9);
      for (final kind in MadarFieldKind.values) {
        expect(
          kind.autocorrect,
          kind == MadarFieldKind.note,
          reason: '$kind autocorrect',
        );
        expect(
          kind.enableSuggestions,
          kind == MadarFieldKind.note,
          reason: '$kind suggestions',
        );
      }
    });

    testWidgets('a figure is an LTR island inside an Arabic screen', (
      tester,
    ) async {
      _size(tester, _ipad9);
      await tester.pumpWidget(
        _app(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'المبلغ',
            kind: MadarFieldKind.decimal,
          ),
          dir: TextDirection.rtl,
        ),
      );
      expect(_field(tester).textDirection, TextDirection.ltr);
    });

    testWidgets('prose follows the screen, it is not forced LTR', (
      tester,
    ) async {
      _size(tester, _ipad9);
      await tester.pumpWidget(
        _app(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'ملاحظة',
            kind: MadarFieldKind.note,
          ),
          dir: TextDirection.rtl,
        ),
      );
      expect(_field(tester).textDirection, isNull);
    });
  });

  group('paste', () {
    testWidgets('a typed manager PIN cannot be selected or pasted into', (
      tester,
    ) async {
      _size(tester, _ipad9);
      await tester.pumpWidget(
        _app(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'PIN',
            kind: MadarFieldKind.pin,
          ),
        ),
      );
      final f = _field(tester);
      expect(f.enableInteractiveSelection, isFalse);
      expect(f.obscureText, isTrue, reason: 'a PIN is masked by its kind');
    });

    testWidgets('an activation code IS pasteable — it is read off a screen', (
      tester,
    ) async {
      _size(tester, _ipad9);
      await tester.pumpWidget(
        _app(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'Code',
            kind: MadarFieldKind.code,
          ),
        ),
      );
      expect(_field(tester).enableInteractiveSelection, isTrue);
      expect(_field(tester).obscureText, isFalse);
    });

    test('every kind but the typed PIN allows paste', () {
      for (final kind in MadarFieldKind.values) {
        expect(
          kind.allowsPaste,
          kind != MadarFieldKind.pin,
          reason: '$kind paste',
        );
      }
    });
  });

  group('Arabic and mixed digits', () {
    test('Arabic-Indic and Persian digits fold to ASCII', () {
      expect(MadarDigitsFormatter.foldDigits('١٢٣'), '123');
      expect(MadarDigitsFormatter.foldDigits('۴۵۶'), '456');
      expect(MadarDigitsFormatter.foldDigits('٠٫٥'), '0.5');
      // A mixed entry — the Arabic keyboard's number row beside an ASCII one.
      expect(MadarDigitsFormatter.foldDigits('1٢3'), '123');
      expect(MadarDigitsFormatter.foldDigits('abc'), 'abc');
    });

    testWidgets(
      'a quantity typed in Arabic digits reaches the caller as ASCII',
      (tester) async {
        _size(tester, _ipad9);
        final controller = TextEditingController();
        String? seen;
        await tester.pumpWidget(
          _app(
            MadarField(
              controller: controller,
              placeholder: 'الكمية',
              kind: MadarFieldKind.decimal,
              onChanged: (v) => seen = v,
            ),
            dir: TextDirection.rtl,
          ),
        );
        await tester.enterText(find.byType(TextField), '١٢٫٥');
        await tester.pump();
        expect(seen, '12.5');
        expect(controller.text, '12.5');
        expect(double.tryParse(controller.text), 12.5);
      },
    );

    testWidgets('a quantity refuses letters and a second separator', (
      tester,
    ) async {
      _size(tester, _ipad9);
      final controller = TextEditingController();
      await tester.pumpWidget(
        _app(
          MadarField(
            controller: controller,
            placeholder: 'Qty',
            kind: MadarFieldKind.decimal,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '1a2.3.4');
      await tester.pump();
      expect(controller.text, '12.34');
    });

    testWidgets('an amount field folds Arabic digits too', (tester) async {
      _size(tester, _ipad9);
      int? minor;
      await tester.pumpWidget(
        _app(
          MadarAmountField(
            amountMinor: null,
            currencyCode: 'EGP',
            onAmountMinor: (v) => minor = v,
          ),
          dir: TextDirection.rtl,
        ),
      );
      await tester.enterText(find.byType(TextField), '١٢٫٥٠');
      await tester.pump();
      expect(minor, 1250, reason: 'EGP 12.50, typed on an Arabic keyboard');
    });
  });

  group('the Done bar, for a keyboard with no return key', () {
    testWidgets('a number pad claims it; the bar sits above the keys', (
      tester,
    ) async {
      _size(tester, _ipad9);
      _keyboardUp(tester);
      await tester.pumpWidget(
        _appWithBar(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'Count',
            kind: MadarFieldKind.digits,
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      final bar = tester.getRect(find.text('Done'));
      expect(
        bar.bottom,
        lessThanOrEqualTo(810 - _keyboard),
        reason: 'the bar is above the keyboard, not under it',
      );
    });

    // The bar lives in MaterialApp.builder, above every Scaffold, so no
    // Material paints under it. Without one, Flutter falls back to its debug
    // text style: the "Done" word came out with a double yellow underline on
    // real iOS and Android builds.
    testWidgets('the Done word is plain text, not the debug fallback style', (
      tester,
    ) async {
      _size(tester, _ipad9);
      _keyboardUp(tester);
      await tester.pumpWidget(
        _appWithBar(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'Count',
            kind: MadarFieldKind.digits,
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      final word = tester.widget<RichText>(
        find.descendant(of: find.text('Done'), matching: find.byType(RichText)),
      );
      final style = word.text.style!;
      expect(
        style.decoration,
        anyOf(isNull, TextDecoration.none),
        reason: 'no debug underline under the word',
      );
      expect(
        style.debugLabel ?? '',
        isNot(contains('fallback style')),
        reason: 'the bar sits on a Material, not on the debug fallback',
      );
    });

    testWidgets('a note keyboard has a return key, so no bar appears', (
      tester,
    ) async {
      _size(tester, _ipad9);
      _keyboardUp(tester);
      await tester.pumpWidget(
        _appWithBar(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'Note',
            kind: MadarFieldKind.note,
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsNothing);
    });

    testWidgets('tapping Done drops focus and puts the keyboard away', (
      tester,
    ) async {
      _size(tester, _ipad9);
      _keyboardUp(tester);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _appWithBar(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'Count',
            kind: MadarFieldKind.digits,
            focusNode: focus,
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(find.text('Done'), findsNothing, reason: 'the bar goes with it');
    });

    testWidgets(
      'with a hardware keyboard (no inset) there is nothing to dismiss',
      (tester) async {
        _size(tester, _ipad9);
        await tester.pumpWidget(
          _appWithBar(
            MadarField(
              controller: TextEditingController(),
              placeholder: 'Count',
              kind: MadarFieldKind.digits,
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(find.text('Done'), findsNothing);
      },
    );

    testWidgets('an amount field claims the bar as well', (tester) async {
      _size(tester, _ipad9Portrait);
      _keyboardUp(tester);
      await tester.pumpWidget(
        _appWithBar(
          const MadarAmountField(amountMinor: null, currencyCode: 'EGP'),
          label: 'تم',
          dir: TextDirection.rtl,
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('تم'), findsOneWidget);
    });
  });

  group('focus order', () {
    testWidgets('the return key moves to the next field', (tester) async {
      _size(tester, _ipad9);
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              MadarField(
                controller: TextEditingController(),
                placeholder: 'Name',
                kind: MadarFieldKind.name,
                focusNode: first,
                nextFocus: second,
              ),
              MadarField(
                controller: TextEditingController(),
                placeholder: 'Phone',
                kind: MadarFieldKind.phone,
                focusNode: second,
              ),
            ],
          ),
        ),
      );
      final name = tester.widget<TextField>(find.byType(TextField).first);
      expect(name.textInputAction, TextInputAction.next);

      first.requestFocus();
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(second.hasFocus, isTrue, reason: 'Tab / next lands on the phone');
    });

    testWidgets('a search field offers a search key', (tester) async {
      _size(tester, _ipad9);
      await tester.pumpWidget(
        _app(
          MadarField(
            controller: TextEditingController(),
            placeholder: 'Search',
            kind: MadarFieldKind.search,
          ),
        ),
      );
      expect(_field(tester).textInputAction, TextInputAction.search);
    });
  });

  group('the keyboard never covers the field', () {
    testWidgets('a field low on an iPad form scrolls clear of the keys', (
      tester,
    ) async {
      _size(tester, _ipad9);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final target = GlobalKey();
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: Column(
              children: [
                // A tall form: the field below it starts off-screen-low.
                const SizedBox(height: 700),
                MadarField(
                  key: target,
                  controller: TextEditingController(),
                  placeholder: 'Counted',
                  kind: MadarFieldKind.decimal,
                  focusNode: focus,
                ),
                const SizedBox(height: 700),
              ],
            ),
          ),
        ),
      );
      final before = tester.getTopLeft(find.byKey(target)).dy;
      expect(before, greaterThan(810 - _keyboard), reason: 'under the keys');

      _keyboardUp(tester);
      focus.requestFocus();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      final after = tester.getTopLeft(find.byKey(target)).dy;
      expect(
        after,
        lessThan(810 - _keyboard),
        reason: 'the field was brought above the keyboard',
      );
    });
  });

  group('a value survives the screen being rebuilt', () {
    testWidgets('rotating the iPad keeps what was typed', (tester) async {
      _size(tester, _ipad9);
      final controller = TextEditingController();
      Widget build() => _app(
        MadarField(
          controller: controller,
          placeholder: 'Note',
          kind: MadarFieldKind.note,
        ),
      );
      await tester.pumpWidget(build());
      await tester.enterText(find.byType(TextField), 'no onions');
      await tester.pump();

      // Rotate: a new size, a full rebuild.
      _size(tester, _ipad9Portrait);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(_field(tester).controller!.text, 'no onions');
      expect(find.text('no onions'), findsOneWidget);
    });

    testWidgets('an amount field keeps a figure typed before the value lands', (
      tester,
    ) async {
      _size(tester, _ipad9);
      int? minor;
      await tester.pumpWidget(
        _app(
          MadarAmountField(
            amountMinor: null,
            currencyCode: 'EGP',
            onAmountMinor: (v) => minor = v,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '25');
      await tester.pump();
      expect(minor, 2500);
      // The owner's value arrives on a later frame; the text must not reset.
      await tester.pumpWidget(
        _app(
          MadarAmountField(
            amountMinor: 2500,
            currencyCode: 'EGP',
            onAmountMinor: (v) => minor = v,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('25'), findsOneWidget);
    });
  });
}
