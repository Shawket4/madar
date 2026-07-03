/// Shift-feature control kit — the Flutter mirror of the natives' shared
/// components used by the shift screens (Components.kt / SharedComponents.kt:
/// MadarButton, MadarTextField, AmountField, MadarCard, SectionHeader).
/// Tokens-only, plus a few native component metrics that fall between the
/// 4-pt Space steps, kept verbatim (the design system's banners.dart pattern)
/// so the Flutter chrome measures identically to the Kotlin/Swift natives.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Primary-CTA top-lit gradient: a hint of white at the top edge so the
/// filled button reads lifted rather than flat (natives: lerp(accent, white, 0.16)).
const double _ctaTopLight = 0.16;

/// Button label letter-spacing (natives: 0.2.sp).
const double _buttonTracking = 0.2;

/// Button loading spinner diameter / stroke (natives: 20.dp / 2.5.dp).
const double _spinnerSize = 20;
const double _spinnerStroke = 2.5;

/// Outline button border width (natives: 1.5.dp).
const double _outlineBorder = 1.5;

/// Text-field vertical inset (natives: 16.dp) and icon↔text gap (10.dp).
const double _fieldVPad = 16;
const double _fieldGap = 10;

/// Focus glow blur on text fields (natives: shadow(8.dp, accent)).
const double _fieldGlowBlur = 8;

/// Section-header accent capsule (natives: 3×12dp).
const Size _sectionTick = Size(3, 12);

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Button variants — the natives' `BtnVariant`.
enum ShiftButtonVariant { primary, outline, ghost, danger }

/// The natives' `MadarButton`: flat rounded CTA on the shared press-scale,
/// with a top-lit gradient + accent glow on the primary variant and a
/// centered spinner while [loading].
class ShiftButton extends StatelessWidget {
  const ShiftButton({
    required this.label,
    required this.onTap,
    this.variant = ShiftButtonVariant.primary,
    this.loading = false,
    this.enabled = true,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final ShiftButtonVariant variant;
  final bool loading;
  final bool enabled;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final active = enabled && !loading;
    final fg = switch (variant) {
      ShiftButtonVariant.primary => colors.textOnAccent,
      ShiftButtonVariant.danger => colors.textOnAccent,
      ShiftButtonVariant.outline => colors.accent,
      ShiftButtonVariant.ghost => colors.textSecondary,
    };
    final gradient = variant == ShiftButtonVariant.primary && active
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
      ShiftButtonVariant.primary =>
        active ? null : colors.accent.withValues(alpha: Opacities.disabled),
      ShiftButtonVariant.danger =>
        active
            ? colors.danger
            : colors.danger.withValues(alpha: Opacities.disabled),
      ShiftButtonVariant.outline || ShiftButtonVariant.ghost => null,
    };

    final button = Container(
      height: Metrics.buttonHeight,
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(Radii.md),
        border: variant == ShiftButtonVariant.outline
            ? Border.all(color: colors.accent, width: _outlineBorder)
            : null,
        boxShadow: variant == ShiftButtonVariant.primary && active
            ? MadarElevation.glow.shadows(colors, dark: _isDark(context))
            : null,
      ),
      alignment: Alignment.center,
      child: loading
          ? SizedBox.square(
              dimension: _spinnerSize,
              child: CircularProgressIndicator(
                color: fg,
                strokeWidth: _spinnerStroke,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  MadarIcon(icon, tint: fg),
                  const SizedBox(width: Space.sm),
                ],
                Text(
                  label,
                  style: MadarType.title.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: _buttonTracking,
                    color: fg,
                  ),
                ),
              ],
            ),
    );

    if (!active) return button;
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: button,
      ),
    );
  }
}

/// The natives' `MadarCard`: bordered, softly-elevated surface container
/// with a spaced column of [children].
class ShiftCard extends StatelessWidget {
  const ShiftCard({required this.children, this.spacing = Space.md, super.key});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(colors, dark: _isDark(context)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: spacing,
          children: children,
        ),
      ),
    );
  }
}

/// The natives' `SectionHeader`: uppercase muted label with a signature
/// accent tick (or a leading accent icon when [icon] is given).
class ShiftSectionHeader extends StatelessWidget {
  const ShiftSectionHeader({required this.text, this.icon, super.key});

  final String text;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      spacing: Space.sm,
      children: [
        if (icon != null)
          MadarIcon(icon, tint: colors.accent, size: IconSize.xs)
        else
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
      ],
    );
  }
}

/// The natives' `MadarTextField`: rounded field with an animated focus ring
/// (accent border + soft glow, surfaceAlt → surface fill) and an optional
/// leading icon that tints accent while focused.
class ShiftTextField extends StatefulWidget {
  const ShiftTextField({
    required this.controller,
    required this.placeholder,
    this.icon,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;
  final String? icon;

  @override
  State<ShiftTextField> createState() => _ShiftTextFieldState();
}

class _ShiftTextFieldState extends State<ShiftTextField> {
  /// Widget-local ephemera — the focus ring repaints through a
  /// [ListenableBuilder] on the node, never setState.
  final FocusNode _focus = FocusNode();

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
        final focused = _focus.hasFocus;
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
                    cursorColor: colors.accent,
                    style: MadarType.title.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colors.textPrimary,
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
            ],
          ),
        );
      },
    );
  }
}

/// The natives' `AmountField`: one contained hero row — a muted currency
/// prefix, then the big tabular amount at [Metrics.amountFieldHeight].
/// External prefills (the carried-over suggestion arriving async) update the
/// text only when they differ from the last value the teller emitted, so the
/// count is never clobbered mid-typing.
class AmountField extends StatefulWidget {
  const AmountField({
    required this.amountMinor,
    required this.onAmountMinor,
    required this.currencyCode,
    this.autofocus = false,
    super.key,
  });

  final int amountMinor;
  final ValueChanged<int> onAmountMinor;
  final String currencyCode;
  final bool autofocus;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField>
    with EntranceFocus<AmountField> {
  /// Widget-local ephemera — the focus border repaints through a
  /// [ListenableBuilder] on the node, never setState.
  late final TextEditingController _controller = TextEditingController(
    text: widget.amountMinor == 0 ? '' : _minorToText(widget.amountMinor),
  );
  final FocusNode _focus = FocusNode();
  late int _lastEmitted = widget.amountMinor;

  @override
  void initState() {
    super.initState();
    // Never raw `autofocus: true` — on iPad it races the route transition and
    // wedges the text-input connection. Focus once the entrance settles.
    if (widget.autofocus) focusAfterEntrance(_focus);
  }

  @override
  void didUpdateWidget(AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amountMinor != _lastEmitted) {
      _controller.text = widget.amountMinor == 0
          ? ''
          : _minorToText(widget.amountMinor);
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
    final minor = _toMinor(value);
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
                    // Focus is driven by focusAfterEntrance, never autofocus.
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

/// Parse a major-unit decimal string ("500", "499.50") → minor units.
int _toMinor(String s) {
  final cleaned = String.fromCharCodes(
    s.codeUnits.where((u) => (u >= 0x30 && u <= 0x39) || u == 0x2E),
  );
  final major = double.tryParse(cleaned) ?? 0;
  return (major * 100).round();
}

/// Minor units → the editable major-unit text ("12.50", whole "12").
String _minorToText(int minor) {
  if (minor % 100 == 0) return '${minor ~/ 100}';
  return (minor / 100).toStringAsFixed(2);
}

/// A zero-inset [ShiftCard]: same surface / hairline border / soft
/// elevation, but flush children (the natives' `MadarCard(padding = 0,
/// spacing = 0)`) so list rows and table headers own their insets and
/// separators.
class ShiftFlushCard extends StatelessWidget {
  /// Creates the flush card.
  const ShiftFlushCard({required this.children, super.key});

  /// Flush rows, top to bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(colors, dark: _isDark(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// 1-px hairline separator — [light] picks borderLight over border.
class ShiftHairline extends StatelessWidget {
  /// Creates the hairline.
  const ShiftHairline({this.light = true, super.key});

  /// Whether to use the lighter in-card rule color.
  final bool light;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return SizedBox(
      height: 1,
      child: ColoredBox(color: light ? colors.borderLight : colors.border),
    );
  }
}
