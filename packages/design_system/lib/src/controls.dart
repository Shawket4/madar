/// THE shared control kit — one button, one field, one card, one section
/// header, one hairline, for the whole app.
///
/// These lived as six near-identical copies, one per feature package
/// (`ActionButton` in order AND checkout, `MadarButton` in auth,
/// `HistoryButton`, `IncomingButton`, `ShiftButton`), each carrying its own
/// variant enum. They were not merely redundant: they had drifted apart, and
/// every fork was missing a fix made in one of its siblings —
///
///   * checkout's button never got order's unbounded-width guard, so putting
///     one in a bare `Row` threw and blanked the whole subtree;
///   * checkout's amount field never got shift's `EntranceFocus`, the fix for
///     the iPad race that wedges the text-input connection;
///   * order's and checkout's buttons were flat 50pt/`Radii.sm` while the
///     other four were lifted 54pt/`Radii.md`, so the same "confirm" read two
///     different ways depending on which screen you were standing on.
///
/// The design here is the one four of the six already followed, which is also
/// the natives' spec (`Components.kt` / `SharedComponents.swift`): a top-lit
/// gradient with an accent glow on the primary action, a neutral hairline on
/// the secondary, and a tactile press scale on both.
///
/// A control that is genuinely one screen's own — a PIN pad, a payment badge,
/// a floor-plan table — still belongs to that feature. Only the things every
/// screen needs live here.
library;

import 'package:design_system/src/focus.dart';
import 'package:design_system/src/icons.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/elevation.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/material.dart';

// Native component metrics that fall between the 4-pt Space steps, kept
// verbatim so the Flutter chrome measures identically to the natives.

/// Primary-CTA top-lit gradient: a hint of white along the top edge so the
/// filled button reads lifted rather than flat (natives: lerp(accent, white,
/// 0.16)).
const double _ctaTopLight = 0.16;

/// Button label letter-spacing (natives: 0.2.sp).
const double _buttonTracking = 0.2;

/// Loading spinner diameter / stroke (natives: 20.dp / 2.5.dp).
const double _spinnerSize = 20;
const double _spinnerStroke = 2.5;

/// Outline button border width (natives: 1.5.dp).
const double _outlineBorder = 1.5;

/// Dense-toolbar button height (natives: 50.dp) — see [MadarButtonSize].
const double _compactHeight = 50;

/// Text-field vertical inset (natives: 16.dp) and icon-to-text gap (10.dp).
const double _fieldVPad = 16;
const double _fieldGap = 10;

/// Focus glow blur on text fields (natives: shadow(8.dp, accent)).
const double _fieldGlowBlur = 8;

/// Section-header accent capsule (natives: 3x12dp).
const Size _sectionTick = Size(3, 12);

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Shadow list for [level] resolved against the current theme.
List<BoxShadow> elevationShadows(BuildContext context, MadarElevation level) =>
    level.shadows(context.madarColors, dark: _isDark(context));

// ── Button ───────────────────────────────────────────────────────────────

/// Emphasis of a [MadarButton] — the natives' `BtnVariant`.
enum MadarButtonVariant {
  /// The one terminal action on the surface: accent fill, top-lit gradient,
  /// accent glow. At most one per screen or sheet.
  primary,

  /// The alternative to the primary: hairline border on surface, plain label.
  ///
  /// Deliberately NEUTRAL rather than accent-tinted. Two accent-coloured
  /// buttons side by side make the reader stop and choose, which is exactly
  /// what a secondary action must not do.
  outline,

  /// Recessive exit — cancel, sign out, "not now". No fill, no border.
  ghost,

  /// Destructive confirm. Reads as loud as primary, on purpose.
  danger,
}

/// Height/rhythm of a [MadarButton].
enum MadarButtonSize {
  /// The default: 54pt, [Radii.md], [MadarType.title]. Every full-width CTA
  /// and every sheet's confirm.
  regular,

  /// 50pt, [Radii.sm], [MadarType.body], no glow — for a dense toolbar row
  /// where several buttons sit shoulder to shoulder and a halo on each would
  /// be noise (the floor's arrivals/waitlist/view controls, the cart's row of
  /// verbs).
  compact,
}

/// THE button. Tactile press scale, impact haptic, optional leading icon,
/// spinner while [loading], 45%-alpha when disabled.
///
/// Width adapts to the parent: it fills and ellipsizes when the parent bounds
/// it (a Column with stretch, the common case) and shrink-wraps when it does
/// not (a bare child of a Row). A `Flexible` under unbounded width is illegal
/// and the assertion does not merely break the button — it fails the whole
/// subtree's layout and blanks the screen hosting it.
class MadarButton extends StatelessWidget {
  /// Creates a button.
  const MadarButton({
    required this.label,
    required this.onTap,
    this.variant = MadarButtonVariant.primary,
    this.size = MadarButtonSize.regular,
    this.icon,
    this.loading = false,
    this.enabled = true,
    this.tooltip,
    super.key,
  });

  /// Already-localized label.
  final String label;

  /// Tap handler; fires after the impact haptic.
  final VoidCallback onTap;

  /// Visual emphasis.
  final MadarButtonVariant variant;

  /// Height/rhythm.
  final MadarButtonSize size;

  /// Optional leading [MadarIcon] name.
  final String? icon;

  /// Replaces the label with a spinner and blocks taps.
  final bool loading;

  /// Dims the fill and blocks taps when false.
  final bool enabled;

  /// When set, wraps the button in a [Tooltip] — use it to say WHY a disabled
  /// button is disabled, which is the only honest way to disable one.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final active = enabled && !loading;
    final compact = size == MadarButtonSize.compact;

    final fg = switch (variant) {
      MadarButtonVariant.primary => colors.textOnAccent,
      MadarButtonVariant.danger => colors.textOnAccent,
      MadarButtonVariant.outline => colors.textPrimary,
      MadarButtonVariant.ghost => colors.textSecondary,
    };

    // The lift: a primary action is the only thing on the surface that
    // catches light. `gradient` REPLACES `color` in a BoxDecoration, so the
    // two are never both set.
    final lit = variant == MadarButtonVariant.primary && active;
    final gradient = lit
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(colors.accent, Colors.white, _ctaTopLight)!,
              colors.accent,
            ],
          )
        : null;
    final fill = switch (variant) {
      MadarButtonVariant.primary =>
        active ? null : colors.accent.withValues(alpha: Opacities.disabled),
      MadarButtonVariant.danger =>
        active
            ? colors.danger
            : colors.danger.withValues(alpha: Opacities.disabled),
      MadarButtonVariant.outline => colors.surface,
      MadarButtonVariant.ghost => null,
    };

    final labelStyle = (compact ? MadarType.body : MadarType.title).copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: compact ? null : _buttonTracking,
      color: active ? fg : fg.withValues(alpha: Opacities.disabled),
    );

    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: labelStyle,
    );

    Widget button = Container(
      height: compact ? _compactHeight : Metrics.buttonHeight,
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: compact ? Space.md : Space.lg,
      ),
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(compact ? Radii.sm : Radii.md),
        border: variant == MadarButtonVariant.outline
            ? Border.all(
                color: colors.border,
                width: compact ? 1 : _outlineBorder,
              )
            : null,
        // A halo belongs to the one action that owns the screen, not to a row
        // of toolbar buttons.
        boxShadow: lit && !compact
            ? elevationShadows(context, MadarElevation.glow)
            : null,
      ),
      // NO `alignment:` here. A Container with an alignment wraps its child in
      // an Align, which EXPANDS to fill loose constraints — which turned a
      // toolbar of four compact buttons into four full-width bars stacked down
      // the page. The Row below does the centring instead.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // TIGHT, not merely bounded. A button fills its line only when the
          // parent actually dictates the width — `Expanded`, a stretched
          // Column, a `SizedBox(width:)`. A `Wrap` or a bare `Row` child hands
          // down LOOSE constraints, and filling those turns a toolbar of four
          // buttons into four full-width bars stacked down the page.
          final fill = constraints.hasTightWidth;
          // Ellipsis needs a bound; a `Flexible` under an UNBOUNDED width is
          // illegal and its assertion blanks the whole subtree, not just the
          // button.
          final bounded = constraints.hasBoundedWidth;
          if (loading) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: _spinnerSize,
                  child: CircularProgressIndicator(
                    color: fg,
                    strokeWidth: _spinnerStroke,
                  ),
                ),
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (icon != null) ...[
                MadarIcon(
                  icon,
                  tint: active ? fg : fg.withValues(alpha: Opacities.disabled),
                  size: IconSize.lg,
                ),
                // A button with an icon and NO label is a square glyph tile;
                // it must not carry a gap that pushes the glyph off centre.
                if (label.isNotEmpty) const SizedBox(width: Space.sm),
              ],
              if (label.isNotEmpty)
                if (bounded) Flexible(child: text) else text,
            ],
          );
        },
      ),
    );

    if (active) {
      button = TactileScale(
        haptic: false,
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: button,
      );
    }
    final tip = tooltip;
    if (tip != null) button = Tooltip(message: tip, child: button);
    return Semantics(button: true, enabled: active, child: button);
  }
}

/// A square glyph tile — a verb with no room for a word, standing beside a
/// [MadarButton] in the same row.
///
/// It matches the button's height and corner radius at the same [size], which
/// is the whole point: the pair used to be a 50pt tile beside a 54pt button,
/// and a row of controls that do not line up is the cheapest way to make a
/// screen look unfinished.
class MadarGlyphTile extends StatelessWidget {
  /// Creates a glyph tile.
  const MadarGlyphTile({
    required this.icon,
    required this.onTap,
    required this.tint,
    required this.background,
    this.semanticLabel,
    this.size = MadarButtonSize.regular,
    super.key,
  });

  /// [MadarIcon] name.
  final String icon;

  /// Tap handler; fires after the impact haptic.
  final VoidCallback onTap;

  /// Glyph colour.
  final Color tint;

  /// Tile fill — usually the tint's `*Bg` companion.
  final Color background;

  /// What the tile does, for a screen reader. A glyph alone says nothing.
  final String? semanticLabel;

  /// Matches the [MadarButton] it stands beside.
  final MadarButtonSize size;

  @override
  Widget build(BuildContext context) {
    final compact = size == MadarButtonSize.compact;
    final side = compact ? _compactHeight : Metrics.buttonHeight;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: TactileScale(
        haptic: false,
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(compact ? Radii.sm : Radii.md),
          ),
          child: MadarIcon(icon, tint: tint, size: IconSize.lg),
        ),
      ),
    );
  }
}

// ── Text field ───────────────────────────────────────────────────────────

/// THE text field: rounded fill with an animated focus ring — accent border,
/// soft accent glow, `surfaceAlt` warming to `surface` — and a leading icon
/// that tints accent while focused.
///
/// The ring repaints off the [FocusNode] through a [ListenableBuilder], never
/// `setState`: focus changes on every keystroke's worth of caret work and
/// rebuilding the enclosing screen for a border colour is how a POS starts
/// dropping frames on a cheap tablet.
class MadarField extends StatefulWidget {
  /// Creates a field.
  const MadarField({
    required this.controller,
    required this.placeholder,
    this.icon,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.trailing,
    super.key,
  });

  /// Text being edited.
  final TextEditingController controller;

  /// Already-localized placeholder.
  final String placeholder;

  /// Optional leading [MadarIcon] name.
  final String? icon;

  /// Live edits.
  final ValueChanged<String>? onChanged;

  /// Keyboard "done"/"next".
  final ValueChanged<String>? onSubmitted;

  /// Greys the field and blocks editing when false.
  final bool enabled;

  /// Masks the text (a PIN, a password).
  final bool obscure;

  /// Focuses once the enclosing route's entrance animation settles. NEVER
  /// raw `autofocus: true` — see [EntranceFocus].
  final bool autofocus;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Lines; `null` grows without bound.
  final int? maxLines;

  /// Optional trailing affordance (a clear button, a unit).
  final Widget? trailing;

  @override
  State<MadarField> createState() => _MadarFieldState();
}

class _MadarFieldState extends State<MadarField>
    with EntranceFocus<MadarField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) focusAfterEntrance(_focus);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, _) {
        final focused = _focus.hasFocus && widget.enabled;
        return AnimatedContainer(
          duration: MotionSpec.standardDuration,
          curve: MotionSpec.standardCurve,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
            vertical: _fieldVPad,
          ),
          decoration: BoxDecoration(
            color: focused ? colors.surface : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: focused ? colors.accent : colors.border,
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: colors.accent.withValues(
                        alpha: Opacities.focusGlow,
                      ),
                      blurRadius: _fieldGlowBlur,
                    ),
                  ]
                : null,
          ),
          child: Row(
            spacing: _fieldGap,
            children: [
              if (widget.icon != null)
                MadarIcon(
                  widget.icon,
                  tint: focused ? colors.accent : colors.textMuted,
                  size: IconSize.lg,
                ),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    obscureText: widget.obscure,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    maxLines: widget.obscure ? 1 : widget.maxLines,
                    cursorColor: colors.accent,
                    style: MadarType.title.copyWith(
                      fontWeight: FontWeight.w400,
                      color: widget.enabled
                          ? colors.textPrimary
                          : colors.textMuted,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: widget.placeholder,
                      hintStyle: MadarType.title.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              ?widget.trailing,
            ],
          ),
        );
      },
    );
  }
}

/// THE amount field: a hero money input with the currency code set quietly
/// ahead of a large tabular figure.
class MadarAmountField extends StatefulWidget {
  /// Creates an amount field.
  const MadarAmountField({
    required this.amountMinor,
    required this.onAmountMinor,
    required this.currencyCode,
    this.autofocus = false,
    super.key,
  });

  /// Current value in minor units.
  final int amountMinor;

  /// Emitted on every edit, in minor units.
  final ValueChanged<int> onAmountMinor;

  /// ISO code shown ahead of the figure.
  final String currencyCode;

  /// Focuses once the route's entrance settles (never raw `autofocus`).
  final bool autofocus;

  @override
  State<MadarAmountField> createState() => _MadarAmountFieldState();
}

class _MadarAmountFieldState extends State<MadarAmountField>
    with EntranceFocus<MadarAmountField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.amountMinor == 0 ? '' : minorToText(widget.amountMinor),
  );
  final FocusNode _focus = FocusNode();
  late int _lastEmitted = widget.amountMinor;

  @override
  void initState() {
    super.initState();
    // Never raw `autofocus: true` — on iPad it races the route transition and
    // wedges the text-input connection, after which EVERY later tap on ANY
    // field does nothing.
    if (widget.autofocus) focusAfterEntrance(_focus);
  }

  @override
  void didUpdateWidget(MadarAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amountMinor != _lastEmitted) {
      _controller.text = widget.amountMinor == 0
          ? ''
          : minorToText(widget.amountMinor);
      _lastEmitted = widget.amountMinor;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String value) {
    final minor = textToMinor(value);
    _lastEmitted = minor;
    widget.onAmountMinor(minor);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, _) {
        final focused = _focus.hasFocus;
        return Container(
          height: Metrics.amountFieldHeight,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: focused ? colors.accent : colors.border,
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            spacing: Space.sm,
            children: [
              Text(
                widget.currencyCode.toUpperCase(),
                style: MadarType.title.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textMuted,
                ),
              ),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    onChanged: _changed,
                    cursorColor: colors.accent,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: MadarType.moneyLg.copyWith(
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: '0.00',
                      hintStyle: MadarType.moneyLg.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Typed major-unit text to minor units. Tolerates whatever a keyboard hands
/// over — grouping marks, a stray currency glyph — by keeping only digits and
/// the decimal point.
int textToMinor(String s) {
  final cleaned = String.fromCharCodes(
    s.codeUnits.where((u) => (u >= 0x30 && u <= 0x39) || u == 0x2E),
  );
  final major = double.tryParse(cleaned) ?? 0;
  return (major * 100).round();
}

/// Minor units to the editable major-unit text ("12.50", whole "12").
String minorToText(int minor) {
  if (minor % 100 == 0) return '${minor ~/ 100}';
  return (minor / 100).toStringAsFixed(2);
}

// ── Card, section header, hairline ───────────────────────────────────────

/// THE card: surface fill, hairline border, soft card elevation, [Radii.lg]
/// corners.
///
/// Takes either a single [child] or a stacked [children] list. Pass [flush]
/// for a zero-inset card whose children own their own padding — list rows and
/// table headers whose separators must reach the edge — which also clips them
/// to the corner radius so a row's fill cannot square off the card.
class MadarCard extends StatelessWidget {
  /// Creates a card around one [child].
  const MadarCard({
    required Widget this.child,
    this.padding,
    this.flush = false,
    this.clip = false,
    super.key,
  }) : children = null,
       spacing = 0;

  /// Creates a card around a stacked [children] list.
  const MadarCard.column({
    required List<Widget> this.children,
    this.spacing = Space.md,
    this.padding,
    this.flush = false,
    this.clip = false,
    super.key,
  }) : child = null;

  /// The single child, when built with the default constructor.
  final Widget? child;

  /// Stacked children, when built with [MadarCard.column].
  final List<Widget>? children;

  /// Gap between [children]. Ignored when [flush].
  final double spacing;

  /// Inset override. Defaults to [Space.lg], or zero when [flush].
  final EdgeInsetsGeometry? padding;

  /// Zero inset, zero spacing, clipped — the children own both.
  final bool flush;

  /// Clip the content to the corner radius (implied by [flush]).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final radius = BorderRadius.circular(Radii.lg);
    final list = children;
    var content = list == null
        ? child!
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: flush ? 0 : spacing,
            children: list,
          );
    final inset =
        padding ??
        (flush
            ? EdgeInsetsDirectional.zero
            : const EdgeInsetsDirectional.all(Space.lg));
    if (inset != EdgeInsetsDirectional.zero) {
      content = Padding(padding: inset, child: content);
    }
    if (flush || clip) {
      content = ClipRRect(borderRadius: radius, child: content);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: radius,
        border: Border.all(color: colors.borderLight),
        boxShadow: elevationShadows(context, MadarElevation.card),
      ),
      child: content,
    );
  }
}

/// THE section header: an accent tick (or a small accent glyph) ahead of an
/// uppercase, tracked label.
class MadarSectionHeader extends StatelessWidget {
  /// Creates a section header.
  const MadarSectionHeader({
    required this.text,
    this.icon,
    this.trailing,
    this.tick = true,
    super.key,
  });

  /// Label; uppercased for display.
  final String text;

  /// Optional [MadarIcon] name replacing the accent tick.
  final String? icon;

  /// Optional end-aligned affordance (a count, a "see all").
  final Widget? trailing;

  /// Draws the accent tick ahead of the label. Clear it for a label that
  /// merely names a block INSIDE a card — a tick there competes with the
  /// section header that already opened the page.
  final bool tick;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      spacing: Space.sm,
      children: [
        if (icon != null)
          MadarIcon(icon, tint: colors.accent, size: IconSize.xs)
        else if (tick)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: SizedBox.fromSize(size: _sectionTick),
          ),
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: MadarType.label.copyWith(
              color: colors.textSecondary,
              letterSpacing: MadarType.tracking,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// THE hairline: a one-pixel rule in the border tone.
class MadarHairline extends StatelessWidget {
  /// Creates a hairline.
  const MadarHairline({this.inset = 0, this.light = false, super.key});

  /// Start/end inset, for a rule that stops short of a card's edge.
  final double inset;

  /// The quieter `borderLight` tone — separating rows INSIDE a card, where
  /// the full border weight would out-shout the card's own edge.
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: inset),
      child: ColoredBox(
        color: light
            ? context.madarColors.borderLight
            : context.madarColors.border,
        child: const SizedBox(height: 1, width: double.infinity),
      ),
    );
  }
}
