import 'package:design_system/src/tokens/colors.dart';
import 'package:flutter/widgets.dart';

/// Soft layered shadows — the natives' Elevation levels. Light mode tints
/// with the Madar ink, dark mode with pure black; GLOW radiates the accent.
enum MadarElevation { none, card, raised, glow }

extension MadarElevationX on MadarElevation {
  /// Shadow list for this level. [colors] picks the ink/black/accent tint;
  /// [dark] switches the blur radii the natives use per theme.
  List<BoxShadow> shadows(MadarColors colors, {required bool dark}) {
    const ink = Color(0xFF14181E);
    final base = dark ? const Color(0xFF000000) : ink;
    switch (this) {
      case MadarElevation.none:
        return const [];
      case MadarElevation.card:
        return [
          BoxShadow(
            color: base.withValues(alpha: dark ? 0.45 : 0.07),
            blurRadius: dark ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ];
      case MadarElevation.raised:
        return [
          BoxShadow(
            color: base.withValues(alpha: dark ? 0.55 : 0.13),
            blurRadius: dark ? 30 : 22,
            offset: const Offset(0, 10),
          ),
        ];
      case MadarElevation.glow:
        return [
          BoxShadow(
            color: colors.accent.withValues(alpha: dark ? 0.55 : 0.38),
            blurRadius: 18,
          ),
        ];
    }
  }
}
