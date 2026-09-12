/// THE shared control kit — system v2.
///
/// One button, one field, one card, one row, one chip, one segment, for the
/// whole app. Flat teal primary on a paper surface; an ink-tinted (sunk)
/// secondary; a filled danger. No gradients, no glows, no hairline-outline
/// buttons — the old kit had all three and they are gone. Four heights carry
/// everything: 44 for small things, 52–56 for the things you press all day,
/// 64 for a row or the money bar, 72 for the amount you are about to take.
///
/// Every string a control shows arrives ALREADY LOCALISED. Translation is
/// `bridge.tr`, which this package cannot see; nothing in here carries a
/// user-visible literal.
///
/// Compatibility. The old kit's names still compile — `MadarButtonVariant
/// .outline` draws the new secondary, `MadarButtonSize.compact` is the 44
/// small button, `MadarSectionHeader.tick` is accepted and ignored — so the
/// feature packages keep building while they migrate screen by screen.
///
/// A control that is genuinely one screen's own — a PIN pad, a floor-plan
/// table — still belongs to that feature. Only the things every screen needs
/// live here.
library;

import 'package:design_system/src/focus.dart';
import 'package:design_system/src/glyphs.dart';
import 'package:design_system/src/icons.dart';
import 'package:design_system/src/money.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/elevation.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/material.dart';

/// Loading spinner diameter / stroke.
const double _spinnerSize = 20;
const double _spinnerStroke = 2.5;

/// A field's edge at rest, and the focus ring's spread.
const double _fieldBorder = 1.5;
const double _focusRing = 3;

/// A segmented control's inner padding and its thumb's radius.
const double _segmentPad = 4;
const double _segmentThumbRadius = 9;

/// The state bar at the start of a row ("▌T5").
const double _rowBarWidth = 4;

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Shadow list for [level] resolved against the current theme.
List<BoxShadow> elevationShadows(BuildContext context, MadarElevation level) =>
    level.shadows(context.madarColors, dark: _isDark(context));

/// A colour role for a tag, a chip's count, a row's state bar.
enum MadarTone { neutral, accent, success, warning, danger }

extension MadarToneX on MadarTone {
  /// The solid colour.
  Color color(MadarColors c) => switch (this) {
    MadarTone.neutral => c.textSecondary,
    MadarTone.accent => c.accent,
    MadarTone.success => c.success,
    MadarTone.warning => c.warning,
    MadarTone.danger => c.danger,
  };

  /// The wash behind it.
  Color tint(MadarColors c) => switch (this) {
    MadarTone.neutral => c.surfaceAlt,
    MadarTone.accent => c.accentBg,
    MadarTone.success => c.successBg,
    MadarTone.warning => c.warningBg,
    MadarTone.danger => c.dangerBg,
  };
}

// ── Button ───────────────────────────────────────────────────────────────

/// Emphasis of a [MadarButton].
enum MadarButtonVariant {
  /// The one terminal action on the surface: flat teal. At most one per
  /// screen or sheet.
  primary,

  /// The alternative to the primary: the sunk grey with ink text. Quiet on
  /// purpose — two teal buttons side by side make the reader stop and choose,
  /// which is exactly what a secondary action must not do.
  secondary,

  /// Legacy name for [secondary]. The hairline outline it used to draw is
  /// gone; it renders the sunk fill.
  outline,

  /// A link-weight action: no fill, teal text. "Add tip", "Not now".
  ghost,

  /// Destructive confirm. Reads as loud as primary, on purpose.
  danger,

  /// An ink fill — the chrome's own button, for a dark surface (the done
  /// card's "New sale").
  ink,
}

/// Height of a [MadarButton].
/// The ink variant's fill. Light: the chrome's own ink, a dark button on
/// paper. Dark: the RAISED ink — the plain chrome is within a shade of the
/// dark page ground and a button painted in it disappears (the Till's
/// "Close shift" did).
Color _inkFill(BuildContext context, MadarColors colors) =>
    Theme.of(context).brightness == Brightness.dark
    ? colors.chromeRaised
    : colors.chromeAlt;

enum MadarButtonSize {
  /// 56 — every full-width action and every sheet's confirm.
  regular,

  /// 44 — a dense row where several buttons stand shoulder to shoulder (a
  /// card's Accept / Decline, a row's Retry / Discard).
  compact,
}

/// THE button. Flat fill, 12px corners, a 17-bold label, a tactile press
/// scale and an impact haptic; a spinner while [loading]; 40% when disabled.
///
/// Width adapts to the parent: it fills and ellipsizes when the parent bounds
/// it (a stretched Column, an `Expanded`) and shrink-wraps when it does not
/// (a bare child of a Row or a Wrap).
class MadarButton extends StatelessWidget {
  const MadarButton({
    required this.label,
    required this.onTap,
    this.variant = MadarButtonVariant.primary,
    this.size = MadarButtonSize.regular,
    this.glyph,
    this.icon,
    this.trailing,
    this.loading = false,
    this.enabled = true,
    this.tooltip,
    super.key,
  });

  /// Already-localized label. Empty for a glyph-only square.
  final String label;

  /// Tap handler; fires after the impact haptic.
  final VoidCallback onTap;

  final MadarButtonVariant variant;
  final MadarButtonSize size;

  /// Leading glyph from the v2 set.
  final MadarGlyph? glyph;

  /// Legacy leading icon by SF-Symbol name. Prefer [glyph].
  final String? icon;

  /// An end-aligned figure or glyph — a count, an amount.
  final Widget? trailing;

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

    final (Color? fill, Color fg) = switch (variant) {
      MadarButtonVariant.primary => (colors.accent, colors.textOnAccent),
      MadarButtonVariant.secondary ||
      MadarButtonVariant.outline => (colors.surfaceAlt, colors.textPrimary),
      MadarButtonVariant.ghost => (null, colors.accent),
      MadarButtonVariant.danger => (colors.danger, Colors.white),
      MadarButtonVariant.ink => (_inkFill(context, colors), Colors.white),
    };

    final labelStyle = (compact ? MadarType.buttonSm : MadarType.button)
        .copyWith(color: fg);
    final glyphSize = compact ? IconSize.md : IconSize.lg;
    final hPad = variant == MadarButtonVariant.ghost
        ? Space.md
        : (compact ? Space.lg : 22.0);

    Widget button = Container(
      height: compact ? Metrics.buttonSmallHeight : Metrics.buttonHeight,
      constraints: BoxConstraints(
        minWidth: compact ? Metrics.buttonSmallHeight : Metrics.buttonHeight,
      ),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: label.isEmpty ? 0 : hPad,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(compact ? Radii.sm : Radii.control),
      ),
      // NO `alignment:` here. A Container with an alignment wraps its child
      // in an Align, which EXPANDS to fill loose constraints — which turned a
      // toolbar of four compact buttons into four full-width bars stacked
      // down the page. The Row below does the centring instead.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // TIGHT, not merely bounded. A button fills its line only when the
          // parent actually dictates the width — `Expanded`, a stretched
          // Column, a `SizedBox(width:)`. A `Wrap` or a bare `Row` child
          // hands down LOOSE constraints, and filling those turns a row of
          // buttons into a stack of bars.
          final fillLine = constraints.hasTightWidth;
          // Ellipsis needs a bound; a `Flexible` under an UNBOUNDED width is
          // illegal and its assertion blanks the whole subtree.
          final bounded = constraints.hasBoundedWidth;
          if (loading) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: fillLine ? MainAxisSize.max : MainAxisSize.min,
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
          final text = Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          );
          return Row(
            mainAxisAlignment: trailing == null
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            mainAxisSize: fillLine ? MainAxisSize.max : MainAxisSize.min,
            spacing: compact ? Space.sm : 10,
            children: [
              if (glyph != null)
                MadarGlyphIcon(glyph!, size: glyphSize, color: fg)
              else if (icon != null)
                MadarIcon(icon, tint: fg, size: glyphSize),
              if (label.isNotEmpty)
                if (bounded) Flexible(child: text) else text,
              if (trailing != null)
                DefaultTextStyle.merge(
                  style: labelStyle,
                  child: IconTheme.merge(
                    data: IconThemeData(color: fg),
                    child: trailing!,
                  ),
                ),
            ],
          );
        },
      ),
    );

    if (!active) {
      button = Opacity(opacity: Opacities.disabled, child: button);
    } else {
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

/// THE money bar — the 64px primary that carries an amount: *Charge ·
/// EGP 196.00*, *Record · 60.00*. The verb sits at the start, the figure at
/// the end in Plex Mono, an LTR island in both scripts.
///
/// The one control on a screen that is allowed to be taller than a button,
/// because it is the one that takes money. When [enabled] is false pass
/// [reason] — "Open the shift first" — and it is shown in place of the
/// figure, which is the only honest way to disable it.
class MadarMoneyBar extends StatelessWidget {
  const MadarMoneyBar({
    required this.label,
    required this.amountMinor,
    required this.onTap,
    this.currency = '',
    this.enabled = true,
    this.loading = false,
    this.reason,
    this.variant = MadarButtonVariant.primary,
    super.key,
  });

  final String label;
  final int amountMinor;
  final VoidCallback onTap;

  /// ISO code shown before the figure; empty hides it.
  final String currency;
  final bool enabled;
  final bool loading;

  /// Why the bar is disabled, already localised. Shown instead of the figure.
  final String? reason;

  /// [MadarButtonVariant.primary] or [MadarButtonVariant.danger] (a refund).
  final MadarButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final active = enabled && !loading;
    final (Color fill, Color fg) = switch (variant) {
      MadarButtonVariant.danger => (colors.danger, Colors.white),
      MadarButtonVariant.ink => (_inkFill(context, colors), Colors.white),
      MadarButtonVariant.secondary ||
      MadarButtonVariant.outline => (colors.surfaceAlt, colors.textPrimary),
      _ => (colors.accent, colors.textOnAccent),
    };
    final showReason = !enabled && reason != null;

    Widget bar = Container(
      height: Metrics.moneyBarHeight,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.xl),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Same rule as the button: fill a dictated width, shrink-wrap a
          // loose one, and never put a Flexible under an unbounded one.
          final bounded = constraints.hasBoundedWidth;
          final text = Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.button.copyWith(fontSize: 18, color: fg),
          );
          return Row(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            spacing: Space.lg,
            children: [
              if (bounded) Expanded(child: text) else text,
              if (loading)
                SizedBox.square(
                  dimension: _spinnerSize,
                  child: CircularProgressIndicator(
                    color: fg,
                    strokeWidth: _spinnerStroke,
                  ),
                )
              else if (showReason)
                Flexible(
                  child: Text(
                    reason!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(color: fg),
                  ),
                )
              else
                MoneyText(
                  amountMinor,
                  currency: currency,
                  style: MadarType.moneyMd,
                  color: fg,
                ),
            ],
          );
        },
      ),
    );
    if (!active) {
      bar = Opacity(opacity: Opacities.disabled, child: bar);
    } else {
      bar = TactileScale(
        haptic: false,
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: bar,
      );
    }
    return Semantics(button: true, enabled: active, child: bar);
  }
}

/// A square glyph tile — a verb with no room for a word: the header's back
/// tile, a row's ⋯, a field's clear. 44 square on the sunk grey; 56 beside
/// a regular button so the pair lines up.
class MadarGlyphTile extends StatelessWidget {
  const MadarGlyphTile({
    required this.onTap,
    this.glyph,
    this.icon,
    this.tint,
    this.background,
    this.semanticLabel,
    this.size = MadarButtonSize.compact,
    this.enabled = true,
    super.key,
  }) : assert(glyph != null || icon != null, 'a tile needs a glyph');

  /// The v2 glyph.
  final MadarGlyph? glyph;

  /// Legacy SF-Symbol name. Prefer [glyph].
  final String? icon;

  /// Tap handler; fires after the impact haptic.
  final VoidCallback onTap;

  /// Glyph colour. Defaults to the primary text.
  final Color? tint;

  /// Tile fill. Defaults to the sunk grey.
  final Color? background;

  /// What the tile does, for a screen reader. A glyph alone says nothing.
  final String? semanticLabel;

  /// [MadarButtonSize.compact] is 44; [MadarButtonSize.regular] is 56.
  final MadarButtonSize size;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final compact = size == MadarButtonSize.compact;
    final side = compact ? Metrics.glyphTile : Metrics.glyphTileLarge;
    final fg = tint ?? colors.textPrimary;
    Widget tile = Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? colors.surfaceAlt,
        borderRadius: BorderRadius.circular(compact ? Radii.sm : Radii.control),
      ),
      child: glyph != null
          ? MadarGlyphIcon(glyph!, size: IconSize.xl, color: fg)
          : MadarIcon(icon, tint: fg, size: IconSize.xl),
    );
    if (!enabled) {
      tile = Opacity(opacity: Opacities.disabled, child: tile);
    } else {
      tile = TactileScale(
        haptic: false,
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: tile,
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: tile,
    );
  }
}

// ── Text field ───────────────────────────────────────────────────────────

/// THE text field: 52 tall on the surface with a 1.5px edge; focused, the
/// edge turns teal and a 3px teal-wash ring sits outside it. A leading
/// glyph tints teal while focused.
///
/// The ring repaints off the [FocusNode] through a [ListenableBuilder], never
/// `setState`: focus changes on every keystroke's worth of caret work and
/// rebuilding the enclosing screen for a border colour is how a POS starts
/// dropping frames on a cheap tablet.
class MadarField extends StatefulWidget {
  const MadarField({
    required this.controller,
    required this.placeholder,
    this.glyph,
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
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;

  /// Already-localized placeholder.
  final String placeholder;

  /// Leading v2 glyph.
  final MadarGlyph? glyph;

  /// Legacy leading icon by SF-Symbol name. Prefer [glyph].
  final String? icon;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  /// Masks the text (a PIN, a password).
  final bool obscure;

  /// Focuses once the enclosing route's entrance animation settles. NEVER
  /// raw `autofocus: true` — see [EntranceFocus].
  final bool autofocus;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  /// Lines; `null` grows without bound. A multi-line field grows past 52.
  final int? maxLines;

  /// Optional trailing affordance (a clear button, a unit).
  final Widget? trailing;

  /// An external focus node, for a screen that moves focus itself.
  final FocusNode? focusNode;

  @override
  State<MadarField> createState() => _MadarFieldState();
}

class _MadarFieldState extends State<MadarField>
    with EntranceFocus<MadarField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) focusAfterEntrance(_focus);
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final single = widget.obscure || widget.maxLines == 1;
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, _) {
        final focused = _focus.hasFocus && widget.enabled;
        final textStyle = MadarType.title.copyWith(
          fontWeight: FontWeight.w500,
          color: widget.enabled ? colors.textPrimary : colors.textMuted,
        );
        return AnimatedContainer(
          duration: MotionSpec.standardDuration,
          curve: MotionSpec.standardCurve,
          constraints: BoxConstraints(
            minHeight: Metrics.inputHeight,
            maxHeight: single ? Metrics.inputHeight : double.infinity,
          ),
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
            vertical: single ? 0 : Space.md,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
              color: focused ? colors.accent : colors.border,
              width: _fieldBorder,
            ),
            // A hard ring, not a glow: zero blur, a 3px spread of the wash.
            boxShadow: focused
                ? [BoxShadow(color: colors.accentBg, spreadRadius: _focusRing)]
                : null,
          ),
          child: Row(
            crossAxisAlignment: single
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              if (widget.glyph != null)
                MadarGlyphIcon(
                  widget.glyph!,
                  color: focused ? colors.accent : colors.textMuted,
                )
              else if (widget.icon != null)
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
                    maxLines: single ? 1 : widget.maxLines,
                    cursorColor: colors.accent,
                    style: textStyle,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.placeholder,
                      hintStyle: textStyle.copyWith(color: colors.textMuted),
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

/// THE amount field: 72 tall, the currency code set quietly ahead of a large
/// tabular figure. Same edge and ring as [MadarField].
class MadarAmountField extends StatefulWidget {
  const MadarAmountField({
    required this.amountMinor,
    required this.onAmountMinor,
    required this.currencyCode,
    this.autofocus = false,
    this.onSubmitted,
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

  /// The keyboard's done key.
  final ValueChanged<int>? onSubmitted;

  @override
  State<MadarAmountField> createState() => _MadarAmountFieldState();
}

class _MadarAmountFieldState extends State<MadarAmountField>
    with EntranceFocus<MadarAmountField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.amountMinor == 0 ? '' : minorToText(widget.amountMinor),
  );
  final FocusNode _focus = FocusNode();

  /// The last amount this field and its owner agreed on. Set in initState,
  /// never lazily: a `late` initialiser here is first evaluated inside
  /// didUpdateWidget, where `widget` is already the NEW widget, so a value
  /// that arrives after mount (the open-shift carry-over) compares equal to
  /// itself and never reaches the text.
  late int _lastEmitted;

  @override
  void initState() {
    super.initState();
    _lastEmitted = widget.amountMinor;
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
        return AnimatedContainer(
          duration: MotionSpec.standardDuration,
          curve: MotionSpec.standardCurve,
          height: Metrics.amountFieldHeight,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.card,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? colors.accent : colors.border,
              width: _fieldBorder,
            ),
            boxShadow: focused
                ? [BoxShadow(color: colors.accentBg, spreadRadius: _focusRing)]
                : null,
          ),
          child: Row(
            spacing: Space.md,
            children: [
              Text(
                widget.currencyCode.toUpperCase(),
                style: MadarType.title.copyWith(color: colors.textMuted),
              ),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    onChanged: _changed,
                    onSubmitted: (v) =>
                        widget.onSubmitted?.call(textToMinor(v)),
                    cursorColor: colors.accent,
                    // Figures are LTR islands, whatever the script around them.
                    textDirection: TextDirection.ltr,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: MadarType.moneyDisplay.copyWith(
                      fontSize: 28,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: '0.00',
                      hintStyle: MadarType.moneyDisplay.copyWith(
                        fontSize: 28,
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

// ── Card, row, section header, hairline ──────────────────────────────────

/// THE card: surface fill, a 1px light edge, 16px corners, a 20px inset. No
/// shadow — the edge does the work.
///
/// Takes either a single [child] or a stacked [children] list. Pass [flush]
/// for a zero-inset card whose children own their own padding — a list of
/// [MadarRow]s whose hairlines must reach the edge — which also clips them to
/// the corner radius so a row's fill cannot square off the card.
class MadarCard extends StatelessWidget {
  const MadarCard({
    required Widget this.child,
    this.padding,
    this.flush = false,
    this.clip = false,
    this.onTap,
    this.selected = false,
    super.key,
  }) : children = null,
       spacing = 0;

  const MadarCard.column({
    required List<Widget> this.children,
    this.spacing = Space.md,
    this.padding,
    this.flush = false,
    this.clip = false,
    this.onTap,
    this.selected = false,
    super.key,
  }) : child = null;

  final Widget? child;
  final List<Widget>? children;

  /// Gap between [children]. Ignored when [flush].
  final double spacing;

  /// Inset override. Defaults to [Space.card], or zero when [flush].
  final EdgeInsetsGeometry? padding;

  /// Zero inset, zero spacing, clipped — the children own both.
  final bool flush;

  /// Clip the content to the corner radius (implied by [flush]).
  final bool clip;

  /// Makes the whole card a press target (a queue card, a menu tile).
  final VoidCallback? onTap;

  /// A 2px teal edge — the tile that is in the cart, the method that is
  /// chosen.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final radius = BorderRadius.circular(Radii.card);
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
            : const EdgeInsetsDirectional.all(Space.card));
    if (inset != EdgeInsetsDirectional.zero) {
      content = Padding(padding: inset, child: content);
    }
    if (flush || clip) {
      content = ClipRRect(borderRadius: radius, child: content);
    }
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: radius,
        border: Border.all(
          color: selected ? colors.accent : colors.borderLight,
          width: selected ? 2 : 1,
        ),
      ),
      child: content,
    );
    if (onTap != null) {
      card = TactileScale(onTap: onTap, child: card);
    }
    return card;
  }
}

/// THE row: 64 tall, a title with an optional second line, an optional
/// leading glyph or state bar, an optional trailing figure and a disclosure
/// chevron when it goes somewhere. Rows stack inside a flush [MadarCard]
/// with a [MadarHairline] between them.
///
/// The [bar] is the 4px stripe at the start edge that carries a table's or
/// a bill's state ("▌T5") — the row's colour lives there and nowhere else,
/// so a list of twenty rows is not twenty tinted cards.
class MadarRow extends StatelessWidget {
  const MadarRow({
    required this.title,
    this.subtitle,
    this.glyph,
    this.leading,
    this.bar,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron,
    this.dense = false,
    this.titleStyle,
    super.key,
  });

  /// Already-localised. Ellipsised on one line.
  final String title;

  /// Meta under the title — who, when, how much.
  final String? subtitle;

  /// A leading glyph in the secondary text colour.
  final MadarGlyph? glyph;

  /// Any leading widget (an avatar, a count disc) when a glyph is not it.
  final Widget? leading;

  /// The state stripe's colour. `null` draws none.
  final Color? bar;

  /// A figure at the end — an amount, a time — set as given. Use [MoneyText]
  /// for money.
  final Widget? value;

  /// Anything else at the end (a chip, a small button). After [value].
  final Widget? trailing;

  /// Makes the row a press target. A tappable row shows a chevron unless
  /// [chevron] says otherwise.
  final VoidCallback? onTap;

  /// Force the disclosure chevron on or off.
  final bool? chevron;

  /// 56 tall instead of 64 — a settings list, a receipt's lines.
  final bool dense;

  /// Override the title style (a mono ref, a struck-through voided line).
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final showChevron = chevron ?? onTap != null;
    Widget row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: dense ? Metrics.tableRowHeight : Metrics.rowHeight,
      ),
      child: Row(
        children: [
          // The stripe itself is painted by the Stack below so it spans the
          // row's full height without an IntrinsicHeight — which a row
          // holding a MadarButton (a LayoutBuilder) cannot answer.
          SizedBox(width: bar != null ? Space.lg : Space.card),
          if (glyph != null) ...[
            MadarGlyphIcon(
              glyph!,
              size: IconSize.xl,
              color: colors.textSecondary,
            ),
            const SizedBox(width: Space.lg),
          ] else if (leading != null) ...[
            leading!,
            const SizedBox(width: Space.lg),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                vertical: Space.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        titleStyle ??
                        MadarType.title.copyWith(color: colors.textPrimary),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: Space.lg),
            DefaultTextStyle.merge(
              style: MadarType.money.copyWith(color: colors.textPrimary),
              child: value!,
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: Space.lg), trailing!],
          if (showChevron) ...[
            const SizedBox(width: Space.md),
            MadarGlyphIcon(
              MadarGlyph.chevronForward,
              size: IconSize.md,
              color: colors.textMuted,
            ),
          ],
          const SizedBox(width: Space.card),
        ],
      ),
    );
    if (bar != null) {
      row = Stack(
        children: [
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: _rowBarWidth,
              child: ColoredBox(color: bar!),
            ),
          ),
          row,
        ],
      );
    }
    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          MadarHaptics.selection();
          onTap!();
        },
        child: row,
      ),
    );
  }
}

/// THE section header: a 12-bold tracked uppercase label in the secondary
/// colour, with an optional end-aligned affordance.
class MadarSectionHeader extends StatelessWidget {
  const MadarSectionHeader({
    required this.text,
    this.icon,
    this.glyph,
    this.trailing,
    this.tick = true,
    super.key,
  });

  /// Label; uppercased for display.
  final String text;

  /// Legacy SF-Symbol glyph ahead of the label.
  final String? icon;

  /// A small glyph ahead of the label.
  final MadarGlyph? glyph;

  /// Optional end-aligned affordance (a count, a "see all").
  final Widget? trailing;

  /// Accepted for compatibility; the v2 header draws no tick.
  final bool tick;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return SizedBox(
      height: 20,
      child: Row(
        spacing: 10,
        children: [
          if (glyph != null)
            MadarGlyphIcon(
              glyph!,
              size: IconSize.xs,
              color: colors.textSecondary,
            )
          else if (icon != null)
            MadarIcon(icon, tint: colors.textSecondary, size: IconSize.xs),
          Expanded(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.label.copyWith(
                color: colors.textSecondary,
                letterSpacing: MadarType.tracking,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// THE hairline: a one-pixel rule. [MadarHairline.row] is the light one
/// between rows inside a card; the default is the full border weight between
/// blocks on the paper.
class MadarHairline extends StatelessWidget {
  const MadarHairline({this.inset = 0, this.light = false, super.key});

  /// The light rule between two [MadarRow]s in a flush card.
  const MadarHairline.row({this.inset = 0, super.key}) : light = true;

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

// ── Chip, segment, tag, stepper ──────────────────────────────────────────

/// THE chip: a 44 pill on the sunk grey; on, it fills with ink. A category,
/// a filter, a reason. [MadarChip.tile] is the squarer 52 version that
/// carries a figure — a party size, a minute count — and fills TEAL when on,
/// because choosing a number is choosing, not filtering.
class MadarChip extends StatelessWidget {
  const MadarChip({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.glyph,
    this.count,
    this.enabled = true,
    super.key,
  }) : _tile = false;

  const MadarChip.tile({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    super.key,
  }) : glyph = null,
       count = null,
       _tile = true;

  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// Leading glyph (a bag on "Parked").
  final MadarGlyph? glyph;

  /// A trailing figure, mono ("Parked 2").
  final int? count;
  final bool enabled;
  final bool _tile;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final (Color fill, Color fg) = _tile
        ? (
            selected ? colors.accent : colors.surfaceAlt,
            selected ? colors.textOnAccent : colors.textSecondary,
          )
        : (
            selected ? _inkFill(context, colors) : colors.surfaceAlt,
            selected ? Colors.white : colors.textSecondary,
          );
    final style = _tile
        ? MadarType.numLg.copyWith(fontSize: 17, color: fg)
        : MadarType.buttonSm.copyWith(color: fg);

    Widget chip = AnimatedContainer(
      duration: MotionSpec.standardDuration,
      curve: MotionSpec.standardCurve,
      height: _tile ? Metrics.chipTileHeight : Metrics.chipHeight,
      constraints: BoxConstraints(
        minWidth: _tile ? Metrics.chipTileMinWidth : 0,
      ),
      padding: EdgeInsetsDirectional.symmetric(horizontal: _tile ? 14 : 18),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(_tile ? Radii.control : Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: Space.sm,
        children: [
          if (glyph != null)
            MadarGlyphIcon(glyph!, size: IconSize.md, color: fg),
          Text(label, maxLines: 1, style: style),
          if (count != null)
            Text(
              '$count',
              textDirection: TextDirection.ltr,
              style: MadarType.numMd.copyWith(color: fg),
            ),
        ],
      ),
    );
    if (!enabled) {
      chip = Opacity(opacity: Opacities.disabled, child: chip);
    } else {
      chip = TactileScale(onTap: onTap, child: chip);
    }
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: chip,
    );
  }
}

/// One option in a [MadarSegmented].
@immutable
class MadarSegmentItem<T> {
  const MadarSegmentItem(this.value, this.label, {this.count, this.glyph});

  final T value;
  final String label;

  /// A count in the label ("Bills 3"), mono.
  final int? count;
  final MadarGlyph? glyph;
}

/// THE segmented control: a 48 sunk track holding equal cells; the chosen
/// one is a white thumb with a 1px lift. Plan / List; Bills / Online /
/// Kitchen. The whole thing is one widget so every screen's segment has the
/// same cell width rule: equal, filling the track.
class MadarSegmented<T> extends StatelessWidget {
  const MadarSegmented({
    required this.items,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<MadarSegmentItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      height: Metrics.segmentHeight,
      padding: const EdgeInsets.all(_segmentPad),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _SegmentCell<T>(
                item: item,
                on: item.value == value,
                onTap: () {
                  if (item.value == value) return;
                  MadarHaptics.selection();
                  onChanged(item.value);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentCell<T> extends StatelessWidget {
  const _SegmentCell({
    required this.item,
    required this.on,
    required this.onTap,
  });

  final MadarSegmentItem<T> item;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = on ? colors.textPrimary : colors.textSecondary;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: MotionSpec.standardDuration,
          curve: MotionSpec.standardCurve,
          decoration: BoxDecoration(
            color: on ? colors.surface : null,
            borderRadius: BorderRadius.circular(_segmentThumbRadius),
            boxShadow: on
                ? elevationShadows(context, MadarElevation.thumb)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: Space.sm,
            children: [
              if (item.glyph != null)
                MadarGlyphIcon(item.glyph!, size: IconSize.md, color: fg),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.buttonSm.copyWith(color: fg),
                ),
              ),
              if (item.count != null)
                Text(
                  '${item.count}',
                  textDirection: TextDirection.ltr,
                  style: MadarType.numMd.copyWith(color: fg),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// THE tag: a 26px uppercase state word on its tone's wash — NEW, READY,
/// QUEUED, VOIDED — with an optional glyph. It names a state; it is not
/// pressed.
class MadarTag extends StatelessWidget {
  const MadarTag({
    required this.label,
    this.tone = MadarTone.neutral,
    this.glyph,
    super.key,
  });

  final String label;
  final MadarTone tone;
  final MadarGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = tone.color(colors);
    return Container(
      height: Metrics.tagHeight,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tone.tint(colors),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (glyph != null)
            MadarGlyphIcon(glyph!, size: IconSize.xs, color: fg),
          Text(
            label.toUpperCase(),
            style: MadarType.label.copyWith(color: fg, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}

/// THE stepper: − figure + on a 40 sunk track. A line's quantity.
class MadarStepper extends StatelessWidget {
  const MadarStepper({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.decrementLabel,
    this.incrementLabel,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int? max;

  /// Screen-reader labels for the two keys, already localised.
  final String? decrementLabel;
  final String? incrementLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final canDown = value > min;
    final canUp = max == null || value < max!;
    Widget key(
      MadarGlyph glyph, {
      required bool enabled,
      required VoidCallback onTap,
      String? label,
    }) {
      return Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  MadarHaptics.selection();
                  onTap();
                }
              : null,
          child: SizedBox.square(
            dimension: Metrics.stepper,
            child: Center(
              child: MadarGlyphIcon(
                glyph,
                size: IconSize.md,
                color: enabled ? colors.textPrimary : colors.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: Metrics.stepper,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          key(
            MadarGlyph.minus,
            enabled: canDown,
            onTap: () => onChanged(value - 1),
            label: decrementLabel,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: MadarType.numLg.copyWith(color: colors.textPrimary),
            ),
          ),
          key(
            MadarGlyph.plus,
            enabled: canUp,
            onTap: () => onChanged(value + 1),
            label: incrementLabel,
          ),
        ],
      ),
    );
  }
}
