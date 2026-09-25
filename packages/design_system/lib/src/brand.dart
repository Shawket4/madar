/// Madar brand marks — logo lockups and the standalone symbol.
///
/// Assets live under `assets/brand/` in this package; each mark has a
/// `_reversed` variant that is picked automatically in dark theme.
library;

import 'package:flutter/material.dart';

const String _package = 'design_system';
const String _brandPath = 'assets/brand';
const String _semanticLabel = 'Madar';

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Colours of the Madar orbit that are the brand's own, not the theme's.
///
/// Since 2026-09-25 the orbit wears the app icon's colouring everywhere: the
/// ring and the centre dot in the ground's ink (Ink on light, Paper on dark)
/// and the satellite in Madar Teal deep on both (the Madar Design System
/// kit's "THE ORBIT'S COLOURS"). The PNG marks below carry it baked in; a
/// mark drawn in vector (`AnimatedBrandMark`) takes the satellite from here.
abstract final class MadarBrandColors {
  /// Madar Teal deep, #0D6273: the orbit's satellite on every ground.
  static const Color satellite = Color(0xFF0D6273);
}

/// The full Madar logo lockup (symbol + wordmark).
///
/// Renders the Latin lockup by default; set [arabic] for the Arabic
/// lockup. Automatically switches to the reversed (light-on-dark)
/// variant when the ambient [Theme] brightness is dark.
class MadarLockup extends StatelessWidget {
  /// Creates a Madar logo lockup.
  const MadarLockup({super.key, this.width = 220, this.arabic = false});

  /// Rendered width in logical pixels; height follows the asset's
  /// aspect ratio.
  final double width;

  /// Whether to render the Arabic lockup instead of the Latin one.
  final bool arabic;

  @override
  Widget build(BuildContext context) {
    final script = arabic ? 'arabic' : 'latin';
    final variant = _isDark(context) ? '_reversed' : '';
    return Image.asset(
      '$_brandPath/lockup_$script$variant.png',
      package: _package,
      width: width,
      fit: BoxFit.contain,
      semanticLabel: _semanticLabel,
    );
  }
}

/// The standalone Madar brand symbol (no wordmark).
///
/// Automatically switches to the reversed (light-on-dark) variant when
/// the ambient [Theme] brightness is dark.
class MadarSymbol extends StatelessWidget {
  /// Creates the standalone Madar symbol at [size] logical pixels.
  const MadarSymbol({
    super.key,
    this.size = 48,
    this.opacity = 1,
    this.reversed,
  });

  /// Rendered width and height in logical pixels.
  final double size;

  /// Paint-level alpha (0–1) — applied in the image paint itself, so faded
  /// watermarks don't need an [Opacity] wrapper (which forces a saveLayer).
  final double opacity;

  /// Force the light-on-dark artwork regardless of the ambient theme.
  ///
  /// For a mark sitting on a surface that is dark in BOTH themes — the rail's
  /// accent plate — where the ambient brightness says nothing about what this
  /// particular symbol is standing on. `null` reads the theme, which is right
  /// everywhere else.
  final bool? reversed;

  @override
  Widget build(BuildContext context) {
    final variant = (reversed ?? _isDark(context)) ? 'reversed' : 'primary';
    return Image.asset(
      '$_brandPath/symbol_$variant.png',
      package: _package,
      width: size,
      height: size,
      fit: BoxFit.contain,
      opacity: opacity == 1 ? null : AlwaysStoppedAnimation(opacity),
      semanticLabel: _semanticLabel,
    );
  }
}

/// The Madar wordmark on its own (no symbol).
///
/// Automatically switches to the reversed (light-on-dark) variant when
/// the ambient [Theme] brightness is dark.
class MadarWordmark extends StatelessWidget {
  /// Creates the Madar wordmark at [width] logical pixels wide.
  const MadarWordmark({super.key, this.width = 160});

  /// Rendered width in logical pixels; height follows the asset's
  /// aspect ratio.
  final double width;

  @override
  Widget build(BuildContext context) {
    final variant = _isDark(context) ? 'reversed' : 'primary';
    return Image.asset(
      '$_brandPath/wordmark_$variant.png',
      package: _package,
      width: width,
      fit: BoxFit.contain,
      semanticLabel: _semanticLabel,
    );
  }
}

/// Dawam's mark, "the heavy d" (Dawam Design System v2): one round-capped
/// stroke, 20 units of a 100-unit box, a lowercase d whose bowl opens to the
/// left like an isolated dal (د). Drawn as a vector from the kit's geometry,
/// so it is crisp at any size. Ink on light, Paper on dark (never tinted).
class DawamSymbol extends StatelessWidget {
  /// Creates the Dawam mark at [size] logical pixels.
  const DawamSymbol({
    super.key,
    this.size = 48,
    this.opacity = 1,
    this.reversed,
  });

  /// Rendered width and height in logical pixels.
  final double size;

  /// Paint-level alpha (0–1), for faded watermarks.
  final double opacity;

  /// Force the light-on-dark (Paper) artwork regardless of the theme.
  final bool? reversed;

  /// Ink and Paper, the brand's only colours.
  static const Color ink = Color(0xFF14181E);
  static const Color paper = Color(0xFFEFF3F4);

  @override
  Widget build(BuildContext context) {
    final colour = (reversed ?? _isDark(context)) ? paper : ink;
    return Semantics(
      label: 'Dawam',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _HeavyDPainter(colour.withValues(alpha: opacity)),
      ),
    );
  }
}

class _HeavyDPainter extends CustomPainter {
  const _HeavyDPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    // The kit's 100-unit box; the tight bbox is x 15–85, y 8–92.
    canvas.scale(size.width / 100, size.height / 100);
    final pen = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Stem, then the base running left and hooking up into the tail.
    final body = Path()
      ..moveTo(75, 18)
      ..lineTo(75, 82)
      ..lineTo(37, 82)
      ..quadraticBezierTo(25, 82, 25, 70)
      ..lineTo(25, 64);
    // The head leaves the stem and curls up-left.
    final head = Path()
      ..moveTo(75, 46)
      ..lineTo(47, 46)
      ..quadraticBezierTo(39, 46, 35, 40);
    canvas
      ..drawPath(body, pen)
      ..drawPath(head, pen);
  }

  @override
  bool shouldRepaint(_HeavyDPainter old) => old.colour != colour;
}
