/// The hold hint: text that is cut off on screen shows its whole self when
/// the person presses and holds it.
///
/// The owner's ask (2026-09-26): "hold should display a hint text, and that
/// goes for all truncated items only across the whole app". Three pieces:
///
///  * [MadarClippedText] — THE text for anything that may not fit: an item
///    name on a tile, a parked order's chip, a customer, a category, a table
///    label, a tag, a modifier summary. A drop-in [Text] (same parameters,
///    same layout, same paint) that measures whether it was actually cut and,
///    only then, answers a long press with the full text.
///  * [MadarHoldHint] — the bubble itself, for a control that dropped its
///    word for room and shows a glyph alone (a glyph tile, a glyph-only
///    button, the compact outbox pill). The hint is the missing word.
///  * [MadarHoldHints.off] — marks a subtree whose long press already DOES
///    something (a tile's long-press open, a drag to reorder, a preview). No
///    hint under it takes the press away; the full text must be reachable in
///    what that long press opens instead.
///  * [MadarRevealHints] — the other half of that: a surface that IS the
///    answer to someone else's long press (a parked chip lifted to be
///    dragged) shows, at once and while it is up, the whole of every text
///    cut under it, in the same bubble.
///
/// A tablet has no hover, so the trigger is a long press. On a desktop build
/// a mouse resting on a cut text shows the same bubble.
///
/// @docImport 'package:design_system/src/controls.dart';
library;

import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// How long the bubble stays after the finger lifts: long enough to read a
/// two-line Arabic name without holding on.
const Duration _linger = Duration(milliseconds: 2500);

/// A mouse must rest this long before the bubble shows (desktop builds):
/// sweeping across a grid of cut names must not flash a bubble per tile.
const Duration _hoverWait = Duration(milliseconds: 500);

/// The widest a bubble grows before its text wraps.
const double _bubbleMaxWidth = 440;

/// Past this many pixels a paragraph's text is cut, not merely rounded.
const double _slack = 0.5;

/// Where a long press already belongs to something else.
///
/// [TactileScale] with an `onLongPress` puts one around its child by itself,
/// so a kit control with a long press (a [MadarButton]'s preview, a
/// [MadarGlyphTile]'s sheet) is covered. A feature that recognises a long
/// press on its own — a raw `GestureDetector(onLongPress:)`, a
/// `ReorderableDelayedDragStartListener` — wraps what it owns in
/// [MadarHoldHints.off], and says where the full text can be read instead
/// (the sheet that long press opens, or a [MadarRevealHints] on what it
/// lifts).
///
/// Under it a [MadarClippedText] draws exactly as before and still gives a
/// screen reader its whole text; it just installs no hint and no gesture.
class MadarHoldHints extends InheritedWidget {
  /// Hints off for [child]: its long press is spoken for.
  const MadarHoldHints.off({required super.child, super.key});

  /// Whether a hold hint may take a long press at [context].
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MadarHoldHints>() == null;

  @override
  bool updateShouldNotify(MadarHoldHints oldWidget) => false;
}

/// Where cut texts report to a [MadarRevealHints] above them. Separate from
/// [MadarHoldHints] on purpose: a reveal is about SHOWING, not about who owns
/// a press, so it wins over any `off` between it and the text (the lifted
/// chip is the same chip that turned its hints off in the strip).
class _RevealScope extends InheritedWidget {
  const _RevealScope({required this.reveal, required super.child});

  final _MadarRevealHintsState reveal;

  static _MadarRevealHintsState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RevealScope>()?.reveal;

  @override
  bool updateShouldNotify(_RevealScope oldWidget) => reveal != oldWidget.reveal;
}

/// Shows, at once and for as long as it is up, the whole of every
/// [MadarClippedText] cut under [child] — one bubble over [child], a line per
/// text, in the order they sit in the tree. Nothing shows when nothing under
/// it is cut.
///
/// For a surface that is the ANSWER to a long press someone else owns: the
/// parked-order chip a hold lifts to be dragged is drawn again as a proxy in
/// the overlay, and the proxy wears this, so the hold that picks it up also
/// says its whole name — while the drag keeps the press. The bubble follows
/// the proxy as it moves and goes with it.
class MadarRevealHints extends StatefulWidget {
  const MadarRevealHints({required this.child, super.key});

  final Widget child;

  @override
  State<MadarRevealHints> createState() => _MadarRevealHintsState();
}

class _MadarRevealHintsState extends State<MadarRevealHints> {
  final OverlayPortalController _portal = OverlayPortalController();

  /// Every text under the reveal, in tree order (they enrol as they mount),
  /// with its words while it is cut and null while it fits.
  final Map<State, String?> _cut = {};

  String get _message => _cut.values.whereType<String>().join('\n');

  /// [owner] mounted under this reveal: its place in the reading order.
  void _enrol(State owner) => _cut.putIfAbsent(owner, () => null);

  /// [owner] is cut and says [text] (null: it fits); [gone] when it leaves.
  /// Called from a descendant's build or dispose, so the rebuild waits for
  /// the frame's end.
  void _report(State owner, String? text, {bool gone = false}) {
    final before = _message;
    if (gone) {
      _cut.remove(owner);
    } else {
      _cut[owner] = text;
    }
    if (_message == before) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      if (_message.isEmpty) {
        _portal.hide();
      } else {
        _portal.show();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final scoped = _RevealScope(reveal: this, child: widget.child);
    if (context.findAncestorWidgetOfExactType<Overlay>() == null) {
      return scoped;
    }
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, info) {
        final message = _message;
        if (message.isEmpty) return const SizedBox.shrink();
        final box = info.childPaintTransform;
        final rect = MatrixUtils.transformRect(
          box,
          Offset.zero & info.childSize,
        );
        // Neither pressed nor read out: the texts under it already say
        // themselves in full to a screen reader.
        return Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: CustomSingleChildLayout(
                delegate: _AboveDelegate(rect),
                child: _Bubble(message: message),
              ),
            ),
          ),
        );
      },
      child: scoped,
    );
  }
}

/// Puts the bubble over [target] (centred, kept on screen), or under it when
/// there is no room above — the placement a [Tooltip] uses.
class _AboveDelegate extends SingleChildLayoutDelegate {
  const _AboveDelegate(this.target);

  final Rect target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - Space.lg * 2).clamp(
          0,
          _bubbleMaxWidth,
        ),
        maxHeight: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: target.center,
    verticalOffset: target.height / 2 + Space.sm,
    preferBelow: false,
    margin: Space.lg,
  );

  @override
  bool shouldRelayout(_AboveDelegate oldDelegate) =>
      target != oldDelegate.target;
}

/// The bubble's look, shared by the hold hint and the reveal: inverse — ink
/// on paper in the light theme, paper on ink in the dark — so it reads over
/// any surface it lands on.
BoxDecoration _bubbleDecoration(MadarColors colors) => BoxDecoration(
  color: colors.textPrimary,
  borderRadius: BorderRadius.circular(Radii.sm),
);

TextStyle _bubbleText(MadarColors colors) =>
    MadarType.body.copyWith(color: colors.surface);

const EdgeInsetsGeometry _bubblePadding = EdgeInsetsDirectional.symmetric(
  horizontal: Space.md,
  vertical: Space.sm,
);

MadarColors _colorsOf(BuildContext context) =>
    Theme.of(context).extension<MadarColors>() ?? MadarColors.light;

/// The reveal's bubble — the hold hint's, drawn without a [Tooltip].
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsOf(context);
    return Container(
      constraints: const BoxConstraints(minHeight: Metrics.tagHeight),
      padding: _bubblePadding,
      decoration: _bubbleDecoration(colors),
      child: Text(
        message,
        textAlign: TextAlign.start,
        style: _bubbleText(colors),
      ),
    );
  }
}

/// THE hint bubble: [message] over [child] on a long press (and on a
/// resting mouse), inverse ink on paper, the app's face, wrapped past
/// [_bubbleMaxWidth], laid out in the reading direction.
///
/// For a control that shows a glyph where its word would not fit — the
/// message is that word. A cut TEXT uses [MadarClippedText], which puts one
/// of these around itself only when it was actually cut.
///
/// Nothing is installed when [message] is empty, under [MadarHoldHints.off],
/// or where no [Overlay] exists to float the bubble in.
class MadarHoldHint extends StatelessWidget {
  const MadarHoldHint({
    required this.message,
    required this.child,
    this.hold = true,
    this.semantics = false,
    super.key,
  });

  /// The words the bubble shows, already localised.
  final String message;

  final Widget child;

  /// Whether a long press shows it. False when the control's own long press
  /// does something (the bubble then answers a resting mouse only), so the
  /// two never race for the same press.
  final bool hold;

  /// Whether [message] is also read out as the control's tooltip. Off when
  /// the child already says it — a [Text], a labelled [Semantics] — so a
  /// screen reader does not say it twice.
  final bool semantics;

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return child;
    if (!MadarHoldHints.enabledOf(context)) return child;
    if (context.findAncestorWidgetOfExactType<Overlay>() == null) return child;
    final colors = _colorsOf(context);
    return Tooltip(
      message: message,
      triggerMode: hold
          ? TooltipTriggerMode.longPress
          : TooltipTriggerMode.manual,
      excludeFromSemantics: !semantics,
      // Above the finger that is holding it, not under the hand.
      preferBelow: false,
      // The kit's own tick, on iOS too (the platform feedback is Android's
      // only), and never twice.
      enableFeedback: false,
      onTriggered: MadarHaptics.selection,
      waitDuration: _hoverWait,
      showDuration: _linger,
      constraints: const BoxConstraints(
        maxWidth: _bubbleMaxWidth,
        minHeight: Metrics.tagHeight,
      ),
      padding: _bubblePadding,
      margin: const EdgeInsets.symmetric(horizontal: Space.lg),
      decoration: _bubbleDecoration(colors),
      textStyle: _bubbleText(colors),
      child: child,
    );
  }
}

/// THE text that may not fit: a [Text] that knows when it was cut off.
///
/// Takes exactly [Text]'s parameters and lays out and paints exactly as that
/// [Text] would — swap `Text(` for `MadarClippedText(` and keep the rest.
/// After each paint it reads its paragraph: an ellipsis, a fade or a clip
/// that actually dropped something (a line past [maxLines], a run past the
/// box's width or height). Only then does it wrap itself in a
/// [MadarHoldHint] showing the whole text ([hint] when given). A text that
/// fits gets no bubble, no gesture and no tooltip — nothing but the [Text].
///
/// It re-measures whenever it repaints, so a new text, a text-size change, a
/// locale flip or a narrower column all move it in or out of the hint.
///
/// A screen reader always hears the WHOLE text: the paragraph's semantics are
/// its full string, never the ellipsised run, and the bubble adds no second
/// reading.
///
/// A long press that already does something keeps doing it: under
/// [MadarHoldHints.off] (put there by [TactileScale] with an `onLongPress`,
/// or by the feature that owns the press) no hint is installed.
class MadarClippedText extends StatefulWidget {
  const MadarClippedText(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.hint,
  }) : textSpan = null;

  /// A [Text.rich] that may not fit; the hint is its plain text.
  const MadarClippedText.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.hint,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;

  /// What the hold shows when the text is cut. Defaults to the whole text;
  /// pass it when the whole story is longer than the text (a chip that
  /// shows a name, whose hint also says who started the order).
  final String? hint;

  /// The words the bubble shows.
  String get fullText => hint ?? data ?? _plainText(textSpan!);

  @override
  State<MadarClippedText> createState() => _MadarClippedTextState();
}

/// [span]'s words, reading into a [WidgetSpan] that holds a text (a mono
/// figure set as an LTR island) instead of the placeholder character
/// [InlineSpan.toPlainText] writes for it.
String _plainText(InlineSpan span) {
  final out = StringBuffer();
  span.visitChildren((s) {
    switch (s) {
      case TextSpan(:final text?):
        out.write(text);
      case WidgetSpan(child: final Text t):
        out.write(
          t.data ?? (t.textSpan == null ? '' : _plainText(t.textSpan!)),
        );
      case WidgetSpan(child: final MadarClippedText t):
        out.write(t.fullText);
      default:
        break;
    }
    return true;
  });
  return out.toString();
}

class _MadarClippedTextState extends State<MadarClippedText> {
  /// What the last paint measured, as far as this build knows.
  bool _clipped = false;

  /// The [MadarRevealHints] this text reports to, when it sits under one.
  _MadarRevealHintsState? _reveal;

  void _measured(bool clipped) {
    if (!mounted || clipped == _clipped) return;
    setState(() => _clipped = clipped);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reveal = _RevealScope.maybeOf(context);
    if (reveal != _reveal) {
      _reveal?._report(this, null, gone: true);
      _reveal = reveal?.._enrol(this);
    }
  }

  @override
  void dispose() {
    _reveal?._report(this, null, gone: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final text = w.textSpan == null
        ? Text(
            w.data!,
            style: w.style,
            strutStyle: w.strutStyle,
            textAlign: w.textAlign,
            textDirection: w.textDirection,
            locale: w.locale,
            softWrap: w.softWrap,
            overflow: w.overflow,
            textScaler: w.textScaler,
            maxLines: w.maxLines,
            semanticsLabel: w.semanticsLabel,
            textWidthBasis: w.textWidthBasis,
            textHeightBehavior: w.textHeightBehavior,
          )
        : Text.rich(
            w.textSpan!,
            style: w.style,
            strutStyle: w.strutStyle,
            textAlign: w.textAlign,
            textDirection: w.textDirection,
            locale: w.locale,
            softWrap: w.softWrap,
            overflow: w.overflow,
            textScaler: w.textScaler,
            maxLines: w.maxLines,
            semanticsLabel: w.semanticsLabel,
            textWidthBasis: w.textWidthBasis,
            textHeightBehavior: w.textHeightBehavior,
          );
    final probe = _ClipProbe(
      clipped: _clipped,
      onMeasured: _measured,
      child: text,
    );
    // Under a reveal: say it there (its bubble is up while the surface is),
    // never on a press of its own.
    if (_reveal case final reveal?) {
      reveal._report(this, _clipped ? w.fullText : null);
      return probe;
    }
    if (!_clipped) return probe;
    return MadarHoldHint(message: w.fullText, child: probe);
  }
}

/// Reads its [Text]'s paragraph after each paint and reports a change in
/// "was it cut?" once the frame is done — a rebuild cannot happen mid-paint.
class _ClipProbe extends SingleChildRenderObjectWidget {
  const _ClipProbe({
    required this.clipped,
    required this.onMeasured,
    required Widget super.child,
  });

  /// What the owner believes; a paint that measures otherwise reports.
  final bool clipped;
  final ValueChanged<bool> onMeasured;

  @override
  _RenderClipProbe createRenderObject(BuildContext context) =>
      _RenderClipProbe(clipped: clipped, onMeasured: onMeasured);

  @override
  void updateRenderObject(BuildContext context, _RenderClipProbe renderObject) {
    renderObject
      ..clipped = clipped
      ..onMeasured = onMeasured;
  }
}

class _RenderClipProbe extends RenderProxyBox {
  _RenderClipProbe({required this.clipped, required this.onMeasured});

  bool clipped;
  ValueChanged<bool> onMeasured;

  /// The latest measurement, read when the frame's callback runs.
  bool _measured = false;
  bool _reportPending = false;

  // The check rides PAINT, not layout: any change to the paragraph — new
  // words, a text scale, a locale, a narrower box — relayouts it, and a
  // relayout always repaints it and so this probe above it. Layout alone
  // would miss a paragraph that is its own relayout boundary (a box tight on
  // both axes), whose relayout never reaches its parent.
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _measured = _isCut(_paragraphIn(child));
    if (_measured == clipped || _reportPending) return;
    _reportPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _reportPending = false;
      if (attached && _measured != clipped) onMeasured(_measured);
    });
  }

  /// The [Text]'s paragraph: the first one down the tree ([Text] may wrap it
  /// in a [Semantics] or a [MouseRegion]; a [WidgetSpan]'s own paragraphs
  /// sit under it and are never reached first).
  static RenderParagraph? _paragraphIn(RenderObject? node) {
    if (node == null) return null;
    if (node is RenderParagraph) return node;
    RenderParagraph? found;
    node.visitChildren((c) => found ??= _paragraphIn(c));
    return found;
  }

  /// RenderParagraph's own test for "clip or fade this", plus the lines that
  /// [Text.maxLines] dropped — the same facts it paints the ellipsis from.
  static bool _isCut(RenderParagraph? p) {
    if (p == null || !p.hasSize) return false;
    if (p.didExceedMaxLines) return true;
    if (p.overflow == TextOverflow.visible) return false;
    final text = p.textSize;
    return text.width > p.size.width + _slack ||
        text.height > p.size.height + _slack;
  }
}
