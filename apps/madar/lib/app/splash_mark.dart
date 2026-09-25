import 'package:flutter/widgets.dart';

/// The orbit from Madar's app icon, drawn the way the native launch screen
/// draws it, so the hand-off from the OS splash to the boot splash keeps the
/// same picture in the same place.
///
/// Source: the Madar Design System kit, `app/masters/launch-image-*.svg`,
/// itself the owner's app icon ("Asset 1", 2026-09-25). The ring and the
/// centre dot are Ink on a light ground (Paper on a dark one); the satellite
/// is Madar Teal deep on both. The numbers are Asset 1's own, in its
/// 179.2-unit tile, where the orbit's 100-unit box is 0.46 of the tile.
class SplashOrbit extends StatelessWidget {
  /// Creates the orbit with its 100-unit box [box] logical pixels wide.
  const SplashOrbit({super.key, this.box = 120, this.dark = false});

  /// Width of the orbit's 100-unit box. 120 matches the native splash: the
  /// iOS launch image (box 120 of its 150 pt square) and the Android one.
  final double box;

  /// Paper ring and dot (for a dark ground) instead of Ink.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Madar',
      image: true,
      child: CustomPaint(
        size: Size.square(box),
        painter: SplashOrbitPainter(dark: dark),
      ),
    );
  }
}

/// Paints [SplashOrbit]; public so a test can check the geometry.
class SplashOrbitPainter extends CustomPainter {
  /// Creates the painter.
  const SplashOrbitPainter({required this.dark});

  /// Paper ring and dot instead of Ink.
  final bool dark;

  /// Ink, Paper and Madar Teal deep: the brand kit's palette, not UI tokens.
  /// This is artwork that must match the native splash pixel for pixel (like
  /// the symbol PNGs, which carry their colours too), so it does not follow
  /// the theme's colours.
  static const ink = Color(0xFF14181E);
  static const paper = Color(0xFFEFF3F4);
  static const tealDeep = Color(0xFF0D6273);

  // Asset 1, verbatim: ring centre (89.7, 89.7) r 28.1 stroke 5.4, centre
  // dot r 9.9, satellite (109.5, 69.8) r 6.6; the orbit's box is 0.46 × 179.2.
  static const double _box = 0.46 * 179.2;
  static const double _ringR = 28.1;
  static const double _ringStroke = 5.4;
  static const double _dotR = 9.9;
  static const double _satDx = 109.5 - 89.7;
  static const double _satDy = 69.8 - 89.7;
  static const double _satR = 6.6;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / _box;
    final c = size.center(Offset.zero);
    final fg = dark ? paper : ink;
    canvas
      ..drawCircle(
        c,
        _ringR * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ringStroke * k
          ..color = fg
          ..isAntiAlias = true,
      )
      ..drawCircle(c, _dotR * k, Paint()..color = fg)
      ..drawCircle(
        c + Offset(_satDx * k, _satDy * k),
        _satR * k,
        Paint()..color = tealDeep,
      );
  }

  @override
  bool shouldRepaint(SplashOrbitPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
