/// Auth-flow form controls — verbatim ports of the Kotlin natives'
/// `Components.kt` (MadarButton / MadarTextField / PinPad) and
/// `SharedComponents.kt` (MadarCard / SectionHeader). The design_system
/// package ships tokens + chrome only, so these feature-local controls live
/// here. NOT exported from the feature_auth barrel.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// ── Native-verbatim metrics (Components.kt literals that fall between the
// 4-pt Space steps — kept exact so the port measures identically) ────────────

/// Icon↔label gap inside a text field (natives: 10.dp).
const double _fieldGap = 10;

/// Text-field vertical inset (natives: 16.dp).
const double _fieldVPad = 16;

/// Focus-ring glow blur (natives: 8.dp shadow elevation).
const double _fieldGlowBlur = 8;

/// Focused border width (natives: 2.dp; resting 1.dp).
const double _fieldFocusBorder = 2;

/// Button loading-spinner diameter / stroke (natives: 20.dp / 2.5.dp).
const double _spinnerSize = 20;
const double _spinnerStroke = 2.5;

/// Primary CTA top-lit gradient: lerp(accent → white, 0.16) at the top edge
/// (natives' "glossy" fill). White is the literal highlight the natives lerp
/// toward, not a theme role.
const double _gradientLerp = 0.16;
const Color _gradientHighlight = Color(0xFFFFFFFF);

/// PIN key gutter within a row (natives: 14.dp).
const double _keyGap = 14;

/// PIN key border width (natives: 1.5.dp).
const double _keyBorder = 1.5;

/// PIN key glyph size — digit text and the delete icon (natives: 22.sp/dp).
const double _keyGlyph = 22;

/// PIN dot diameters — empty / filled (natives: 12.dp → 14.dp spring).
const double _dotEmpty = 12;
const double _dotFilled = 14;

/// PIN dot border width (natives: 2.dp).
const double _dotBorder = 2;

/// Filled PIN dot accent-glow blur (natives: 6.dp shadow).
const double _dotGlowBlur = 6;

/// SectionHeader accent capsule (natives: 3×12.dp).
const Size _headerTick = Size(3, 12);

/// Resolve a [MadarElevation] level against the ambient theme.
List<BoxShadow> elevationShadows(BuildContext context, MadarElevation level) {
  return level.shadows(
    context.madarColors,
    dark: Theme.of(context).brightness == Brightness.dark,
  );
}

/// Button emphasis — the subset of the natives' `BtnVariant` the auth
/// screens use.
enum AuthButtonVariant {
  /// Accent-filled, top-lit gradient + glow — the screen's single CTA.
  primary,

  /// Transparent, secondary-text label — recessive exits (cancel, sign out).
  ghost,
}

/// The natives' `MadarButton`: flat rounded CTA with an optional leading
/// icon, a loading spinner state, tactile press-scale, and an impact haptic.
class MadarButton extends StatelessWidget {
  /// Creates an auth CTA button.
  const MadarButton({
    required this.label,
    required this.onPressed,
    this.variant = AuthButtonVariant.primary,
    this.loading = false,
    this.enabled = true,
    this.height = Metrics.buttonHeight,
    this.icon,
    super.key,
  });

  /// Button label (already localized).
  final String label;

  /// Tap handler; fires after the impact haptic.
  final VoidCallback onPressed;

  /// Visual emphasis.
  final AuthButtonVariant variant;

  /// Replaces the label with a spinner and blocks taps.
  final bool loading;

  /// Dims the fill and blocks taps when false.
  final bool enabled;

  /// Row height (natives default: Metric.buttonHeight; login passes 52).
  final double height;

  /// Optional leading [MadarIcon] name.
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final active = enabled && !loading;
    final fg = switch (variant) {
      AuthButtonVariant.primary => colors.textOnAccent,
      AuthButtonVariant.ghost => colors.textSecondary,
    };
    final radius = BorderRadius.circular(Radii.md);
    final decoration = switch (variant) {
      AuthButtonVariant.primary => BoxDecoration(
        gradient: active
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(colors.accent, _gradientHighlight, _gradientLerp)!,
                  colors.accent,
                ],
              )
            : null,
        color: active
            ? null
            : colors.accent.withValues(alpha: Opacities.disabled),
        borderRadius: radius,
        boxShadow: active
            ? elevationShadows(context, MadarElevation.glow)
            : null,
      ),
      AuthButtonVariant.ghost => BoxDecoration(borderRadius: radius),
    };

    final labelStyle = MadarType.title.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: fg,
    );
    final content = loading
        ? SizedBox.square(
            dimension: _spinnerSize,
            child: CircularProgressIndicator(
              color: fg,
              strokeWidth: _spinnerStroke,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              MadarIcon(icon, tint: fg),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
            ],
          );

    final button = Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      decoration: decoration,
      alignment: Alignment.center,
      child: content,
    );
    if (!active) return button;
    return Semantics(
      button: true,
      child: TactileScale(
        haptic: false,
        onTap: () {
          MadarHaptics.impact();
          onPressed();
        },
        child: button,
      ),
    );
  }
}

/// The natives' `MadarTextField`: rounded filled field with an optional
/// leading icon and an animated focus ring (accent border + soft glow,
/// surfaceAlt → surface fill).
class MadarTextField extends StatefulWidget {
  /// Creates an auth text field bound to [controller].
  const MadarTextField({
    required this.controller,
    required this.placeholder,
    this.icon,
    this.secure = false,
    this.enabled = true,
    this.keyboardType,
    this.onSubmitted,
    super.key,
  });

  /// Owns the field's text (owned/disposed by the parent form).
  final TextEditingController controller;

  /// Hint shown while empty (already localized).
  final String placeholder;

  /// Optional leading [MadarIcon] name (accent-tinted while focused).
  final String? icon;

  /// Obscures input (password).
  final bool secure;

  /// Dims and blocks input while a request is in flight.
  final bool enabled;

  /// Soft-keyboard type.
  final TextInputType? keyboardType;

  /// Keyboard action handler.
  final ValueChanged<String>? onSubmitted;

  @override
  State<MadarTextField> createState() => _MadarTextFieldState();
}

class _MadarTextFieldState extends State<MadarTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The focus ring re-renders via ListenableBuilder on the FocusNode —
    // no setState (contract: zero setState; controller-driven bits rebuild
    // through listenable builders).
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, _) => _buildField(context),
    );
  }

  Widget _buildField(BuildContext context) {
    final colors = context.madarColors;
    final focused = _focus.hasFocus;
    final textStyle = MadarType.body.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w400,
    );

    final field = AnimatedContainer(
      duration: MotionSpec.standardDuration,
      curve: MotionSpec.standardCurve,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: _fieldVPad,
      ),
      decoration: BoxDecoration(
        color: focused ? colors.surface : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: focused ? colors.accent : colors.border,
          width: focused ? _fieldFocusBorder : 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: colors.accent.withValues(alpha: Opacities.focusGlow),
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
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              obscureText: widget.secure,
              keyboardType: widget.keyboardType,
              onSubmitted: widget.onSubmitted,
              cursorColor: colors.accent,
              style: textStyle.copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: textStyle.copyWith(color: colors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
    // Dim the whole field while disabled (busy state) — parity with natives.
    return Opacity(
      opacity: widget.enabled ? 1 : Opacities.disabled,
      child: field,
    );
  }
}

/// The natives' `PinPad`: 6 spring-animated dots over a 4×3 circular keypad.
/// Forced LTR so the digit rows and dots keep phone/POS order in Arabic.
class PinPad extends StatelessWidget {
  /// Creates a PIN pad reflecting [pin].
  const PinPad({
    required this.pin,
    required this.onDigit,
    required this.onBackspace,
    this.maxLength = 6,
    this.keySize = Metrics.pinKey,
    super.key,
  });

  /// Digits entered so far (drives the dots).
  final String pin;

  /// Dot count / auto-submit length.
  final int maxLength;

  /// Key diameter (natives default 64.dp — [Metrics.pinKey]).
  final double keySize;

  /// Fired with the pressed digit ("0"–"9").
  final ValueChanged<String> onDigit;

  /// Fired by the delete key.
  final VoidCallback onBackspace;

  static const List<List<String>> _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '<'],
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.lg,
              children: [
                for (var i = 0; i < maxLength; i++)
                  _PinDot(filled: i < pin.length),
              ],
            ),
          ),
          for (final row in _rows)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: _keyGap,
              children: [
                for (final key in row)
                  _PinKey(
                    glyph: key,
                    size: keySize,
                    onDigit: onDigit,
                    onBackspace: onBackspace,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One PIN dot — springs 12→14 on fill with the shared bouncy spec and an
/// accent glow (mirrors the natives' `animateDpAsState(MotionSpec.bouncy)`).
class _PinDot extends StatefulWidget {
  const _PinDot({required this.filled});

  final bool filled;

  @override
  State<_PinDot> createState() => _PinDotState();
}

class _PinDotState extends State<_PinDot> with SingleTickerProviderStateMixin {
  late final AnimationController _size = AnimationController.unbounded(
    vsync: this,
    value: widget.filled ? _dotFilled : _dotEmpty,
  );

  @override
  void didUpdateWidget(_PinDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filled == widget.filled) return;
    unawaited(
      _size.animateWith(
        SpringSimulation(
          MotionSpec.bouncy,
          _size.value,
          widget.filled ? _dotFilled : _dotEmpty,
          _size.velocity,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return SizedBox.square(
      dimension: _dotFilled,
      child: Center(
        child: AnimatedBuilder(
          animation: _size,
          builder: (context, _) {
            final d = _size.value;
            return Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.filled ? colors.accent : null,
                border: Border.all(
                  color: widget.filled ? colors.accent : colors.border,
                  width: _dotBorder,
                ),
                boxShadow: widget.filled
                    ? [
                        BoxShadow(
                          color: colors.accent,
                          blurRadius: _dotGlowBlur,
                        ),
                      ]
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One circular PIN key — raised surface disc, deep press-scale, selection
/// haptic; `'<'` renders the delete glyph, `''` an invisible spacer.
class _PinKey extends StatelessWidget {
  const _PinKey({
    required this.glyph,
    required this.size,
    required this.onDigit,
    required this.onBackspace,
  });

  final String glyph;
  final double size;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    if (glyph.isEmpty) return SizedBox.square(dimension: size);
    final colors = context.madarColors;
    final backspace = glyph == '<';
    return TactileScale(
      scale: MotionSpec.pressScaleKey,
      onTap: () => backspace ? onBackspace() : onDigit(glyph),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface,
          border: Border.all(color: colors.border, width: _keyBorder),
          boxShadow: elevationShadows(context, MadarElevation.card),
        ),
        alignment: Alignment.center,
        child: backspace
            ? MadarIcon(
                'delete.left',
                tint: colors.textSecondary,
                size: _keyGlyph,
              )
            : Text(
                glyph,
                style: MadarType.h3.copyWith(
                  fontSize: _keyGlyph,
                  color: colors.textPrimary,
                ),
              ),
      ),
    );
  }
}

/// The natives' `MadarCard`: bordered raised surface column.
class SurfaceCard extends StatelessWidget {
  /// Creates a bordered surface card around [children].
  const SurfaceCard({
    required this.children,
    this.spacing = Space.md,
    super.key,
  });

  /// Card content, stacked with [spacing].
  final List<Widget> children;

  /// Vertical gap between [children].
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderLight),
        boxShadow: elevationShadows(context, MadarElevation.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: spacing,
        children: children,
      ),
    );
  }
}

/// The natives' `SectionHeader`: uppercase muted label anchored by an accent
/// icon (or the signature 3×12 accent capsule when no icon is given).
class SectionHeader extends StatelessWidget {
  /// Creates a section label.
  const SectionHeader({required this.text, this.icon, super.key});

  /// Label (already localized; rendered uppercase).
  final String text;

  /// Optional leading [MadarIcon] name.
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
          Container(
            width: _headerTick.width,
            height: _headerTick.height,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
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
      ],
    );
  }
}
