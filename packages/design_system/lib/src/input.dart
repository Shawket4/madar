/// THE text-entry rules — what a field is FOR, not how it is drawn.
///
/// Every text input in the POS is a `MadarField` or a `MadarAmountField`
/// (`controls.dart`). What changes between them is the KIND of thing being
/// typed, and on iOS that kind decides half a dozen things at once: which
/// keyboard rises, whether the system tries to autocorrect it, whether it is
/// capitalised, which characters are accepted, whether the figures stay
/// left-to-right inside an Arabic screen, and whether the keyboard offers any
/// way to dismiss itself.
///
/// Getting those right one screen at a time is how they drift, so they are
/// declared ONCE here, as [MadarFieldKind]. A screen says what the field is
/// ("this is a phone number"), never how the keyboard should behave.
///
/// ## What iOS gets wrong without this
///
/// * **No return key.** The iOS number pad, decimal pad and phone pad have no
///   return key at all: with one of them up, a person on an iPad has no way to
///   put the keyboard away, and the button they are reaching for is underneath
///   it. Those kinds get [MadarFieldKind.needsDoneBar], and the app draws an
///   accessory bar above the keyboard ([MadarKeyboardDoneBar]).
/// * **Autocorrect on codes.** An activation code or a PIN typed into a field
///   with autocorrect and sentence-capitalisation on comes out capitalised,
///   "corrected", or with a trailing space from the suggestion bar.
/// * **Arabic-Indic digits.** An Arabic keyboard on iOS can emit ٠-٩ (and a
///   Persian one ۰-۹). `int.parse` does not read them, so a quantity typed on
///   an Arabic iPad silently became nothing. [MadarDigitsFormatter] folds them
///   to ASCII as they are typed, so a mixed-script entry still adds up.
/// * **RTL figures.** A number in an Arabic line reorders unless it is pinned
///   LTR — "12.50" can render as "50.12".
library;

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What is being typed. The kind decides the keyboard, the corrections, the
/// accepted characters, the direction and the return key — see the library
/// doc for why each one is what it is.
enum MadarFieldKind {
  /// Free text with no expectations: a name for an order, a label.
  text,

  /// A person's name. Capitalised per word; autocorrect off, because a name
  /// is not a word iOS's dictionary knows and "Mona" becoming "Moan" is worse
  /// than no help at all.
  name,

  /// A sentence someone writes: a kitchen note, a void reason, a waste
  /// reason. The one kind where autocorrect and suggestions EARN their place.
  note,

  /// A filter over a list. No autocorrect (it fights an item code), no
  /// capitalisation, and the keyboard's return key reads "search".
  search,

  /// A phone number. Phone pad, digits and the dialling punctuation only.
  phone,

  /// A whole number: a quantity, a count. Number pad, digits only.
  digits,

  /// A money or measure figure: an amount, a weight. Decimal pad, digits and
  /// one separator.
  decimal,

  /// A code typed or pasted from elsewhere — an activation code, a device
  /// code, a LAN token. Upper-cased, never autocorrected, never capitalised
  /// by the system on top of that, and pinned LTR.
  code,

  /// A secret typed by the person standing there: a manager's PIN. A number
  /// pad, digits only, masked, and NOT selectable — see [allowsPaste].
  pin,

  /// An email address.
  email,

  /// A password.
  password,

  /// A host or URL: a printer address, a hub address.
  url,

  /// A calendar date typed as `YYYY-MM-DD`.
  date;

  /// The keyboard iOS raises.
  TextInputType get keyboardType => switch (this) {
    MadarFieldKind.phone => TextInputType.phone,
    MadarFieldKind.digits || MadarFieldKind.pin => TextInputType.number,
    MadarFieldKind.decimal => const TextInputType.numberWithOptions(
      decimal: true,
    ),
    MadarFieldKind.email => TextInputType.emailAddress,
    MadarFieldKind.url => TextInputType.url,
    MadarFieldKind.date => TextInputType.datetime,
    // `visiblePassword` is the one ALPHANUMERIC keyboard iOS raises with its
    // corrections and predictions off for good — what a typed code wants. A
    // code has letters in it, so it cannot take the number pad.
    MadarFieldKind.code => TextInputType.visiblePassword,
    MadarFieldKind.note => TextInputType.multiline,
    MadarFieldKind.name => TextInputType.name,
    MadarFieldKind.text ||
    MadarFieldKind.search ||
    MadarFieldKind.password => TextInputType.text,
  };

  /// Whether iOS may autocorrect what is typed. Only prose gets it.
  bool get autocorrect => this == MadarFieldKind.note;

  /// Whether the predictive strip appears. Same rule as [autocorrect], and
  /// never on a secret.
  bool get enableSuggestions => this == MadarFieldKind.note;

  /// How the system capitalises.
  TextCapitalization get textCapitalization => switch (this) {
    MadarFieldKind.name => TextCapitalization.words,
    MadarFieldKind.note => TextCapitalization.sentences,
    MadarFieldKind.code => TextCapitalization.characters,
    _ => TextCapitalization.none,
  };

  /// Whether the text may be selected, copied and pasted.
  ///
  /// Everything is selectable EXCEPT [MadarFieldKind.pin] — the typed
  /// manager PIN. That is a deliberate choice, not an oversight: a manager's
  /// PIN is a credential the manager types at the till to stand behind an
  /// act, and a PIN sitting on the clipboard (or long-press-pasted by the
  /// person asking for the approval) is exactly the sharing the approval
  /// exists to prevent. It is four to six digits — nobody needs paste.
  ///
  /// An activation code ([MadarFieldKind.code]) is the opposite case: it is
  /// READ off the dashboard and pasted in, so it stays selectable.
  bool get allowsPaste => this != MadarFieldKind.pin;

  /// Figures and codes are LTR islands whatever the script around them.
  bool get forcesLtr => switch (this) {
    MadarFieldKind.phone ||
    MadarFieldKind.digits ||
    MadarFieldKind.decimal ||
    MadarFieldKind.pin ||
    MadarFieldKind.code ||
    MadarFieldKind.email ||
    MadarFieldKind.url ||
    MadarFieldKind.date => true,
    _ => false,
  };

  /// Whether this kind is masked by default.
  bool get obscures =>
      this == MadarFieldKind.pin || this == MadarFieldKind.password;

  /// Whether the keyboard iOS raises for this kind has NO return key, so the
  /// app must supply a Done affordance of its own.
  ///
  /// The number pad, decimal pad and phone pad are all keys-only: without a
  /// bar above them there is no way to put them away except tapping outside,
  /// which on a form whose fields fill the screen is no way at all.
  bool get needsDoneBar => switch (this) {
    MadarFieldKind.phone ||
    MadarFieldKind.digits ||
    MadarFieldKind.decimal ||
    MadarFieldKind.pin ||
    MadarFieldKind.date => true,
    _ => false,
  };

  /// The return key, when the keyboard has one and the caller did not choose.
  TextInputAction? get defaultAction => switch (this) {
    MadarFieldKind.search => TextInputAction.search,
    // A note is the one field where the return key must insert a newline.
    MadarFieldKind.note => TextInputAction.newline,
    _ when needsDoneBar => null,
    _ => TextInputAction.done,
  };

  /// What may be typed. Every numeric kind also folds Arabic-Indic and
  /// Persian digits to ASCII (see [MadarDigitsFormatter]).
  List<TextInputFormatter> get inputFormatters => switch (this) {
    MadarFieldKind.digits ||
    MadarFieldKind.pin => const [MadarDigitsFormatter()],
    MadarFieldKind.decimal => const [MadarDigitsFormatter(decimal: true)],
    // A phone keeps the punctuation a number is written with.
    MadarFieldKind.phone => const [MadarDigitsFormatter(extra: '+()- ')],
    MadarFieldKind.date => const [MadarDigitsFormatter(extra: '-/')],
    MadarFieldKind.code => const [
      MadarDigitsFormatter(extra: _codeLetters, letters: true),
    ],
    _ => const [],
  };
}

/// The punctuation an activation code may carry between its groups.
const String _codeLetters = '-';

/// Folds Arabic-Indic (٠-٩) and Persian (۰-۹) digits to ASCII and keeps only
/// what the field accepts.
///
/// The folding is the point. An Arabic iOS keyboard emits U+0660–U+0669 for
/// its number row; `int.parse`, `double.parse` and every `RegExp(r'\d')` in
/// the app read ASCII only, so a quantity or an amount typed on an Arabic
/// iPad parsed as nothing at all and the field silently stayed empty. Folding
/// as the person types means a mixed-script entry still adds up, and what the
/// field SHOWS is what will be stored.
class MadarDigitsFormatter extends TextInputFormatter {
  const MadarDigitsFormatter({
    this.decimal = false,
    this.extra = '',
    this.letters = false,
  });

  /// Accept one decimal separator (`.` or `٫`, folded to `.`).
  final bool decimal;

  /// Extra characters this field accepts beyond digits.
  final String extra;

  /// Accept ASCII letters too, upper-cased (an activation code).
  final bool letters;

  /// Arabic-Indic U+0660 and Persian U+06F0, the two zero code points whose
  /// blocks run 0-9 in order.
  static const int _arabicZero = 0x0660;
  static const int _persianZero = 0x06F0;

  /// Fold every Arabic-Indic / Persian digit in [s] to ASCII, and the Arabic
  /// decimal separator (U+066B) to a point. Anything else passes through.
  static String foldDigits(String s) {
    final out = StringBuffer();
    for (final rune in s.runes) {
      if (rune >= _arabicZero && rune <= _arabicZero + 9) {
        out.writeCharCode(0x30 + (rune - _arabicZero));
      } else if (rune >= _persianZero && rune <= _persianZero + 9) {
        out.writeCharCode(0x30 + (rune - _persianZero));
      } else if (rune == 0x066B) {
        out.write('.'); // Arabic decimal separator
      } else if (rune == 0x066C) {
        continue; // Arabic thousands separator: not part of the figure
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final folded = foldDigits(newValue.text);
    final kept = StringBuffer();
    var seenSeparator = false;
    for (final rune in folded.runes) {
      final isDigit = rune >= 0x30 && rune <= 0x39;
      if (isDigit) {
        kept.writeCharCode(rune);
        continue;
      }
      if (decimal && rune == 0x2E) {
        // One separator only: a second one is a typo, not a figure.
        if (seenSeparator) continue;
        seenSeparator = true;
        kept.writeCharCode(rune);
        continue;
      }
      final ch = String.fromCharCode(rune);
      if (letters && RegExp('[A-Za-z]').hasMatch(ch)) {
        kept.write(ch.toUpperCase());
        continue;
      }
      if (extra.contains(ch)) kept.write(ch);
    }
    final text = kept.toString();
    if (text == newValue.text) return newValue;
    // Keep the caret where the person left it, measured from the END, so
    // dropping a rejected character does not throw them to position zero.
    final fromEnd = newValue.text.length - newValue.selection.baseOffset;
    final offset = (text.length - fromEnd).clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// The field that currently wants a Done bar over the keyboard, if any.
///
/// A `MadarField` publishes its own focus node here while it holds focus and
/// its kind has a keyboard with no return key; [MadarKeyboardDoneBar], which
/// wraps the whole app, draws the bar and clears the focus when it is tapped.
/// A `ValueNotifier` rather than an `InheritedWidget` because the publisher
/// and the bar are at opposite ends of the tree, and the value changes on
/// focus — not something to rebuild a screen for.
abstract final class MadarKeyboardDone {
  static final ValueNotifier<FocusNode?> node = ValueNotifier<FocusNode?>(null);

  /// The already-localized word on the bar's button. The app sets it once
  /// from the core's i18n (`common.done`); the English default keeps the bar
  /// working before the language is known.
  static String label = 'Done';

  /// This field has focus and needs the bar.
  static void claim(FocusNode focus) => _set(focus);

  /// This field lost focus: drop the bar, unless another field already
  /// claimed it (focus moves before the old node reports it lost).
  static void release(FocusNode focus) {
    if (identical(node.value, focus)) _set(null);
  }

  /// Focus notifications arrive at any point in the frame, build and layout
  /// included (a route swap moves focus while the tree is being built).
  /// Writing the notifier there marks the bar dirty inside a locked tree —
  /// "setState() called when widget tree was locked". So: set it now when the
  /// frame is idle, and after this frame when it is not.
  static void _set(FocusNode? value) {
    if (node.value == value) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      node.value = value;
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (node.value != value) node.value = value;
    });
  }
}

/// Draws a Done bar directly above the software keyboard whenever a field
/// with a keys-only keyboard (number / decimal / phone pad) has focus.
///
/// Wrap the app once, around everything, at the level that already owns the
/// tap-outside-to-dismiss handler. It renders nothing at all when no such
/// field is focused or the keyboard is down, so it costs a
/// `ValueListenableBuilder` and nothing else.
class MadarKeyboardDoneBar extends StatelessWidget {
  const MadarKeyboardDoneBar({required this.child, this.label, super.key});

  final Widget child;

  /// The already-localized word on the button ("Done" / "تم"). Defaults to
  /// [MadarKeyboardDone.label], which the app sets from the core's i18n.
  final String? label;

  /// The bar's height, so a caller can reserve room for it.
  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FocusNode?>(
      valueListenable: MadarKeyboardDone.node,
      builder: (context, focus, _) {
        final inset = MediaQuery.viewInsetsOf(context).bottom;
        // No claim, or the keyboard is not up (a hardware keyboard is
        // attached — then there is nothing to dismiss).
        if (focus == null || inset <= 0) return child;
        return Stack(
          children: [
            child,
            Positioned(
              left: 0,
              right: 0,
              bottom: inset,
              child: _DoneBar(
                label: label ?? MadarKeyboardDone.label,
                onDone: focus.unfocus,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DoneBar extends StatelessWidget {
  const _DoneBar({required this.label, required this.onDone});

  final String label;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    // The bar sits in MaterialApp.builder, above every Scaffold, so nothing
    // under it is a Material. Without this one the word falls back to
    // Flutter's debug text style: a double yellow underline on real devices.
    return Semantics(
      container: true,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          height: MadarKeyboardDoneBar.height,
          alignment: AlignmentDirectional.centerEnd,
          padding: const EdgeInsetsDirectional.only(end: 12),
          decoration: const BoxDecoration(color: Color(0xFFD1D4DA)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDone,
            child: Container(
              // The 44pt touch rule applies to the one control on this bar.
              constraints: const BoxConstraints(minWidth: 64, minHeight: 44),
              alignment: Alignment.center,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B63CE),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
