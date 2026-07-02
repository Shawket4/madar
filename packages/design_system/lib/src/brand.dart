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

/// The full Madar logo lockup (symbol + wordmark).
///
/// Renders the Latin lockup by default; set [arabic] for the Arabic
/// lockup. Automatically switches to the reversed (light-on-dark)
/// variant when the ambient [Theme] brightness is dark.
class MadarLockup extends StatelessWidget {
  /// Creates a Madar logo lockup.
  const MadarLockup({
    super.key,
    this.width = 220,
    this.arabic = false,
  });

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
  const MadarSymbol({super.key, this.size = 48});

  /// Rendered width and height in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final variant = _isDark(context) ? 'reversed' : 'primary';
    return Image.asset(
      '$_brandPath/symbol_$variant.png',
      package: _package,
      width: size,
      height: size,
      fit: BoxFit.contain,
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
