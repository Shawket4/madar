/// Auth-flow form controls — verbatim ports of the Kotlin natives'
/// `Components.kt` (MadarButton / MadarTextField / PinPad) and
/// `SharedComponents.kt` (MadarCard / SectionHeader). The design_system
/// package ships tokens + chrome only, so these feature-local controls live
/// here. NOT exported from the feature_auth barrel.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// ── Native-verbatim metrics (Components.kt literals that fall between the
// 4-pt Space steps — kept exact so the port measures identically) ────────────

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
    _size.animateWith(
      SpringSimulation(
        MotionSpec.bouncy,
        _size.value,
        widget.filled ? _dotFilled : _dotEmpty,
        _size.velocity,
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
